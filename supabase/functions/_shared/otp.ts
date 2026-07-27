// Lógica compartida del OTP nativo (ADR-0030). Port 1:1 del hardening de
// jayalo-main: src/lib/whatsapp-otp.functions.ts + otpChannel.ts + phone.ts.
// Todo cambio de hardening debe aplicarse también allá (deuda registrada en la ADR).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const OTP_TTL_MS = 10 * 60 * 1000;
export const MAX_ATTEMPTS = 5;
export const RESEND_COOLDOWN_MS = 60 * 1000;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01/Accounts";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/** userId del Bearer token, o null. */
export async function requireUser(
  req: Request,
  admin: SupabaseClient,
): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const { data, error } = await admin.auth.getUser(auth.slice(7));
  if (error || !data?.user) return null;
  return data.user.id;
}

/**
 * El negocio debe ser del usuario (anti-IDOR). SELECT directo con service role:
 * la RPC owns_business decide por auth.uid(), que bajo service role es NULL y
 * devolvería false siempre — NO usarla aquí.
 */
export async function ownsBusiness(
  admin: SupabaseClient,
  userId: string,
  businessId: string,
): Promise<boolean> {
  const { data } = await admin
    .from("provider_businesses")
    .select("user_id")
    .eq("id", businessId)
    .maybeSingle();
  return data?.user_id === userId;
}

// ── ports 1:1 de jayalo-main (phone.ts / otpChannel.ts) ─────────────────────

export function normalizePhone(raw: string): string {
  const t = raw.replace(/[^\d+]/g, "");
  if (!t) return "";
  if (t.startsWith("+")) return t;
  if (t.length === 10) return `+1${t}`;
  return t;
}

export function normalizePhoneStrict(raw: string): string {
  let v = normalizePhone(raw);
  if (!v) throw new Error("Teléfono inválido");
  if (!v.startsWith("+")) v = "+" + v;
  if (!/^\+\d{8,15}$/.test(v)) throw new Error("Teléfono inválido (formato E.164)");
  return v;
}

export function toWhatsappDigits(raw: string): string {
  return normalizePhone(raw).replace(/^\+/, "");
}

export function sameWhatsappNumber(a?: string | null, b?: string | null): boolean {
  if (!a || !b) return false;
  const da = toWhatsappDigits(a);
  const db = toWhatsappDigits(b);
  return da.length > 0 && da === db;
}

export type OtpChannel = "sms" | "whatsapp";

export function parseOtpChannel(value: unknown): OtpChannel {
  let v: unknown = value;
  if (v && typeof v === "object" && "channel" in (v as object)) {
    v = (v as { channel: unknown }).channel;
  }
  return typeof v === "string" && v.trim().toLowerCase() === "sms" ? "sms" : "whatsapp";
}

export function buildOtpAddresses(channel: OtpChannel, fromRaw: string, toE164: string) {
  const bareFrom = fromRaw.replace(/^whatsapp:/i, "");
  const bareTo = toE164.replace(/^whatsapp:/i, "");
  return channel === "sms"
    ? { from: bareFrom, to: bareTo }
    : { from: `whatsapp:${bareFrom}`, to: `whatsapp:${bareTo}` };
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function getOtpChannel(admin: SupabaseClient): Promise<OtpChannel> {
  const { data } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "otp_channel")
    .maybeSingle();
  return parseOtpChannel(data?.value ?? Deno.env.get("OTP_CHANNEL"));
}

/**
 * Cuerpo del SMS/WhatsApp del OTP. Con canal SMS y hash presente, usa el formato
 * de Google SMS Retriever (autofill Android): `<#>` al inicio, el código en el
 * cuerpo, y el hash de 11 chars en la última línea; todo ≤140 bytes.
 */
export function buildOtpMessage(
  code: string,
  channel: OtpChannel,
  smsRetrieverHash: string | null,
): string {
  if (channel === "sms" && smsRetrieverHash) {
    return `<#> Tu codigo Jayalo es ${code}. Vence en 10 min.\n${smsRetrieverHash}`;
  }
  return `Tu código de verificación Jayalo: ${code}\n\nVence en 10 minutos.`;
}

export async function sendOtpMessage(admin: SupabaseClient, to: string, body: string) {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  if (!accountSid || !authToken) throw new Error("Twilio no está configurado");
  const channel = await getOtpChannel(admin);
  const { data } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "twilio_whatsapp_from")
    .maybeSingle();
  const base =
    ((data?.value as Record<string, unknown> | null)?.from as string | undefined) ||
    Deno.env.get("TWILIO_WHATSAPP_FROM") ||
    "+14155238886";
  const fromRaw = channel === "sms" ? (Deno.env.get("TWILIO_SMS_FROM") || base) : base;
  const { from, to: toAddr } = buildOtpAddresses(channel, fromRaw, to);
  const resp = await fetch(`${TWILIO_API_BASE}/${accountSid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ To: toAddr, From: from, Body: body }),
  });
  const j = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    throw new Error(`Twilio error [${resp.status}] ${j?.message ?? j?.code ?? "desconocido"}`);
  }
}
