'use strict';

// AVA Sync Social: single-PC HTTP API. Message bodies are accepted only as
// authenticated ciphertext; plaintext and invite secrets are never persisted.
const http = require('node:http');
const https = require('node:https');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

const PORT = Number(process.env.SOCIAL_PORT || 8787);
const HOST = process.env.SOCIAL_HOST || '127.0.0.1';
const DATA_DIR = process.env.SOCIAL_DATA_DIR || path.join(__dirname, 'data');
const DB_FILE = path.join(DATA_DIR, 'social.json');
const SECRET_FILE = path.join(DATA_DIR, 'token-secret');
const TLS_KEY = process.env.SOCIAL_TLS_KEY;
const TLS_CERT = process.env.SOCIAL_TLS_CERT;

let db;
let jwtSecret;
let writeQueue = Promise.resolve();
const authAttempts = new Map();

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function b64url(input) {
  return Buffer.from(input).toString('base64url');
}

function inviteHash(secret) {
  return crypto.createHash('sha256').update(secret, 'utf8').digest('hex');
}

function tokenFor(userId) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify({ sub: userId, iat: now, exp: now + 60 * 60 * 24 * 14 }));
  const sig = crypto.createHmac('sha256', jwtSecret).update(`${head}.${body}`).digest('base64url');
  return `${head}.${body}.${sig}`;
}

function userFromToken(value) {
  if (!value) fail(401, 'Entre na conta Social novamente.');
  const parts = value.split('.');
  if (parts.length !== 3) fail(401, 'Sessão inválida.');
  const expected = crypto.createHmac('sha256', jwtSecret).update(`${parts[0]}.${parts[1]}`).digest();
  let provided;
  try { provided = Buffer.from(parts[2], 'base64url'); } catch (_) { fail(401, 'Sessão inválida.'); }
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) fail(401, 'Sessão inválida.');
  let payload;
  try { payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')); } catch (_) { fail(401, 'Sessão inválida.'); }
  if (!payload.sub || payload.exp < Math.floor(Date.now() / 1000)) fail(401, 'Sessão expirada. Entre novamente.');
  const user = db.users.find((u) => u.id === payload.sub);
  if (!user) fail(401, 'Conta não encontrada.');
  return user;
}

function publicUser(user) {
  return { id: user.id, email: user.email, username: user.username, display_name: user.displayName };
}

function secureCompareHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  try { return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex')); } catch (_) { return false; }
}

function memberships(userId) {
  return db.members.filter((m) => m.userId === userId).map((m) => m.conversationId);
}

function isMember(conversationId, userId) {
  return db.members.some((m) => m.conversationId === conversationId && m.userId === userId);
}

function messageForClient(message) {
  const sender = db.users.find((u) => u.id === message.senderId);
  return {
    id: message.id,
    conversation_id: message.conversationId,
    sender_id: message.senderId,
    sender_name: sender?.displayName || 'Colega',
    ciphertext: message.ciphertext,
    nonce: message.nonce,
    mac: message.mac,
    created_at: message.createdAt,
  };
}

async function persist() {
  writeQueue = writeQueue.then(async () => {
    const temporary = `${DB_FILE}.tmp`;
    await fs.writeFile(temporary, JSON.stringify(db), { mode: 0o600 });
    await fs.rename(temporary, DB_FILE);
  });
  return writeQueue;
}

async function readBody(req) {
  const chunks = [];
  let length = 0;
  for await (const chunk of req) {
    length += chunk.length;
    if (length > 96 * 1024) fail(413, 'Requisição muito grande.');
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (_) { fail(400, 'JSON inválido.'); }
}

function rateLimit(ip) {
  const now = Date.now();
  const recent = (authAttempts.get(ip) || []).filter((time) => now - time < 10 * 60 * 1000);
  if (recent.length >= 12) fail(429, 'Muitas tentativas. Aguarde alguns minutos.');
  recent.push(now);
  authAttempts.set(ip, recent);
}

function response(res, status, data) {
  const bytes = Buffer.from(JSON.stringify(data));
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': bytes.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  });
  res.end(bytes);
}

async function handle(req, res) {
  const origin = req.headers.origin;
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  }
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  const url = new URL(req.url, 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);
  if (req.method === 'GET' && url.pathname === '/health') return response(res, 200, { ok: true, service: 'ava-sync-social' });
  if (parts[0] !== 'api') return response(res, 404, { error: 'Rota não encontrada.' });

  if (req.method === 'POST' && parts[1] === 'auth' && ['signup', 'signin'].includes(parts[2])) {
    rateLimit(req.socket.remoteAddress || 'unknown');
    const input = await readBody(req);
    const email = String(input.email || '').trim().toLowerCase();
    const password = String(input.password || '');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 10 || password.length > 256) fail(400, 'Informe e-mail válido e senha com pelo menos 10 caracteres.');
    if (parts[2] === 'signup') {
      const username = String(input.username || '').trim().toLowerCase();
      const displayName = String(input.displayName || '').trim();
      if (!/^[a-z0-9_]{3,24}$/.test(username) || displayName.length < 1 || displayName.length > 48) fail(400, 'Confira nome de usuário e nome de exibição.');
      if (db.users.some((u) => u.email === email)) fail(409, 'Já existe conta com esse e-mail.');
      if (db.users.some((u) => u.username === username)) fail(409, 'Esse nome de usuário já está em uso.');
      const salt = crypto.randomBytes(16);
      const passwordHash = crypto.scryptSync(password, salt, 64);
      const user = { id: crypto.randomUUID(), email, username, displayName, salt: salt.toString('hex'), passwordHash: passwordHash.toString('hex'), createdAt: new Date().toISOString() };
      db.users.push(user);
      await persist();
      return response(res, 201, { token: tokenFor(user.id), user: publicUser(user) });
    }
    const user = db.users.find((u) => u.email === email);
    const salt = user ? Buffer.from(user.salt, 'hex') : Buffer.alloc(16);
    const hash = crypto.scryptSync(password, salt, 64);
    const expected = user ? Buffer.from(user.passwordHash, 'hex') : Buffer.alloc(64);
    if (!user || !crypto.timingSafeEqual(hash, expected)) fail(401, 'E-mail ou senha incorretos.');
    return response(res, 200, { token: tokenFor(user.id), user: publicUser(user) });
  }

  const auth = String(req.headers.authorization || '');
  const user = userFromToken(auth.startsWith('Bearer ') ? auth.substring(7) : '');
  if (req.method === 'GET' && parts[1] === 'auth' && parts[2] === 'me') return response(res, 200, { user: publicUser(user) });
  if (req.method === 'POST' && parts[1] === 'auth' && parts[2] === 'signout') return response(res, 200, { ok: true });

  if (req.method === 'GET' && parts[1] === 'conversations' && parts.length === 2) {
    const ids = memberships(user.id);
    const result = db.conversations.filter((c) => ids.includes(c.id)).map((c) => {
      const last = db.messages.filter((m) => m.conversationId === c.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0];
      return { id: c.id, title: c.title, created_at: c.createdAt, is_group: true, last_message: last ? messageForClient(last) : null };
    }).sort((a, b) => b.created_at.localeCompare(a.created_at));
    return response(res, 200, result);
  }

  if (req.method === 'POST' && parts[1] === 'conversations' && parts.length === 2) {
    const input = await readBody(req);
    const title = String(input.title || '').trim();
    const secret = String(input.inviteSecret || '');
    if (title.length < 1 || title.length > 64 || secret.length < 32 || secret.length > 128) fail(400, 'Dados do grupo ou convite inválidos.');
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    db.conversations.push({ id, title, createdBy: user.id, inviteHash: inviteHash(secret), createdAt: now });
    db.members.push({ conversationId: id, userId: user.id, joinedAt: now });
    await persist();
    return response(res, 201, { id, title, created_at: now, is_group: true });
  }

  if (req.method === 'POST' && parts[1] === 'conversations' && parts[2] === 'join') {
    const input = await readBody(req);
    const conversationId = String(input.conversationId || '');
    const secret = String(input.inviteSecret || '');
    const conversation = db.conversations.find((c) => c.id === conversationId);
    if (!conversation || secret.length < 32 || !secureCompareHex(conversation.inviteHash, inviteHash(secret))) fail(403, 'Convite inválido.');
    if (!isMember(conversationId, user.id)) {
      db.members.push({ conversationId, userId: user.id, joinedAt: new Date().toISOString() });
      await persist();
    }
    return response(res, 200, { ok: true });
  }

  if (parts[1] === 'conversations' && parts[2] && parts[3] === 'messages') {
    const conversationId = parts[2];
    if (!isMember(conversationId, user.id)) fail(403, 'Você não participa deste grupo.');
    if (req.method === 'GET') {
      const after = url.searchParams.get('after');
      const messages = db.messages
        .filter((m) => m.conversationId === conversationId && (!after || m.createdAt > after))
        .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
        .slice(-500)
        .map(messageForClient);
      return response(res, 200, messages);
    }
    if (req.method === 'POST') {
      const input = await readBody(req);
      const ciphertext = String(input.ciphertext || '');
      const nonce = String(input.nonce || '');
      const mac = String(input.mac || '');
      if (ciphertext.length < 1 || ciphertext.length > 24000 || nonce.length < 12 || nonce.length > 64 || mac.length < 16 || mac.length > 128) fail(400, 'Mensagem cifrada inválida.');
      const message = { id: crypto.randomUUID(), conversationId, senderId: user.id, ciphertext, nonce, mac, createdAt: new Date().toISOString() };
      db.messages.push(message);
      await persist();
      return response(res, 201, messageForClient(message));
    }
  }

  return response(res, 404, { error: 'Rota não encontrada.' });
}

async function start() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try { jwtSecret = await fs.readFile(SECRET_FILE); }
  catch (_) {
    jwtSecret = crypto.randomBytes(48);
    await fs.writeFile(SECRET_FILE, jwtSecret, { mode: 0o600, flag: 'wx' });
  }
  try { db = JSON.parse(await fs.readFile(DB_FILE, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    db = { users: [], conversations: [], members: [], messages: [] };
    await persist();
  }
  const server = TLS_KEY && TLS_CERT
    ? https.createServer({ key: await fs.readFile(TLS_KEY), cert: await fs.readFile(TLS_CERT) }, listener)
    : http.createServer(listener);
  if (HOST !== '127.0.0.1' && HOST !== '::1' && !(TLS_KEY && TLS_CERT) && process.env.SOCIAL_ALLOW_INSECURE_LAN !== 'true') {
    throw new Error('Refusing non-local HTTP. Configure TLS certificates before exposing the service to the network.');
  }
  server.listen(PORT, HOST, () => process.stdout.write(`AVA Sync Social listening on ${HOST}:${PORT}${TLS_KEY && TLS_CERT ? ' (HTTPS)' : ' (loopback only)'}\n`));
  server.on('request', (req, res) => {
    // Keep logs free of request bodies, authorization headers, and invite secrets.
    if (req.url !== '/health') process.stdout.write(`${new Date().toISOString()} ${req.method} ${new URL(req.url, 'http://localhost').pathname}\n`);
  });
  server.on('clientError', (_, socket) => socket.end('HTTP/1.1 400 Bad Request\r\n\r\n'));
}

function listener(req, res) {
  handle(req, res).catch((error) => {
    if (!res.headersSent) response(res, error.status || 500, { error: error.status ? error.message : 'Erro interno do servidor.' });
    else res.destroy();
  });
}

start().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
