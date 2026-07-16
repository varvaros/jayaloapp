# Spec de diseño — Jayalo v1: "El corazón en Flutter" (app 100% nativa)

- **Fecha:** 2026-07-16 (rev. 2 — incorpora las 4 decisiones del PO; la rev. 1 proponía híbrido
  con WebViews y quedó superada)
- **Estado:** propuesta (pendiente de revisión final del PO)
- **Repo:** `jayalo-app` (git aparte — `C:\Users\ac\Downloads\jayalo-app`)
- **Siguiente paso:** `superpowers:writing-plans` sobre este spec.

> Este documento describe el **qué** y el **porqué**. El **cómo** paso a paso (tasks, orden,
> criterios de aceptación) vive en el plan de implementación que se escribe después.

---

## 0. Decisiones del PO que gobiernan este spec (2026-07-16)

1. **Crear solicitud (IA) es NATIVA** en la v1 (no WebView).
2. **El Worker de jayalo-main no se toca**: el emisor de push es una **Supabase Edge Function**.
3. **El repo se llama `jayalo-app`.**
4. **Principio de diseño:** *"No quiero que Flutter replique la web. Quiero que tome la lógica de
   negocio existente (Supabase, Edge Functions, autenticación, IA y base de datos), pero que la
   experiencia de usuario sea diseñada específicamente para móvil siguiendo Material 3 y las
   mejores prácticas de Android e iOS."*

**Consecuencia estructural de la decisión 4: NO hay capa WebView.** La app es 100% nativa. Lo que
no esté construido en nativo simplemente **no está en la v1** (se difiere), salvo lo que por
política externa deba abrirse en el **navegador del sistema** (PayPal). Esto elimina de raíz el
punto más delicado del diseño anterior (compartir la sesión Supabase con WebViews) y lo reemplaza
por un riesgo nuevo y más acotado (hablar con el endpoint de IA desde un cliente nativo, §7).

---

## 1. Objetivo y motivación

Llevar Jayalo a una app Android **nativa** (Flutter), empezando por un *vertical slice* del
**corazón del producto**. El corazón de Jayalo **no es una pantalla**: es la **máquina de estados
de una solicitud/oferta** que cliente y proveedor siguen juntos, con **push nativo (FCM) en cada
transición**.

Metas de la v1:

1. **Validar el rendimiento y el "feel" nativo** en el teléfono de gama media del PO antes de
   invertir en el resto de la app.
2. **Encender la punta de lanza** (push nativas): cliente y proveedor reciben un push en el momento
   exacto en que el estado de su pedido cambia. Hoy solo hay notificaciones in-app + correo.
3. **Probar la filosofía de diseño**: UX pensada para móvil (Material 3, patrones Android/iOS),
   no un calco de las pantallas web.

**Restricción de aislamiento (PO, firme):** el trabajo vive en este repo git separado. La **web de
Jayalo (frontend) y el Worker NO se tocan**. Las únicas costuras son de datos/backend (§9): una
tabla nueva + una Edge Function, ambas aditivas y reversibles.

---

## 2. Filosofía de diseño (decisión 4 del PO)

- **Se reusa la lógica de negocio, no la interfaz.** La fuente de verdad de *comportamiento* es el
  backend existente: Supabase (Auth, Postgres, RLS, RPCs atómicas), el endpoint de IA del Worker y
  las reglas de dinero. La fuente de verdad de *interfaz* es este spec + Material 3 — **no** el
  layout de jayalo.com.
- **Material 3 expresivo**: theming dinámico donde aporte, tipografía y elevación M3, componentes
  nativos (bottom navigation, sheets, FAB donde corresponda), motion con propósito (transiciones
  de contenedor en las transiciones de fase del pedido, no animación decorativa porque sí).
- **Patrones móviles, no páginas**: bottom sheet para acciones contextuales (aceptar oferta,
  desbloquear), pull-to-refresh, estados vacíos con guía (el público es análogo — misma doctrina
  a-prueba-de-tontos del QA de usabilidad de la web), jerga dominicana y montos en RD$ como en la
  web (la *voz* sí se hereda; el *layout* no).
- **Android primero, iOS-ready**: v1 compila y se prueba solo en Android (el PO está en Windows),
  pero el diseño evita Android-ismos que bloqueen iOS después (Flutter lo permite de fábrica).
- La web queda como referencia de **copy y semántica de fases** (§4), que ya están validadas,
  no de composición visual.

---

## 3. Alcance de la v1

### 3.1 Dentro (todo nativo)

**El ciclo completo del corazón, ambos actores:**

- **Cliente:** crear solicitud (flujo conversacional IA, §5.1) · mis solicitudes con su fase ·
  estado del pedido · ver ofertas · **aceptar UNA oferta** · ver contacto al desbloquearse ·
  marcar completada / calificar.
- **Proveedor:** bandeja de solicitudes que matchean su negocio · **hacer oferta** (gratis) ·
  mis ofertas con estado · **desbloquear contacto** pagando con créditos existentes · obtener el
  WhatsApp verificado del cliente · saldo de créditos (lectura).
- **Login nativo con Google** (innegociable) reusando la config OAuth existente (§10).
- **Push FCM** en cada transición del corazón (§8) con deep link a la pantalla de estado.

### 3.2 Fuera de la v1 (diferido — NO está en la app, ni en WebView)

- **Recarga de créditos / PayPal**: el CTA "Recargar" abre `jayalo.com/wallet` en el **navegador
  del sistema** (Custom Tab). Doble motivo: la política de PayPal prohíbe sus páginas en WebView,
  y el flujo de dinero es lo más riesgoso de reescribir. El usuario se autentica en su navegador
  (Google en Chrome funciona normal). Fricción aceptada en v1; recarga nativa = fase posterior.
- **Chat interno**: el contacto post-desbloqueo en v1 es el **WhatsApp verificado** (deep link),
  que ya es el desenlace de primera clase del modelo. Chat nativo = fase posterior.
  **▶ A validar por el PO** (§12).
- **Perfil/configuración/historial completo**: v1 incluye solo lo mínimo (ver §5.3); el resto,
  en el navegador si hace falta.
- **Alta/registro de proveedor y onboarding de cuentas nuevas**: la v1 asume **cuentas ya
  existentes** (el login Google de un usuario registrado funciona; un usuario totalmente nuevo se
  registra en la web). **▶ A validar por el PO** (§12).
- **Play Store** (fase posterior: US$25, Data Safety, ~12 testers) e **iOS** (requiere Mac).

---

## 4. El corazón: la máquina de estados (sin cambios respecto a rev. 1)

La máquina **ya existe y está probada en la web**; la app **replica el modelo de datos, no las
pantallas**, leyendo las mismas columnas de `customer_requests` y `provider_offers`.

Estados de una **oferta** (`provider_offers.status`): `pending | accepted | completed | rejected`,
más `unlocked_at` y `points_charged`.

Fases del **pedido** (semántica heredada de la web, presentación nativa nueva):

| Fase | Condición | Semántica |
|---|---|---|
| `waiting` | solicitud creada, 0 ofertas | "Esperando ofertas" |
| `with_offers` | ≥1 oferta, ninguna aceptada | "N ofertas recibidas" |
| `accepted` | el cliente aceptó **una** oferta, sin desbloquear | "Oferta aceptada — el proveedor te contactará" |
| `unlocked` | la oferta aceptada tiene `unlocked_at` | "Contacto desbloqueado" |
| `completed` | solicitud/oferta completada o cerrada | "Completada — califica" |

**Reglas confirmadas en código:**
- El cliente **acepta UNA sola oferta** por solicitud; la aceptación es atómica
  (`UPDATE … SET status='accepted' WHERE status='pending'`, guard anti-doble-aceptación).
- **Ofertar es GRATIS**; el **proveedor** paga créditos al **desbloquear** tras `accepted`, vía la
  RPC `try_unlock_offer` — **el costo se calcula DENTRO de la RPC** (el `_cost` del cliente se
  ignora), atómica e idempotente. La app muestra el costo estimado con la misma tabla de tiers
  (portar `pointsForOffer` a Dart **solo para UI**).
- Al desbloquear, el proveedor obtiene el WhatsApp verificado vía `get_unlocked_offer_contact`.

**Transiciones que disparan push (§8):** nueva solicitud que matchea → proveedor · nueva oferta →
cliente · oferta aceptada → proveedor · contacto desbloqueado → cliente. Los cuatro eventos ya
existen como puntos de disparo en la BD (insert en `notifications` / correo); el push se engancha
ahí, no se inventan eventos nuevos.

---

## 5. Pantallas nativas (v1)

Navegación con `go_router`; home por rol (`profiles.account_type`). Lo que sigue define contenido
y comportamiento; la composición visual la decide la implementación siguiendo §2.

### 5.1 Cliente

1. **Crear solicitud (IA) — nativa** (decisión 1). Chat conversacional móvil de verdad: burbujas,
   chips de respuesta rápida cuando la IA ofrezca opciones, campo con micro-affordances móviles.
   Habla con el endpoint existente `/api/ai/chat-stream` del Worker **sin modificarlo** —
   *corrección post-spec verificada en código*: pese al nombre, NO es streaming; cada turno es
   un POST que devuelve UN objeto JSON tipado. Ver contrato y riesgos en §7. Al confirmar, inserta la
   `customer_request` (misma escritura que hace la web hoy). Incluye el flag "al por mayor"
   (kind producto).
2. **Mis solicitudes** — lista con fase visible de un vistazo (color/badge por fase).
3. **Estado del pedido** — la pantalla insignia: fase actual prominente, timeline/stepper de las 5
   fases con transición animada (M3 container transform), lista de ofertas recibidas.
4. **Aceptar oferta** — bottom sheet con el detalle (precio/rango, mensaje, reputación del
   proveedor incl. "responde en ~X") + confirmación. Ejecuta el `UPDATE` con guard.
5. **Contacto** — al pasar a `unlocked`: datos del proveedor + botón WhatsApp.
6. **Completar/calificar** — cierre del ciclo (rating simple).

### 5.2 Proveedor

1. **Bandeja de solicitudes** — solicitudes que matchean el negocio; filtro producto/servicio;
   marca visual para "al por mayor".
2. **Hacer oferta** — formulario nativo: precio fijo / rango / por hora + mensaje; muestra el
   costo de desbloqueo estimado ANTES de ofertar (transparencia, mismo dato que la web).
3. **Mis ofertas** — lista con estado; resalta `accepted` pendientes de desbloquear (es la acción
   que gana dinero para Jayalo — merece prominencia).
4. **Desbloquear** — bottom sheet con costo + saldo + confirmación deliberada (equivalente nativo
   del hold-to-confirm de la web); al éxito, revela el WhatsApp del cliente con celebración sobria.
5. **Saldo** — lectura del wallet + CTA "Recargar" → Custom Tab a `jayalo.com/wallet` (§3.2).

### 5.3 Comunes

- **Splash + Login Google nativo** (hoja de cuentas Android).
- **Home/tabs por rol** (bottom navigation M3).
- **Ajustes mínimos**: cuenta activa, cerrar sesión, versión, enlaces legales (navegador).

---

## 6. Superficies que salen al navegador del sistema (Custom Tabs)

| Superficie | Por qué navegador y no la app |
|---|---|
| Recarga / PayPal (`jayalo.com/wallet`) | Política PayPal anti-WebView + flujo de dinero sin reescribir en v1 |
| Registro de cuenta nueva / alta proveedor | Fuera del alcance v1 (§3.2) |
| Términos / Privacidad | Contenido estático; no amerita nativo |

No se comparte sesión con el navegador (imposible/innecesario): el usuario se loguea ahí una vez
con Google. La app refresca el saldo al volver (`onResume`).

---

## 7. Riesgo técnico central: el endpoint de IA desde un cliente nativo

Verificado en el código (`src/routes/api/ai/chat-stream.ts` de jayalo-main):

- **`Origin` falla cerrado**: rechaza requests sin header `Origin` o con uno no permitido.
  → La app **fija el header** `Origin: https://jayalo.com` en su cliente HTTP (legítimo: es
  nuestro propio cliente de confianza; en apps nativas el header es controlable). Cero cambios
  al Worker.
- **Turnstile en el primer turno** (`messages.length === 1` exige `turnstileToken` cuando el
  secreto está configurado — y en prod lo está). Turnstile es un widget **web**; no hay SDK
  nativo. Opciones, a decidir en el plan:
  - **(a) Widget en WebView invisible SOLO para obtener el token** (patrón conocido; no es
    "experiencia web", es plomería oculta de ~1s). Respeta "no tocar el Worker". ⚠️ Requiere que
    el hostname del widget esté permitido (gotcha 110200 ya conocido).
  - **(b) Excepción autenticada en el Worker** (aceptar sesión Supabase válida en lugar del token
    en el primer turno) — **tensión con la decisión 2** (no tocar el Worker); solo si (a) falla.
- **Rate limit por IP** ya existe (ADR-0025) — aplica igual a la app, sin cambios.
- **Contrato del endpoint (verificado)**: NO es SSE — cada turno es un POST→JSON con `type` en
  `{question, routing, ready, kind_switch, image_request}`. `BodySchema`: `messages[{role,
  content}]`, `kind?`, `wholesale?`, `turnstileToken?`, `imageDataUrl?`. Cliente Dart = `http`
  simple.
- El endpoint **no valida sesión server-side** (el "login antes de la IA" de la web es UX
  client-side + rate limit). La app igualmente exigirá login antes de crear solicitud, como la web.

**Riesgo de auth ya conocido:** Turnstile global de Supabase Auth puede devolver `captcha_failed`
en `signInWithIdToken` → fix conocido: pasar `options.captchaToken`. Verificar en device al
implementar el login (mismo patrón (a) si hace falta token).

---

## 8. Push notifications (FCM)

- `firebase_messaging` + proyecto Firebase enganchado al package `com.jayalo.app`
  (`google-services.json`).
- Al loguear/arrancar: guardar el FCM token en la tabla nueva `device_tokens` (§9) vía
  `supabase_flutter`; refrescar en `onTokenRefresh`; borrar al cerrar sesión.
- Payload con `type` + `request_id`/`offer_id` → deep link (`go_router`) a la pantalla de estado
  correcta, en foreground/background/terminated.
- Mensajes de las 4 transiciones (§4), copy final en el plan.

---

## 9. Costura de backend (única — la web y el Worker no se tocan)

**Decisión 2 del PO: Edge Function, no Worker.**

1. **Tabla `device_tokens`** `(user_id, token, platform, updated_at)` — migración nueva. RLS por
   dueño; grants de mínimo privilegio; patrón de seguridad del proyecto (revisar checklist
   `db-security-check.sql` al crearla).
2. **Edge Function `send-push`** (Supabase): invocada desde los mismos puntos de disparo que hoy
   generan `notifications`/correo (trigger → `pg_net`/cola, igual que `enqueue_notification_email`),
   lee los `device_tokens` del destinatario y envía vía **FCM HTTP v1** (service account de
   Firebase como secreto de la función). Aditiva, aislada, reversible.
3. **Nada más.** Las lecturas/escrituras del corazón usan tablas y RPCs existentes tal cual.

**▶ Decisión menor pendiente (plan):** proyecto Firebase nuevo dedicado vs. crear FCM dentro del
proyecto Google Cloud existente `jayalo-501005`. Sin impacto arquitectónico; se decide al hacer
el setup.

---

## 10. Stack técnico

**Flutter (GRATIS, BSD). NO FlutterFlow** (builder de pago tipo Lovable — evitar).

| Paquete | Para qué |
|---|---|
| `supabase_flutter` | Auth + PostgREST + RLS heredada. Mismo proyecto `mfaikl…` |
| `google_sign_in` | Login nativo Google |
| `firebase_messaging` + `firebase_core` | Push FCM |
| `go_router` | Navegación + deep links |
| `url_launcher` / Custom Tabs | PayPal, WhatsApp, legal, registro |
| `http` (POST + JSON por turno) | Chat IA nativo (§7) |
| Material 3 nativo; `lottie`/`rive` solo si una transición concreta lo pide | El "feel" (§2) |

**Reuso de config existente (el trabajo caro no se pierde):**
- OAuth client **Android** (proyecto `jayalo-501005`, package `com.jayalo.app`, SHA-1 debug
  `C0:02:66:E7:F6:0A:88:9B:02:4A:C3:14:C4:9F:04:8E:B6:89:45:2E`) → idéntico para `google_sign_in`.
- **Web Client ID** `606236193258-80p6roa1ohq3dd63n3uodnrvqncpt44k.apps.googleusercontent.com` →
  para `supabase.auth.signInWithIdToken`.
- Android Studio + SDK API 36 instalados.

**Setup pendiente (una vez, guiado con el PO):** SDK de Flutter en Windows; proyecto/config
Firebase (`google-services.json`).

---

## 11. Trabajo previo en jayalo-main (fuera de este repo)

- **Revertir `cb675fc`** (helper `signInWithGoogle` de la cáscara Capacitor; sin desplegar;
  Flutter no lo usa). Decisión del PO. Se ejecuta en `jayalo-main` como paso previo.
- El repo Capacitor `jayalo-android` queda **archivado**.

---

## 12. Decisiones — cerradas y abiertas

**Cerradas (PO, 2026-07-16):**
1. Alcance v1 = ciclo completo, ambos actores. ✔
2. Crear solicitud (IA) = **nativa**. ✔
3. Push = **Edge Function** (`send-push`); el Worker no se toca. ✔
4. Repo = **`jayalo-app`**. ✔
5. Filosofía = **100% nativa, mobile-first M3**; la web no se replica; sin WebViews. ✔
6. Revertir `cb675fc` en jayalo-main. ✔

**Abiertas (validar en la revisión de este spec):**
1. **Chat interno fuera de v1** — contacto post-desbloqueo = WhatsApp (§3.2). ¿OK?
2. **Onboarding de cuentas nuevas fuera de v1** — la app asume cuentas existentes; registro en la
   web (§3.2). ¿OK?
3. **Turnstile para la IA nativa** — opción (a) WebView invisible solo-token (default, no toca el
   Worker) vs (b) excepción autenticada en el Worker (§7). Se confirma en el plan tras probar (a).

---

## 13. Criterios de éxito de la v1

- El PO instala el APK debug en su teléfono de gama media y la app **se siente nativa y diseñada
  para móvil** — no una web calcada.
- **Ciclo completo de punta a punta en el device con dos cuentas**: crear solicitud (IA nativa,
  streaming fluido) → oferta → aceptación → desbloqueo (créditos reales de prueba) → WhatsApp.
- Cada transición dispara un **push** que abre la pantalla correcta (deep link), incluso con la
  app cerrada.
- Login Google nativo funcional; recarga abre el navegador y el saldo se refresca al volver.
- `jayalo-main` (web + Worker) **sin cambios** (salvo el revert de `cb675fc`); los cobros siguen
  pasando por las RPCs atómicas server-side.

---

## Apéndice — referencias de lógica de negocio en `jayalo-main` (fuente de verdad)

- Fases del pedido: `src/routes/requests/$requestId.tsx` (derivación `waiting…completed`).
- Aceptación única: `src/routes/requests/$requestId.tsx` (`hasAcceptedElsewhere`, guard pending).
- Lado proveedor: `src/components/provider/ProviderOffersSection.tsx`.
- Desbloqueo/cobro: `src/lib/offer-unlock.functions.ts` → RPC `try_unlock_offer`;
  `src/lib/pointPricing.ts` (tiers para UI).
- Contacto: migración `…_whatsapp_reveal_offer.sql` (`get_unlocked_offer_contact`).
- Endpoint IA: `src/routes/api/ai/chat-stream.ts` (Origin fail-closed, Turnstile primer turno,
  `BodySchema`, rate limit ADR-0025).
- Disparo de notificaciones existente (modelo para `send-push`): trigger
  `enqueue_notification_email` y `notify_new_request_matches`.
- Reglas de dinero: `CLAUDE.md` de jayalo-main → "Seguridad — decisiones tomadas".
