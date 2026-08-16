// Verificación del OTP para la app nativa (ADR-0030): intentos, expiración,
// sello de account_verifications y espejo del badge del negocio SOLO si el
// número verificado es el público (semántica exacta de la web).
import {
  adminClient,
  json,
  requireUser,
  ownsBusiness,
  sameWhatsappNumber,
  sha256Hex,
  MAX_ATTEMPTS,
} from "../_shared/otp.ts";

Deno.serve(async (req) => {
  try {
    const admin = adminClient();
    const userId = await requireUser(req, admin);
    if (!userId) return json({ error: "No autenticado" }, 401);

    const { code, business_id: businessId } = await req.json().catch(() => ({}));
    if (typeof code !== "string" || !/^\d{6}$/.test(code.trim())) {
      return json({ error: "Código inválido" }, 400);
    }
    if (businessId && !(await ownsBusiness(admin, userId, businessId))) {
      return json({ error: "No autorizado para este negocio" }, 403);
    }

    // Leer-comprobar-incrementar vivía aquí y no era atómico: dos peticiones
    // concurrentes leían el mismo `whatsapp_attempts` y ambas escribían el
    // mismo +1, así que el tope de 5 se rebasaba con solo lanzarlas en
    // paralelo. Ahora el ciclo entero ocurre en la base con la fila bloqueada.
    const { data: result, error: rpcErr } = await admin.rpc(
      "consume_whatsapp_otp_attempt",
      {
        _user_id: userId,
        _business_id: businessId ?? null,
        _code_hash: await sha256Hex(code.trim()),
        _max_attempts: MAX_ATTEMPTS,
      },
    );
    if (rpcErr) {
      // Antes el UPDATE del contador se hacía sin mirar el error: un fallo
      // transitorio se traducía en un intento gratis. Ahora se rechaza.
      console.error("verify-otp: falló la RPC del intento:", rpcErr.message);
      return json({ error: "No pudimos verificar el código. Inténtalo de nuevo." }, 500);
    }
    const outcome = (result ?? {}) as {
      status?: string;
      phone?: string | null;
      verified_at?: string;
      attempts_left?: number;
    };
    if (outcome.status === "no_pending") {
      return json({ error: "No hay código pendiente. Envía uno nuevo." }, 400);
    }
    if (outcome.status === "expired") {
      return json({ error: "El código expiró. Envía uno nuevo." }, 400);
    }
    if (outcome.status === "too_many") {
      return json({ error: "Demasiados intentos. Envía un código nuevo." }, 400);
    }
    if (outcome.status !== "ok") {
      // Los intentos restantes son del propio usuario, así que decírselos no
      // filtra nada y evita que el bloqueo le llegue de golpe y sin aviso.
      const left = outcome.attempts_left ?? 0;
      return json({
        error: left > 0
          ? `Código incorrecto. Te ${left === 1 ? "queda 1 intento" : `quedan ${left} intentos`}.`
          : "Código incorrecto",
      }, 400);
    }

    // Mismo instante que el sello de la fila: lo pone la RPC, no este proceso.
    const verifiedAt = outcome.verified_at ?? new Date().toISOString();
    const verifiedPhone = outcome.phone ?? null;

    let businessBadgeVerified = false;
    if (businessId) {
      const { data: biz, error: bizErr } = await admin
        .from("provider_businesses")
        .select("whatsapp")
        .eq("id", businessId)
        .maybeSingle();
      // Si no se pudo LEER el negocio, no se decide nada sobre su sello: con
      // `biz` nulo, `sameWhatsappNumber` da false para todo y el sello se
      // borraría por un fallo transitorio. El OTP en sí ya quedó sellado
      // arriba, así que se devuelve OK sin tocar el negocio.
      if (bizErr) {
        console.error("verify-otp: no se pudo leer el negocio:", bizErr.message);
        return json({ ok: true, phone: verifiedPhone, business_badge_verified: false });
      }
      businessBadgeVerified = sameWhatsappNumber(verifiedPhone, biz?.whatsapp ?? null);
      if (businessBadgeVerified) {
        await admin
          .from("provider_businesses")
          .update({ whatsapp_verified_at: verifiedAt })
          .eq("id", businessId);
      } else {
        // El número verificado NO es el público del negocio. Antes esto ponía
        // el sello a NULL sin más, así que verificar cualquier otro número
        // BORRABA un sello ya ganado. Solo se retira si ningún número
        // verificado del dueño respalda el número público de hoy (que es el
        // caso real que el borrado quería cubrir: cambiaron el público por uno
        // sin verificar).
        const { data: verifiedRows, error: vErr } = await admin
          .from("account_verifications")
          .select("whatsapp_e164")
          .eq("user_id", userId)
          .not("whatsapp_verified_at", "is", null);
        if (vErr) {
          // Lectura fallida ⇒ NO se toca el sello. Antes se descartaba este
          // error y un timeout de PostgREST bastaba para borrar estado
          // permanente: fallar hacia lo destructivo es el peor default aquí.
          console.error(
            "verify-otp: no se pudo comprobar el respaldo del sello:", vErr.message);
        } else {
          const stillBacked = (verifiedRows ?? []).some((v) =>
            sameWhatsappNumber(v.whatsapp_e164 as string | null, biz?.whatsapp ?? null)
          );
          if (!stillBacked) {
            await admin
              .from("provider_businesses")
              .update({ whatsapp_verified_at: null })
              .eq("id", businessId);
          }
        }
      }
    }
    return json({
      ok: true,
      phone: verifiedPhone,
      business_badge_verified: businessBadgeVerified,
    });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Error inesperado" }, 500);
  }
});
