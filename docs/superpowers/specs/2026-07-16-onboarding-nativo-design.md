# Spec de diseño — Onboarding nativo (consumidor y proveedor)

- **Fecha:** 2026-07-16
- **Estado:** propuesta (pendiente de revisión del PO)
- **Repo:** `jayalo-app` (+ 2 ADRs en jayalo-main: 0029 RPC atómica, 0030 OTP Edge Functions)
- **Siguiente paso:** validación del PO → `superpowers:writing-plans` sobre este spec.

> Este documento describe el **qué** y el **porqué**. El **cómo** paso a paso vive en el plan
> de implementación que se escribe después. Complementa (no reemplaza) el spec de la v1
> (`2026-07-16-v1-corazon-flutter-design.md`): elimina su supuesto §3.2 "la app asume cuentas
> ya existentes".

---

## 0. Decisiones del PO que gobiernan este spec (2026-07-16)

1. **El onboarding es 100% NATIVO** (consumidor Y proveedor). Registrarse "en jayalo.com" deja
   de ser el camino; es bloqueante de Play Store.
2. **Sin fecha: calidad sobre fecha.**
3. **Diseñar móvil desde cero** — NO portar el wizard web de 5 pasos. Usar lo que el teléfono
   da gratis: claims de Google precargadas, GPS, cámara.
4. **RPC atómica `complete_provider_onboarding` aprobada** (ADR-0029 en jayalo-main, escrita,
   estado propuesta). ADR antes de implementar: cumplido.
5. **iOS descartado** (sin Mac ni cuenta Apple). No generar `ios/`.

---

## 1. Objetivo y motivación: el bug de dinero

**Bug verificado (2026-07-16), bloqueante de Play Store:** un usuario nuevo que entra con
Google en la app queda con la fila de `profiles` creada por `handle_new_user` pero con
`phone`, `account_type` y verificación de WhatsApp en NULL — el trigger solo crea
negocio/categorías/wallet dentro del `IF pending_business`, que un login Google nunca trae.
La cadena de fallo cuesta dinero real:

1. Ese usuario crea una solicitud (nada se lo impide).
2. Un proveedor oferta, el cliente acepta, el proveedor **paga créditos** con
   `try_unlock_offer` (cobra sin mirar la verificación del cliente).
3. `get_unlocked_offer_contact` **lanza** ("El cliente no tiene WhatsApp disponible") porque
   no existe `account_verifications.whatsapp_verified_at`.
4. `my_offers_screen.dart:202` **traga la excepción** y muestra la hoja de contacto vacía:
   el proveedor pagó y no recibió nada.

La web no sufre el paso 2-3 porque chequea `can_reveal_offer_whatsapp` ANTES de cobrar
(`ProviderOffersSection.tsx:670`) — chequeo que a la app le falta (§8). El onboarding ataca
la raíz (usuarios sin identidad completa); los fixes de §8 atacan los síntomas. Se hacen ambos.

Metas:

1. **Cero usuarios "a medias"**: al terminar el onboarding, todo consumidor tiene contacto
   revelable y todo proveedor tiene negocio + categorías + wallet, atómicamente.
2. **Registro nativo digno de la Play Store**: un usuario totalmente nuevo instala, entra con
   Google y llega a operar sin tocar jayalo.com.
3. **Ningún cobro sin contraprestación posible** (fixes §8, independientes del onboarding).

---

## 2. Principios (heredados y nuevos)

- **La fuente de verdad es el modelo de datos, no las pantallas web.** Lo que el onboarding
  debe producir está definido por `profiles`, `provider_businesses`,
  `provider_business_categories`, `provider_business_rubros`, `provider_wallets` y
  `account_verifications` — no por el layout del wizard.
- **Móvil desde cero** (decisión 3): claims de Google rellenan el nombre; el GPS propone la
  ubicación; la cámara captura la foto del negocio. Cada dato que el teléfono ya sabe no se
  pregunta.
- **A-prueba-de-tontos para RD** (doctrina del QA de usabilidad): un dato por pantalla o
  grupo pequeño, copy en jerga dominicana, estados de error con salida, nunca perder lo
  tecleado (drafts en memoria durante el flujo).
- **Servidor manda**: unicidad, validez de categorías/rubros y atomicidad viven en la RPC
  (ADR-0029), no en Dart. La app solo pre-valida para UX.
- **Cubrir el camino negativo** (lección del QA: "Ese registro ya existe" a la primera):
  teléfono/WhatsApp/RNC duplicados, OTP incorrecto/expirado, sin señal GPS, sin permiso de
  cámara — todos con copy y salida definidos en el plan.

---

## 3. Alcance

### 3.1 Dentro

- **Gate post-login** (§4): sesión con `account_type` NULL → onboarding, siempre.
- **Selector de rol** (§5).
- **Onboarding de consumidor** (§6): nombre precargado, WhatsApp + OTP por SMS, ubicación
  GPS, términos.
- **Onboarding de proveedor** (§7): negocio, categorías/rubros, ubicación, WhatsApp + OTP,
  foto opcional, términos → `complete_provider_onboarding`.
- **OTP nativo** vía Edge Functions `send-otp`/`verify-otp` (ADR-0030).
- **Fixes correlacionados en la app** (§8): catch silencioso, chequeo pre-desbloqueo,
  redirección por rol.

### 3.2 Fuera

- **Keystore de release + SHA-1** en Google Cloud (el login Google se ROMPERÁ con firma
  release; `build.gradle.kts:34` firma con debug hoy). Tarea hermana obligatoria pre-Play
  Store, pero independiente de este spec — va como tarea propia en el plan o aparte.
- **Edición de perfil/negocio post-onboarding** (cambiar foto, categorías, etc.): fase
  posterior; v1 de edición sigue siendo la web.
- **Migrar la web** al RPC/Edge Functions (registrado como paso posterior en ADR-0029/0030).
- **Recarga/PayPal, chat interno, iOS**: sin cambios respecto al spec v1.

---

## 4. El gate post-login

Hoy `router.dart` solo distingue logueado/no-logueado. Nuevo estado intermedio:

| Estado tras login | Destino |
|---|---|
| Sin fila en `profiles` (carrera con el trigger) o `account_type` NULL | `/onboarding` |
| `account_type = 'consumer'` | `/client` |
| `account_type = 'provider'` **con** negocio | `/provider` |
| `account_type = 'provider'` **sin** negocio (dato legacy, no debería existir post-RPC) | `/onboarding` (rama proveedor, retoma) |

- El redirect del router consulta una sola vez por sesión y cachea; el onboarding invalida el
  caché al terminar. Salir de la app a mitad del onboarding y volver → mismo lugar (el gate
  re-dispara; los pasos completados en servidor no se repiten porque la RPC es idempotente y
  el OTP sellado persiste).
- El usuario NO puede saltarse el gate: no hay ruta del shell alcanzable con `account_type`
  NULL. Es la garantía de que el bug de §1 no puede volver a nacer.

## 5. Selector de rol

Una pantalla: "¿Cómo quieres usar Jayalo?" con dos tarjetas (pedir / ofrecer), mismo lenguaje
que la web pero composición M3 nativa.

**Regla dura (lección `choose-role.tsx:67-72`): elegir NO escribe `account_type`.** El rol se
persiste únicamente al COMPLETAR el flujo elegido (upsert del consumidor o RPC del proveedor).
Si se escribiera al elegir, quien abandona queda atrapado como proveedor-sin-negocio y el gate
ya no lo devuelve al selector. Volver atrás desde cualquier paso → selector de nuevo, sin
residuo en la BD.

## 6. Onboarding de consumidor

Produce exactamente lo que la web escribe en `choose-role.tsx:85-105` + la verificación OTP
que la web deja para después (aquí es parte del flujo, ver decisión abierta §10.1):

1. **"Así te llamas"** — nombre y apellido precargados de las claims de Google
   (`given_name`/`family_name`, fallback split de `full_name`), editables. Cero tecleo en el
   caso feliz.
2. **"Tu WhatsApp"** — teléfono RD (normalización E.164, mismas reglas que
   `normalizePhone`), luego **OTP**: "Te enviamos un código por SMS al ###" (copy SMS, no
   WhatsApp — el canal real es `app_settings.otp_channel`, hoy `'sms'`). Reenvío con
   countdown de 60s; errores con copy propio (incorrecto / expirado / demasiados intentos).
   Sella `account_verifications.whatsapp_verified_at` (fila personal) → el contacto queda
   revelable = la raíz del bug de §1 cerrada para cuentas nuevas.
3. **"Dónde estás"** — botón "Usar mi ubicación" (permiso de ubicación → lat/lng +
   `location_captured_at`) + campo de dirección en texto (obligatorio, como la web). Sin
   permiso o sin señal → solo dirección manual, lat/lng NULL (la web lo permite igual).
4. **Términos** — aceptación explícita (`terms_accepted_at`, `terms_version` = el
   `TERMS_VERSION` vigente); enlaces a /terminos y /privacidad en Custom Tab.
5. **Cierre** — upsert único de `profiles` (payload idéntico al de la web:
   `first_name,last_name,phone,whatsapp,address,lat,lng,location_captured_at,
   account_type='consumer',terms_accepted_at,terms_version`). Errores 23505 mapeados
   ("Este teléfono ya está registrado en otra cuenta…"). → `/client` con push ya operativo.

Sin RPC nueva: es una escritura única, atómica por naturaleza (ADR-0029 lo justifica).

## 7. Onboarding de proveedor

El flujo recolecta el shape `pending_business` (contrato ya validado por el trigger) y lo
entrega ENTERO a `complete_provider_onboarding` al final. Nada se escribe en la BD hasta el
cierre — abandonar en el paso N deja cero residuo (regla del §5). Contenido por paso (la
composición visual la decide la implementación, M3 §2 del spec v1):

1. **"Tu negocio"** — nombre del negocio; tipo (`informal`/`formal`, chips con explicación
   llana); si formal → RNC; qué ofreces (`productos`/`servicios`/`ambos`); toggle "Vendo al
   por mayor" (solo si ofrece productos).
2. **"Qué vendes"** — categorías (máx 2, la primera es la primaria) y rubros de esas
   categorías, como chips buscables. Misma data (`categories` mock + tabla `rubros`) que
   consume la web.
3. **"Dónde trabajas"** — GPS propone ciudad/sector (reverse geocode local si es viable, si
   no, selección manual con listas de la web); país fijo RD en v1.
4. **"Tu WhatsApp"** — número del negocio precargado con el del perfil si existe; OTP igual
   que §6.2. Al verificar DESPUÉS del cierre (ver orden abajo) se espeja el badge
   `provider_businesses.whatsapp_verified_at` si el número coincide (semántica web).
5. **"Foto" (opcional)** — cámara o galería → bucket `business-logos` (`logo_url`).
   Saltable con "Después".
6. **Términos + cierre** — un solo tap final: llama
   `complete_provider_onboarding(_first_name, _last_name, _phone, _business, _terms_version)`.
   Errores por slug (`whatsapp_taken`, `phone_taken`, `rnc_taken`) → copy específico con
   salida ("Usa otro número o inicia sesión con la cuenta que lo tiene"). → `/provider` con
   wallet en 0 y el CTA "Recargar" existente.

**Orden OTP vs RPC:** el OTP del negocio requiere `business_id` para espejar el badge → la
verificación del paso 4 se ejecuta contra la fila personal durante el flujo, y el espejo al
negocio ocurre tras el cierre (la Edge Function `verify-otp` re-sellada con `business_id`, o
el espejo diferido — detalle para el plan). Alternativa simple: paso 4 verifica solo la fila
personal y el badge del negocio se ofrece post-onboarding en `/provider` — ver §10.2.

## 8. Fixes correlacionados (independientes del onboarding, mismo PR-tema)

1. **Catch silencioso** — `my_offers_screen.dart:198-204`: hoy `catch (_) → contacto vacío`
   presenta un error de servidor como "el cliente no tiene WhatsApp". Fix: distinguir
   excepción (hoja de error con "Reintentar", conservando el derecho ya pagado) de contacto
   genuinamente no disponible.
2. **Chequeo pre-desbloqueo** — antes de cobrar, llamar `can_reveal_offer_whatsapp`
   (paridad con `ProviderOffersSection.tsx:670`). Si no es revelable, la hoja de desbloqueo
   lo dice ANTES del hold-to-confirm y no deja pagar. Cierra el "cobrado sin
   contraprestación" incluso para cuentas viejas sin verificación.
3. **Redirección por rol en el router** — hoy `initialLocation: '/client'` fijo; con el gate
   de §4 el home pasa a depender de `account_type` (el spec v1 §5 ya lo pedía: "home por
   rol").

## 9. Costuras de backend (todas en jayalo-main, ninguna toca el Worker)

| Pieza | Qué es | ADR |
|---|---|---|
| `complete_provider_onboarding` | RPC SECURITY DEFINER atómica e idempotente; REVOKE anon; slugs de error estables; check nuevo en `db-security-check.sql` | 0029 (escrita, propuesta) |
| `send-otp` / `verify-otp` | Edge Functions con el hardening exacto de `whatsapp-otp.functions.ts` (cooldown, TTL, intentos, rate limit, persist-antes-de-enviar, guard `owns_business`, espejo de badge); secretos Twilio por CLI desde archivo | 0030 (escrita, propuesta) |

La web migra a ambas DESPUÉS (registrado en los ADRs como deuda con dueño, no como intención).

## 10. Decisiones — cerradas y abiertas

**Cerradas (PO, 2026-07-16):** onboarding 100% nativo · sin fecha · diseño móvil desde cero ·
RPC atómica · iOS descartado.

**Abiertas (validar en la revisión de este spec):**

1. **¿OTP obligatorio para el consumidor dentro del onboarding?** Propuesta: SÍ (este spec,
   §6.2). Es más fricción que la web (que lo difiere), pero garantiza que toda solicitud
   nueva sea desbloqueable — y el producto vende leads con WhatsApp verificado. Alternativa:
   saltable con re-prompt bloqueante al crear la primera solicitud.
2. **¿Badge de WhatsApp del negocio dentro del onboarding o después?** Propuesta: la
   verificación personal va dentro (paso 4) y el espejo del badge se resuelve tras el cierre;
   si complica, mover el badge a post-onboarding como la web (§7, orden OTP vs RPC).
3. **¿Foto del negocio en v1 del onboarding?** Propuesta: sí pero opcional y saltable (§7.5).
   Quitar el paso si el PO prefiere el flujo mínimo.

## 11. Criterios de éxito

- **Cuenta Google NUEVA de punta a punta en el Redmi**: instalar → Google → onboarding
  consumidor (nombre precargado, OTP por SMS real, GPS) → crear solicitud; con la segunda
  cuenta: onboarding proveedor → ofertar → aceptación → desbloqueo → **el contacto revela el
  número verificado** (el bug de §1, reproducido antes del fix, ya no reproduce).
- **Atomicidad demostrada**: simular fallo a mitad del alta (p. ej. categoría inválida) →
  cero filas nuevas en `profiles`/`provider_businesses`/`provider_wallets`; reintento con
  éxito no duplica nada (`already` funciona).
- **Camino negativo cubierto**: WhatsApp duplicado, OTP incorrecto/expirado, sin GPS, sin
  cámara — cada uno con su copy y su salida, probados en device.
- **Abandono limpio**: salir a mitad del flujo y volver → selector/paso correcto, sin
  proveedor-sin-negocio ni consumidor a medias en la BD.
- Los fixes §8: desbloquear una oferta de un cliente sin verificación queda IMPOSIBLE (el
  sheet lo bloquea antes de cobrar), y un error de red en el revelado muestra "Reintentar",
  nunca la hoja vacía.

---

## Apéndice — referencias (fuente de verdad en jayalo-main)

- Trigger de alta y shape `pending_business`: `supabase/migrations/20260711150000_wholesale_flags.sql`.
- Flujo authed del wizard (lo que la RPC atomiza): `src/components/provider/ProviderSignupWizard.tsx:643-810`.
- Payload del consumidor: `src/routes/auth/choose-role.tsx:85-105`; lección del selector: `:62-75`.
- OTP actual (hardening a replicar): `src/lib/whatsapp-otp.functions.ts`.
- Gate de revelado: `supabase/migrations/20260715060000_reveal_returns_verified_whatsapp.sql`.
- Chequeo pre-cobro de la web: `src/components/provider/ProviderOffersSection.tsx:670`.
- Bug del catch en la app: `app/lib/features/provider/my_offers_screen.dart:198-204` (este repo).
- ADRs: `docs/adr/0029-rpc-atomica-complete-provider-onboarding.md`,
  `docs/adr/0030-otp-nativo-via-edge-functions.md` (jayalo-main).
