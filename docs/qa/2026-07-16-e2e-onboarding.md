# E2E onboarding nativo — runbook (preparado 2026-07-16)

**Estado (actualizado 2026-07-17):** la app está lista e instalada en el Redmi (build debug con
los 9 commits del plan).

- ✅ **Edge Functions DESPLEGADAS y vivas** (`send-otp`, `verify-otp`): verificado con curl —
  ambas responden `401 UNAUTHORIZED_NO_AUTH_HEADER` sin token (gateway `verify_jwt` activo).
- ✅ **`can_reveal_offer_whatsapp` existe en prod** y `anon` está bloqueado (`42501`) → la RPC
  que usa el fix de dinero (Task 9) está disponible.
- ✅ **RPC `complete_provider_onboarding` APLICADA y VERIFICADA en prod** (2026-07-17, vía MCP
  autorizado por el PO). Evidencia:
  - **Check #11 en verde**: `anon` sin `EXECUTE` (0 filas); vía PostgREST con la anon key
    responde `42501 permission denied` (antes `PGRST202`).
  - **Atomicidad**: en una tx de prueba sobre un usuario real con `account_type` NULL y sin
    wallet (el estado exacto del bug) → perfil `provider` + phone + terms 2.0 + negocio con
    `is_wholesale` + 2 categorías + **wallet en 0**, todo en una sola llamada.
  - **ROLLBACK sin residuo**: tras la prueba, el usuario sigue en `account_type=NULL`,
    0 negocios, 0 wallets.
  - **Idempotencia**: 1ª llamada `already=false`, 2ª `already=true` con el **mismo**
    `business_id` (reintentos por timeout móvil no duplican).
  - **Slugs de error**: WhatsApp de otro usuario → `whatsapp_taken`; sin nombre →
    `invalid_business` (son los que mapea `onboarding_errors.dart`).
  - `get_advisors('security')` sin hallazgos nuevos vs. baseline (los WARN de SECURITY DEFINER
    son por diseño; la RPC nueva NO aparece como ejecutable por `anon`).
- ⛔ **Secretos Twilio ausentes en Supabase** (`secrets list` no los tiene). El `.env` local
  tiene `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN` **vacíos** y los del Worker de Cloudflare son
  de solo-escritura (no recuperables) → los valores debe ponerlos el PO desde la consola de
  Twilio. **Paso 2 de abajo, [PO].**

**Único bloqueante restante: el número emisor `TWILIO_SMS_FROM` (paso 1).** El SID y el Auth
Token ya están cargados (verificado con `secrets list` el 2026-07-17). Todo lo demás del ciclo
(onboarding de consumidor y de proveedor, fixes de dinero) ya funciona contra prod.

## Paso 0 — Backend

1. **Secretos Twilio para las Edge Functions.** Hacen falta **TRES**: `TWILIO_ACCOUNT_SID` ✅,
   `TWILIO_AUTH_TOKEN` ✅ y **`TWILIO_SMS_FROM`** ⛔ (falta).

   > ⚠️ **Corrección (2026-07-17).** Una versión previa de este runbook decía que bastaban dos
   > porque el emisor saldría de `app_settings.twilio_whatsapp_from`. **Era falso**: verificado
   > contra prod, esa fila **no existe** (`app_settings` tiene 8 claves y esa no está). La web
   > funciona porque lee el secreto `TWILIO_WHATSAPP_FROM` **del Worker de Cloudflare**, que
   > las Edge Functions no ven. Sin `TWILIO_SMS_FROM`, `send-otp` cae al sandbox
   > `+14155238886` y Twilio rechaza el envío (error 21606 o similar).
   >
   > Se usa un secreto y NO se puebla `app_settings.twilio_whatsapp_from` porque esa fila
   > tendría precedencia también para la **web** (`getOtpFromRaw` la lee primero) — y la
   > doctrina es no alterar el comportamiento del Worker.

   `TWILIO_SMS_FROM` = el mismo número Twilio SMS-capable que la web usa hoy (el del secreto
   `TWILIO_WHATSAPP_FROM` del Worker; en la consola de Twilio → Phone Numbers → Active
   numbers). **No es una credencial**: es el remitente que ven los usuarios en el SMS.

   Cargar **desde archivo por CLI**, nunca pegando en el dashboard (gotcha de corrupción de
   `FCM_SERVICE_ACCOUNT`):

   ```bash
   # archivo temporal FUERA del repo. Ya cargados: SID y AUTH_TOKEN.
   # Falta:  TWILIO_SMS_FROM=+1XXXXXXXXXX
   npx supabase secrets set --env-file %TEMP%\twilio.env --project-ref mfaiklvobnvgusbcssbx
   del %TEMP%\twilio.env
   ```

   Verificar después: `npx supabase secrets list --project-ref mfaiklvobnvgusbcssbx` debe
   listar los tres.

   > **Por qué el SID/Auth Token los carga el PO y no el agente:** manejar tokens/API keys en
   > texto plano está fuera de lo que Claude puede hacer, aunque se le autorice — leerlos de la
   > consola de Twilio los volcaría al transcript. El `Auth Token` permite enviar SMS (dinero
   > real / toll fraud), así que es exactamente el tipo de credencial que no debe pasar por el
   > agente. `TWILIO_SMS_FROM` sí puede pasar por el agente: es un número público, no un
   > secreto.

2. ~~**Aplicar la migración de la RPC**~~ ✅ **HECHO y verificado** (2026-07-17) — ver la
   evidencia arriba.

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
