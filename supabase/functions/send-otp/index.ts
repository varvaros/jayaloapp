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
  generateOtpCode,
  sameWhatsappNumber,
} from "../_shared/otp.ts";

/** Copy común de los dos topes: ver el comentario del tope por número. */
const TOO_MANY = "Enviaste demasiados códigos. Inténtalo de nuevo más tarde.";

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
      return json({ error: TOO_MANY }, 429);
    }

    let q = admin
      .from("account_verifications")
      .select("id, whatsapp_last_sent_at, whatsapp_e164")
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
      // Este tope es GLOBAL por número, así que también es un arma: quien
      // conozca el teléfono de otro puede agotarlo y dejarlo sin poder darse de
      // alta. Por eso no se aprieta al mínimo que soporta el caso legítimo
      // (verificar número personal y de negocio con un reenvío cada uno = 4):
      // 10/hora sigue acotando el gasto en Twilio y encarece el bloqueo dirigido.
      _max: 10,
      _window_seconds: 3600,
    });
    // Mismo copy que el tope por usuario: uno distinto diría si el número está
    // siendo verificado por alguien más. Sin prometer plazo — las ventanas son
    // distintas (15 min por usuario, 1 hora por número) y "espera unos minutos"
    // era mentira en este segundo caso.
    if (!toErr && toAllowed === false) {
      return json({ error: TOO_MANY }, 429);
    }

    const code = generateOtpCode();
    // Si el número CAMBIA respecto al que había en la fila, el sello anterior
    // deja de aplicar: se refiere a otro teléfono. Sin esto, el par
    // (whatsapp_e164, whatsapp_verified_at) se desincroniza con solo PEDIR un
    // código y abandonarlo — la fila pasa a decir "el número Z está verificado
    // desde T0" cuando lo que se verificó fue A. Todo lo que lee ese par (el
    // gate de revelado y el sello del negocio) se lo creería.
    const numberChanged = existing != null &&
      !sameWhatsappNumber(existing.whatsapp_e164 as string | null, phone);
    const row = {
      whatsapp_e164: phone,
      whatsapp_otp_hash: await sha256Hex(code),
      whatsapp_otp_expires_at: new Date(Date.now() + OTP_TTL_MS).toISOString(),
      whatsapp_attempts: 0,
      whatsapp_last_sent_at: new Date().toISOString(),
      ...(numberChanged ? { whatsapp_verified_at: null } : {}),
    };

    // NO usar upsert/onConflict aquí. La unicidad de las filas PERSONALES la da
    // un índice PARCIAL (`account_verifications_personal_unique`: user_id WHERE
    // business_id IS NULL) — Postgres no puede inferirlo en `ON CONFLICT
    // (user_id)` y PostgREST no permite expresar el WHERE del índice, así que
    // devuelve 42P10 "no unique or exclusion constraint matching...". Ese es el
    // bug que dejó `account_verifications` con CERO filas personales en prod: la
    // verificación del cliente nunca se pudo sellar (y por eso
    // get_unlocked_offer_contact siempre lanzaba). Update-or-insert explícito:
    // El cooldown previo se guarda para poder DESHACERLO si el envío falla.
    const previousSentAt: string | null = existing?.whatsapp_last_sent_at ?? null;
    // Copy genérico en los 500: el mensaje crudo de PostgREST no le dice nada
    // al usuario y expone interioridades (misma política que `friendlyOtpError`).
    const saveFailed = "No pudimos preparar el código. Inténtalo de nuevo.";
    let rowId: string;
    if (existing) {
      // `.select()` para comprobar que de verdad se tocó la fila: si alguien la
      // borró entre el SELECT y este UPDATE, PostgREST devuelve 200 con cero
      // filas y sin error, y saldría un SMS con un código que no está guardado
      // en ninguna parte (verify-otp diría "No hay código pendiente").
      const { data: updated, error: upErr } = await admin
        .from("account_verifications").update(row).eq("id", existing.id)
        .select("id").maybeSingle();
      if (upErr || !updated) {
        console.error("send-otp: no se pudo actualizar account_verifications:",
          upErr?.message ?? "0 filas afectadas");
        return json({ error: saveFailed }, 500);
      }
      rowId = updated.id as string;
    } else {
      const { data: inserted, error: insErr } = await admin
        .from("account_verifications")
        .insert({ ...row, user_id: userId, business_id: businessId ?? null })
        .select("id")
        .single();
      if (insErr || !inserted?.id) {
        console.error("send-otp: no se pudo crear account_verifications:",
          insErr?.message ?? "sin id devuelto");
        return json({ error: saveFailed }, 500);
      }
      rowId = inserted.id as string;
    }

    // Devolver el canal REAL usado: el copy de la app lo sigue, así no miente
    // cuando app_settings.otp_channel cambie a 'whatsapp' (Twilio Sender).
    const channel = await getOtpChannel(admin);
    const hash = Deno.env.get("SMS_RETRIEVER_HASH") ?? null;
    if (channel === "sms" && !hash) {
      // Sin el hash, `buildOtpMessage` manda el SMS en formato normal (sin el
      // `<#>` ni la firma), y entonces Android NO se lo entrega a la app: el
      // autocompletado del código no puede funcionar, pase lo que pase en el
      // cliente. Degradaba en SILENCIO, que es justo lo que lo volvía
      // imposible de diagnosticar desde la app.
      console.error(
        "SMS_RETRIEVER_HASH no configurado: el SMS sale sin formato de Google " +
          "SMS Retriever y el autocompletado en Android queda inoperativo. " +
          "Configura el secreto con el hash de 11 caracteres de la firma de release.",
      );
    }
    try {
      await sendOtpMessage(admin, phone, buildOtpMessage(code, channel, hash));
    } catch (e) {
      // El envío falló: devolver `whatsapp_last_sent_at` a como estaba. Si no,
      // un fallo NUESTRO deja al usuario 60s bloqueado sin haber recibido nada.
      // Los topes por usuario y por número ya se consumieron y siguen
      // consumidos, así que esto no reabre el bypass de spam que motivó el
      // "persistir antes de enviar".
      const { error: rbErr } = await admin
        .from("account_verifications")
        .update({ whatsapp_last_sent_at: previousSentAt })
        .eq("id", rowId);
      if (rbErr) {
        // Sin esta traza, un rollback fallido deja al usuario 60s bloqueado
        // justo en el modo de fallo que este bloque existe para evitar.
        console.error("send-otp: falló el rollback del cooldown:", rbErr.message);
      }
      throw e;
    }
    return json({ ok: true, phone, channel });
  } catch (e) {
    // Todo lo que llega aquí ya trae copy apto para el usuario (teléfono
    // inválido, límites, y los mensajes de friendlyOtpError). Se registra
    // igual: si algún día cae un error inesperado, sin este log queda ciego.
    console.error("send-otp falló:", e instanceof Error ? e.stack ?? e.message : String(e));
    return json({ error: (e as Error).message ?? "No pudimos enviar el código." }, 500);
  }
});
