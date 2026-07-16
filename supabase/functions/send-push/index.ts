// Supabase Edge Function: send-push
// Deploy: --no-verify-jwt (la auth es x-webhook-secret, patrón de los webhooks
// internos de Jayalo). Secretos requeridos (supabase secrets set):
//   INTERNAL_WEBHOOK_SECRET  = mismo valor que app_settings.internal_webhook_secret
//   FCM_SERVICE_ACCOUNT      = JSON completo de la cuenta de servicio de Firebase
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta la plataforma.
import { createClient } from "npm:@supabase/supabase-js@2";

const enc = new TextEncoder();

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", enc.encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- OAuth2 para FCM HTTP v1 (JWT RS256 con la service account) ---
let cachedToken: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? enc.encode(data) : data;
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function fcmAccessToken(
  sa: { client_email: string; private_key: string },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----|\n/g, "");
  const keyData = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`)),
  );
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`OAuth FCM falló: ${JSON.stringify(json)}`);
  cachedToken = { token: json.access_token, exp: now + 3500 };
  return json.access_token;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("INTERNAL_WEBHOOK_SECRET") ?? "";
  const got = req.headers.get("x-webhook-secret") ?? "";
  if (!secret || (await sha256Hex(got)) !== (await sha256Hex(secret))) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const { user_id, kind, title, body, link } = await req.json();
    if (!user_id || !title) return new Response("bad request", { status: 400 });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: tokens } = await admin
      .from("device_tokens").select("token").eq("user_id", user_id);
    if (!tokens?.length) return new Response("no tokens", { status: 200 });

    // FCM_SERVICE_ACCOUNT puede ser el JSON crudo o (recomendado) base64 del
    // JSON — base64 es una sola línea sin caracteres que un editor de secretos
    // pueda mutilar (pegar el JSON multilínea corrompía las comillas/saltos).
    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) throw new Error("FCM_SERVICE_ACCOUNT no está configurado");
    const saJson = saRaw.trimStart().startsWith("{")
      ? saRaw
      : new TextDecoder().decode(
          // Quita TODO whitespace (saltos que un editor pudo intercalar al pegar)
          // antes de decodificar base64.
          Uint8Array.from(atob(saRaw.replace(/\s/g, "")), (c) => c.charCodeAt(0)),
        );
    const sa = JSON.parse(saJson);
    const access = await fcmAccessToken(sa);
    const results: string[] = [];

    for (const { token } of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: body ?? "" },
              data: { link: link ?? "", kind: kind ?? "" },
              android: { priority: "HIGH" },
            },
          }),
        },
      );
      const respBody = await res.text();
      if (res.status === 404 || res.status === 400) {
        // Token muerto (UNREGISTERED/INVALID) → limpiar.
        await admin.from("device_tokens").delete().eq("token", token);
        results.push(`dead:${res.status}:${respBody.slice(0, 120)}`);
      } else if (res.status !== 200) {
        results.push(`err:${res.status}:${respBody.slice(0, 200)}`);
      } else {
        results.push(`sent:${res.status}`);
      }
    }
    return new Response(JSON.stringify({ ok: true, results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("send-push error:", e);
    return new Response(
      JSON.stringify({ ok: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
