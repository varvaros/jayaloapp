# Diseño: registro más limpio, OTP obligatorio con autofill, y responder desde el push

Fecha: 2026-07-27
Repos afectados: `jayalo-app` (Flutter, principal) y `jayalo-main` (web) y `mfaiklvobnvgusbcssbx` (Supabase: edge functions).

## Contexto

Punch list del PO sobre el alta de consumidor y el push de chat. Cinco ajustes que se
agrupan en tres tandas independientes (cada una se construye, revisa y prueba por separado).
El alta de consumidor vive en:

- App: `lib/features/onboarding/consumer_onboarding_screen.dart`
- Web: `src/components/consumer/ConsumerProfileForm.tsx`

y el mismo criterio de nombre/WhatsApp aplica en el alta de proveedor por paridad:

- App: `lib/features/onboarding/provider_onboarding_screen.dart`
- Web: `src/components/provider/ProviderSignupWizard.tsx`

Hallazgos que cambian el enfoque respecto al brief inicial:

1. **El OTP ya se envía por SMS**, no por WhatsApp — confirmado en
   `lib/features/verification/otp_sheet.dart` (`_channel = 'sms'`, leído de
   `app_settings.otp_channel`) y en el copy de la hoja. El autofill es viable **sin** cambiar
   de canal.
2. **`geocoding` ya está en `pubspec.yaml`** y usa el geocodificador nativo del SO → reverse
   geocoding en la app **gratis y sin API key**.
3. La app usa **solo `firebase_messaging`** (no `flutter_local_notifications`); la notificación
   la pinta el sistema y el tap rutea por `data['link']` (`/messages?c=<convId>`), ver
   `lib/push/push_service.dart`. Una notificación pintada por el sistema **no** puede llevar
   campo de respuesta inline → hay que pintarla nosotros.

## Objetivos

- Limitar longitud/caracteres de nombre y apellido.
- WhatsApp con prefijo RD seleccionable (809/829/849) + campo numérico de 7 dígitos.
- Verificación de WhatsApp por OTP **obligatoria y bloqueante** en el alta de consumidor.
- Autocompletado automático del código OTP en Android (SMS Retriever) e iOS (nativo).
- Que "Usar mi ubicación" rellene también el campo de dirección.
- Botón "Responder" **dentro de la notificación push** de chat (Android), sin abrir la app.

## No-objetivos (fuera de alcance)

- Responder desde el push en **iOS** — fase futura (requiere categoría nativa
  `UNTextInputNotificationAction` + posible Notification Service Extension). La app hoy es
  Android-primero (`device_tokens.platform = 'android'` fijo).
- Responder desde el push en **web** — las notificaciones web no soportan campo de texto inline
  de forma confiable. Esta feature es solo-app.
- Cita/quote de un mensaje específico dentro del chat ("responder a este mensaje" estilo hilo).
  El responder-desde-push envía un mensaje normal a la conversación, no cita un mensaje. **No se
  agrega la columna `reply_to_message_id`.**
- Números de teléfono fuera de RD (el selector de prefijo hace el registro solo-RD, decisión PO).

## Decisiones de producto cerradas

- Máximo nombre/apellido: **40 caracteres** cada uno.
- OTP: **bloqueante en el registro** (no se crea la cuenta hasta verificar).
- Autofill Android: **SMS Retriever** (automático, sin diálogo) → obliga a tocar `send-otp`.
- Alcance: **app + web** para puntos 1/2/4; **solo app (Android)** para 3 (autofill) y 5 (push).
- Un solo spec con las tres tandas.

---

## Tanda A — Campos del registro (puntos 1, 2, 4)

Cohesiva, bajo riesgo, sin cambios de BD.

### A1. Límite de nombre/apellido

- **Regla:** máx 40 caracteres; permitir letras Unicode (acentos, ñ), espacios, guion (`-`) y
  apóstrofo (`'`); bloquear dígitos y otros símbolos. Cubre nombres como *María José*, *D'Oleo*.
- **App** (`consumer_onboarding_screen.dart`, y `provider_onboarding_screen.dart` por paridad):
  `maxLength: 40` + `inputFormatters: [LengthLimitingTextInputFormatter(40), FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} '\-]", unicode: true))]`.
- **Web** (`ConsumerProfileForm.tsx` `signupSchema` + `ProviderSignupWizard.tsx`): en Zod
  `firstName`/`lastName` → `.trim().min(1).max(40).regex(/^[\p{L}\p{M} '\-]+$/u, "...")`; en el
  `<Input>` `maxLength={40}`.

### A2. WhatsApp con prefijo seleccionable + numérico

- **Modelo:** el número es `+1` + prefijo (`809|829|849`) + 7 dígitos. Se compone y pasa por el
  `normalizePhone` existente (que ya normaliza 10 dígitos a `+1…`). El resto de la app (chequeo
  de duplicado, OTP, `toWhatsappDigits`) no cambia porque recibe el mismo E.164.
- **App** (`consumer_onboarding_screen.dart`): sustituir el `TextField _phone` por un `Row` con
  un `DropdownButton<String>` (809/829/849, default 809) + un `TextField` numérico
  (`keyboardType: TextInputType.number`, `inputFormatters: [FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(7)]`). El estado guarda `_prefix` + `_localDigits`;
  `_composedPhone => normalizePhone('$_prefix$_localDigits')`. Validez: `_localDigits.length == 7`.
  El chequeo `isWhatsappTakenRemote` y `_phoneError` se mantienen sobre el compuesto.
- **Web** (`ConsumerProfileForm.tsx` + `ProviderSignupWizard.tsx`): `Select` (shadcn) con las tres
  opciones + `Input inputMode="numeric"` con `maxLength={7}` y saneo a solo dígitos en `onChange`.
  Componer igual antes de `normalizePhone`.
- **Nota de paridad:** el proveedor también captura WhatsApp — aplicar el mismo control en su
  wizard/edición.

### A3. Ubicación rellena la dirección

- **App** (`consumer_onboarding_screen.dart`, `_useLocation`): tras obtener `pos`, llamar
  `placemarkFromCoordinates(pos.latitude, pos.longitude)` (paquete `geocoding`) y armar una
  cadena legible a partir del primer `Placemark` (p. ej. `street`, `subLocality`, `locality`,
  `administrativeArea`, filtrando vacíos y duplicados). **Solo escribir en `_address` si está
  vacío** (no pisar lo que el usuario ya tecleó); siempre editable. Si el geocoding falla o
  devuelve vacío, comportamiento actual intacto (solo lat/lng). Envolver en try/catch; nunca
  bloquear el flujo. Fijar `localeIdentifier: 'es_DO'` si el API lo permite.
- **Web** (`ConsumerProfileForm.tsx`, `captureLocation`): el navegador no tiene geocoder nativo →
  nueva **server function** `reverseGeocode({ lat, lng })` en `src/lib/geo.functions.ts` que
  consulta Nominatim (`https://nominatim.openstreetmap.org/reverse?format=jsonc&lat=…&lon=…`,
  header `User-Agent: jayalo.com` obligatorio por su política de uso; `Accept-Language: es`).
  Rellenar `address` solo si está vacío. Best-effort: si falla, se queda solo con lat/lng.
  ⚠️ Respetar el rate-limit de Nominatim (1 req/s) — es una llamada puntual por captura manual,
  aceptable; documentar que si el volumen crece habrá que mover a un geocoder propio/pagado.

---

## Tanda B — OTP obligatorio + autofill (punto 3, solo app)

### B1. OTP bloqueante en el registro

- Hoy `_submit()` escribe el perfil y redirige, **sin** OTP (el OTP estaba diferido). Nuevo flujo
  en `consumer_onboarding_screen.dart._submit()`:
  1. Validar (incluye WhatsApp compuesto válido).
  2. Abrir `showOtpSheet(context, phone: _composedPhone)` — envía el SMS y **bloquea** hasta
     verificar. Devuelve `true` solo si el código fue correcto.
  3. Si `false`/cancelado → no se crea la cuenta; se queda en el formulario con aviso.
  4. Si `true` → `completeConsumerProfile(...)` con el WhatsApp verificado → `roleStore.refresh()`.
- **Invariante:** el número que se verifica es exactamente el que se guarda en `profiles`. El
  usuario ya está autenticado (Google OAuth) al llegar a esta pantalla, así que `verifyOtp` puede
  asociar la verificación al usuario. Confirmar en el plan que `verifyOtp` no exige que el perfil
  exista antes (por firma `sendOtp(phone, businessId)` no lo exige).
- **Alcance:** solo el alta de **consumidor**. El alta de proveedor ya tiene su flujo de
  verificación propio (`verify_banner`, sello del negocio) y no se toca en esta tanda.

### B2. Autofill del código

- **Paquete:** `smart_auth` (soporta SMS Retriever y expone `getAppSignature()` para obtener el
  hash de 11 chars por keystore).
- **iOS:** añadir `autofillHints: const [AutofillHints.oneTimeCode]` al `TextField _code` de
  `otp_sheet.dart`. Automático, sin permiso ni backend.
- **Android (SMS Retriever, automático):**
  - En `otp_sheet.dart`, al abrir la hoja: iniciar el listener de `smart_auth`
    (`SmartAuth.getSmsCode(...)` o el stream equivalente) y, al recibir el código, poblar `_code`
    y auto-verificar (respetando el estado `_sending`). Cancelar el listener en `dispose`.
  - **Backend (`send-otp` edge function):** el cuerpo del SMS debe cumplir el formato de SMS
    Retriever: empezar con `<#>`, contener el código, y **terminar con el hash de 11 chars de la
    app**, todo ≤140 bytes. Ej.:
    ```
    <#> Tu codigo Jayalo es 123456
    FA+9qCX9VSu
    ```
  - **Hash por keystore:** el hash de release (keystore `jayalo-upload.jks`, Firebase
    `jayalo-350bc`) difiere del de debug. Se obtienen con `getAppSignature()` en cada build y se
    incrustan en `send-otp` (release; el de debug para pruebas locales). Documentar ambos en el
    plan. ⚠️ Play App Signing puede re-firmar el binario → el hash efectivo en producción es el
    de la clave de firma de Play, no la de upload; verificar el hash real de un APK/AAB servido
    por Play antes de dar por bueno el autofill en release.
- **Riesgo/prueba:** validar en device real que (a) el SMS con el hash correcto dispara el
  autollenado, y (b) sin el hash correcto, el flujo manual (tipear el código) sigue intacto —
  el autofill es una mejora, nunca un requisito para verificar.

---

## Tanda C — Responder desde el push de chat (punto 5, solo Android)

La respuesta inline envía un **mensaje normal** a la conversación (no cita un mensaje). Sin
cambios de esquema.

### C1. Backend (`send-push` edge function)

- Los push de chat (`message_new`) pasan a incluir los datos necesarios para responder:
  `conversation_id` (ya derivable del `link`), y el tipo para que la app sepa que debe pintar la
  notificación con acción de respuesta.
- Enviar como **data-message** (o notification+data) para que la app controle el pintado en
  Android. Mantener el `link` actual para el tap normal y para el ruteo en frío.
- Conservar el comportamiento de badge/contador ya existente (`notification_count`, `send-push`
  v15) — no regresarlo.

### C2. App (Flutter, Android)

- Añadir `flutter_local_notifications`; configurar un canal de chat con una **acción "Responder"**
  con `AndroidNotificationActionInput` (RemoteInput).
- **Pintado:** en `FirebaseMessaging.onMessage` (foreground) y en el handler de background
  (`FirebaseMessaging.onBackgroundMessage`), si el push es de chat, pintar la notificación local
  con la acción de responder, portando `conversation_id` en el payload de la acción.
- **Handler de respuesta** (`onDidReceiveBackgroundNotificationResponse`, top-level, con la app
  cerrada): recibir el texto tecleado → reinicializar Supabase en el isolate → recuperar la
  sesión persistida → `INSERT` en `conversation_messages` (mismo camino de envío que usa el
  chat, ver `data/repos.dart`) para `conversation_id` → actualizar/descartar la notificación
  ("Enviado") o mostrar error si no hay sesión viva.
- **Ruteo del tap** (abrir la conversación) se mantiene por `data['link']` como hoy.

### C3. Riesgo principal

Enviar el mensaje **con la app cerrada** exige que la sesión de Supabase esté viva y accesible en
el background isolate (`supabase_flutter` la persiste; hay que reinicializar y restaurarla). Es lo
primero a probar en device. Fallback si no hay sesión: notificación de "no pudimos enviar, abre la
app" (no perder el texto silenciosamente si se puede evitar).

---

## Secuencia de implementación

**A → B → C.**

- **A** es rápida, visible y de bajo riesgo (formularios).
- **B** necesita prueba en device real (SMS + hash de firma).
- **C** es la más grande y arriesgada (background isolate + envío con app cerrada).

Cada tanda se puede mergear/probar de forma independiente.

## Pruebas

- **A:** análisis estático (`flutter analyze`, `tsc`/lint); prueba manual del formulario en device
  (límite de caracteres, prefijo→E.164 correcto, geocoding rellena dirección y respeta lo tecleado).
- **B:** device real — SMS llega con el formato SMS Retriever, autollenado dispara, y el camino
  manual sigue vivo; el registro NO se completa sin verificar.
- **C:** device real — notificación con campo de respuesta, envío con app en background y **cerrada**,
  el mensaje aparece en la conversación, contador/badge intactos, y degradación si no hay sesión.

## Archivos afectados (resumen)

| Área | App (`jayalo-app`) | Web (`jayalo-main`) | Backend (Supabase) |
|---|---|---|---|
| A1 nombre | `features/onboarding/consumer_onboarding_screen.dart`, `provider_onboarding_screen.dart` | `components/consumer/ConsumerProfileForm.tsx`, `components/provider/ProviderSignupWizard.tsx` | — |
| A2 WhatsApp | idem A1 | idem A1 | — |
| A3 dirección | `consumer_onboarding_screen.dart` | `ConsumerProfileForm.tsx`, nuevo `src/lib/geo.functions.ts` | — |
| B OTP+autofill | `features/verification/otp_sheet.dart`, `consumer_onboarding_screen.dart`, `pubspec.yaml` (`smart_auth`) | — | `send-otp` |
| C push reply | `push/push_service.dart`, nuevo handler local-notifications, `pubspec.yaml` (`flutter_local_notifications`) | — | `send-push` |
