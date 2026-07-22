// Auto-login al wallet web desde la app nativa (ADR-0031 + refinamiento
// 2026-07-17): la app NUNCA procesa pagos, pero puede evitarle al proveedor
// un segundo login manual generando un magic link de Supabase Auth hacia
// /provider/wallet. El pago sigue ocurriendo 100% en la web (PayPal), esto
// es solo un handoff de sesión.
import { adminClient, json, requireUser } from "../_shared/otp.ts";

const SITE_URL = "https://jayalo.com";

Deno.serve(async (req) => {
  try {
    const admin = adminClient();
    const userId = await requireUser(req, admin);
    if (!userId) return json({ error: "No autenticado" }, 401);

    const { data: userRes, error: userErr } = await admin.auth.admin.getUserById(userId);
    if (userErr || !userRes?.user?.email) {
      return json({ error: "No se pudo resolver el usuario" }, 500);
    }

    // `?from=app`: marca a la web que la sesión llegó DESDE la app nativa, para
    // que el wallet muestre el botón "Volver a la app" (deep link jayalo://wallet)
    // e intente el retorno automático tras recargar. Supabase preserva el query
    // en el 302 de /auth/v1/verify (no forma parte del match del allowlist); la
    // ruta base /provider/wallet ya está permitida porque el handoff funciona.
    const { data, error } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: userRes.user.email,
      options: { redirectTo: `${SITE_URL}/provider/wallet?from=app` },
    });
    if (error || !data?.properties?.action_link) {
      return json({ error: error?.message ?? "No se pudo generar el enlace" }, 500);
    }

    return json({ ok: true, url: data.properties.action_link });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Error inesperado" }, 500);
  }
});
