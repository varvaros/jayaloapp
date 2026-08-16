// Envío de OTP por SMS/WhatsApp para la app nativa (ADR-0030).
// Mismo orden de guards que la web: rate limit → cooldown → PERSISTIR ANTES
// de enviar (cierra el bypass de spam) → Twilio.
import {
  adminClient,
  json,
  requireUser,
  ownsBusiness,
  normalizePhoneStrict,
  sha256Hex,
  OTP_TTL_MS,
  RESEND_COOLDOWN_MS,
  sendOtpMessage,
  getOtpChannel,
  buildOtpMessage,
} from "../_shared/otp.ts";

Deno.serve(async (req) => {
  try {
    const admin = adminClient();
    const userId = await requireUser(req, admin);
    if (!userId) return json({ error: "No autenticado" }, 401);

    const { phone: rawPhone, business_id: businessId } = await req.json().catch(() => ({}));
    if (typeof rawPhone !== "string" || rawPhone.trim().length < 7) {
      return json({ error: "Teléfono inválido" }, 400);
    }
    let phone: string;
    try {
      phone = normalizePhoneStrict(rawPhone);
    } catch (e) {
      return json({ error: (e as Error).message }, 400);
    }
    if (businessId && !(await ownsBusiness(admin, userId, businessId))) {
      return json({ error: "No autorizado para este negocio" }, 403);
    }

    // Tope por usuario (anti toll-fraud); fail-open si el limiter falla en BD.
    const { data: allowed, error: rlErr } = await admin.rpc("try_consume_rate_limit", {
      _bucket: `wa_otp_send:${userId}`,
      _max: 5,
      _window_seconds: 900,
    });
    if (!rlErr && allowed === false) {
      return json(
        { error: "Enviaste demasiados códigos. Espera unos minutos e intenta de nuevo." },
        429,
      );
    }

    let q = admin
      .from("account_verifications")
      .select("id, whatsapp_last_sent_at")
      .eq("user_id", userId);
    q = businessId ? q.eq("business_id", businessId) : q.is("business_id", null);
    const { data: existing } = await q.maybeSingle();
    if (existing?.whatsapp_last_sent_at) {
      const last = new Date(existing.whatsapp_last_sent_at).getTime();
      if (Date.now() - last < RESEND_COOLDOWN_MS) {
        const wait = Math.ceil((RESEND_COOLDOWN_MS - (Date.now() - last)) / 1000);
        return json({ error: `Espera ${wait}s antes de reenviar el código` }, 429);
      }
    }

    // Tope por NÚMERO DESTINO, además del tope por usuario de arriba. Sin este,
    // el cupo se estrena entero con cada cuenta nueva: juntando cuentas se puede
    // dirigir SMS ilimitados al mismo teléfono (SMS-pumping — cada envío nos
    // cuesta dinero en Twilio, y al dueño del número lo acosa). Va después del
    // cooldown para que los reintentos que el cooldown ya rechazó no gasten el
    // cupo del destino. La clave se HASHEA: `api_rate_limits.bucket` es texto
    // plano y no hay razón para dejar teléfonos ahí.
    const phoneKey = (await sha256Hex(`wa_otp_to:${phone}`)).slice(0, 32);
    const { data: toAllowed, error: toErr } = await admin.rpc("try_consume_rate_limit", {
      _bucket: `wa_otp_to:${phoneKey}`,
      // 6/hora cubre el caso legítimo más largo (verificar el número personal y
      // el del negocio, con un reenvío cada uno) sin dejar margen al abuso.
      _max: 6,
      _window_seconds: 3600,
    });
    // Mismo copy que el tope por usuario a propósito: un mensaje distinto según
    // el teléfono convertiría esto en un oráculo de qué números se están usando.
    if (!toErr && toAllowed === false) {
      return json(
        { error: "Enviaste demasiados códigos. Espera unos minutos e intenta de nuevo." },
        429,
      );
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const row = {
      whatsapp_e164: phone,
      whatsapp_otp_hash: await sha256Hex(code),
      whatsapp_otp_expires_at: new Date(Date.now() + OTP_TTL_MS).toISOString(),
      whatsapp_attempts: 0,
      whatsapp_last_sent_at: new Date().toISOString(),
    };

    // NO usar upsert/onConflict aquí. La unicidad de las filas PERSONALES la da
    // un índice PARCIAL (`account_verifications_personal_unique`: user_id WHERE
    // business_id IS NULL) — Postgres no puede inferirlo en `ON CONFLICT
    // (user_id)` y PostgREST no permite expresar el WHERE del índice, así que
    // devuelve 42P10 "no unique or exclusion constraint matching...". Ese es el
    // bug que dejó `account_verifications` con CERO filas personales en prod: la
    // verificación del cliente nunca se pudo sellar (y por eso
    // get_unlocked_offer_contact siempre lanzaba). Update-or-insert explícito:
    const { error: upErr } = existing
        ? await admin.from("account_verifications").update(row).eq("id", existing.id)
        : await admin.from("account_verifications").insert({
            ...row,
            user_id: userId,
            business_id: businessId ?? null,
          });
    if (upErr) return json({ error: upErr.message }, 500);

    // Devolver el canal REAL usado: el copy de la app lo sigue, así no miente
    // cuando app_settings.otp_channel cambie a 'whatsapp' (Twilio Sender).
    const channel = await getOtpChannel(admin);
    const hash = Deno.env.get("SMS_RETRIEVER_HASH") ?? null;
    await sendOtpMessage(admin, phone, buildOtpMessage(code, channel, hash));
    return json({ ok: true, phone, channel });
  } catch (e) {
    // Todo lo que llega aquí ya trae copy apto para el usuario (teléfono
    // inválido, límites, y los mensajes de friendlyOtpError). Se registra
    // igual: si algún día cae un error inesperado, sin este log queda ciego.
    console.error("send-otp falló:", e instanceof Error ? e.stack ?? e.message : String(e));
    return json({ error: (e as Error).message ?? "No pudimos enviar el código." }, 500);
  }
});
