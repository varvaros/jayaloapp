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

    let q = admin
      .from("account_verifications")
      .select(
        "id, whatsapp_otp_hash, whatsapp_otp_expires_at, whatsapp_attempts, whatsapp_e164",
      )
      .eq("user_id", userId);
    q = businessId ? q.eq("business_id", businessId) : q.is("business_id", null);
    const { data: row } = await q.maybeSingle();

    if (!row?.whatsapp_otp_hash) {
      return json({ error: "No hay código pendiente. Envía uno nuevo." }, 400);
    }
    if (
      row.whatsapp_otp_expires_at &&
      new Date(row.whatsapp_otp_expires_at).getTime() < Date.now()
    ) {
      return json({ error: "El código expiró. Envía uno nuevo." }, 400);
    }
    if ((row.whatsapp_attempts ?? 0) >= MAX_ATTEMPTS) {
      return json({ error: "Demasiados intentos. Envía un código nuevo." }, 400);
    }
    if ((await sha256Hex(code.trim())) !== row.whatsapp_otp_hash) {
      await admin
        .from("account_verifications")
        .update({ whatsapp_attempts: (row.whatsapp_attempts ?? 0) + 1 })
        .eq("id", row.id);
      return json({ error: "Código incorrecto" }, 400);
    }

    const verifiedAt = new Date().toISOString();
    await admin
      .from("account_verifications")
      .update({
        whatsapp_verified_at: verifiedAt,
        whatsapp_otp_hash: null,
        whatsapp_otp_expires_at: null,
        whatsapp_attempts: 0,
      })
      .eq("id", row.id);

    let businessBadgeVerified = false;
    if (businessId) {
      const { data: biz } = await admin
        .from("provider_businesses")
        .select("whatsapp")
        .eq("id", businessId)
        .maybeSingle();
      businessBadgeVerified = sameWhatsappNumber(row.whatsapp_e164, biz?.whatsapp ?? null);
      await admin
        .from("provider_businesses")
        .update({ whatsapp_verified_at: businessBadgeVerified ? verifiedAt : null })
        .eq("id", businessId);
    }
    return json({
      ok: true,
      phone: row.whatsapp_e164,
      business_badge_verified: businessBadgeVerified,
    });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Error inesperado" }, 500);
  }
});
