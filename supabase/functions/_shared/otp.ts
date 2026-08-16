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

/**
 * Código de 6 dígitos con CSPRNG. `Math.random()` NO sirve para esto: su estado
 * interno es predecible a partir de unas pocas salidas, así que quien observe
 * códigos propios puede anticipar los ajenos. El muestreo es por RECHAZO —
 * 2^32 no es múltiplo de 900000, y un `% 900000` a secas haría más probables
 * los primeros códigos del rango.
 */
export function generateOtpCode(): string {
  const buf = new Uint32Array(1);
  const limit = Math.floor(4294967296 / 900000) * 900000;
  let v: number;
  do {
    crypto.getRandomValues(buf);
    v = buf[0];
  } while (v >= limit);
  return String(100000 + (v % 900000));
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

/**
 * Traduce un código de error de Twilio a algo que el usuario pueda entender y
 * accionar. El mensaje crudo (`Twilio error [400] to number cannot be a…`) NO
 * debe llegar nunca a la pantalla: no dice qué hacer y expone al proveedor.
 * El detalle técnico queda en los logs del servidor (ver `sendOtpMessage`).
 * Códigos: https://www.twilio.com/docs/api/errors
 */
export function friendlyOtpError(code: number | null, channel: OtpChannel): string {
  const via = channel === "whatsapp" ? "WhatsApp" : "SMS";
  switch (code) {
    // El número no existe o está mal escrito.
    case 21211:
    case 21214:
    case 21212:
      return "Ese número no parece válido. Revísalo e inténtalo de nuevo.";
    // El número existe pero no recibe mensajes (fijo, VoIP, sin servicio).
    case 21614:
    case 21612:
    case 30006:
      return `Ese número no puede recibir ${via}. Parece un teléfono fijo: usa un celular.`;
    // País fuera de los permisos de envío de la cuenta.
    case 21408:
    case 21215:
      return "Todavía no podemos enviar mensajes a ese país.";
    // El usuario respondió STOP y quedó dado de baja.
    case 21610:
      return "Ese número bloqueó nuestros mensajes. Responde START al último " +
        "mensaje de Jayalo para volver a recibirlos.";
    // No se pudo entregar (apagado, sin señal, operador desconocido).
    case 30003:
    case 30005:
      return `No pudimos entregar el ${via}. Verifica que el número esté ` +
        "activo y con señal.";
    // Fallos de configuración NUESTROS: no culpar al usuario ni pedirle nada.
    case 21617:
    case 20003:
    case 21606:
    case 21266:
      return "No pudimos enviar el código por un problema de configuración " +
        "nuestro. Ya estamos al tanto: inténtalo más tarde.";
    default:
      return `No pudimos enviarte el código por ${via}. Revisa el número o ` +
        "inténtalo de nuevo en un minuto.";
  }
}

/** Deja solo los últimos 4 dígitos visibles (para logs sin PII completa). */
function maskPhone(v: string): string {
  return v.replace(/\d(?=\d{4})/g, "•");
}

export async function sendOtpMessage(admin: SupabaseClient, to: string, body: string) {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  if (!accountSid || !authToken) {
    console.error("TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN no configurados");
    throw new Error(
      "No pudimos enviar el código por un problema de configuración nuestro. " +
        "Ya estamos al tanto: inténtalo más tarde.",
    );
  }
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
    // El detalle técnico vive AQUÍ (logs del servidor), no en la pantalla del
    // usuario: sin esto, un fallo de Twilio se vuelve imposible de diagnosticar.
    console.error("Twilio rechazó el envío de OTP:", JSON.stringify({
      http: resp.status,
      code: j?.code ?? null,
      message: j?.message ?? null,
      more_info: j?.more_info ?? null,
      channel,
      to: maskPhone(toAddr),
      from: maskPhone(from),
    }));
    const code = typeof j?.code === "number" ? j.code : null;
    throw new Error(friendlyOtpError(code, channel));
  }
}
