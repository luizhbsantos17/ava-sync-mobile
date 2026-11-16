// Push do Social pelo Firebase Cloud Messaging (API HTTP v1).
//
// Só manda um AVISO, sem conteúdo: { tipo: "social", conversa, canal }. O aparelho acorda,
// busca as mensagens cifradas, decifra com a chave da conversa e monta a notificação com
// quem mandou e o texto. O Google nunca vê o texto nem quem mandou.
//
// Configuração: o segredo FCM_SERVICE_ACCOUNT da Edge Function guarda o JSON da conta de
// serviço do Firebase (Configurações do projeto > Contas de serviço > Gerar chave). Sem ele,
// o push fica desligado e o resto do Social funciona normalmente.

type Conta = { project_id: string; client_email: string; private_key: string };

let conta: Conta | null | undefined;
let acesso: { token: string; ate: number } | null = null;

function lerConta(): Conta | null {
  if (conta !== undefined) return conta;
  try {
    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    const c = raw ? JSON.parse(raw) : null;
    conta = c?.project_id && c?.client_email && c?.private_key ? c : null;
  } catch (_) {
    conta = null;
  }
  return conta;
}

export function pushConfigurado() {
  return lerConta() !== null;
}

function base64url(bytes: Uint8Array | string) {
  const b = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemParaDer(pem: string) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/// Token OAuth do Google (válido ~1 h), guardado enquanto a função estiver quente.
async function tokenDeAcesso(c: Conta) {
  const agora = Math.floor(Date.now() / 1000);
  if (acesso && acesso.ate > agora + 60) return acesso.token;
  const cab = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = base64url(JSON.stringify({
    iss: c.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: agora,
    exp: agora + 3600,
  }));
  const chave = await crypto.subtle.importKey(
    "pkcs8", pemParaDer(c.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const assinatura = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", chave, new TextEncoder().encode(`${cab}.${corpo}`)));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${cab}.${corpo}.${base64url(assinatura)}`,
    }),
  });
  if (!r.ok) throw new Error(`OAuth do Firebase respondeu ${r.status}`);
  const j = await r.json();
  acesso = { token: String(j.access_token), ate: agora + Number(j.expires_in ?? 3600) };
  return acesso.token;
}

/// Manda o aviso para cada token. Devolve os tokens que o Firebase disse que não valem
/// mais (app desinstalado, dados apagados), para a função apagar.
export async function enviarPush(tokens: string[], dados: Record<string, string>): Promise<string[]> {
  const c = lerConta();
  if (!c || !tokens.length) return [];
  const bearer = await tokenDeAcesso(c);
  const invalidos: string[] = [];
  await Promise.all(tokens.map(async (token) => {
    try {
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${c.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            data: dados,
            // prioridade alta: o Android acorda o app mesmo em economia de bateria
            android: { priority: "HIGH", ttl: "3600s", collapse_key: dados.conversa ?? "social" },
          },
        }),
      });
      if (r.status === 404 || r.status === 400) {
        const t = await r.text();
        if (t.includes("UNREGISTERED") || t.includes("INVALID_ARGUMENT")) invalidos.push(token);
      }
    } catch (_) {
      // sem internet do lado do servidor: a próxima mensagem tenta de novo
    }
  }));
  return invalidos;
}
