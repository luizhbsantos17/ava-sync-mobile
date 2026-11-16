// Edge Function "social" do AVA Sync.
//
// Identidade: o token do AVA (Moodle) é validado em core_webservice_get_site_info
// na ação "session", que devolve uma sessão assinada (HMAC) de 12 h. As demais
// ações usam essa sessão, sem consultar o AVA a cada chamada. Ações de professor
// (matérias) sempre revalidam no AVA.
//
// Privacidade: o servidor só guarda texto cifrado (AES-GCM feito no aparelho). As
// chaves das conversas circulam em convites ou em envelopes X25519 por aparelho.
// Toda permissão (membro, admin, dono, professor) é conferida aqui.
//
// Compatibilidade: as ações antigas (me, list, messages, send_message, join_group,
// create_group) continuam funcionando para o app 0.7.0 (build 11).

import { enviarPush, pushConfigurado } from "./push.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
});

class HttpError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}
const fail = (message: string, status = 400): never => {
  throw new HttpError(message, status);
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedHosts = new Set(["ava3.cefor.ifes.edu.br", "ava.cefor.ifes.edu.br", "ava.ifes.edu.br"]);
const BUCKET = "social";
const SESSION_HOURS = 12;
const ONLINE_WINDOW_MS = 100_000;
const POLL_WAIT_MS = 20_000;
const POLL_STEP_MS = 900;
const MAX_CHANNELS = 30;
const PROFILE_FIELDS = "user_key,username,display_name,bio,avatar_path,banner_path,banner_color,status,custom_status,custom_emoji,public_key,last_seen,created_at";
const MESSAGE_FIELDS = "id,conversation_id,channel_id,sender_id,ciphertext,nonce,mac,format,reply_to,mentions,edited_at,deleted_at,pinned_at,pinned_by,created_at,rev";
const roleRank: Record<string, number> = { owner: 3, admin: 2, member: 1 };
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------- utilidades
const enc = new TextEncoder();

function b64url(bytes: Uint8Array) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function hex(bytes: ArrayBuffer) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(value)));
}

const str = (value: unknown, max: number) => (typeof value === "string" ? value.trim().slice(0, max) : "");
const optStr = (value: unknown, max: number) => {
  if (value === null) return null;
  if (typeof value !== "string") return undefined;
  const v = value.trim().slice(0, max);
  return v.length ? v : null;
};
const isUuid = (value: unknown) => typeof value === "string" && /^[0-9a-f-]{36}$/i.test(value);
const uuid = (value: unknown, label = "Identificador") => {
  if (!isUuid(value)) fail(`${label} inválido.`);
  return value as string;
};
const q = encodeURIComponent;
// valor entre aspas para filtros or=() e in.() (as chaves têm ponto e dois-pontos)
const qv = (value: string) => encodeURIComponent(`"${value.replace(/"/g, "")}"`);

// ---------------------------------------------------------------- sessão assinada
let hmacKey: CryptoKey | null = null;
async function sessionKey() {
  if (!hmacKey) {
    const raw = await crypto.subtle.digest("SHA-256", enc.encode(`${serviceKey}|ava-sync-social-session-v1`));
    hmacKey = await crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  }
  return hmacKey;
}

async function issueSession(userKey: string) {
  const exp = Math.floor(Date.now() / 1000) + SESSION_HOURS * 3600;
  const body = `${b64url(enc.encode(userKey))}.${exp}`;
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await sessionKey(), enc.encode(body)));
  return { session: `${body}.${b64url(sig)}`, expiresAt: exp };
}

async function readSession(token: unknown) {
  if (typeof token !== "string" || token.length > 400) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const body = `${parts[0]}.${parts[1]}`;
  const expected = b64url(new Uint8Array(await crypto.subtle.sign("HMAC", await sessionKey(), enc.encode(body))));
  if (expected.length !== parts[2].length) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ parts[2].charCodeAt(i);
  if (diff !== 0) return null;
  if (Number(parts[1]) < Date.now() / 1000) return null;
  const padded = parts[0].replace(/-/g, "+").replace(/_/g, "/");
  return new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
}

// ---------------------------------------------------------------- AVA (Moodle)
function siteOrigin(raw: unknown): URL {
  if (typeof raw !== "string") fail("Endereço do AVA ausente.");
  const url = new URL(raw as string);
  if (url.protocol !== "https:" || !allowedHosts.has(url.hostname.toLowerCase()) || (url.pathname !== "/" && url.pathname !== "")) {
    fail("Este recurso aceita somente o AVA oficial do Ifes.");
  }
  return new URL(url.origin);
}

function flatten(value: unknown, prefix: string, out: URLSearchParams) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => flatten(item, `${prefix}[${index}]`, out));
  } else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) flatten(item, prefix ? `${prefix}[${key}]` : key, out);
  } else if (value !== undefined && value !== null) {
    out.append(prefix, String(value));
  }
}

async function moodleCall(site: URL, token: string, functionName: string, parameters: Record<string, unknown> = {}) {
  const form = new URLSearchParams({ wstoken: token, wsfunction: functionName, moodlewsrestformat: "json" });
  flatten(parameters, "", form);
  const response = await fetch(new URL("/webservice/rest/server.php", site), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) fail("O AVA recusou a validação da conta.", 401);
  const value = await response.json();
  if (!value || typeof value !== "object" || value.exception || value.errorcode) {
    fail("O token do AVA expirou ou não tem acesso ao serviço necessário.", 401);
  }
  return value;
}

async function validateMoodle(site: URL, token: string) {
  if (!token || token.length > 4096) fail("Entre novamente no AVA para usar o Social.", 401);
  const info = await moodleCall(site, token, "core_webservice_get_site_info") as Record<string, unknown>;
  const userId = Number(info.userid);
  if (!Number.isSafeInteger(userId) || userId <= 0) fail("Não foi possível identificar a conta do AVA.", 401);
  return { userId, displayName: String(info.fullname ?? "Estudante").slice(0, 48) };
}

async function courseUsers(site: URL, token: string, courseId: number) {
  const result = await moodleCall(site, token, "core_enrol_get_enrolled_users", {
    courseid: courseId,
    options: [{ name: "userfields", value: "id,fullname,roles" }],
  });
  return Array.isArray(result) ? result as Array<Record<string, unknown>> : [];
}

const teacherRoles = new Set(["editingteacher", "teacher", "manager", "coursecreator"]);
function hasTeacherRole(user: Record<string, unknown>) {
  const roles = Array.isArray(user.roles) ? user.roles as Array<Record<string, unknown>> : [];
  return roles.some((role) => teacherRoles.has(String(role.shortname ?? "").toLowerCase()));
}

// ---------------------------------------------------------------- banco e arquivos
type Row = Record<string, unknown>;

async function db(path: string, method = "GET", body?: unknown, prefer?: string): Promise<any> {
  const headers: Record<string, string> = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (prefer) headers.Prefer = prefer;
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(12000),
  });
  const text = await response.text();
  if (!response.ok) {
    if (response.status === 409 || /duplicate key/.test(text)) fail("Esse nome já está em uso.");
    if (/check constraint/.test(text)) fail("Algum campo está fora do formato permitido.");
    throw new Error(`Falha no banco Social (${response.status}): ${text.slice(0, 180)}`);
  }
  return text ? JSON.parse(text) : null;
}

const rpc = (fn: string, args: Row) => db(`rpc/${fn}`, "POST", args);

async function storage(path: string, method: string, body?: unknown) {
  const response = await fetch(`${supabaseUrl}/storage/v1/${path}`, {
    method,
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(12000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Falha nos arquivos do Social (${response.status}): ${text.slice(0, 160)}`);
  return text ? JSON.parse(text) : null;
}

// ---------------------------------------------------------------- perfis
const userHash = async (userKey: string) => (await sha256(userKey)).slice(0, 16);

async function socialUser(host: string, moodleUserId: number, displayName: string, refreshName: boolean) {
  const userKey = `${host}:${moodleUserId}`;
  const hostCode = (await sha256(host)).slice(0, 6);
  const username = `ifes_${hostCode}_${moodleUserId}`.slice(0, 24).toLowerCase();
  const name = displayName.trim().slice(0, 48) || "Estudante";
  await db("social_profiles?on_conflict=user_key", "POST", { user_key: userKey, username, display_name: name },
    "resolution=ignore-duplicates,return=minimal");
  if (refreshName) {
    await db(`social_profiles?user_key=eq.${q(userKey)}&name_locked=eq.false`, "PATCH", { display_name: name }, "return=minimal");
  }
  return userKey;
}

function presence(p: Row) {
  const seen = p.last_seen ? Date.parse(String(p.last_seen)) : 0;
  if (p.status === "invisible" || !seen || Date.now() - seen > ONLINE_WINDOW_MS) return "offline";
  return String(p.status ?? "online");
}

function shapeProfile(p: Row | null | undefined, self = false): Row | null {
  if (!p) return null;
  const out: Row = {
    user_key: p.user_key,
    username: p.username,
    display_name: p.display_name,
    bio: p.bio ?? null,
    avatar_path: p.avatar_path ?? null,
    banner_path: p.banner_path ?? null,
    banner_color: p.banner_color ?? null,
    custom_status: p.custom_status ?? null,
    custom_emoji: p.custom_emoji ?? null,
    public_key: p.public_key ?? null,
    presence: self && p.status !== "invisible" ? String(p.status ?? "online") : presence(p),
    last_seen: p.status === "invisible" && !self ? null : p.last_seen ?? null,
    created_at: p.created_at ?? null,
  };
  if (self) out.status = p.status ?? "online";
  return out;
}

async function profilesByKeys(keys: string[]) {
  const unique = [...new Set(keys.filter(Boolean))];
  const out: Record<string, Row | null> = {};
  for (let i = 0; i < unique.length; i += 80) {
    const slice = unique.slice(i, i + 80);
    const rows = await db(`social_profiles?user_key=in.(${slice.map(qv).join(",")})&select=${PROFILE_FIELDS}`) as Row[];
    for (const r of rows) out[String(r.user_key)] = shapeProfile(r);
  }
  return out;
}

async function myProfile(userId: string) {
  const rows = await db(`social_profiles?user_key=eq.${q(userId)}&select=${PROFILE_FIELDS}`) as Row[];
  if (!rows[0]) fail("Perfil social não encontrado. Entre novamente.", 401);
  return rows[0];
}

async function touchSeen(userId: string) {
  const limit = new Date(Date.now() - 30_000).toISOString();
  await db(`social_profiles?user_key=eq.${q(userId)}&or=(last_seen.is.null,last_seen.lt.${qv(limit)})`, "PATCH",
    { last_seen: new Date().toISOString() }, "return=minimal");
}

// ---------------------------------------------------------------- conversas e permissões
async function getConversation(id: string) {
  const rows = await db(`social_conversations?id=eq.${q(id)}&select=*`) as Row[];
  if (!rows[0]) fail("Conversa não encontrada.");
  return rows[0];
}

async function getMember(conversationId: string, userId: string) {
  const rows = await db(`social_members?conversation_id=eq.${q(conversationId)}&user_key=eq.${q(userId)}&select=*`) as Row[];
  return rows[0] ?? null;
}

async function requireMember(conversationId: string, userId: string) {
  const m = await getMember(conversationId, userId);
  if (!m) fail("Você não participa deste grupo.", 403);
  return m!;
}

// Permissões dos cargos personalizados. Dono e admin têm todas.
const PERMISSOES = [
  "gerenciar_grupo", "gerenciar_canais", "gerenciar_cargos", "expulsar", "banir",
  "apagar_mensagens", "fixar", "mencionar_todos", "enviar_avisos",
] as const;
const RANK_DONO = 1_000_000;
const RANK_ADMIN = 900_000;

type Poder = { member: Row; rank: number; perms: Set<string> };

/// Cargo efetivo: dono > admin > maior cargo personalizado (position). Permissões somadas.
async function poder(conversationId: string, userId: string): Promise<Poder | null> {
  const m = await getMember(conversationId, userId);
  if (!m) return null;
  if (m.role === "owner") return { member: m, rank: RANK_DONO, perms: new Set(PERMISSOES) };
  if (m.role === "admin") return { member: m, rank: RANK_ADMIN, perms: new Set(PERMISSOES) };
  const roles = await db(`social_member_roles?conversation_id=eq.${q(conversationId)}&user_key=eq.${q(userId)}&select=social_roles(position,permissions)`) as Row[];
  let rank = 0;
  const perms = new Set<string>();
  for (const r of roles) {
    const ro = r.social_roles as Row | null;
    if (!ro) continue;
    rank = Math.max(rank, Number(ro.position) || 0);
    for (const x of (ro.permissions as string[] ?? [])) perms.add(x);
  }
  return { member: m, rank, perms };
}

async function requirePerm(conversationId: string, userId: string, perm: string) {
  const p = await poder(conversationId, userId);
  if (!p) fail("Você não participa deste grupo.", 403);
  if (!p!.perms.has(perm)) fail("Você não tem permissão para fazer isso neste grupo.", 403);
  return p!;
}

async function requireRole(conversationId: string, userId: string, min: "admin" | "owner") {
  const m = await requireMember(conversationId, userId);
  if ((roleRank[String(m.role)] ?? 0) < roleRank[min]) fail(min === "owner" ? "Só o dono do grupo pode fazer isso." : "Só administradores podem fazer isso.", 403);
  return m;
}

async function getChannel(channelId: string) {
  const rows = await db(`social_channels?id=eq.${q(channelId)}&select=*`) as Row[];
  if (!rows[0]) fail("Canal não encontrado.");
  return rows[0];
}

async function defaultChannel(conversationId: string) {
  const rows = await db(`social_channels?conversation_id=eq.${q(conversationId)}&select=*&order=position.asc,created_at.asc&limit=1`) as Row[];
  if (rows[0]) return rows[0];
  const created = await db("social_channels", "POST", { conversation_id: conversationId, name: "geral", position: 0 }, "return=representation") as Row[];
  return created[0];
}

async function getMessage(messageId: string) {
  const rows = await db(`social_messages?id=eq.${q(messageId)}&select=${MESSAGE_FIELDS}`) as Row[];
  if (!rows[0]) fail("Mensagem não encontrada.");
  return rows[0];
}

const pairOf = (a: string, b: string) => (a < b ? [a, b] : [b, a]);

async function friendship(a: string, b: string) {
  const [x, y] = pairOf(a, b);
  const rows = await db(`social_friendships?user_a=eq.${q(x)}&user_b=eq.${q(y)}&select=*`) as Row[];
  return rows[0] ?? null;
}

async function blockedBetween(a: string, b: string) {
  const rows = await db(`social_blocks?or=(and(blocker.eq.${qv(a)},blocked.eq.${qv(b)}),and(blocker.eq.${qv(b)},blocked.eq.${qv(a)}))&select=blocker`) as Row[];
  return rows.map((r) => String(r.blocker));
}

async function createConversation(fields: Row, ownerKey: string, channelNames: Array<{ name: string; only_admins?: boolean }>) {
  const rows = await db("social_conversations", "POST", fields, "return=representation") as Row[];
  const id = String(rows[0].id);
  await db("social_members", "POST", { conversation_id: id, user_key: ownerKey, role: "owner" }, "return=minimal");
  await db("social_channels", "POST", channelNames.map((c, i) => ({ conversation_id: id, name: c.name, position: i, only_admins: !!c.only_admins })), "return=minimal");
  return id;
}

function shapeMessages(rows: Row[]) {
  return rows.map((r) => {
    const reactions = Array.isArray(r.social_reactions) ? r.social_reactions as Row[] : [];
    const { social_reactions: _ignored, ...rest } = r;
    return { ...rest, reactions: reactions.map((x) => ({ emoji: x.emoji, user_key: x.user_key })) } as Row;
  });
}

async function withRefs(rows: Row[]) {
  const messages = shapeMessages(rows);
  const have = new Set(messages.map((m) => String(m.id)));
  const missing = [...new Set(messages.map((m) => m.reply_to).filter((id) => id && !have.has(String(id))).map(String))];
  const refs = missing.length
    ? await db(`social_messages?id=in.(${missing.map(q).join(",")})&select=${MESSAGE_FIELDS}`) as Row[]
    : [];
  const profiles = await profilesByKeys([...messages, ...refs].map((m) => String(m.sender_id)));
  return { messages, refs, profiles };
}

async function typingIn(channelId: string, userId: string) {
  const rows = await db(`social_typing?channel_id=eq.${q(channelId)}&expires_at=gt.${q(new Date().toISOString())}&user_key=neq.${q(userId)}&select=user_key`) as Row[];
  return rows.map((r) => String(r.user_key)).sort();
}

async function leave(conversationId: string, userId: string) {
  const me = await requireMember(conversationId, userId);
  await db(`social_members?conversation_id=eq.${q(conversationId)}&user_key=eq.${q(userId)}`, "DELETE", undefined, "return=minimal");
  await db(`social_key_envelopes?conversation_id=eq.${q(conversationId)}&user_key=eq.${q(userId)}`, "DELETE", undefined, "return=minimal");
  const rest = await db(`social_members?conversation_id=eq.${q(conversationId)}&select=user_key,role,joined_at&order=joined_at.asc`) as Row[];
  if (!rest.length) {
    await db(`social_conversations?id=eq.${q(conversationId)}`, "DELETE", undefined, "return=minimal");
    return;
  }
  if (me.role === "owner") {
    const next = rest.find((r) => r.role === "admin") ?? rest[0];
    await db(`social_members?conversation_id=eq.${q(conversationId)}&user_key=eq.${q(String(next.user_key))}`, "PATCH", { role: "owner" }, "return=minimal");
  }
}

function sinceOf(payload: Row) {
  return typeof payload.since === "string" ? payload.since : new Date(Date.now() - 3600_000).toISOString();
}

async function unmutedConversations(userId: string) {
  const members = await db(`social_members?user_key=eq.${q(userId)}&muted=eq.false&select=conversation_id`) as Row[];
  return members.map((m) => String(m.conversation_id));
}

/// Mensagens novas (de outras pessoas) depois de `since`, com títulos, canais e perfis
/// para montar a notificação no aparelho.
async function eventosDesde(userId: string, since: string) {
  return await db(`social_events?user_key=eq.${q(userId)}&created_at=gt.${q(since)}&select=id,kind,data,created_at&order=created_at.desc&limit=30`) as Row[];
}

async function inboxSince(userId: string, since: string, ids: string[]) {
  const events = await eventosDesde(userId, since);
  if (!ids.length) return { messages: [], conversations: [], channels: [], profiles: {}, events };
  const rows = await db(`social_messages?conversation_id=in.(${ids.map(q).join(",")})&sender_id=neq.${q(userId)}&deleted_at=is.null&created_at=gt.${q(since)}&select=${MESSAGE_FIELDS}&order=created_at.desc&limit=30`) as Row[];
  const convIds = [...new Set(rows.map((r) => String(r.conversation_id)))];
  const chIds = [...new Set(rows.map((r) => String(r.channel_id)))];
  const [conversations, channels, profiles] = await Promise.all([
    convIds.length ? db(`social_conversations?id=in.(${convIds.map(q).join(",")})&select=id,title,group_kind`) : Promise.resolve([]),
    chIds.length ? db(`social_channels?id=in.(${chIds.map(q).join(",")})&select=id,name`) : Promise.resolve([]),
    profilesByKeys(rows.map((r) => String(r.sender_id))),
  ]);
  return { messages: rows, conversations, channels, profiles, events };
}

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

/// Continua o trabalho depois de responder (Supabase Edge Runtime); fora dele, só não espera.
function emSegundoPlano(p: Promise<unknown>) {
  const segura = p.catch((e) => console.error("segundo plano:", e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(segura);
}

async function getCategoria(id: string) {
  const rows = await db(`social_categories?id=eq.${q(id)}&select=*`) as Row[];
  if (!rows[0]) fail("Categoria não encontrada.");
  return rows[0];
}

/// Categoria só vale se for do mesmo grupo; null tira o canal da categoria.
async function categoriaDoGrupo(conversationId: string, value: unknown) {
  if (value === null || value === undefined || value === "") return null;
  const cat = await getCategoria(uuid(value, "Categoria"));
  if (String(cat.conversation_id) !== conversationId) fail("Categoria de outro grupo.");
  return cat.id;
}

async function getCargo(id: string) {
  const rows = await db(`social_roles?id=eq.${q(id)}&select=*`) as Row[];
  if (!rows[0]) fail("Cargo não encontrado.");
  return rows[0];
}

/// Campos editáveis de um cargo. Ninguém dá a um cargo permissão que não tem.
function camposCargo(payload: Row, eu: Poder, novo: boolean): Row {
  const out: Row = {};
  if (novo || payload.name !== undefined) {
    const name = str(payload.name, 32);
    if (!name) fail("Dê um nome ao cargo.");
    out.name = name;
  }
  if (payload.color !== undefined) {
    const c = Number(payload.color);
    out.color = payload.color !== null && Number.isSafeInteger(c) && c >= 0 && c <= 0xFFFFFFFF ? c : null;
  }
  if (Array.isArray(payload.permissions)) {
    const perms = [...new Set((payload.permissions as unknown[]).map(String))].filter((p) => (PERMISSOES as readonly string[]).includes(p));
    for (const p of perms) if (!eu.perms.has(p)) fail("Você não pode dar uma permissão que não tem.");
    out.permissions = perms;
  }
  if (typeof payload.mentionable === "boolean") out.mentionable = payload.mentionable;
  if (typeof payload.hoist === "boolean") out.hoist = payload.hoist;
  return out;
}

/// Evento que vira notificação para uma pessoa (pedido de amizade, removido do grupo,
/// cargo novo...). Fica guardado para a caixa de entrada e acorda o celular por push.
async function evento(userKey: string, kind: string, data: Row) {
  await db("social_events", "POST", { user_key: userKey, kind, data }, "return=minimal");
  emSegundoPlano((async () => {
    if (!pushConfigurado()) return;
    const tokens = await db(`social_push_tokens?user_key=eq.${q(userKey)}&select=token`) as Row[];
    const invalidos = await enviarPush(tokens.map((t) => String(t.token)), { tipo: "social", evento: kind });
    if (invalidos.length) await db(`social_push_tokens?token=in.(${invalidos.map(q).join(",")})`, "DELETE", undefined, "return=minimal");
  })());
}

async function nomeDe(userKey: string) {
  const r = await db(`social_profiles?user_key=eq.${q(userKey)}&select=display_name`) as Row[];
  return String(r[0]?.display_name ?? "Alguém");
}

/// Push para os aparelhos dos outros membros (não silenciados) da conversa.
async function avisarMembros(conversationId: string, channelId: string, senderId: string) {
  if (!pushConfigurado()) return;
  const membros = await db(`social_members?conversation_id=eq.${q(conversationId)}&user_key=neq.${q(senderId)}&muted=eq.false&select=user_key`) as Row[];
  if (!membros.length) return;
  const tokens = await db(`social_push_tokens?user_key=in.(${membros.map((m) => qv(String(m.user_key))).join(",")})&select=token`) as Row[];
  const invalidos = await enviarPush(tokens.map((t) => String(t.token)), { tipo: "social", conversa: conversationId, canal: channelId });
  if (invalidos.length) {
    await db(`social_push_tokens?token=in.(${invalidos.map(q).join(",")})`, "DELETE", undefined, "return=minimal");
  }
}

// ---------------------------------------------------------------- ações
const moodleActions = new Set(["session", "me", "teacher_courses", "create_course_group"]);

type Ctx = { userId: string; payload: Row; site?: URL; token?: string; host?: string; moodle?: { userId: number; displayName: string } };

const actions: Record<string, (ctx: Ctx) => Promise<unknown>> = {
  // --- sessão e compatibilidade
  async session({ userId }) {
    await touchSeen(userId);
    return { ...(await issueSession(userId)), me: shapeProfile(await myProfile(userId), true) };
  },
  async me({ userId, moodle }) {
    return { id: userId, name: moodle?.displayName ?? "" };
  },
  async list({ userId }) {
    const rows = await rpc("social_overview", { p_user: userId }) as Row[];
    return rows.filter((r) => r.group_kind !== "dm").map((r) => ({
      id: r.id, title: r.title, created_at: r.created_at, group_kind: r.group_kind,
      moodle_course_id: r.moodle_course_id, moodle_course_name: r.moodle_course_name, last_message: r.last_message,
    }));
  },

  // --- visão geral
  async overview({ userId }) {
    await touchSeen(userId);
    const me = await myProfile(userId);
    const [conversations, envelopes, keyRequests, pending] = await Promise.all([
      rpc("social_overview", { p_user: userId }),
      me.public_key
        ? db(`social_key_envelopes?user_key=eq.${q(userId)}&recipient_public=eq.${q(String(me.public_key))}&select=conversation_id,sender_public,sealed,nonce,mac`)
        : Promise.resolve([]),
      rpc("social_key_requests", { p_user: userId }),
      db(`social_friendships?status=eq.pending&requested_by=neq.${q(userId)}&or=(user_a.eq.${qv(userId)},user_b.eq.${qv(userId)})&select=user_a`),
    ]);
    return { me: shapeProfile(me, true), conversations, envelopes, keyRequests, pendingFriends: (pending as Row[]).length };
  },

  // --- push (Firebase): cada aparelho Android registra o seu token
  async push_register({ userId, payload }) {
    const token = str(payload.token, 4096);
    if (token.length < 20) fail("Token de notificação inválido.");
    await db("social_push_tokens?on_conflict=token", "POST",
      { token, user_key: userId, platform: "android", updated_at: new Date().toISOString() },
      "resolution=merge-duplicates,return=minimal");
    return { ok: true, push: pushConfigurado() };
  },
  async push_unregister({ userId, payload }) {
    const token = str(payload.token, 4096);
    await db(`social_push_tokens?token=eq.${q(token)}&user_key=eq.${q(userId)}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  async notifications({ userId, payload }) {
    return await inboxSince(userId, sinceOf(payload), await unmutedConversations(userId));
  },

  // Caixa de entrada em tempo real (long polling): segura a chamada até chegar mensagem
  // nova de outra pessoa numa conversa não silenciada, ou até POLL_WAIT_MS. O app de
  // computador (na bandeja) e o celular com o app aberto chamam em sequência, então a
  // notificação aparece em ~1 s. O conteúdo continua cifrado: quem decifra é o aparelho.
  async inbox({ userId, payload }) {
    const since = sinceOf(payload);
    const ids = await unmutedConversations(userId);
    const deadline = Date.now() + (payload.wait === false ? 0 : POLL_WAIT_MS);
    while (true) {
      const [fresh, evs] = await Promise.all([
        ids.length
          ? db(`social_messages?conversation_id=in.(${ids.map(q).join(",")})&sender_id=neq.${q(userId)}&deleted_at=is.null&created_at=gt.${q(since)}&select=id&limit=1`) as Promise<Row[]>
          : Promise.resolve([] as Row[]),
        db(`social_events?user_key=eq.${q(userId)}&created_at=gt.${q(since)}&select=id&limit=1`) as Promise<Row[]>,
      ]);
      if (fresh.length || evs.length || Date.now() >= deadline) return { ...(await inboxSince(userId, since, ids)), live: true };
      await sleep(POLL_STEP_MS);
    }
  },

  // --- perfil
  async profile({ userId, payload }) {
    const target = str(payload.userKey, 120);
    const rows = await db(`social_profiles?user_key=eq.${q(target)}&select=${PROFILE_FIELDS}`) as Row[];
    if (!rows[0]) fail("Pessoa não encontrada.");
    const self = target === userId;
    const [f, blocks, mine, theirs] = await Promise.all([
      self ? Promise.resolve(null) : friendship(userId, target),
      self ? Promise.resolve([]) : blockedBetween(userId, target),
      db(`social_members?user_key=eq.${q(userId)}&select=conversation_id`),
      db(`social_members?user_key=eq.${q(target)}&select=conversation_id`),
    ]);
    const theirSet = new Set((theirs as Row[]).map((r) => String(r.conversation_id)));
    const shared = (mine as Row[]).map((r) => String(r.conversation_id)).filter((id) => theirSet.has(id));
    const groups = shared.length
      ? await db(`social_conversations?id=in.(${shared.map(q).join(",")})&group_kind=neq.dm&select=id,title,icon_path,group_kind`) as Row[]
      : [];
    let friend = "none";
    if (f) friend = f.status === "accepted" ? "friends" : f.requested_by === userId ? "outgoing" : "incoming";
    return {
      profile: shapeProfile(rows[0], self),
      friendship: friend,
      friendsSince: f?.status === "accepted" ? f.updated_at : null,
      blockedByMe: (blocks as string[]).includes(userId),
      blockedMe: (blocks as string[]).includes(target),
      mutualGroups: groups,
    };
  },

  async update_profile({ userId, payload }) {
    const patch: Row = { updated_at: new Date().toISOString() };
    if (payload.displayName !== undefined) {
      const name = str(payload.displayName, 48);
      if (!name) fail("Informe um nome.");
      patch.display_name = name;
      patch.name_locked = true;
    }
    if (payload.username !== undefined) {
      const u = str(payload.username, 24).toLowerCase();
      if (!/^[a-z0-9_.]{3,24}$/.test(u)) fail("O nome de usuário precisa ter de 3 a 24 letras minúsculas, números, _ ou ponto.");
      patch.username = u;
    }
    for (const [key, col, max] of [["bio", "bio", 190], ["customStatus", "custom_status", 64], ["customEmoji", "custom_emoji", 16]] as const) {
      const v = optStr(payload[key], max);
      if (v !== undefined) patch[col] = v;
    }
    if (payload.status !== undefined) {
      if (!["online", "busy", "away", "invisible"].includes(String(payload.status))) fail("Status inválido.");
      patch.status = payload.status;
    }
    if (payload.bannerColor !== undefined) {
      const c = Number(payload.bannerColor);
      patch.banner_color = payload.bannerColor !== null && Number.isSafeInteger(c) && c >= 0 && c <= 0xFFFFFFFF ? c : null;
    }
    if (payload.bannerPath !== undefined) {
      if (payload.bannerPath === null) patch.banner_path = null;
      else {
        const prefix = `banner/${await userHash(userId)}/`;
        if (typeof payload.bannerPath !== "string" || !payload.bannerPath.startsWith(prefix)) fail("Imagem de fundo inválida.");
        patch.banner_path = payload.bannerPath;
      }
    }
    if (payload.avatarPath !== undefined) {
      if (payload.avatarPath === null) patch.avatar_path = null;
      else {
        const prefix = `avatar/${await userHash(userId)}/`;
        if (typeof payload.avatarPath !== "string" || !payload.avatarPath.startsWith(prefix)) fail("Foto inválida.");
        patch.avatar_path = payload.avatarPath;
      }
    }
    if (payload.publicKey !== undefined) {
      const k = str(payload.publicKey, 64);
      if (!/^[A-Za-z0-9_-]{43}$/.test(k)) fail("Chave pública inválida.");
      patch.public_key = k;
    }
    const rows = await db(`social_profiles?user_key=eq.${q(userId)}&select=${PROFILE_FIELDS}`, "PATCH", patch, "return=representation") as Row[];
    return { me: shapeProfile(rows[0], true) };
  },

  async search_users({ userId, payload }) {
    const term = str(payload.query, 48).toLowerCase().replace(/^@/, "");
    if (term.length < 3) return [];
    const safe = term.replace(/[%*,()"\\]/g, "");
    const rows = await db(`social_profiles?or=(username.ilike.${qv(safe + "*")},display_name.ilike.${qv("*" + safe + "*")})&user_key=neq.${q(userId)}&select=${PROFILE_FIELDS}&limit=15`) as Row[];
    return rows.map((r) => shapeProfile(r));
  },

  // --- amizades
  async friends({ userId }) {
    const rows = await db(`social_friendships?or=(user_a.eq.${qv(userId)},user_b.eq.${qv(userId)})&select=*&order=updated_at.desc`) as Row[];
    const others = rows.map((r) => (r.user_a === userId ? String(r.user_b) : String(r.user_a)));
    const blocks = await db(`social_blocks?blocker=eq.${q(userId)}&select=blocked`) as Row[];
    const profiles = await profilesByKeys([...others, ...blocks.map((b) => String(b.blocked))]);
    return {
      friends: rows.map((r, i) => ({
        profile: profiles[others[i]],
        status: r.status === "accepted" ? "friends" : r.requested_by === userId ? "outgoing" : "incoming",
        since: r.updated_at,
      })).filter((x) => x.profile),
      blocked: blocks.map((b) => profiles[String(b.blocked)]).filter(Boolean),
    };
  },

  async friend_request({ userId, payload }) {
    let target = str(payload.userKey, 120);
    if (!target && payload.username) {
      const rows = await db(`social_profiles?username=eq.${q(str(payload.username, 24).toLowerCase().replace(/^@/, ""))}&select=user_key`) as Row[];
      if (!rows[0]) fail("Ninguém com esse nome de usuário usa o Social.");
      target = String(rows[0].user_key);
    }
    if (!target || target === userId) fail("Pessoa inválida.");
    if ((await blockedBetween(userId, target)).length) fail("Não é possível enviar pedido para esta pessoa.");
    const existing = await friendship(userId, target);
    const [a, b] = pairOf(userId, target);
    if (existing) {
      if (existing.status === "accepted") return { status: "friends" };
      if (existing.requested_by !== userId) {
        await db(`social_friendships?user_a=eq.${q(a)}&user_b=eq.${q(b)}`, "PATCH", { status: "accepted", updated_at: new Date().toISOString() }, "return=minimal");
        await evento(target, "amizade_aceita", { de: userId, nome: await nomeDe(userId) });
        return { status: "friends" };
      }
      return { status: "outgoing" };
    }
    await db("social_friendships", "POST", { user_a: a, user_b: b, requested_by: userId, status: "pending" }, "return=minimal");
    await evento(target, "amizade_pedido", { de: userId, nome: await nomeDe(userId) });
    return { status: "outgoing" };
  },

  async friend_respond({ userId, payload }) {
    const target = str(payload.userKey, 120);
    const f = await friendship(userId, target);
    if (!f || f.status !== "pending" || f.requested_by === userId) fail("Pedido não encontrado.");
    const [a, b] = pairOf(userId, target);
    if (payload.accept === true) {
      await db(`social_friendships?user_a=eq.${q(a)}&user_b=eq.${q(b)}`, "PATCH", { status: "accepted", updated_at: new Date().toISOString() }, "return=minimal");
      await evento(target, "amizade_aceita", { de: userId, nome: await nomeDe(userId) });
      return { status: "friends" };
    }
    await db(`social_friendships?user_a=eq.${q(a)}&user_b=eq.${q(b)}`, "DELETE", undefined, "return=minimal");
    return { status: "none" };
  },

  async friend_remove({ userId, payload }) {
    const [a, b] = pairOf(userId, str(payload.userKey, 120));
    await db(`social_friendships?user_a=eq.${q(a)}&user_b=eq.${q(b)}`, "DELETE", undefined, "return=minimal");
    return { status: "none" };
  },

  async block({ userId, payload }) {
    const target = str(payload.userKey, 120);
    if (!target || target === userId) fail("Pessoa inválida.");
    await db("social_blocks?on_conflict=blocker,blocked", "POST", { blocker: userId, blocked: target }, "resolution=ignore-duplicates,return=minimal");
    const [a, b] = pairOf(userId, target);
    await db(`social_friendships?user_a=eq.${q(a)}&user_b=eq.${q(b)}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  async unblock({ userId, payload }) {
    await db(`social_blocks?blocker=eq.${q(userId)}&blocked=eq.${q(str(payload.userKey, 120))}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  // --- mensagens diretas
  async open_dm({ userId, payload }) {
    const target = str(payload.userKey, 120);
    if (!target || target === userId) fail("Pessoa inválida.");
    const peer = await db(`social_profiles?user_key=eq.${q(target)}&select=${PROFILE_FIELDS}`) as Row[];
    if (!peer[0]) fail("Pessoa não encontrada.");
    const [a, b] = pairOf(userId, target);
    const dmKey = `${a}|${b}`;
    const existing = await db(`social_conversations?dm_key=eq.${q(dmKey)}&select=id`) as Row[];
    if (existing[0]) {
      const id = String(existing[0].id);
      if (!await getMember(id, userId)) await db("social_members", "POST", { conversation_id: id, user_key: userId, role: "member" }, "return=minimal");
      return { conversationId: id, created: false, peer: shapeProfile(peer[0]) };
    }
    if ((await blockedBetween(userId, target)).length) fail("Não é possível conversar com esta pessoa.");
    const f = await friendship(userId, target);
    if (f?.status !== "accepted") {
      const mine = await db(`social_members?user_key=eq.${q(userId)}&select=conversation_id`) as Row[];
      const ids = mine.map((r) => String(r.conversation_id));
      const shared = ids.length
        ? await db(`social_members?user_key=eq.${q(target)}&conversation_id=in.(${ids.map(q).join(",")})&select=conversation_id&limit=1`) as Row[]
        : [];
      if (!shared.length) fail("Vocês precisam ser amigos ou estar no mesmo grupo para conversar.");
    }
    const id = await createConversation({ title: "Mensagem direta", created_by: userId, group_kind: "dm", dm_key: dmKey }, userId, [{ name: "conversa" }]);
    await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(userId)}`, "PATCH", { role: "member" }, "return=minimal");
    await db("social_members", "POST", { conversation_id: id, user_key: target, role: "member" }, "return=minimal");
    return { conversationId: id, created: true, peer: shapeProfile(peer[0]) };
  },

  // --- grupos
  async create_group({ userId, payload }) {
    const title = str(payload.title, 64);
    if (!title) fail("Dê um nome ao grupo.");
    const inviteSecret = typeof payload.inviteSecret === "string" ? payload.inviteSecret : "";
    if (inviteSecret && (inviteSecret.length < 32 || inviteSecret.length > 128)) fail("Convite inválido.");
    const id = await createConversation({
      title,
      description: optStr(payload.description, 300) ?? null,
      created_by: userId,
      invite_hash: inviteSecret ? await sha256(inviteSecret) : null,
      group_kind: "friends",
    }, userId, [{ name: "geral" }]);
    return { conversationId: id };
  },

  async group_info({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const eu = await poder(id, userId);
    if (!eu) fail("Você não participa deste grupo.", 403);
    const me = eu!.member;
    const [conv, channels, members, bans, invites, roles, memberRoles, categories] = await Promise.all([
      getConversation(id),
      db(`social_channels?conversation_id=eq.${q(id)}&select=*&order=position.asc,created_at.asc`),
      db(`social_members?conversation_id=eq.${q(id)}&select=user_key,role,nickname,joined_at`),
      eu!.perms.has("banir") ? db(`social_bans?conversation_id=eq.${q(id)}&select=user_key,created_at`) : Promise.resolve([]),
      db(`social_invites?conversation_id=eq.${q(id)}&select=invite_hash,expires_at,max_uses,uses,created_at`),
      db(`social_roles?conversation_id=eq.${q(id)}&select=*&order=position.desc,created_at.asc`),
      db(`social_member_roles?conversation_id=eq.${q(id)}&select=role_id,user_key`),
      db(`social_categories?conversation_id=eq.${q(id)}&select=*&order=position.asc,created_at.asc`),
    ]);
    const rolesDe = new Map<string, string[]>();
    for (const r of memberRoles as Row[]) {
      const k = String(r.user_key);
      rolesDe.set(k, [...(rolesDe.get(k) ?? []), String(r.role_id)]);
    }
    const profiles = await profilesByKeys([...(members as Row[]), ...(bans as Row[])].map((m) => String(m.user_key)));
    const { invite_hash: _hash, dm_key: _dm, ...publicConv } = conv;
    return {
      conversation: publicConv,
      myRole: me.role,
      muted: me.muted,
      nickname: me.nickname,
      channels,
      members: (members as Row[]).map((m) => ({ ...m, roles: rolesDe.get(String(m.user_key)) ?? [], profile: profiles[String(m.user_key)] })),
      roles,
      categories,
      myRank: eu!.rank,
      myPerms: [...eu!.perms],
      bans: (bans as Row[]).map((b) => ({ ...b, profile: profiles[String(b.user_key)] })),
      activeInvites: (invites as Row[]).filter((i) => (!i.expires_at || Date.parse(String(i.expires_at)) > Date.now()) && (!i.max_uses || Number(i.uses) < Number(i.max_uses))).length,
    };
  },

  async update_group({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "gerenciar_grupo");
    const conv = await getConversation(id);
    if (conv.group_kind === "dm") fail("Conversas diretas não têm configurações de grupo.");
    const patch: Row = { updated_at: new Date().toISOString() };
    if (payload.title !== undefined) {
      const t = str(payload.title, 64);
      if (!t) fail("Dê um nome ao grupo.");
      patch.title = t;
    }
    const d = optStr(payload.description, 300);
    if (d !== undefined) patch.description = d;
    if (payload.iconPath !== undefined) {
      if (payload.iconPath === null) patch.icon_path = null;
      else if (typeof payload.iconPath === "string" && payload.iconPath.startsWith(`icon/${id}/`)) patch.icon_path = payload.iconPath;
      else fail("Imagem inválida.");
    }
    if (payload.bannerPath !== undefined) {
      if (payload.bannerPath === null) patch.banner_path = null;
      else if (typeof payload.bannerPath === "string" && payload.bannerPath.startsWith(`gbanner/${id}/`)) patch.banner_path = payload.bannerPath;
      else fail("Imagem de fundo inválida.");
    }
    if (payload.accentColor !== undefined) {
      const c = Number(payload.accentColor);
      patch.accent_color = payload.accentColor !== null && Number.isSafeInteger(c) && c >= 0 && c <= 0xFFFFFFFF ? c : null;
    }
    await db(`social_conversations?id=eq.${q(id)}`, "PATCH", patch, "return=minimal");
    return { ok: true };
  },

  async delete_group({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requireRole(id, userId, "owner");
    await db(`social_conversations?id=eq.${q(id)}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  async leave_group({ userId, payload }) {
    await leave(uuid(payload.conversationId, "Grupo"), userId);
    return { ok: true };
  },

  async create_invite({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requireMember(id, userId);
    const conv = await getConversation(id);
    if (conv.group_kind === "dm") fail("Conversas diretas não têm convite.");
    const secret = String(payload.inviteSecret ?? "");
    if (secret.length < 32 || secret.length > 128) fail("Convite inválido.");
    const hours = Number(payload.expiresHours);
    const maxUses = Number(payload.maxUses);
    await db("social_invites", "POST", {
      invite_hash: await sha256(secret),
      conversation_id: id,
      created_by: userId,
      expires_at: Number.isFinite(hours) && hours > 0 ? new Date(Date.now() + hours * 3600_000).toISOString() : null,
      max_uses: Number.isSafeInteger(maxUses) && maxUses > 0 ? maxUses : null,
    }, "return=minimal");
    return { ok: true };
  },

  async revoke_invites({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "gerenciar_grupo");
    await db(`social_invites?conversation_id=eq.${q(id)}`, "DELETE", undefined, "return=minimal");
    await db(`social_conversations?id=eq.${q(id)}`, "PATCH", { invite_hash: null }, "return=minimal");
    return { ok: true };
  },

  async join_group({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const hash = await sha256(String(payload.inviteSecret ?? ""));
    const conv = await getConversation(id);
    if (conv.group_kind === "dm") fail("Convite inválido ou expirado.");
    const bans = await db(`social_bans?conversation_id=eq.${q(id)}&user_key=eq.${q(userId)}&select=user_key`) as Row[];
    if (bans.length) fail("Você foi banido deste grupo.", 403);
    const already = await getMember(id, userId);
    if (!already) {
      let ok = conv.invite_hash === hash;
      if (!ok) {
        const inv = await db(`social_invites?invite_hash=eq.${q(hash)}&conversation_id=eq.${q(id)}&select=*`) as Row[];
        const i = inv[0];
        if (i && (!i.expires_at || Date.parse(String(i.expires_at)) > Date.now()) && (!i.max_uses || Number(i.uses) < Number(i.max_uses))) {
          ok = true;
          await db(`social_invites?invite_hash=eq.${q(hash)}`, "PATCH", { uses: Number(i.uses) + 1 }, "return=minimal");
        }
      }
      if (!ok) fail("Convite inválido ou expirado.");
      if (conv.group_kind === "course") fail("Este grupo é da matéria: só quem está inscrito nela no AVA participa.", 403);
      await db("social_members?on_conflict=conversation_id,user_key", "POST", { conversation_id: id, user_key: userId, role: "member" },
        "resolution=ignore-duplicates,return=minimal");
    }
    return { ok: true, title: conv.title };
  },

  async add_member({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const me = await requireMember(id, userId);
    const conv = await getConversation(id);
    if (conv.group_kind !== "friends") fail("Só é possível adicionar pessoas em grupos de amigos.");
    const target = str(payload.userKey, 120);
    const bans = await db(`social_bans?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}&select=user_key`) as Row[];
    if (bans.length) fail("Essa pessoa está banida. Desfaça o banimento antes.");
    if ((roleRank[String(me.role)] ?? 0) < 2) {
      const f = await friendship(userId, target);
      if (f?.status !== "accepted") fail("Você só pode adicionar amigos. Administradores podem adicionar qualquer pessoa.");
    }
    if ((await blockedBetween(userId, target)).length) fail("Não é possível adicionar esta pessoa.");
    const ja = await getMember(id, target);
    await db("social_members?on_conflict=conversation_id,user_key", "POST", { conversation_id: id, user_key: target, role: "member" },
      "resolution=ignore-duplicates,return=minimal");
    if (!ja) await evento(target, "adicionado", { grupo: id, titulo: conv.title, por: await nomeDe(userId) });
    return { ok: true };
  },

  async kick({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const ban = payload.ban === true;
    const eu = await requirePerm(id, userId, ban ? "banir" : "expulsar");
    const target = str(payload.userKey, 120);
    const ele = await poder(id, target);
    if (!ele) fail("Essa pessoa não está no grupo.");
    if (ele!.rank >= eu.rank) fail("Você não pode remover alguém com cargo igual ou maior.");
    const conv = await getConversation(id);
    await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}`, "DELETE", undefined, "return=minimal");
    await db(`social_key_envelopes?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}`, "DELETE", undefined, "return=minimal");
    await db(`social_member_roles?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}`, "DELETE", undefined, "return=minimal");
    if (ban) {
      await db("social_bans?on_conflict=conversation_id,user_key", "POST", { conversation_id: id, user_key: target, banned_by: userId },
        "resolution=ignore-duplicates,return=minimal");
    }
    await evento(target, ban ? "banido" : "removido", { grupo: id, titulo: conv.title, por: await nomeDe(userId) });
    return { ok: true };
  },

  async unban({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "banir");
    await db(`social_bans?conversation_id=eq.${q(id)}&user_key=eq.${q(str(payload.userKey, 120))}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  async set_role({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requireRole(id, userId, "owner");
    const target = str(payload.userKey, 120);
    if (target === userId) fail("Use \"Transferir posse\" para mudar o dono.");
    const role = String(payload.role);
    if (!["admin", "member"].includes(role)) fail("Cargo inválido.");
    if (!await getMember(id, target)) fail("Essa pessoa não está no grupo.");
    await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}`, "PATCH", { role }, "return=minimal");
    const conv = await getConversation(id);
    await evento(target, "cargo", { grupo: id, titulo: conv.title, cargo: role === "admin" ? "Admin" : "Membro", ganhou: role === "admin" });
    return { ok: true };
  },

  async transfer_owner({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requireRole(id, userId, "owner");
    const target = str(payload.userKey, 120);
    if (!await getMember(id, target)) fail("Essa pessoa não está no grupo.");
    await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}`, "PATCH", { role: "owner" }, "return=minimal");
    await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(userId)}`, "PATCH", { role: "admin" }, "return=minimal");
    const conv = await getConversation(id);
    await evento(target, "cargo", { grupo: id, titulo: conv.title, cargo: "Dono", ganhou: true });
    return { ok: true };
  },

  async set_member_prefs({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requireMember(id, userId);
    const patch: Row = {};
    if (typeof payload.muted === "boolean") patch.muted = payload.muted;
    const nick = optStr(payload.nickname, 32);
    if (nick !== undefined) patch.nickname = nick;
    if (Object.keys(patch).length) {
      await db(`social_members?conversation_id=eq.${q(id)}&user_key=eq.${q(userId)}`, "PATCH", patch, "return=minimal");
    }
    return { ok: true };
  },

  // --- canais
  async create_channel({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "gerenciar_canais");
    const conv = await getConversation(id);
    if (conv.group_kind === "dm") fail("Conversas diretas não têm canais.");
    const name = str(payload.name, 32).toLowerCase().replace(/\s+/g, "-");
    if (!name) fail("Dê um nome ao canal.");
    const existing = await db(`social_channels?conversation_id=eq.${q(id)}&select=id`) as Row[];
    if (existing.length >= MAX_CHANNELS) fail(`Um grupo pode ter no máximo ${MAX_CHANNELS} canais.`);
    const rows = await db("social_channels", "POST", {
      conversation_id: id, name, topic: optStr(payload.topic, 200) ?? null, position: existing.length, only_admins: payload.onlyAdmins === true,
      category_id: await categoriaDoGrupo(id, payload.categoryId),
    }, "return=representation") as Row[];
    return rows[0];
  },

  async update_channel({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requirePerm(String(ch.conversation_id), userId, "gerenciar_canais");
    const patch: Row = {};
    if (payload.categoryId !== undefined) patch.category_id = await categoriaDoGrupo(String(ch.conversation_id), payload.categoryId);
    if (payload.name !== undefined) {
      const name = str(payload.name, 32).toLowerCase().replace(/\s+/g, "-");
      if (!name) fail("Dê um nome ao canal.");
      patch.name = name;
    }
    const topic = optStr(payload.topic, 200);
    if (topic !== undefined) patch.topic = topic;
    if (typeof payload.onlyAdmins === "boolean") patch.only_admins = payload.onlyAdmins;
    if (Number.isSafeInteger(payload.position)) patch.position = payload.position;
    if (Object.keys(patch).length) await db(`social_channels?id=eq.${q(String(ch.id))}`, "PATCH", patch, "return=minimal");
    return { ok: true };
  },

  async reorder_channels({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "gerenciar_canais");
    const order = Array.isArray(payload.channelIds) ? payload.channelIds.filter(isUuid) as string[] : [];
    for (let i = 0; i < order.length; i++) {
      await db(`social_channels?id=eq.${q(order[i])}&conversation_id=eq.${q(id)}`, "PATCH", { position: i }, "return=minimal");
    }
    return { ok: true };
  },

  async delete_channel({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requirePerm(String(ch.conversation_id), userId, "gerenciar_canais");
    const all = await db(`social_channels?conversation_id=eq.${q(String(ch.conversation_id))}&select=id`) as Row[];
    if (all.length <= 1) fail("O grupo precisa ter pelo menos um canal.");
    await db(`social_channels?id=eq.${q(String(ch.id))}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  // --- categorias de canais (#2)
  async create_category({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    await requirePerm(id, userId, "gerenciar_canais");
    const name = str(payload.name, 32);
    if (!name) fail("Dê um nome à categoria.");
    const existing = await db(`social_categories?conversation_id=eq.${q(id)}&select=id`) as Row[];
    if (existing.length >= 20) fail("Um grupo pode ter no máximo 20 categorias.");
    const rows = await db("social_categories", "POST", { conversation_id: id, name, position: existing.length }, "return=representation") as Row[];
    return rows[0];
  },

  async update_category({ userId, payload }) {
    const cat = await getCategoria(uuid(payload.categoryId, "Categoria"));
    await requirePerm(String(cat.conversation_id), userId, "gerenciar_canais");
    const patch: Row = {};
    if (payload.name !== undefined) {
      const name = str(payload.name, 32);
      if (!name) fail("Dê um nome à categoria.");
      patch.name = name;
    }
    if (Number.isSafeInteger(payload.position)) patch.position = payload.position;
    if (Object.keys(patch).length) await db(`social_categories?id=eq.${q(String(cat.id))}`, "PATCH", patch, "return=minimal");
    return { ok: true };
  },

  async delete_category({ userId, payload }) {
    const cat = await getCategoria(uuid(payload.categoryId, "Categoria"));
    await requirePerm(String(cat.conversation_id), userId, "gerenciar_canais");
    // os canais continuam, só ficam sem categoria
    await db(`social_categories?id=eq.${q(String(cat.id))}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  // --- cargos personalizados (#2)
  async create_role({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const eu = await requirePerm(id, userId, "gerenciar_cargos");
    const conv = await getConversation(id);
    if (conv.group_kind === "dm") fail("Conversas diretas não têm cargos.");
    const existing = await db(`social_roles?conversation_id=eq.${q(id)}&select=position`) as Row[];
    if (existing.length >= 40) fail("Um grupo pode ter no máximo 40 cargos.");
    // cargo novo nasce logo abaixo do seu (ou no topo, para dono/admin)
    const topo = existing.reduce((m, r) => Math.max(m, Number(r.position) || 0), 0);
    const position = Math.min(topo + 1, eu.rank - 1);
    if (position < 1) fail("Você não pode criar cargos acima do seu.");
    const rows = await db("social_roles", "POST", { conversation_id: id, ...camposCargo(payload, eu, true), position }, "return=representation") as Row[];
    return rows[0];
  },

  async update_role({ userId, payload }) {
    const role = await getCargo(uuid(payload.roleId, "Cargo"));
    const id = String(role.conversation_id);
    const eu = await requirePerm(id, userId, "gerenciar_cargos");
    if (Number(role.position) >= eu.rank) fail("Você só pode editar cargos abaixo do seu.");
    const patch = camposCargo(payload, eu, false);
    if (Number.isSafeInteger(payload.position)) {
      const pos = Number(payload.position);
      if (pos < 1 || pos >= eu.rank) fail("Você só pode pôr o cargo abaixo do seu.");
      patch.position = pos;
    }
    if (Object.keys(patch).length) await db(`social_roles?id=eq.${q(String(role.id))}`, "PATCH", patch, "return=minimal");
    return { ok: true };
  },

  async reorder_roles({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const eu = await requirePerm(id, userId, "gerenciar_cargos");
    // lista do mais alto para o mais baixo; só mexe nos cargos abaixo do seu
    const order = Array.isArray(payload.roleIds) ? (payload.roleIds as unknown[]).filter(isUuid) as string[] : [];
    const roles = await db(`social_roles?conversation_id=eq.${q(id)}&select=id,position`) as Row[];
    const meus = new Set(roles.filter((r) => Number(r.position) < eu.rank).map((r) => String(r.id)));
    const lista = order.filter((r) => meus.has(r));
    for (let i = 0; i < lista.length; i++) {
      await db(`social_roles?id=eq.${q(lista[i])}&conversation_id=eq.${q(id)}`, "PATCH", { position: lista.length - i }, "return=minimal");
    }
    return { ok: true };
  },

  async delete_role({ userId, payload }) {
    const role = await getCargo(uuid(payload.roleId, "Cargo"));
    const eu = await requirePerm(String(role.conversation_id), userId, "gerenciar_cargos");
    if (Number(role.position) >= eu.rank) fail("Você só pode apagar cargos abaixo do seu.");
    await db(`social_roles?id=eq.${q(String(role.id))}`, "DELETE", undefined, "return=minimal");
    return { ok: true };
  },

  /// Troca os cargos personalizados de alguém (pode ter vários).
  async set_member_roles({ userId, payload }) {
    const id = uuid(payload.conversationId, "Grupo");
    const eu = await requirePerm(id, userId, "gerenciar_cargos");
    const target = str(payload.userKey, 120);
    const ele = await poder(id, target);
    if (!ele) fail("Essa pessoa não está no grupo.");
    if (target !== userId && ele!.rank >= eu.rank) fail("Você não pode mudar os cargos de alguém com cargo igual ou maior.");
    const roles = await db(`social_roles?conversation_id=eq.${q(id)}&select=id,name,position`) as Row[];
    const pedidos = new Set(Array.isArray(payload.roleIds) ? (payload.roleIds as unknown[]).map(String) : []);
    const atuais = new Set((await db(`social_member_roles?conversation_id=eq.${q(id)}&user_key=eq.${q(target)}&select=role_id`) as Row[]).map((r) => String(r.role_id)));
    const ganhou: string[] = [];
    for (const r of roles) {
      const rid = String(r.id);
      if (pedidos.has(rid) === atuais.has(rid)) continue;
      if (Number(r.position) >= eu.rank) fail(`Você não pode dar ou tirar o cargo ${r.name}.`);
      if (pedidos.has(rid)) {
        await db("social_member_roles", "POST", { role_id: rid, conversation_id: id, user_key: target }, "return=minimal");
        ganhou.push(String(r.name));
      } else {
        await db(`social_member_roles?role_id=eq.${q(rid)}&user_key=eq.${q(target)}`, "DELETE", undefined, "return=minimal");
      }
    }
    if (ganhou.length && target !== userId) {
      const conv = await getConversation(id);
      await evento(target, "cargo", { grupo: id, titulo: conv.title, cargo: ganhou.join(", "), ganhou: true });
    }
    return { ok: true };
  },

  // --- mensagens
  async messages({ userId, payload }) {
    if (!payload.channelId && payload.conversationId) {
      // app 0.7.0: lista simples da conversa toda
      const conversationId = uuid(payload.conversationId, "Grupo");
      await requireMember(conversationId, userId);
      const rows = await db(`social_messages?conversation_id=eq.${q(conversationId)}&deleted_at=is.null&select=*&order=created_at.desc&limit=200`) as Row[];
      const profiles = await profilesByKeys(rows.map((r) => String(r.sender_id)));
      return rows.reverse().map((row) => ({ ...row, sender_name: profiles[String(row.sender_id)]?.display_name ?? "Colega" }));
    }
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requireMember(String(ch.conversation_id), userId);
    const limit = Math.min(Math.max(Number(payload.limit) || 50, 1), 100);
    const before = typeof payload.before === "string" ? `&created_at=lt.${q(payload.before)}` : "";
    const rows = await db(`social_messages?channel_id=eq.${q(String(ch.id))}${before}&select=${MESSAGE_FIELDS},social_reactions(emoji,user_key)&order=created_at.desc&limit=${limit}`) as Row[];
    const revRows = await db(`social_messages?channel_id=eq.${q(String(ch.id))}&select=rev&order=rev.desc&limit=1`) as Row[];
    const out = await withRefs(rows.reverse());
    return { ...out, rev: revRows[0]?.rev ?? 0, hasMore: rows.length === limit, typing: await typingIn(String(ch.id), userId) };
  },

  async poll({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requireMember(String(ch.conversation_id), userId);
    await touchSeen(userId);
    const cursor = Number(payload.rev) || 0;
    const seenTyping = Array.isArray(payload.typing) ? (payload.typing as unknown[]).map(String).sort().join(",") : "";
    const deadline = Date.now() + (payload.wait === false ? 0 : POLL_WAIT_MS);
    while (true) {
      const [rows, typing] = await Promise.all([
        db(`social_messages?channel_id=eq.${q(String(ch.id))}&rev=gt.${cursor}&select=${MESSAGE_FIELDS},social_reactions(emoji,user_key)&order=rev.asc&limit=100`) as Promise<Row[]>,
        typingIn(String(ch.id), userId),
      ]);
      if (rows.length || typing.join(",") !== seenTyping || Date.now() >= deadline) {
        const out = await withRefs(rows);
        const rev = rows.reduce((max, r) => Math.max(max, Number(r.rev)), cursor);
        const typingProfiles = await profilesByKeys(typing);
        return { ...out, profiles: { ...out.profiles, ...typingProfiles }, rev, typing };
      }
      await sleep(POLL_STEP_MS);
    }
  },

  async typing({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requireMember(String(ch.conversation_id), userId);
    if (payload.active === false) {
      await db(`social_typing?channel_id=eq.${q(String(ch.id))}&user_key=eq.${q(userId)}`, "DELETE", undefined, "return=minimal");
    } else {
      await db("social_typing?on_conflict=channel_id,user_key", "POST",
        { channel_id: ch.id, user_key: userId, expires_at: new Date(Date.now() + 7000).toISOString() },
        "resolution=merge-duplicates,return=minimal");
    }
    return { ok: true };
  },

  async send_message({ userId, payload }) {
    let ch: Row;
    if (payload.channelId) ch = await getChannel(uuid(payload.channelId, "Canal"));
    else ch = await defaultChannel(uuid(payload.conversationId, "Grupo"));
    const conversationId = String(ch.conversation_id);
    const eu = await poder(conversationId, userId);
    if (!eu) fail("Você não participa deste grupo.", 403);
    if (ch.only_admins && !eu!.perms.has("enviar_avisos")) fail("Só quem tem permissão escreve neste canal.", 403);
    const conv = await getConversation(conversationId);
    if (conv.group_kind === "dm") {
      const others = await db(`social_members?conversation_id=eq.${q(conversationId)}&user_key=neq.${q(userId)}&select=user_key`) as Row[];
      if (others[0] && (await blockedBetween(userId, String(others[0].user_key))).length) fail("Não é possível enviar mensagens para esta pessoa.", 403);
    }
    const ciphertext = String(payload.ciphertext ?? "");
    const nonce = String(payload.nonce ?? "");
    const mac = String(payload.mac ?? "");
    if (!ciphertext || ciphertext.length > 24000 || !nonce || !mac) fail("Mensagem inválida.");
    const format = Number(payload.format) === 2 ? 2 : 1;
    let mentions = Array.isArray(payload.mentions) ? (payload.mentions as unknown[]).map(String).slice(0, 30) : [];
    if (!eu!.perms.has("mencionar_todos") && conv.group_kind !== "dm") mentions = mentions.filter((m) => m !== "everyone");
    // @cargo só vale para cargos marcáveis (ou para quem pode marcar todos)
    const mencoesCargo = mentions.filter((m) => m.startsWith("role:"));
    if (mencoesCargo.length && !eu!.perms.has("mencionar_todos")) {
      const ok = new Set((await db(`social_roles?conversation_id=eq.${q(conversationId)}&mentionable=eq.true&select=id`) as Row[]).map((r) => `role:${r.id}`));
      mentions = mentions.filter((m) => !m.startsWith("role:") || ok.has(m));
    }
    const replyTo = isUuid(payload.replyTo) ? payload.replyTo : null;
    const rows = await db(`social_messages?select=${MESSAGE_FIELDS}`, "POST", {
      conversation_id: conversationId, channel_id: ch.id, sender_id: userId, ciphertext, nonce, mac, format, reply_to: replyTo, mentions,
    }, "return=representation") as Row[];
    await Promise.all([
      db(`social_typing?channel_id=eq.${q(String(ch.id))}&user_key=eq.${q(userId)}`, "DELETE", undefined, "return=minimal"),
      db("social_reads?on_conflict=channel_id,user_key", "POST", { channel_id: ch.id, user_key: userId, last_read_at: new Date().toISOString() },
        "resolution=merge-duplicates,return=minimal"),
    ]);
    // avisa os celulares dos outros membros sem atrasar a resposta de quem enviou
    emSegundoPlano(avisarMembros(conversationId, String(ch.id), userId));
    return payload.channelId ? { message: { ...rows[0], reactions: [] } } : { ok: true };
  },

  async edit_message({ userId, payload }) {
    const m = await getMessage(uuid(payload.messageId, "Mensagem"));
    if (m.sender_id !== userId) fail("Você só pode editar as suas mensagens.", 403);
    if (m.deleted_at) fail("Essa mensagem foi apagada.");
    await requireMember(String(m.conversation_id), userId);
    const ciphertext = String(payload.ciphertext ?? "");
    if (!ciphertext || ciphertext.length > 24000 || !payload.nonce || !payload.mac) fail("Mensagem inválida.");
    const mentions = Array.isArray(payload.mentions) ? (payload.mentions as unknown[]).map(String).slice(0, 30) : m.mentions;
    const rows = await db(`social_messages?id=eq.${q(String(m.id))}&select=${MESSAGE_FIELDS}`, "PATCH", {
      ciphertext, nonce: String(payload.nonce), mac: String(payload.mac), format: 2, mentions, edited_at: new Date().toISOString(),
    }, "return=representation") as Row[];
    return { message: rows[0] };
  },

  async delete_message({ userId, payload }) {
    const m = await getMessage(uuid(payload.messageId, "Mensagem"));
    const conversationId = String(m.conversation_id);
    const eu = await poder(conversationId, userId);
    if (!eu) fail("Você não participa deste grupo.", 403);
    const conv = await getConversation(conversationId);
    const own = m.sender_id === userId;
    if (!own) {
      if (conv.group_kind === "dm" || !eu!.perms.has("apagar_mensagens")) fail("Você só pode apagar as suas mensagens.", 403);
      const sender = await poder(conversationId, String(m.sender_id));
      if (sender && sender.rank >= eu!.rank) fail("Você não pode apagar mensagens de alguém com cargo igual ou maior.", 403);
    }
    await db(`social_reactions?message_id=eq.${q(String(m.id))}`, "DELETE", undefined, "return=minimal");
    await db(`social_messages?id=eq.${q(String(m.id))}`, "PATCH",
      { ciphertext: "", nonce: "", mac: "", mentions: [], deleted_at: new Date().toISOString(), pinned_at: null, pinned_by: null }, "return=minimal");
    if (own && Array.isArray(payload.paths)) {
      const prefix = `att/${conversationId}/${await userHash(userId)}/`;
      const paths = (payload.paths as unknown[]).map(String).filter((p) => p.startsWith(prefix) && !p.includes("..")).slice(0, 20);
      if (paths.length) await storage(`object/${BUCKET}`, "DELETE", { prefixes: paths }).catch(() => null);
    }
    return { ok: true };
  },

  async react({ userId, payload }) {
    const m = await getMessage(uuid(payload.messageId, "Mensagem"));
    await requireMember(String(m.conversation_id), userId);
    if (m.deleted_at) fail("Essa mensagem foi apagada.");
    const emoji = str(payload.emoji, 16);
    if (!emoji) fail("Reação inválida.");
    if (payload.on === false) {
      await db(`social_reactions?message_id=eq.${q(String(m.id))}&user_key=eq.${q(userId)}&emoji=eq.${q(emoji)}`, "DELETE", undefined, "return=minimal");
    } else {
      const count = await db(`social_reactions?message_id=eq.${q(String(m.id))}&select=emoji`) as Row[];
      if (new Set(count.map((c) => c.emoji)).size >= 20 && !count.some((c) => c.emoji === emoji)) fail("Essa mensagem já tem reações demais.");
      await db("social_reactions?on_conflict=message_id,user_key,emoji", "POST", { message_id: m.id, user_key: userId, emoji },
        "resolution=ignore-duplicates,return=minimal");
    }
    return { ok: true };
  },

  async pin({ userId, payload }) {
    const m = await getMessage(uuid(payload.messageId, "Mensagem"));
    const eu = await poder(String(m.conversation_id), userId);
    if (!eu) fail("Você não participa deste grupo.", 403);
    const conv = await getConversation(String(m.conversation_id));
    if (conv.group_kind !== "dm" && !eu!.perms.has("fixar")) fail("Você não tem permissão para fixar mensagens.", 403);
    if (m.deleted_at) fail("Essa mensagem foi apagada.");
    const on = payload.pinned !== false;
    await db(`social_messages?id=eq.${q(String(m.id))}`, "PATCH",
      { pinned_at: on ? new Date().toISOString() : null, pinned_by: on ? userId : null }, "return=minimal");
    return { ok: true };
  },

  async pins({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requireMember(String(ch.conversation_id), userId);
    const rows = await db(`social_messages?channel_id=eq.${q(String(ch.id))}&pinned_at=not.is.null&deleted_at=is.null&select=${MESSAGE_FIELDS},social_reactions(emoji,user_key)&order=pinned_at.desc&limit=50`) as Row[];
    return await withRefs(rows);
  },

  async read({ userId, payload }) {
    const ch = await getChannel(uuid(payload.channelId, "Canal"));
    await requireMember(String(ch.conversation_id), userId);
    await db("social_reads?on_conflict=channel_id,user_key", "POST", { channel_id: ch.id, user_key: userId, last_read_at: new Date().toISOString() },
      "resolution=merge-duplicates,return=minimal");
    return { ok: true };
  },

  // --- arquivos
  async upload_url({ userId, payload }) {
    const kind = String(payload.kind);
    let path: string;
    const name = crypto.randomUUID();
    if (kind === "avatar") path = `avatar/${await userHash(userId)}/${name}.png`;
    else if (kind === "banner") path = `banner/${await userHash(userId)}/${name}.png`;
    else {
      const id = uuid(payload.conversationId, "Grupo");
      if (kind === "icon" || kind === "gbanner") {
        await requirePerm(id, userId, "gerenciar_grupo");
        path = `${kind}/${id}/${name}.png`;
      } else if (kind === "att") {
        await requireMember(id, userId);
        path = `att/${id}/${await userHash(userId)}/${name}.bin`;
      } else return fail("Tipo de arquivo inválido.");
    }
    const signed = await storage(`object/upload/sign/${BUCKET}/${path}`, "POST", {}) as Row;
    return { path, uploadUrl: `${supabaseUrl}/storage/v1${signed.url}` };
  },

  async download_urls({ userId, payload }) {
    const paths = Array.isArray(payload.paths) ? [...new Set((payload.paths as unknown[]).map(String))].slice(0, 60) : [];
    const ok: string[] = [];
    const memberCache = new Map<string, boolean>();
    for (const p of paths) {
      if (p.length > 200 || p.includes("..") || !/^(avatar|banner|att|icon|gbanner)\/[A-Za-z0-9_\-./]+$/.test(p)) continue;
      if (p.startsWith("avatar/") || p.startsWith("banner/")) {
        ok.push(p);
        continue;
      }
      const conv = p.split("/")[1];
      if (!memberCache.has(conv)) memberCache.set(conv, isUuid(conv) && !!(await getMember(conv, userId)));
      if (memberCache.get(conv)) ok.push(p);
    }
    if (!ok.length) return {};
    const signed = await storage(`object/sign/${BUCKET}`, "POST", { expiresIn: 3600, paths: ok }) as Row[];
    const out: Record<string, string> = {};
    for (const s of signed) if (s.signedURL && !s.error) out[String(s.path)] = `${supabaseUrl}/storage/v1${s.signedURL}`;
    return out;
  },

  // --- chaves por envelope
  async put_envelopes({ userId, payload }) {
    const me = await myProfile(userId);
    if (!me.public_key) fail("Seu aparelho ainda não registrou a chave pública.");
    const list = Array.isArray(payload.envelopes) ? (payload.envelopes as Row[]).slice(0, 100) : [];
    const rows: Row[] = [];
    const memberOk = new Map<string, boolean>();
    for (const e of list) {
      const conv = String(e.conversationId);
      const target = String(e.userKey);
      if (!isUuid(conv) || String(e.senderPublic) !== me.public_key) continue;
      if (!memberOk.has(conv)) memberOk.set(conv, !!(await getMember(conv, userId)));
      if (!memberOk.get(conv)) continue;
      const theirMember = await getMember(conv, target);
      if (!theirMember) continue;
      const prof = await db(`social_profiles?user_key=eq.${q(target)}&select=public_key`) as Row[];
      if (!prof[0] || prof[0].public_key !== e.recipientPublic) continue;
      rows.push({
        conversation_id: conv, user_key: target, recipient_public: String(e.recipientPublic), sender_public: me.public_key,
        sealed: str(e.sealed, 200), nonce: str(e.nonce, 40), mac: str(e.mac, 40),
      });
    }
    if (rows.length) {
      await db("social_key_envelopes?on_conflict=conversation_id,user_key,recipient_public", "POST", rows, "resolution=merge-duplicates,return=minimal");
    }
    return { saved: rows.length };
  },

  // --- professor (sempre revalida no AVA)
  async teacher_courses({ site, token, moodle }) {
    const courses = await moodleCall(site!, token!, "core_enrol_get_users_courses", { userid: moodle!.userId, returnusercount: false });
    const out: Array<{ id: number; name: string }> = [];
    for (const course of Array.isArray(courses) ? courses as Row[] : []) {
      const courseId = Number(course.id);
      if (!Number.isSafeInteger(courseId) || courseId <= 1) continue;
      try {
        const people = await courseUsers(site!, token!, courseId);
        const self = people.find((person) => Number(person.id) === moodle!.userId);
        if (self && hasTeacherRole(self)) out.push({ id: courseId, name: String(course.fullname ?? course.shortname ?? `Matéria ${courseId}`) });
      } catch (_) {
        // Sem permissão para consultar participantes, não habilitamos funções de professor.
      }
    }
    return out;
  },

  async create_course_group({ userId, payload, site, token, moodle, host }) {
    const courseId = Number(payload.courseId);
    const title = str(payload.title, 64);
    const inviteSecret = typeof payload.inviteSecret === "string" ? payload.inviteSecret : "";
    if (!Number.isSafeInteger(courseId) || courseId <= 1 || !title) fail("Matéria ou nome inválido.");
    const courses = await moodleCall(site!, token!, "core_enrol_get_users_courses", { userid: moodle!.userId, returnusercount: false });
    const course = (Array.isArray(courses) ? courses as Row[] : []).find((c) => Number(c.id) === courseId);
    if (!course) fail("Esta matéria não está associada à sua conta do AVA.");
    const people = await courseUsers(site!, token!, courseId);
    const teacher = people.find((person) => Number(person.id) === moodle!.userId);
    if (!teacher || !hasTeacherRole(teacher)) fail("O AVA não confirmou seu papel de professor nesta matéria.", 403);

    const id = await createConversation({
      title,
      description: optStr(payload.description, 300) ?? null,
      created_by: userId,
      invite_hash: inviteSecret.length >= 32 ? await sha256(inviteSecret) : null,
      group_kind: "course",
      moodle_course_id: courseId,
      moodle_course_name: String(course!.fullname ?? course!.shortname ?? title).slice(0, 120),
    }, userId, [{ name: "avisos", only_admins: true }, { name: "geral" }, { name: "dúvidas" }]);
    const unique = new Map<number, Row>();
    for (const person of people) {
      const pid = Number(person.id);
      if (Number.isSafeInteger(pid) && pid > 0 && pid !== moodle!.userId) unique.set(pid, person);
    }
    const members: Row[] = [];
    for (const [pid, person] of unique) {
      const memberKey = await socialUser(host!, pid, String(person.fullname ?? `Estudante ${pid}`), false);
      members.push({ conversation_id: id, user_key: memberKey, role: hasTeacherRole(person) ? "admin" : "member" });
    }
    for (let i = 0; i < members.length; i += 100) {
      await db("social_members?on_conflict=conversation_id,user_key", "POST", members.slice(i, i + 100), "resolution=ignore-duplicates,return=minimal");
    }
    return { conversationId: id, members: members.length + 1 };
  },
};

// ---------------------------------------------------------------- entrada
async function main(req: Request) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método não permitido." }, 405);
  let input: Row;
  try {
    const raw = await req.text();
    if (raw.length > 40000) return json({ error: "Requisição muito grande." }, 413);
    input = JSON.parse(raw);
  } catch (_) {
    return json({ error: "Requisição inválida." }, 400);
  }

  try {
    const action = String(input.action ?? "");
    const handler = actions[action];
    if (!handler) return json({ error: "Ação Social desconhecida." }, 400);
    const payload = (input.payload && typeof input.payload === "object") ? input.payload as Row : {};
    const ctx: Ctx = { userId: "", payload };

    const session = !moodleActions.has(action) && input.session ? await readSession(input.session) : null;
    if (session) {
      ctx.userId = session;
    } else {
      if (input.session && !input.token) fail("Sessão do Social expirada.", 401);
      ctx.site = siteOrigin(input.site);
      ctx.token = String(input.token ?? "");
      ctx.moodle = await validateMoodle(ctx.site, ctx.token);
      ctx.host = ctx.site.hostname.toLowerCase();
      ctx.userId = await socialUser(ctx.host, ctx.moodle.userId, ctx.moodle.displayName, true);
    }
    return json(await handler(ctx));
  } catch (error) {
    if (error instanceof HttpError) return json({ error: error.message }, error.status);
    console.error(error);
    const message = error instanceof Error ? error.message : "Erro ao acessar o Social.";
    return json({ error: message }, 500);
  }
}

Deno.serve(main);
