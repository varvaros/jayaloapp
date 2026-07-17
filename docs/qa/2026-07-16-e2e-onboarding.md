# E2E onboarding nativo — runbook (preparado 2026-07-16)

**Estado (actualizado 2026-07-17):** la app está lista e instalada en el Redmi (build debug con
los 9 commits del plan).

- ✅ **Edge Functions DESPLEGADAS y vivas** (`send-otp`, `verify-otp`): verificado con curl —
  ambas responden `401 UNAUTHORIZED_NO_AUTH_HEADER` sin token (gateway `verify_jwt` activo).
- ✅ **`can_reveal_offer_whatsapp` existe en prod** y `anon` está bloqueado (`42501`) → la RPC
  que usa el fix de dinero (Task 9) está disponible.
- ⛔ **RPC `complete_provider_onboarding` NO aplicada**: verificado vía PostgREST →
  `PGRST202 Could not find the function`. El clasificador de auto-mode bloquea la escritura a
  la BD de prod (exige confirmación nombrada por migración). **Paso 1 de abajo, [PO].**
- ⛔ **Secretos Twilio ausentes en Supabase** (`secrets list` no los tiene). El `.env` local
  tiene `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN` **vacíos** y los del Worker de Cloudflare son
  de solo-escritura (no recuperables) → los valores debe ponerlos el PO desde la consola de
  Twilio. **Paso 2 de abajo, [PO].**

Sin los pasos 1 y 2, el onboarding de proveedor y el OTP fallan en runtime aunque la app los
muestre. El resto del ciclo (consumidor, fixes de dinero) sí funciona ya.

## Paso 0 — Backend [PO o sesión con MCP autorizado]

1. **Aplicar la migración de la RPC** — dashboard de Supabase (`mfaiklvobnvgusbcssbx`) → SQL
   editor → pegar completo
   `jayalo-main/supabase/migrations/20260717000000_complete_provider_onboarding.sql` → Run.
   Verificar sin residuo (plan Task 1 Step 4):

   ```sql
   BEGIN;
   SET LOCAL role authenticated;
   SET LOCAL request.jwt.claims TO '{"sub":"<uuid cuenta QA>","role":"authenticated"}';
   SELECT public.complete_provider_onboarding('QA','Onboarding','+18090000001',
     '{"name":"Negocio QA","offers":"productos","category_ids":["hogar"],"rubros":[],
       "whatsapp":"+18090000001","city":"Santo Domingo","business_type":"informal",
       "sector":"","country":"República Dominicana","address":"","description":"","rnc":"",
       "profession":"","experience_years":"","logo_url":"","owner_photo_url":"",
       "is_wholesale":false}'::jsonb, '2.0');
   -- 2ª llamada: already=true con el MISMO business_id
   SELECT public.complete_provider_onboarding('QA','Onboarding','+18090000001',
     '{"name":"Negocio QA"}'::jsonb, '2.0');
   SELECT balance FROM provider_wallets WHERE user_id = '<uuid cuenta QA>';
   ROLLBACK;
   ```

   Y correr el check #11 de `scripts/db-security-check.sql` (debe devolver 0 filas).

2. **Secretos Twilio para las Edge Functions.** Solo hacen falta **DOS**: `TWILIO_ACCOUNT_SID`
   y `TWILIO_AUTH_TOKEN` (el número emisor sale de `app_settings.twilio_whatsapp_from`, que ya
   está poblado y es el que la web usa hoy para SMS — por eso `TWILIO_SMS_FROM` no es
   necesario). Los valores están en la **consola de Twilio** (los del Worker no se pueden leer;
   el `.env` local los tiene vacíos). Cargarlos **desde archivo por CLI**, nunca pegándolos en
   el dashboard (gotcha de corrupción de `FCM_SERVICE_ACCOUNT`):

   ```bash
   # archivo temporal FUERA del repo, con las 2 líneas TWILIO_ACCOUNT_SID=... / TWILIO_AUTH_TOKEN=...
   npx supabase secrets set --env-file %TEMP%\twilio.env --project-ref mfaiklvobnvgusbcssbx
   del %TEMP%\twilio.env
   ```

   Verificar después: `npx supabase secrets list --project-ref mfaiklvobnvgusbcssbx` debe
   listar ambos.

3. ~~**Deploy de las funciones**~~ ✅ **YA HECHO** (2026-07-17). Para redeployar tras un cambio:

   ```bash
   npx supabase functions deploy send-otp --project-ref mfaiklvobnvgusbcssbx
   npx supabase functions deploy verify-otp --project-ref mfaiklvobnvgusbcssbx
   ```

## Checklist E2E (criterios del spec §11) — en el Redmi, APK debug ya instalado

Cuentas: idealmente 2 cuentas Google NUEVAS (o poner `account_type=NULL` a las QA por SQL y
borrar su negocio/wallet/verificación para simular cuenta virgen — restaurar al final).

- [ ] **Consumidor nuevo end-to-end**: login Google → gate → selector → "Quiero pedir" →
      nombre precargado de Google → WhatsApp → "Usar mi ubicación" (permiso real) → dirección →
      términos → aterriza en `/client`. Reabrir la app → directo a `/client`.
- [ ] **Banner cerrable**: crear solicitud → banner "Confirma tu WhatsApp…" visible →
      "Ahora no" lo cierra y NO bloquea el envío → nueva solicitud → banner reaparece →
      "Confirmar ahora" → SMS real llega → código → "✓ WhatsApp confirmado" → banner no vuelve
      y Ajustes muestra "WhatsApp confirmado ✓".
- [ ] **Proveedor nuevo end-to-end**: segunda cuenta → "Quiero ofrecer" → 6 pasos (GPS
      propone ciudad/sector; foto por cámara opcional) → "Crear mi negocio" → `/provider` con
      saldo 0 en "Mis ofertas".
- [ ] **Atomicidad/abandono**: salir a mitad del flujo proveedor (paso 3), matar la app,
      volver → selector de rol de nuevo; por SQL: cero filas nuevas en
      profiles(account_type)/provider_businesses/provider_wallets.
- [ ] **Camino negativo**: WhatsApp de la otra cuenta en el paso 4 → copy "ya está registrado"
      (pre-chequeo) y, si se fuerza el cierre, slug `whatsapp_taken` mapeado.
- [ ] **Ciclo de dinero con verificado**: consumidor verificado crea solicitud → proveedor
      oferta → cliente acepta → "Mis ofertas" → tap en la aceptada → hold-to-confirm →
      contacto revela el **número verificado** (whatsapp_e164).
- [ ] **Ciclo de dinero SIN verificar** (la barrera nueva): con un consumidor sin OTP →
      proveedor tap en oferta aceptada → hoja "Contacto aún no disponible" ANTES de pagar →
      saldo intacto (verificar por SQL).
- [ ] **Error de red post-pago**: modo avión tras desbloquear → hoja "No pudimos cargar el
      contacto" con Reintentar (nunca la hoja vacía del bug).
- [ ] **Sello del negocio**: Ajustes → "Sello de WhatsApp del negocio" → OTP → si el número
      coincide con el público, `provider_businesses.whatsapp_verified_at` sellado.
- [ ] **OTP hardening**: reenviar antes de 60s → "Espera Ns"; 6º envío en 15 min → mensaje de
      demasiados códigos; código malo ×5 → "Demasiados intentos".

## Resultados

_(llenar al correr)_
