# Diseño — "Cerrada" en la lista y los avisos del servidor que decían "Nuevo mensaje"

Fecha: 2026-08-03
Origen: `docs/qa/2026-08-03-hallazgo-cerrada-y-aviso-completado.md` (hallazgo del PO)
Estado: **aprobado por el PO**. Listo para plan de implementación.

Dos partes independientes que comparten un concepto: qué pasa cuando un trato termina. Se pueden
implementar por separado y en cualquier orden.

---

## Lo que el ticket daba por cierto y no lo era

El ticket se escribió sin acceso a la base. Con el conector de Supabase autorizado
(proyecto `jayalo`, `mfaiklvobnvgusbcssbx`) se comprobaron los hechos y tres puntos cambian el
diseño:

1. **El autocierre por inactividad existe y lleva tiempo corriendo.** El ticket lo daba por
   "specificado pero sin construir". Hay dos crons activos: `auto_close_stale_conversations`
   (jobid 9, cada hora, umbral 72 h configurable en `app_settings.conversation_autoclose_hours`) y
   `warn_stale_conversations` (jobid 10, aviso previo a las 48 h). De 26 conversaciones, 25 están
   cerradas y **13 lo están por inactividad**, con la oferta en `accepted` y la solicitud en
   `open`. Esas 13 son exactamente el caso que reportó el PO.

2. **"Nuevo mensaje" no es un cartel, son cuatro.** `notify_conversation_message` dispara con
   cada INSERT en `conversation_messages` y escribe el título a pelo, sin mirar el `kind`.

3. **Reutilizar `sale_completed_provider` es una trampa.** El ticket lo sugería. Ese kind **ya se
   emite** (3 filas, título "Venta completada"), va al **proveedor**, y está en la whitelist de
   `enqueue_notification_email` con la plantilla "Venta completada: resumen y factura". Usarlo para
   avisar al cliente le mandaría la factura de una venta que no es suya. Queda descartado.

Además, un hecho que simplifica la parte B: **las conversaciones solo existen para ofertas
`accepted` o `completed`** (0 conversaciones para `pending`/`rejected`/`cancelled`, verificado).
Así que "conversación cerrada" siempre implica que hubo trato aceptado — no hay caso ambiguo.

---

## Parte A — los avisos del servidor

### El defecto

`notify_conversation_message` inserta una notificación `message_new` con título fijo
`'Nuevo mensaje'` para **todo** INSERT, incluidos los `kind='system'` y `kind='audit'`, que son
carteles de plataforma y no mensajes de nadie. Verificado contra las notificaciones reales:

| Cartel | `kind` | Lo escribe | Llega como |
|---|---|---|---|
| ✓ Marcado como completado por el proveedor. | `system` | `mark_conversation_completed` | "Nuevo mensaje" |
| ✓ Pedido marcado como completado. El chat queda cerrado. | `audit` | `close_conversation_on_offer_completed` | "Nuevo mensaje" |
| ⏳ Este chat está por cerrarse por inactividad… | `audit` | `warn_stale_conversations` | "Nuevo mensaje" |
| El chat se cerró automáticamente por inactividad… | `audit` | `auto_close_stale_conversations` | "Nuevo mensaje" |

Dos defectos más, del mismo origen:

- **El completado se cuenta dos veces.** `mark_conversation_completed` inserta el `system` y además
  pone `provider_offers.status='completed'`, lo que dispara `close_conversation_on_offer_completed`,
  que inserta el `audit`. Resultado: dos carteles seguidos en el chat diciendo lo mismo, y dos
  notificaciones.
- **El proveedor no se entera.** Los `audit` llevan `sender_id = NULL`, y el reparto del trigger
  (`CASE WHEN NEW.sender_id = v_customer THEN v_provider ELSE v_customer END`) manda siempre al
  cliente. El proveedor nunca recibe el aviso de que su chat va a cerrarse — justamente el aviso
  accionable.

### El principio

**Un mensaje del servidor no es un mensaje.** Deja de generar `message_new` y, cuando merece aviso,
lleva el suyo propio, dirigido a las dos partes.

El molde ya existe en el repo y funciona: `warn_stale_conversations` inserta el cartel en el chat
**y además** una notificación `conversation_inactivity_warning` ("Tu chat cerrará por inactividad",
38 filas en producción) a ambos, vía
`CROSS JOIN LATERAL (VALUES (c.customer_id), (c.provider_user_id))`. El único defecto de ese camino
es el `message_new` espurio que el `audit` genera encima.

### Los cambios (una migración)

1. **`notify_conversation_message` se retira ante los carteles.** `RETURN NEW` temprano si
   `NEW.kind IN ('system','audit')`. Esto solo elimina los cuatro títulos falsos y el duplicado del
   aviso de inactividad.

2. **`mark_conversation_completed` emite su notificación.** Kind nuevo `conversation_completed`, a
   ambas partes, con el patrón de `warn_stale_conversations`:
   - Título: **"Trato marcado como completado"**
   - Cuerpo: **"El proveedor dio por completado el trato. Ya puedes calificar."**
   - Link: `'/messages?c=' || id`, `entity_type='conversation'`, `entity_id = id`
   - Va dentro del `IF v_status = 'abierto'` que ya existe, para conservar la idempotencia.

3. **`auto_close_stale_conversations` emite la suya.** Kind nuevo `conversation_closed_inactivity`,
   a ambas partes:
   - Título: **"Tu chat se cerró por inactividad"**
   - Cuerpo: **"Nadie escribió en 72 horas. Puedes calificar la transacción."**
   - El "72" se toma de `v_hours`, que la función ya calcula — no se escribe a mano.

4. **Se corta el cartel duplicado.** En `close_conversation_on_offer_completed`, el INSERT del
   `audit` queda condicionado a que su `UPDATE ... WHERE id = v_conv_id AND status = 'abierto'` haya
   afectado alguna fila (`GET DIAGNOSTICS`). Cuando el cierre vino de `mark_conversation_completed`
   la conversación ya está `cerrado`, así que el cartel no se repite. Cuando el cierre viene de
   completar la oferta por otra vía, el cartel sigue apareciendo como hoy.

### Cambios en la app y la web (pequeños, no son la migración)

- `iconFor` (`app/lib/domain/notifications.dart:29`) recibe los dos kinds nuevos. Sin eso caen al
  fallback por familia, que para `system` es la campana. `conversation_inactivity_warning` ya está
  ahí (`notifications.dart:47`, reloj de arena).
- `iconFor` de la web (`NotificationsBell.tsx:44-74`) recibe los dos kinds nuevos **y también
  `conversation_inactivity_warning`, que hoy le falta**: su `default` es `MessageSquare`, un globo
  de chat, así que la web ya pinta hoy "Tu chat cerrará por inactividad" con icono de mensaje — el
  mismo error de fondo que arregla la parte A, en otra superficie. Se cierra en la misma tanda.
- `familyFor` (`notifications.dart:14`): los `conversation_*` caen hoy en `NotifFamily.system`. Se
  deja así a propósito — no son ofertas ni mensajes.
- `mapLinkToRoute` no necesita cambios: el link `'/messages?c=<id>'` ya está cubierto
  (`notifications.dart:140`).

### Efectos secundarios aceptados

- **El correo del completado desaparece.** Hoy el completado viaja como `message_new`, que **sí**
  está en la whitelist de `enqueue_notification_email` (con tope de 1 correo/día por usuario vía
  `try_consume_rate_limit`), así que puede salir un "Tienes mensajes pendientes en Jayalo" — un
  correo que además miente. Los kinds nuevos **no** se añaden a la whitelist, igual que
  `conversation_inactivity_warning`. Si el PO quiere correo propio, es una tanda aparte con su
  plantilla en `notification-templates.ts`.
- **El badge de chats sin leer deja de encenderse con los carteles.** Los contadores de la app y la
  web cuentan notificaciones `message_new` sin leer; un cartel de servidor ya no creará una. El
  aviso sigue llegando por su notificación propia. Es el comportamiento correcto, pero es un cambio
  visible → entra al smoke.
- **`notifications.kind` no tiene CHECK** (verificado): los kinds nuevos no necesitan migración de
  constraint.
- **`notify_on_conversation_closed`** (los `review_pending_reminder` al cerrar) no se toca. Es un
  camino distinto y correcto.

---

## Parte B — la fase "Cerrada"

### El defecto

`RequestPhase` (`app/lib/domain/phase.dart:1`) conoce cinco fases: `waiting`, `withOffers`,
`accepted`, `unlocked`, `completed`. Una solicitud cuyo chat murió sin completarse sigue pintándose
como trato vivo ("Aceptada" o "En contacto"). Hoy son 13 casos en producción.

**Nada pone `customer_requests.status` en `'closed'`** — confirmado. El valor está contemplado de
forma defensiva en `phase.dart:20` y en la web (`$requestId.tsx:1147`), donde además mapea a
**"Completado"**. Así que no basta con mapear un estado existente, y escribir ese valor sería peor:
haría que la web anuncie como completado un trato que nunca se completó.

### La regla

> La oferta aceptada tiene su conversación con `closed_at` puesto, y la oferta **no** está
> `completed` → la solicitud es **Cerrada**.

Se deriva de datos que ya existen; no se escribe estado nuevo. Cubre los tres caminos de muerte con
una sola condición:

- autocierre por inactividad → `status='cerrado'`, `closed_at` puesto, oferta sigue `accepted`;
- "Marcar como no concretado" → `status='perdido'` (`repos.dart:1679`), `closed_at` puesto por el
  trigger `set_conversation_closed_at`, oferta sigue `accepted`;
- completado → oferta pasa a `completed` → **no** entra en "Cerrada", entra en "Completada".

**El orden de evaluación es parte del contrato**: `completed` se decide primero y gana siempre.

### Dónde vive

En las dos superficies a la vez, con la misma regla. No se escribe estado en la base, así que no hay
dos verdades posibles: ambas leen `conversations.closed_at`. Tocar las dos evita que la web siga
diciendo "En contacto" de un trato muerto.

La web **no tiene lista de solicitudes del cliente** (`/requests/mine` es un `redirect` a
`/requests`, el feed público del marketplace), así que la única superficie web afectada es el
detalle `/requests/$requestId`.

### App

- **`phase.dart`**: valor nuevo `RequestPhase.closed`. `OfferLite` gana el dato de si la
  conversación de esa oferta está cerrada; `phaseForRequest` lo evalúa después de `completed` y
  antes de `unlocked`.
- **`my_requests_screen._fetch`** (`:314`): una consulta más a `conversations`, seleccionando solo
  `source_id, closed_at`, filtrada con `inFilter('source_id', <ids de ofertas accepted>)` — ids que
  ya están en memoria tras la consulta de `provider_offers`. **Si no hay ninguna oferta `accepted`,
  la consulta no se hace.** La pantalla ya pasó por auditoría de rendimiento; esta es una
  ida-y-vuelta más, sobre índice y con proyección mínima.
- **`toneFor`** (`brand_kit.dart:78`): `closed` devuelve el mismo gris que `completed`
  (`JayaloStatus.completedLight/Dark`, `#EFF2F5` / `#2A2E33` — ya es gris neutro, no violeta).
- **La banda violeta no se toca.** Está condicionada a `phase == RequestPhase.completed`
  (`my_requests_screen.dart:864`), así que `closed` cae por su cuenta en la rama `else` y sale la
  píldora gris. Esto satisface literalmente el pedido del PO: apagada como la completada, sin el
  violeta.
- **`phaseChip`** (`my_requests_screen.dart:29`): `closed => 'Cerrada'`, sin conteo de ofertas.
  Ícono: uno de cierre neutro (p. ej. `Icons.lock_outline`), no `done_all` — que es el de
  completada.
- **Permisos**: `blockedReasonForPhase` (`:53`) hoy decide de una vez si se puede editar **y**
  borrar; el swipe pasa `blockedReason != null → actions: []` (`:637`). Se parte en dos motivos
  independientes, para que `closed` permita **borrar** pero no **editar**. Las demás fases conservan
  su comportamiento exacto: `waiting`/`withOffers` ambas cosas, `accepted`/`unlocked`/`completed`
  ninguna.

### El borrado necesita además una migración

Borrar va por la RPC `cancel_customer_request`, que **rechaza con `unlocked_offer_exists` si alguna
oferta de la solicitud tiene `unlocked_at` puesto**. Comprobado contra producción: **las 13
solicitudes cerradas tienen su oferta desbloqueada** — es inevitable, porque el proveedor paga el
desbloqueo justo para abrir el chat que después se cerró. Sin tocar la RPC, el botón "Eliminar"
fallaría siempre, y el toast existente (*"Responde a sus ofertas — si no aceptas ninguna, queda
desierta"*) no tiene sentido en un trato ya cerrado.

Decisión del PO: **añadir una excepción al guard**. El guard existe para no dejar sin respuesta a
quien pagó; cuando la conversación de esa oferta está cerrada y la oferta no se completó, el
proveedor ya obtuvo el contacto y el chat no puede reabrirse, así que el motivo no aplica. La
condición de la excepción es **la misma regla de la fase "Cerrada"**, escrita en SQL — deben
mantenerse en sincronía.

Es una migración sobre una RPC que toca dinero: se verifica en `BEGIN`/`ROLLBACK` contra producción
antes de aplicarse, incluyendo el caso que debe seguir bloqueado (oferta desbloqueada con
conversación **abierta**).
- **Consumidores del enum a revisar**: `request_status_screen.dart`, `request_detail_sheet.dart`,
  `brand_kit.dart`. Cada `switch` sobre `RequestPhase` es exhaustivo, así que el compilador señala
  todos los sitios — no hay que buscarlos a mano.

### Web

Mismo cálculo en `src/routes/requests/$requestId.tsx`, donde hoy se derivan las fases
(`:1146-1164`). El estado de conversación por oferta se suma al `offerExtras` que ya se trae por
oferta (`:298`), siguiendo su patrón. La fase nueva se pinta con el gris ya existente y sin el
tratamiento de completado.

---

## Qué comprobar antes de dar el arreglo por bueno

**Parte A** (requiere el conector de Supabase; verificable en `BEGIN`/`ROLLBACK` contra producción
antes de aplicar):

- Marcar completada una conversación genera **una** notificación por parte, titulada "Trato marcado
  como completado", y **ningún** `message_new`.
- En el chat aparece **un** cartel de completado, no dos.
- El proveedor recibe el aviso, no solo el cliente.
- Un mensaje de persona (`text`, `image`, `address`, `quick`) sigue generando su `message_new` con
  el preview correcto por tipo — el camino normal no se toca.
- El cierre por inactividad genera `conversation_closed_inactivity` a ambas partes; el aviso previo
  sigue generando su `conversation_inactivity_warning` y **ya no** el "Nuevo mensaje" de encima.
- La notificación se ve con su ícono propio en la app y en la web, no con el fallback (campana en
  la app, globo de chat en la web).

**Parte B**:

- Una solicitud completada sigue en gris con su banda violeta "Completado" — sin cambios.
- Una cuya conversación se cerró sin completar sale en gris con la píldora "Cerrada", **sin**
  violeta.
- Las fases vivas (esperando / con ofertas / aceptada / en contacto) no cambian.
- Sobre una "Cerrada", el swipe ofrece **Eliminar** y no **Editar**; sobre una completada no ofrece
  ninguna de las dos.
- Eliminar una "Cerrada" **funciona de verdad** (no sale `unlocked_offer_exists`), y la solicitud
  desaparece de la lista.
- Eliminar una solicitud con oferta desbloqueada y chat **abierto** sigue bloqueada con su toast de
  siempre — la excepción no abre la puerta de par en par.
- La lista no tarda más en abrir, y una lista sin ofertas aceptadas no dispara la consulta extra.
- El detalle en la web dice lo mismo que la app para la misma solicitud.

Ninguno de estos puntos lo cubre un test automatizado por sí solo: la parte A vive en SQL y la
parte B en el cableado de la pantalla. **El smoke en device es el único gate real.**

## Alcance

- **Parte A**: una migración en el repo web (`supabase/migrations/`), más los iconos en app y web.
- **Parte B**: app (`jayalo-app`) y web (`jayalo-main`), más una segunda migración para el guard de
  borrado. El ticket original decía "solo la app" y "sin base de datos"; ambas cosas se amplían por
  decisión del PO — la web, para que las dos superficies digan lo mismo desde el primer día; la
  migración, porque sin ella el botón "Eliminar" sería decorativo.
