# Spec de diseño — Jayalo v1: "El corazón en Flutter"

- **Fecha:** 2026-07-16
- **Estado:** propuesta (pendiente de revisión del PO)
- **Repo:** `jayalo-flutter` (nuevo, git aparte — `C:\Users\ac\Downloads\jayalo-flutter`)
- **Fase anterior:** brainstorming aprobado por el PO (dirección "Flutter híbrido incremental,
  patrón strangler" — decidida, no se re-litiga aquí).
- **Siguiente paso:** `superpowers:writing-plans` sobre este spec.

> Este documento describe el **qué** y el **porqué**. El **cómo** paso a paso (tasks, orden,
> criterios de aceptación) vive en el plan de implementación que se escribe después.

---

## 1. Objetivo y motivación

Llevar Jayalo a una app Android **nativa** (Flutter), empezando por un *vertical slice* del
**corazón del producto**. El corazón de Jayalo **no es una pantalla**: es la **máquina de estados
de una solicitud/oferta** que cliente y proveedor siguen juntos, con **push nativo (FCM) en cada
transición**.

Dos metas concretas para la v1:

1. **Validar barato el miedo #1** (rendimiento): que el PO instale el APK en su teléfono de gama
   media y **SIENTA** una experiencia nativa premium (Material 3, transiciones fluidas) antes de
   invertir en migrar el resto.
2. **Encender la punta de lanza** (push notifications nativas): que cliente y proveedor reciban un
   push en el momento exacto en que el estado de su pedido cambia. Hoy Jayalo solo tiene
   notificaciones in-app (tabla `notifications`) + correo (Resend).

**Restricción de aislamiento (PO, firme):** el trabajo vive en un repo git **totalmente separado**
de `jayalo-main`. La **web de Jayalo (frontend) NO se toca**. La única costura con lo existente es
de backend/datos (ver §9), sin cambios al frontend web.

---

## 2. Alcance de la v1

Decisión del PO (2026-07-16): la v1 cubre el **ciclo completo, ambos actores**.

### 2.1 Dentro del alcance (nativo Flutter)

**El corazón — la máquina de estados**, para los dos roles:

- **Cliente:** ver sus solicitudes y su **estado del pedido**, ver las ofertas recibidas,
  **aprobar una oferta**, ver el contacto una vez desbloqueado, marcar completada / calificar.
- **Proveedor:** bandeja de **solicitudes que matchean** su negocio, **hacer una oferta** (gratis),
  ver cuándo su oferta fue **aceptada**, **desbloquear el contacto** pagando con los créditos que
  ya tiene, obtener el WhatsApp verificado del cliente.
- **Navegación nativa** del catálogo/solicitudes (listas, filtros básicos) suficiente para llegar a
  las acciones del corazón.
- **Login nativo con Google** (innegociable — Jayalo no es email/password) reusando la config OAuth
  de hoy.
- **Push FCM** enganchado a las transiciones del corazón (§8), con deep link a la pantalla de
  estado correspondiente.

### 2.2 Fuera del alcance de la v1 (se quedan en WebView, cargando `jayalo.com`)

Estas superficies se **muestran dentro de la app** vía `webview_flutter`, con la sesión ya
compartida (§7); se migran a nativo en fases posteriores:

- **Recarga de créditos / PayPal.** Se deja en web a propósito: en móvil regala Google Pay gratis,
  y es el flujo de dinero (el más riesgoso de reescribir). Además la política de PayPal prohíbe sus
  páginas en WebView → cuando aplique, se abre en **navegador externo** (no en el WebView embebido).
- **Crear solicitud (cliente).** Es el flujo **conversacional con IA** (`/requests/new` →
  `/api/ai/chat-stream`, streaming). Es la pantalla más compleja y arriesgada de reescribir, y NO
  es parte de las *transiciones* de la máquina de estados (el corazón arranca cuando la solicitud
  ya existe; la acción clave del cliente en el corazón es **aprobar**, que sí es nativa). Se deja
  en WebView en v1. **▶ A validar por el PO** (§11): si el PO quiere "crear solicitud" nativa en la
  v1, sube el alcance de forma notable.
- **Perfil, configuración, historial completo, chat** con el proveedor/cliente.
- **Alta/registro de proveedor** (wizard largo) y **conversión de cuenta**.

### 2.3 Explícitamente fuera (ni siquiera WebView en v1)

- Publicación en Play Store (fase posterior; requiere cuenta Google Play Developer US$25, Data
  Safety, ~12 testers, assets de tienda).
- iOS (requiere Mac; el PO está en Windows).
- Migrar a push por Broadcast/realtime avanzado, analítica, etc.

---

## 3. Arquitectura

**Patrón strangler / híbrido incremental.** La app es un **shell nativo Flutter** que:

- Renderiza **nativo** las pantallas del corazón (§5).
- Embebe **WebViews** de `jayalo.com` para las secciones aún no migradas (§2.2).
- Comparte **una sola sesión Supabase** entre el shell nativo y los WebViews (§7).
- El **backend no cambia**: Supabase (Auth, Postgres, RLS, RPCs) y el Worker de Cloudflare
  (`/api/*`) siguen sirviendo tanto a la web como a la app. La app habla con Supabase vía
  `supabase_flutter` (PostgREST/Auth), exactamente el mismo backend que la web.

```
┌─────────────────────────── App Flutter (Android) ───────────────────────────┐
│                                                                              │
│   Shell nativo (Material 3, go_router)                                       │
│   ├── Auth: google_sign_in → supabase.auth.signInWithIdToken                 │
│   ├── Estado global de sesión (supabase_flutter GoTrue)                      │
│   │                                                                          │
│   ├── PANTALLAS NATIVAS (el corazón)                                         │
│   │     • Cliente: mis solicitudes · estado del pedido · ofertas · aprobar   │
│   │     • Proveedor: bandeja de solicitudes · ofertar · aceptada · desbloq.  │
│   │     Datos ↔ Supabase (RLS hereda; RPCs de cobro server-side)             │
│   │                                                                          │
│   ├── PUSH: firebase_messaging → token en `device_tokens` → deep link        │
│   │                                                                          │
│   └── WebViews (webview_flutter) con sesión inyectada (§7)                    │
│         recarga/PayPal* · crear solicitud (IA) · perfil · config · chat      │
│                                                                              │
└──────────────┬───────────────────────────────────────────┬─────────────────┘
               │ PostgREST / GoTrue                          │ HTTPS
        ┌──────▼───────┐                              ┌──────▼──────────────┐
        │  Supabase    │  (mismo proyecto mfaikl…)    │ Cloudflare Worker    │
        │  Auth+RLS+DB │                              │ jayalo.com  /api/*   │
        └──────────────┘                              └──────────────────────┘
   * PayPal: navegador externo, no WebView embebido (política PayPal).
```

**Por qué así:** reusa toda la lógica de negocio (RPCs atómicas de cobro, RLS, triggers) sin
reescribirla; el riesgo se concentra solo en las pantallas nativas del corazón y en la costura de
sesión. Un fallo en la parte nativa nunca corrompe dinero: los cobros siguen pasando por las mismas
RPCs `SECURITY DEFINER` que calculan el costo **server-side** (el cliente nunca dicta el precio).

---

## 4. El corazón: la máquina de estados

Esta máquina **ya existe y está probada en la web** (`src/routes/requests/$requestId.tsx`,
`MyRequestsView.tsx`, `ProviderOffersSection.tsx`). La app nativa **replica el mismo modelo** (no
inventa uno nuevo) leyendo las mismas columnas de `customer_requests` y `provider_offers`.

### 4.1 Estados y transiciones (fuente de verdad: la BD)

Estados de una **oferta** (`provider_offers.status`): `pending | accepted | completed | rejected`.
Más las columnas `unlocked_at` (timestamp del desbloqueo) y `points_charged`.

Fases del **pedido** desde la perspectiva del cliente (derivadas en la UI web y que la app copia):

| Fase | Condición | Copy actual (web) |
|---|---|---|
| `waiting` | solicitud creada, 0 ofertas | "Esperando ofertas" |
| `with_offers` | ≥1 oferta, ninguna aceptada | "N ofertas recibidas" |
| `accepted` | el cliente aceptó **una** oferta, aún sin desbloquear | "Oferta aceptada — El proveedor te contactará pronto." |
| `unlocked` | la oferta aceptada tiene `unlocked_at` | "Contacto desbloqueado — Ya puedes hablar con el proveedor." |
| `completed` | solicitud/oferta completada o cerrada | "Solicitud completada — Califica al proveedor." |

**Regla clave confirmada en código:** el cliente **acepta UNA sola oferta** por solicitud. Al
aceptarla, las demás quedan "aceptada en otra" (`hasAcceptedElsewhere`). La aceptación es atómica:
`UPDATE ... SET status='accepted' WHERE status='pending'` (guard anti-doble-aceptación concurrente).

### 4.2 Quién paga y cuándo

- **Ofertar es GRATIS** para el proveedor.
- El **proveedor** paga créditos para **desbloquear** el contacto **después** de que el cliente
  aceptó su oferta. El desbloqueo:
  - Va por la server function `unlockOffer` → RPC `try_unlock_offer(_offer_id, _cost)`.
  - **El costo se calcula DENTRO de la RPC** (`points_for_offer_row`), no se confía en el `_cost`
    del cliente. La app nativa muestra el costo estimado con la misma lógica (`pointsForOffer`) solo
    para la UI; el cobro real lo fija el servidor.
  - Es atómico (`SELECT ... FOR UPDATE` sobre oferta + wallet), idempotente
    (`already_unlocked`), y respeta el guard de wallet.
  - Al desbloquear, el proveedor obtiene el **WhatsApp verificado** del cliente vía
    `get_unlocked_offer_contact(_offer_id)` (SECURITY DEFINER, gated por `status='accepted' AND
    unlocked_at IS NOT NULL`).

### 4.3 Transiciones que disparan push (§8)

| Transición | Push a | Mensaje (borrador) |
|---|---|---|
| nueva solicitud que matchea el negocio | proveedor | "Nueva solicitud que te puede interesar" |
| nueva oferta sobre mi solicitud | cliente | "Recibiste una oferta nueva" |
| mi oferta fue aceptada | proveedor | "¡Tu oferta fue aceptada! Desbloquea para contactar" |
| contacto desbloqueado | cliente | "El proveedor ya puede contactarte" |

> Estos cuatro eventos **ya existen** como puntos de disparo de la app (insert en `notifications`
> y/o correo). El push reusa esos mismos puntos (§9); no se inventan eventos nuevos.

---

## 5. Pantallas nativas (v1)

Navegación con `go_router`. El shell decide, según el rol del usuario
(`profiles.account_type`), qué home mostrar.

### 5.1 Cliente

1. **Mis solicitudes** — lista de `customer_requests` del usuario con su fase (badge de color como
   la web: ámbar `accepted`, esmeralda `unlocked`). Entrada al detalle.
2. **Estado del pedido** (la pantalla insignia del corazón) — muestra la fase actual con el mismo
   lenguaje que la web, animada en las transiciones (Material motion). Lista las ofertas recibidas.
3. **Aprobar oferta** — acción nativa: card de la oferta (precio/rango, mensaje, reputación del
   proveedor) + confirmar. Ejecuta el `UPDATE status='accepted'` con el guard de estado.
4. **Contacto desbloqueado** — cuando la oferta pasa a `unlocked`, muestra el CTA para abrir el
   chat (WebView) o el WhatsApp del proveedor.
5. (**Crear solicitud** → botón que abre el WebView de `/requests/new` — no nativo en v1, §2.2.)

### 5.2 Proveedor

1. **Bandeja de solicitudes** — solicitudes que matchean su negocio (misma lógica de matching que
   la web; datos vía las mismas queries/RPC). Filtro básico producto/servicio.
2. **Hacer oferta** — acción nativa: precio fijo / rango / por hora + mensaje. Inserta en
   `provider_offers` (status `pending`). Gratis.
3. **Mis ofertas** — lista con estado; resalta las `accepted` pendientes de desbloquear.
4. **Desbloquear contacto** — acción nativa con confirmación (patrón hold-to-confirm como la web):
   muestra costo estimado, ejecuta `unlockOffer`, y al éxito revela el WhatsApp del cliente
   (`get_unlocked_offer_contact`) + CTA a chat/WhatsApp.
5. **Saldo de créditos** (solo lectura) con CTA "Recargar" → abre WebView/navegador externo (§2.2).

### 5.3 Comunes

- **Login** (Google nativo) y **splash**.
- **Home/tabs** por rol.
- **Host de WebView** reutilizable para las secciones embebidas.

---

## 6. Frontera nativo / WebView

| Superficie | v1 | Motivo |
|---|---|---|
| Estado del pedido, ofertas, aprobar, ofertar, desbloquear | **Nativo** | Es el corazón; donde se juega el "feel" premium y el push |
| Navegación de solicitudes/catálogo (básica) | **Nativo** | Necesaria para llegar a las acciones |
| Login Google | **Nativo** | Google bloquea OAuth en WebView (`disallowed_useragent`) |
| Push + deep link | **Nativo** | Objetivo central de la v1 |
| Crear solicitud (IA) | WebView | Flujo conversacional con streaming; alto riesgo de reescritura |
| Recarga / PayPal | WebView → **navegador externo** para PayPal | Flujo de dinero; política PayPal prohíbe WebView |
| Perfil, config, historial, chat | WebView | Aún no migrado; bajo valor para el "feel" inicial |
| Alta/registro proveedor | WebView | Wizard largo, fuera del corazón |

**Regla de host WebView:** el WebView embebido carga rutas de `jayalo.com` con la sesión ya
inyectada (§7). Cualquier navegación que Google/PayPal rechacen en WebView se delega al navegador
del sistema (`url_launcher` con `LaunchMode.externalApplication`).

---

## 7. Costura de sesión Supabase (nativo ↔ WebView) — punto delicado

**Problema:** el login lo hace el shell nativo (Google → `signInWithIdToken`). Los WebViews cargan
`jayalo.com`, cuyo cliente Supabase JS lee la sesión de `localStorage`. Si no se comparte, el
usuario tendría que volver a loguearse dentro del WebView (y no puede: Google bloquea OAuth en
WebView).

**Enfoque recomendado (a detallar en el plan):** tras el login nativo, obtener la sesión de
`supabase_flutter` (`supabase.auth.currentSession` → `accessToken`, `refreshToken`) y, **antes de
cargar la URL** en el WebView, inyectar esa sesión en el `localStorage` del WebView bajo la **clave
de storage de Supabase** que usa el cliente web (`sb-<project-ref>-auth-token`, formato JSON de
GoTrue). Con eso el cliente JS de `jayalo.com` arranca ya autenticado.

- **Mecanismo:** `webview_flutter` permite ejecutar JS antes/durante la carga
  (`runJavaScript` en un handler de navegación, o inyección temprana). Se escribe el JSON de sesión
  en `window.localStorage` con la clave correcta y luego se navega/recarga.
- **Refresh de token:** GoTrue en el WebView refresca solo mientras la página vive; el shell nativo
  es la fuente de verdad. Al reabrir un WebView, se re-inyecta la sesión vigente del shell nativo
  (que pudo haber refrescado su token). Evita el WebView quedándose con un token viejo.
- **Cierre de sesión:** logout en el shell → limpiar el `localStorage`/cookies del WebView
  (`WebViewCookieManager` + `runJavaScript('localStorage.clear()')`).

**Riesgos / a verificar en el plan:**
- Confirmar la **clave exacta** y el **shape JSON** que el cliente Supabase JS de `jayalo.com`
  espera en `localStorage` (leer cómo persiste la sesión en la web actual antes de codificar).
- Sitio SSR: `jayalo.com` es SSR (TanStack Start). La sesión que importa para las acciones del
  usuario es la del **cliente** (localStorage), no cookies SSR; verificar que las rutas embebidas
  (chat, perfil) funcionan solo con la sesión en localStorage.
- Si en el futuro la web adopta cookies httpOnly para auth, esta costura cambia — documentar como
  supuesto.

---

## 8. Push notifications (FCM)

**Objetivo v1:** el usuario recibe un push nativo en cada transición del corazón (§4.3) y, al
tocarlo, la app abre (deep link) la pantalla de estado correspondiente.

**Lado app (nativo, en `jayalo-flutter`):**
- `firebase_messaging` + un proyecto Firebase enganchado al mismo package `com.jayalo.app`.
- Al loguearse / al arrancar: obtener el **FCM token** y guardarlo en una tabla nueva
  `device_tokens (user_id, token, platform, updated_at)` vía `supabase_flutter` (RLS: cada usuario
  gestiona solo sus tokens). Refrescar el token en `onTokenRefresh`.
- Manejar mensajes en foreground/background/terminated; el payload incluye `type` + `request_id` /
  `offer_id` para el deep link.

**Lado backend (costura mínima, sin tocar el frontend web) — ver §9.**

---

## 9. Costura de backend para el push (única costura con lo existente)

Hoy, en cada uno de los cuatro eventos (§4.3), la BD ya dispara efectos (insert en `notifications`
y/o llamada al Worker para el correo). Para el push, la **opción recomendada** es **NO tocar el
frontend web ni el Worker de jayalo-main**, sino añadir una pieza de backend aislada:

1. **Tabla `device_tokens`** (migración nueva en el proyecto Supabase). RLS por dueño; grants de
   mínimo privilegio (patrón del proyecto).
2. **Un emisor de FCM** que, en los mismos puntos de disparo que hoy generan `notifications`/correo,
   lea los `device_tokens` del destinatario y envíe el push vía FCM HTTP v1. Preferencia por una
   **Supabase Edge Function** dedicada (`send-push`) invocada por el trigger existente, para no
   modificar el Worker de `jayalo-main`. (Alternativa: un endpoint nuevo en el Worker — se descarta
   en v1 para respetar el aislamiento; se decide en el plan.)

> Nota de honestidad sobre el aislamiento: la **web (frontend) no se toca** en ningún caso. Pero el
> push **sí requiere** este añadido de datos/servidor (tabla + emisor). Es aditivo, aislado y
> reversible, pero no es "cero backend". Es la única costura de la v1. **▶ A validar por el PO**
> (§11): ¿Edge Function nueva vs endpoint en el Worker? ¿proyecto Firebase nuevo o reusar uno?

---

## 10. Stack técnico

**Flutter (todo GRATIS, licencia BSD). NO usar FlutterFlow** (es un builder de pago tipo Lovable —
justo la dependencia de la que estamos saliendo).

| Paquete | Para qué |
|---|---|
| `supabase_flutter` | Auth (GoTrue) + PostgREST + RLS heredada. Mismo proyecto `mfaikl…` |
| `google_sign_in` | Login nativo Google (hoja de cuentas Android) |
| `firebase_messaging` + `firebase_core` | Push FCM |
| `webview_flutter` | Secciones híbridas embebidas |
| `go_router` | Navegación nativa + deep links del push |
| `url_launcher` | PayPal / WhatsApp / enlaces al navegador externo |
| Material 3 (nativo) + motion (`Lottie`/`Rive` si hace falta) | El "feel" premium |

**Reuso de la config OAuth de hoy (no se pierde el trabajo caro):**
- OAuth client **Android** en Google Cloud (proyecto `jayalo-501005`, package `com.jayalo.app`,
  SHA-1 debug `C0:02:66:E7:F6:0A:88:9B:02:4A:C3:14:C4:9F:04:8E:B6:89:45:2E`) → sirve idéntico para
  `google_sign_in` (mismo package, mismo debug keystore).
- **Web Client ID** `606236193258-80p6roa1ohq3dd63n3uodnrvqncpt44k.apps.googleusercontent.com` →
  para `supabase.auth.signInWithIdToken` en Flutter.
- Android Studio + SDK API 36 ya instalados.

**Gotcha conocido de auth:** Turnstile global puede devolver `captcha_failed` en
`signInWithIdToken`. Fix conocido: pasar `options.captchaToken`. Verificar en el device.

**Setup pendiente (una vez, guiado con el PO):**
- Instalar el **SDK de Flutter** en Windows.
- Crear/enganchar el **proyecto Firebase** (`google-services.json` para `com.jayalo.app`).

---

## 11. Trabajo previo en jayalo-main (fuera de este repo)

- **Revertir el commit `cb675fc`** (helper `signInWithGoogle`/`detectGoogleLoginMode` para la
  cáscara Capacitor). Era específico de Capacitor (detecta `window.Capacitor`); Flutter no lo usa.
  Está **sin desplegar**, así que revertirlo no afecta prod y deja `jayalo-main` limpio. Decisión
  del PO (2026-07-16). *(Este cambio ocurre en el repo `jayalo-main`, no en `jayalo-flutter`; se
  ejecuta como paso previo, con la confirmación de deploy habitual del PO.)*
- El repo Capacitor `jayalo-android` queda **archivado** (poco código; superado por este enfoque).

---

## 12. Decisiones abiertas para validar con el PO

1. **Crear solicitud (IA):** se deja en WebView en v1 (§2.2). ¿De acuerdo, o el PO la quiere nativa
   ya en la v1? (Subiría el alcance de forma notable.)
2. **Push — arquitectura del emisor:** Edge Function `send-push` (recomendado, respeta aislamiento)
   vs endpoint en el Worker de `jayalo-main`. Y: ¿proyecto Firebase nuevo o reusar uno existente?
3. **Nombre del repo:** `jayalo-flutter` (usado por defecto). ¿OK?
4. **Alcance del "feel":** ¿la v1 debe incluir ya motion/transiciones pulidas (Rive/Lottie), o
   basta Material 3 estándar para la primera validación de rendimiento?

---

## 13. Criterios de éxito de la v1

- El PO instala el APK debug en su teléfono de gama media y el corazón **se siente nativo**
  (transiciones fluidas, sin "sabor a web").
- Un ciclo completo funciona de punta a punta en el device, con dos cuentas de prueba:
  solicitud → oferta → aprobación → desbloqueo (con créditos reales de prueba) → contacto.
- Cada transición dispara un **push nativo** que abre la pantalla de estado correcta (deep link).
- El login Google nativo funciona y la sesión se comparte con al menos un WebView (p. ej. chat o
  perfil) **sin re-login**.
- La web de `jayalo.com` (frontend) **no cambió**; los cobros siguen pasando por las RPCs atómicas
  server-side (verificable: el `_cost` del cliente se ignora).

---

## Apéndice — referencias en el código de `jayalo-main` (fuente de verdad)

- Máquina de estados / fases: `src/routes/requests/$requestId.tsx` (fases `waiting…completed`),
  `src/components/marketplace/MyRequestsView.tsx` (aceptación, `hasAcceptedElsewhere`).
- Lado proveedor: `src/components/provider/ProviderOffersSection.tsx` (estados de oferta, unlock).
- Desbloqueo/cobro: `src/lib/offer-unlock.functions.ts` (`unlockOffer` → `try_unlock_offer`),
  `src/lib/pointPricing.ts` (costo para UI).
- Revelado de contacto: migración `…_whatsapp_reveal_offer.sql` (`get_unlocked_offer_contact`).
- Reglas de dinero y seguridad: `CLAUDE.md` → "Seguridad — decisiones tomadas" (el costo se calcula
  dentro de la RPC; wallet atómica; grants de mínimo privilegio).
