const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
});

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const allowedHosts = new Set([
  "ava3.cefor.ifes.edu.br",
  "ava.cefor.ifes.edu.br",
  "ava.ifes.edu.br",
]);

function siteOrigin(raw: unknown): URL {
  if (typeof raw !== "string") throw new Error("Endereço do AVA ausente.");
  const url = new URL(raw);
  if (url.protocol !== "https:" || !allowedHosts.has(url.hostname.toLowerCase()) || (url.pathname !== "/" && url.pathname !== "")) {
    throw new Error("Este recurso aceita somente o AVA oficial do Ifes.");
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
  if (!response.ok) throw new Error("O AVA recusou a validação da conta.");
  const value = await response.json();
  if (!value || typeof value !== "object" || value.exception || value.errorcode) {
    throw new Error("O token do AVA expirou ou não tem acesso ao serviço necessário.");
  }
  return value;
}

async function validateMoodle(site: URL, token: string) {
  if (!token || token.length > 4096) throw new Error("Entre novamente no AVA para usar o Social.");
  const info = await moodleCall(site, token, "core_webservice_get_site_info") as Record<string, unknown>;
  const userId = Number(info.userid);
  if (!Number.isSafeInteger(userId) || userId <= 0) throw new Error("Não foi possível identificar a conta do AVA.");
  return { userId, displayName: String(info.fullname ?? "Estudante").slice(0, 48) };
}

async function db(path: string, method = "GET", body?: unknown, prefer?: string) {
  const headers: Record<string, string> = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    Accept: "application/json",
  };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (prefer) headers.Prefer = prefer;
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(12000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Falha no banco Social (${response.status}): ${text.slice(0, 180)}`);
  return text ? JSON.parse(text) : null;
}

function hex(bytes: ArrayBuffer) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

async function socialUser(host: string, moodleUserId: number, displayName: string) {
  const userKey = `${host}:${moodleUserId}`;
  const hostCode = (await sha256(host)).slice(0, 6);
  const username = `ifes_${hostCode}_${moodleUserId}`.slice(0, 24).toLowerCase();
  await db("social_profiles?on_conflict=user_key", "POST", {
    user_key: userKey,
    username,
    display_name: displayName.trim().slice(0, 48) || "Estudante",
  }, "resolution=merge-duplicates,return=minimal");
  return userKey;
}

async function requireMember(conversationId: string, userId: string) {
  const rows = await db(`social_members?conversation_id=eq.${encodeURIComponent(conversationId)}&user_key=eq.${encodeURIComponent(userId)}&select=user_key`);
  if (!Array.isArray(rows) || rows.length === 0) throw new Error("Você não participa deste grupo.");
}

async function lastMessages(conversationIds: string[]) {
  const result = new Map<string, Record<string, unknown>>();
  for (const id of conversationIds) {
    const rows = await db(`social_messages?conversation_id=eq.${id}&select=*&order=created_at.desc&limit=1`) as Array<Record<string, unknown>>;
    if (rows[0]) result.set(id, rows[0]);
  }
  const senderIds = [...new Set([...result.values()].map((m) => String(m.sender_id)))];
  if (senderIds.length) {
    const profiles = await db(`social_profiles?user_key=in.(${senderIds.map(encodeURIComponent).join(",")})&select=user_key,display_name`) as Array<Record<string, unknown>>;
    const names = new Map(profiles.map((p) => [String(p.user_key), String(p.display_name)]));
    for (const message of result.values()) message.sender_name = names.get(String(message.sender_id)) ?? "Colega";
  }
  return result;
}

async function conversations(userId: string) {
  const members = await db(`social_members?user_key=eq.${encodeURIComponent(userId)}&select=conversation_id&order=joined_at.desc`) as Array<{ conversation_id: string }>;
  const ids = [...new Set(members.map((m) => m.conversation_id))];
  if (!ids.length) return [];
  const rows = await db(`social_conversations?id=in.(${ids.join(",")})&select=id,title,created_at,group_kind,moodle_course_id,moodle_course_name&order=created_at.desc`) as Array<Record<string, unknown>>;
  const latest = await lastMessages(ids);
  return rows.map((row) => ({ ...row, last_message: latest.get(String(row.id)) ?? null }));
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

async function main(req: Request) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método não permitido." }, 405);
  let input: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > 40000) return json({ error: "Requisição muito grande." }, 413);
    input = JSON.parse(raw);
  } catch (_) {
    return json({ error: "Requisição inválida." }, 400);
  }

  try {
    const site = siteOrigin(input.site);
    const token = String(input.token ?? "");
    const moodle = await validateMoodle(site, token);
    const host = site.hostname.toLowerCase();
    const userId = await socialUser(host, moodle.userId, moodle.displayName);
    const payload = (input.payload && typeof input.payload === "object") ? input.payload as Record<string, unknown> : {};
    const action = String(input.action ?? "");

    if (action === "me") return json({ id: userId, name: moodle.displayName });
    if (action === "list") return json(await conversations(userId));
    if (action === "messages") {
      const conversationId = String(payload.conversationId ?? "");
      await requireMember(conversationId, userId);
      const rows = await db(`social_messages?conversation_id=eq.${encodeURIComponent(conversationId)}&select=*&order=created_at.asc&limit=200`) as Array<Record<string, unknown>>;
      const senderIds = [...new Set(rows.map((m) => String(m.sender_id)))];
      const profiles = senderIds.length
        ? await db(`social_profiles?user_key=in.(${senderIds.map(encodeURIComponent).join(",")})&select=user_key,display_name`) as Array<Record<string, unknown>>
        : [];
      const names = new Map(profiles.map((p) => [String(p.user_key), String(p.display_name)]));
      return json(rows.map((row) => ({ ...row, sender_name: names.get(String(row.sender_id)) ?? "Colega" })));
    }
    if (action === "create_group") {
      const title = String(payload.title ?? "").trim();
      const inviteSecret = String(payload.inviteSecret ?? "");
      if (!title || title.length > 64 || inviteSecret.length < 32 || inviteSecret.length > 128) throw new Error("Nome ou convite do grupo inválido.");
      const rows = await db("social_conversations", "POST", {
        title,
        created_by: userId,
        invite_hash: await sha256(inviteSecret),
        group_kind: "friends",
      }, "return=representation");
      const groupId = String(rows[0].id);
      await db("social_members", "POST", { conversation_id: groupId, user_key: userId }, "return=minimal");
      return json({ conversationId: groupId });
    }
    if (action === "join_group") {
      const conversationId = String(payload.conversationId ?? "");
      const inviteSecret = String(payload.inviteSecret ?? "");
      const rows = await db(`social_conversations?id=eq.${encodeURIComponent(conversationId)}&select=invite_hash,group_kind`) as Array<{ invite_hash: string; group_kind: string }>;
      if (!rows[0] || rows[0].invite_hash !== await sha256(inviteSecret)) throw new Error("Convite inválido ou expirado.");
      if (rows[0].group_kind === "course") {
        await requireMember(conversationId, userId);
      }
      await db("social_members?on_conflict=conversation_id,user_key", "POST", {
        conversation_id: conversationId,
        user_key: userId,
      }, "resolution=merge-duplicates,return=minimal");
      return json({ ok: true });
    }
    if (action === "send_message") {
      const conversationId = String(payload.conversationId ?? "");
      await requireMember(conversationId, userId);
      const ciphertext = String(payload.ciphertext ?? "");
      const nonce = String(payload.nonce ?? "");
      const mac = String(payload.mac ?? "");
      if (!ciphertext || ciphertext.length > 24000 || !nonce || !mac) throw new Error("Mensagem inválida.");
      await db("social_messages", "POST", { conversation_id: conversationId, sender_id: userId, ciphertext, nonce, mac }, "return=minimal");
      return json({ ok: true });
    }
    if (action === "teacher_courses") {
      const courses = await moodleCall(site, token, "core_enrol_get_users_courses", { userid: moodle.userId, returnusercount: false });
      const out: Array<{ id: number; name: string }> = [];
      for (const course of Array.isArray(courses) ? courses as Array<Record<string, unknown>> : []) {
        const courseId = Number(course.id);
        if (!Number.isSafeInteger(courseId) || courseId <= 1) continue;
        try {
          const people = await courseUsers(site, token, courseId);
          const self = people.find((person) => Number(person.id) === moodle.userId);
          if (self && hasTeacherRole(self)) out.push({ id: courseId, name: String(course.fullname ?? course.shortname ?? `Matéria ${courseId}`) });
        } catch (_) {
          // Sem permissão para consultar participantes, não habilitamos funções de professor.
        }
      }
      return json(out);
    }
    if (action === "create_course_group") {
      const courseId = Number(payload.courseId);
      const title = String(payload.title ?? "").trim();
      const inviteSecret = String(payload.inviteSecret ?? "");
      if (!Number.isSafeInteger(courseId) || courseId <= 1 || !title || title.length > 64 || inviteSecret.length < 32 || inviteSecret.length > 128) {
        throw new Error("Matéria, nome ou convite inválido.");
      }
      const courses = await moodleCall(site, token, "core_enrol_get_users_courses", { userid: moodle.userId, returnusercount: false });
      const course = (Array.isArray(courses) ? courses as Array<Record<string, unknown>> : []).find((c) => Number(c.id) === courseId);
      if (!course) throw new Error("Esta matéria não está associada à sua conta do AVA.");
      const people = await courseUsers(site, token, courseId);
      const teacher = people.find((person) => Number(person.id) === moodle.userId);
      if (!teacher || !hasTeacherRole(teacher)) throw new Error("O AVA não confirmou seu papel de professor nesta matéria.");

      const courseName = String(course.fullname ?? course.shortname ?? title).slice(0, 120);
      const created = await db("social_conversations", "POST", {
        title,
        created_by: userId,
        invite_hash: await sha256(inviteSecret),
        group_kind: "course",
        moodle_course_id: courseId,
        moodle_course_name: courseName,
      }, "return=representation");
      const groupId = String(created[0].id);
      const uniquePeople = new Map<number, Record<string, unknown>>();
      for (const person of people) {
        const id = Number(person.id);
        if (Number.isSafeInteger(id) && id > 0) uniquePeople.set(id, person);
      }
      const members: Array<{ conversation_id: string; user_key: string }> = [];
      for (const [id, person] of uniquePeople) {
        const name = String(person.fullname ?? `Estudante ${id}`).trim().slice(0, 48);
        const memberKey = await socialUser(host, id, name);
        members.push({ conversation_id: groupId, user_key: memberKey });
      }
      for (let i = 0; i < members.length; i += 100) {
        await db("social_members?on_conflict=conversation_id,user_key", "POST", members.slice(i, i + 100), "resolution=merge-duplicates,return=minimal");
      }
      return json({ conversationId: groupId, members: members.length });
    }
    return json({ error: "Ação Social desconhecida." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erro ao acessar o Social.";
    const status = /token|entre novamente|recusou a validação/i.test(message) ? 401 : 400;
    return json({ error: message }, status);
  }
}

Deno.serve(main);
