# Diseño: swipe que se explica, acciones en la lista de chats, y calificaciones que sí cuentan

Fecha: 2026-07-31
Repos afectados: `jayalo-app` (Flutter, principal), `jayalo-main` (web, un solo cambio de ícono)
y `mfaiklvobnvgusbcssbx` (Supabase: 1 migración).

## Contexto

Cuatro observaciones del PO sobre la app, agrupadas en cuatro tandas independientes. Cada una
se construye, revisa y prueba por separado; la única dependencia real es que la tanda B necesita
el parámetro que introduce la tanda A en `SwipeToActions`.

El brief inicial era: (1) el swipe de solicitudes no se mueve cuando la solicitud está aceptada
y nada avisa de que el gesto existe; (2) ¿cómo se elimina un chat o se pone "no concretado"?;
(3) ¿solo se califica desde el chat?; (4) el ícono de mensajes preguardados parece de IA.

Hallazgos de la investigación que cambian el enfoque respecto al brief:

1. **No es que el swipe esté bloqueado: no existe.** En `lib/features/client/my_requests_screen.dart:592`
   la tarjeta se devuelve *sin envolver* en `SwipeToActions` cuando la fase no es
   `waiting`/`withOffers`. El dedo no encuentra resistencia ni explicación porque no hay
   detector de gestos en absoluto.

2. **`SwipeToActions` se usa en un solo lugar de toda la app** (`my_requests_screen.dart:622`).
   No hay ninguna pista de descubrimiento en ninguna parte.

3. **Eliminar un chat no existe en ningún lado** — ni RPC, ni UI, ni en la web. Y no debe
   existir como borrado: la conversación es el registro de un lead que el proveedor pagó con
   créditos (doctrina del facilitador de leads). Lo que falta es archivar, no destruir.

4. **La RLS ya permite a los dos participantes cambiar el estado de la conversación.** La
   política `Participants can update status` (migración `20260709204110`) es simétrica, y el
   grant por columna (`GRANT UPDATE (status, agreed_price, …)`, migración `20260615032752`)
   incluye `status`. Que "Marcar como perdido" sea solo del proveedor es **puro gate de UI**
   en `chat_screen.dart:1085` — abrirlo al cliente no necesita migración.

5. **La calificación que el cliente da desde el chat de la app no cuenta para nada.**
   `RatingPanel` escribe en `conversation_ratings`, tabla que **nadie promedia**: su único uso
   fuera de su propia RLS es un `NOT EXISTS` de recordatorio en `20260622124204`. La reputación
   pública del proveedor sale de `business_reviews` (la leen `useProviderDashboardData.ts:384`,
   `ProviderStatsBlock.tsx:49`, `business.$id.tsx:473` y la propia app en `repos.dart:2368`).
   Es escritura muerta.

6. **`request_status_screen.dart:67` promete lo que no cumple**: en la fase Completada muestra
   "Califica al proveedor para ayudar a la comunidad" y no hay ningún control para calificar
   en esa pantalla.

7. **La app ya tiene `submitReview()` escrito y sin usar** (`repos.dart:556`), apuntando a
   `business_reviews` con `onConflict: 'business_id,reviewer_id'`. Su requisito, el índice
   único `uq_business_reviews_one_per_reviewer` (migración `20260722180100`), **ya está en
   prod** — el aviso de "no liberar una build que ejerza este camino" de su comentario ya no
   aplica y debe borrarse al usarlo.

8. **El ícono de IA está en los dos frontends**: `Icons.auto_awesome_outlined` en
   `composer.dart:188` y `Sparkles` en `messages.$conversationId.tsx:1394`.

## Objetivos

- Que deslizar una solicitud no editable **ceda y explique el motivo** en vez de quedar inerte.
- Que la primera vez se **enseñe solo** que la tarjeta se desliza.
- Poder marcar "No concretado" y **archivar** desde la lista de chats, con el mismo gesto.
- Que "No concretado" esté disponible para **ambos roles**, no solo el proveedor.
- Que la calificación del chat **mueva de verdad** las estrellas del proveedor.
- Poder calificar desde el **detalle de solicitud completada** (cliente) y desde la **bandeja**
  (proveedor), en paridad con la web.
- Que el botón de mensajes preguardados **no lea como IA**.

## No objetivos

- **Borrado real de conversaciones.** Decisión explícita del PO: nunca. Archivar oculta, no
  destruye. No se añade ninguna RPC de borrado.
- **"Marcar como completado" en el swipe.** Se queda en el ⋮ del chat: implica calificación y
  cierre de trato, y merece una pantalla, no un gesto rápido.
- **Reabrir una conversación** marcada como perdida. Sigue siendo irreversible.
- **Unificar las tres tablas de calificación.** Se descartó explícitamente (opción "unificar de
  raíz"): `conversation_ratings` sigue existiendo y escribiéndose. Ver "Deuda aceptada".
- Editar solicitudes. El botón sigue mostrando "próximamente" (`my_requests_screen.dart:641`).

---

## Tanda A · El swipe cede y se explica

### A.1 `SwipeToActions` gana modo bloqueado

`lib/features/shared/swipe_to_actions.dart` — nuevo parámetro:

```dart
/// Si no es null, el row NO ejecuta acciones: revela una sola franja gris con
/// candado + este texto, y SIEMPRE vuelve a cero al soltar.
final String? blockedReason;
```

Comportamiento cuando `blockedReason != null`:

- `_revealW` pasa a un ancho fijo mayor (la franja lleva texto de una línea, no un ícono de
  88px): **140** en vez de `actions.length * actionWidth`.
- La franja revelada es una sola: `colorScheme.surfaceContainerHighest` con
  `Icons.lock_outline` + el texto en `onSurfaceVariant`, tamaño 11, dos líneas máximo.
- **No hay snap abierto.** `onHorizontalDragEnd` ignora la decisión por velocidad/posición y
  siempre hace `_springTo(0, v)`. La franja es una revelación momentánea.
- La resistencia de goma aplica **desde el primer píxel** (no 1:1 hasta `_revealW`): `_resist`
  devuelve `_rubber(raw, _revealW)` para todo `raw > 0`. Se siente "cede pero no se queda".
- La franja no es tappable (`InkWell` sin `onTap`), y la capa que captura el tap sobre la
  tarjeta abierta se conserva para cerrar.
- `widget.group` **no se toca**: un row bloqueado nunca reclama el slot de "uno abierto a la
  vez", porque nunca se queda abierto.

Las `actions` se ignoran cuando `blockedReason != null`; la lista puede venir vacía. Assert en
el constructor: `actions.isNotEmpty || blockedReason != null`.

### A.2 La tarjeta siempre se envuelve

`lib/features/client/my_requests_screen.dart` — desaparece el `if (!canManage) return
_RequestCard(...)` de la línea 592. Ahora siempre se construye el card con `margin:
EdgeInsets.zero` y siempre se envuelve. El motivo sale de la fase:

| `RequestPhase` | `blockedReason` |
|---|---|
| `waiting`, `withOffers` | `null` (acciones normales: Eliminar / Editar) |
| `accepted` | `'Ya aceptaste una oferta: no puede editarse'` |
| `unlocked` | `'Ya están en contacto: no puede editarse'` |
| `completed` | `'Solicitud completada'` |

(`RequestPhase` tiene exactamente esos cinco valores, `lib/domain/phase.dart:1`.)

### A.3 Auto-peek la primera vez

Nuevo parámetro `bool peekOnce` en `SwipeToActions`. Solo se pasa `true` en **la primera
tarjeta no bloqueada** de la lista (no simplemente `i == 0`: si la primera está bloqueada, la
pista enseñaría el gesto en una tarjeta que no lo permite).

En `initState`, si `peekOnce && !onboardingStore.isDone('requests.swipe.v1')`:

1. Espera 600 ms (que termine el `cascadeIn` de la lista, y que la pantalla esté quieta).
2. Comprueba `mounted` y que `_dx == 0` (si el usuario ya arrastró, no interrumpir).
3. `_springTo(26, 0)`, y al asentar, `_springTo(0, 0)`.
4. `await onboardingStore.markDone('requests.swipe.v1')`.

Se reusa el `AnimationController _snap` que el widget ya tiene, y el store versionado
(`lib/features/shared/onboarding_store.dart`) que ya persiste en servidor + `SharedPreferences`
— la misma mecánica de las claves `chat.quick_replies.v1` y `chat.report.v1`.

**Reduce motion**: si `MediaQuery.disableAnimationsOf(context)` es true, no se anima; se marca
la clave como hecha igual (no se acumula una pista pendiente para siempre).

`requests.swipe.v1` es una clave **nueva**, no toca las existentes.

---

## Tanda B · Acciones en la lista de chats

### B.1 Migración

Fichero nuevo en ambos repos (`supabase/migrations/`), nombre
`20260801100000_conversation_archive.sql`:

1. **Columnas**:
   ```sql
   ALTER TABLE public.conversations
     ADD COLUMN IF NOT EXISTS archived_by_customer boolean NOT NULL DEFAULT false,
     ADD COLUMN IF NOT EXISTS archived_by_provider boolean NOT NULL DEFAULT false;
   ```

2. **Grant por columna**, sumándose al existente (no reemplazarlo):
   ```sql
   GRANT UPDATE (archived_by_customer, archived_by_provider)
     ON public.conversations TO authenticated;
   ```
   El grant vigente de `status, agreed_price, agreed_hourly_rate, agreed_estimated_hours,
   updated_at` (migración `20260615032752`) se conserva intacto.

3. **Trigger guard** — cada participante solo puede tocar *su* columna. Sin esto, el cliente
   archivaría del lado del proveedor, porque la RLS de UPDATE es simétrica. Se sigue el patrón
   de `enforce_agreed_price_provider_only` (`20260729210000`): función `SECURITY INVOKER`,
   `BEFORE UPDATE`, que lanza `P0001` si `auth.uid() = customer_id` y cambió
   `archived_by_provider`, o viceversa. `service_role` y `admin` exentos, igual que el trigger
   modelo.

4. **`get_my_conversations_list`** devuelve una columna nueva `archived boolean`, ya resuelta
   para quien llama (`CASE WHEN c.customer_id = auth.uid() THEN c.archived_by_customer ELSE
   c.archived_by_provider END`). Sigue devolviendo **todas** las filas: el filtrado es del
   cliente, para que la píldora "Archivados N" pueda contar sin un viaje extra.

   > ⚠️ **Gotcha del proyecto**: cambiar el return type de una RPC exige `DROP FUNCTION` antes
   > del `CREATE` (error 42P13), y **el DROP borra los grants**. El `REVOKE ... FROM anon` +
   > `GRANT EXECUTE ... TO authenticated` al final de la migración es obligatorio.

5. Verificación en `BEGIN`/`ROLLBACK` antes de aplicar a prod, según la rutina del proyecto.

`src/integrations/supabase/types.ts` (web) se regenera desde la BD real tras aplicar; **no** se
parchea a mano ni se añaden overrides en `database.ts`.

### B.2 Repo de la app

`lib/data/repos.dart`:

```dart
Future<void> setConversationArchived(String convId, bool archived, {required bool asProvider});
```

Actualiza la columna que corresponde al rol. `markConversationLost` ya existe (línea 1543) y no
cambia. Ambas invalidan `AppCaches.conversations`.

### B.3 Lista de chats

`lib/features/chat/conversations_screen.dart`:

- Cada `_ConversationRow` se envuelve en el mismo `SwipeToActions`, con `radius: 0` y `margin:
  EdgeInsets.zero` para no romper la lista plana (filas separadas por `Divider`, doctrina
  vigente). Ambos ya son parámetros del widget — no hace falta tocarlo.
- Un `ValueNotifier<Object?>` de grupo por pantalla, igual que `_openRow` en solicitudes.
- Acciones según la pestaña activa:

  | Pestaña | Franjas |
  |---|---|
  | Abierto | `No concretado` (`colorScheme.error`) · `Archivar` (`outline`) |
  | Completado | `Archivar` |
  | No concretado | `Archivar` |
  | Archivados | `Desarchivar` |

- **"No concretado" pide confirmación siempre.** Diálogo con el copy explícito de que es
  irreversible: *"El chat se cierra y no puede reabrirse."* Sin esto, un gesto rápido mata una
  conversación para los dos participantes.
- **Cuarta píldora "Archivados N"**, añadida a `_tabs` dinámicamente y **solo visible si hay al
  menos una conversación archivada**. Los archivados se excluyen de las otras tres pestañas y
  de los conteos de sus píldoras.
- El badge de la barra (`messagesBadge.set`, línea 160) **sigue contando los archivados**:
  archivar organiza la bandeja, no silencia mensajes sin leer. Si el PO lo quiere al revés es
  un cambio de una línea, pero el default es no perder avisos.

### B.4 Menú del chat

`lib/features/chat/chat_screen.dart:1085` — el `if (_isProvider && _isOpen)` que envuelve
"Marcar como completado" y "Marcar como perdido" se parte:

- `if (_isOpen)` → "Marcar como perdido" (ambos roles).
- `if (_isProvider && _isOpen)` → "Marcar como completado" (sigue siendo del proveedor: cierra
  el trato y dispara la calificación).

"Marcar como perdido" gana la misma confirmación que el swipe (mismo diálogo, un solo helper en
`widgets/chat_dialogs.dart`).

---

## Tanda C · Calificaciones que cuentan

### C.1 Arreglar la fuente

`lib/features/chat/widgets/rating_form.dart`, `_RatingPanelState._submit` (línea ~165): tras
`submitConversationRating`, llama también `submitReview(businessId:, rating:, comment:)` →
`business_reviews`, que es lo que mueve las estrellas.

Necesita el `business_id`, que hoy solo se resuelve para el proveedor. `chat_screen.dart`
generaliza `_maybeLoadProviderReview` a `_loadReviewContext`, que resuelve el negocio **para
los dos lados** según el tipo de conversación:

| `conv['kind']` | `source_id` apunta a | business_id |
|---|---|---|
| `offer` | `provider_offers` | `offerBusinessId()` (ya existe, `repos.dart:1612`) |
| `product_interest` | `product_interests` | helper nuevo `interestBusinessId()` — la tabla tiene `business_id` directo (`20260607182500`) |

Son los dos únicos tipos: `get_or_create_conversation` lanza `Invalid kind` para cualquier otro.

La escritura en `business_reviews` es **best-effort**: si falla, la nota ya quedó guardada en
`conversation_ratings` y el usuario ya vio el "Gracias por tu calificación". Se registra el
error y no se rompe el flujo. `submitReview` es un upsert, así que es idempotente ante
reintentos.

Al usarlo, **borrar de `repos.dart:565` el aviso** "hasta que esa migración esté aplicada, NO
liberar una build que ejerza este camino" y la frase "`business_reviews` hoy solo la escribe la
web": ambas quedan obsoletas con este cambio.

### C.2 Calificar desde el detalle de solicitud

`lib/features/client/request_status_screen.dart`: en fase `completed`, panel de calificar bajo
el héroe, cerrando la promesa del copy de la línea 67. Reusa `RatingPanel` (que tras C.1 ya
escribe en las dos tablas). Si el cliente ya calificó, muestra la nota dada en vez del
formulario, igual que hace la web en `$requestId.tsx:2195`.

Necesita `conversation_id` y `business_id` de la oferta aceptada de esa solicitud; la pantalla
ya carga las ofertas para derivar la fase.

### C.3 Calificar al cliente desde la bandeja

`lib/features/provider/my_offers_screen.dart` — es el análogo exacto de
`ProviderOffersSection.tsx` de la web. Sus ofertas ya vienen agrupadas por estado
(`_acceptedCard` para las aceptadas, y el grupo de cerradas que incluye `completed`, líneas
77-85).

En las ofertas `accepted` desbloqueadas y en las `completed` que no tengan reseña del cliente,
la tarjeta gana un botón "Calificar al cliente" que abre `CustomerRatingPanel` en una hoja.
Reusa `hasCustomerReview(offerId)` y `offerBusinessId(offerId)`, que ya existen. El estado de
"¿ya calificó?" se resuelve en lote al cargar la lista, no por tarjeta, para no disparar N
consultas.

**No** se replica el `UPDATE provider_offers SET status='completed'` que la web hace tras
calificar (`ProviderOffersSection.tsx:928`): en la app el cierre lo hace
`mark_conversation_completed`, y duplicar el flip desde dos sitios invita a divergencia. Se
verifica en QA que la oferta acabe en `completed` por el camino de la RPC.

---

## Tanda D · El ícono

| Dónde | De | A |
|---|---|---|
| `app/lib/features/chat/widgets/composer.dart:188` | `Icons.auto_awesome_outlined` | `Icons.quickreply_outlined` |
| `src/routes/messages.$conversationId.tsx:16,1394` | `Sparkles` | `MessageSquareQuote` |

Material trae la burbuja-con-rayo (`quickreply`); lucide no, y `MessageSquareQuote` (burbuja con
comillas = mensaje enlatado) es lo más cercano al mismo concepto. **No quedarán idénticos entre
app y web**, y es aceptado: lo que importa es que ninguno lea como IA.

`Icons.psychology_outlined` se descartó pese a ser "pensamiento": es un cerebro, y leería como
IA *más* que las chispitas.

El copy del onboarding (`onboarding_copy.dart:58`, *"Aquí eliges mensajes predefinidos para
responder rápido"*) sigue siendo correcto: no se toca ni se sube la versión de
`chat.quick_replies.v1`.

---

## Pruebas

**Tanda A** (widget tests sobre `SwipeToActions`):
- Con `blockedReason`, arrastrar revela la franja y al soltar `_dx` vuelve a 0 (nunca queda
  abierta), y `onTap` de ninguna acción se dispara.
- Sin `blockedReason`, el snap abierto sigue funcionando (regresión del comportamiento actual).
- `peekOnce` con la clave ya marcada como hecha no anima.
- `peekOnce` con reduce motion no anima pero marca la clave.
- En `my_requests_screen`, una solicitud `accepted` produce un `SwipeToActions` con el motivo
  correcto (antes producía un `_RequestCard` pelado).

**Tanda B**:
- Migración verificada en `BEGIN`/`ROLLBACK`: el cliente no puede fijar `archived_by_provider`
  (lanza `P0001`) y sí el suyo; `get_my_conversations_list` conserva sus grants tras el
  `DROP`/`CREATE`.
- Widget test: la píldora "Archivados" no aparece con cero archivados y sí con uno.
- Widget test: los archivados no salen en las tres pestañas normales ni en sus conteos.
- Widget test: "No concretado" abre confirmación y no llama al repo si se cancela.
- Widget test: el cliente (no proveedor) ve "Marcar como perdido" en el ⋮ del chat.

**Tanda C**:
- Test de `_RatingPanelState`: con el `business_id` resuelto, se llaman las dos escrituras; si
  `submitReview` lanza, el panel igual reporta éxito.
- `interestBusinessId` devuelve el negocio de un `product_interest`.
- Widget test: fase `completed` en `request_status_screen` renderiza el panel; con reseña
  existente renderiza la nota.

**Tanda D**: verificación visual en las dos plataformas. Sin test.

**Gates del proyecto**, en todas: `flutter analyze` en 0, `npx tsc --noEmit` en 0 en la web, la
suite de la app (550 tests hoy) y la de la web (423) en verde.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| El `DROP FUNCTION` de `get_my_conversations_list` deja la RPC sin grants → la lista de chats muere para todos | `REVOKE`/`GRANT` explícito al final de la migración, verificado en `BEGIN`/`ROLLBACK` y con una llamada real tras aplicar |
| El swipe en la lista de chats compite con el gesto de "atrás" del sistema (edge-swipe desde el borde izquierdo) | El gesto arranca **desde la fila**, no desde el borde; ya convive así en solicitudes. Verificar en dispositivo con navegación por gestos |
| Un swipe accidental marca "No concretado", que es irreversible | Confirmación obligatoria, sin excepción, en los dos puntos de entrada |
| El cliente ahora puede marcar "perdido" y un proveedor pierde un lead por el que pagó | Es el estado real del trato, y la conversación no se borra: queda en su pestaña, archivable y auditable. Se avisa en el diálogo de que el otro participante lo verá |
| Archivar no aparece en la web y un usuario multi-dispositivo se confunde | Las columnas quedan en BD desde el día uno, así que la web puede sumarse sin migración nueva. Se anota como pendiente, no como bloqueante |

## Deuda aceptada a propósito

- **`conversation_ratings` sigue existiendo y escribiéndose en paralelo a `business_reviews`.**
  Se descartó unificar (más riesgo y más trabajo, toca web + app + BD). Consecuencia: hay dos
  filas por cada calificación cliente→proveedor y solo una alimenta la reputación. Si algún día
  se unifica, `conversation_ratings` es la que sobra.
- **`business_reviews` es una reseña vigente por (negocio, reseñador).** Un cliente que califica
  dos tratos distintos con el mismo negocio **sobrescribe** su nota anterior. Es el
  comportamiento que ya eligió `submitReview` al usar `upsert` con `onConflict`, y se mantiene:
  evita que un mismo cliente sesgue el promedio con reseñas repetidas.
- **Editar solicitud sigue en "próximamente"** (`my_requests_screen.dart:641`). La franja azul
  Editar se conserva porque el gesto y su descubrimiento son el objeto de esta sesión.
- **El ícono no queda idéntico entre app y web** (`quickreply` vs `MessageSquareQuote`), por
  falta de equivalente en lucide.
