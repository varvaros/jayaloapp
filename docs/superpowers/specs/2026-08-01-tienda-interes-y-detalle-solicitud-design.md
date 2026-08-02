# Interés de producto, detalle de solicitud y tienda — diseño

Fecha: 2026-08-01
Estado: aprobado por el PO (2026-08-01)

Seis peticiones del PO recogidas en una sesión. Cinco son de la app Flutter; una
(T6) toca además la web y la base de datos. Cada tarea es independiente y está
dimensionada para trabajarse en su propia sesión — el orden sugerido está al
final.

---

## T6 — "No se pudo mejorar oferta"

### Qué pasa

El proveedor abre el chat, toca `+` → *Mejorar oferta*, escribe un precio menor
y recibe **"No se pudo mejorar la oferta."**

### Causa raíz: son DOS fallos encadenados, y el primero tapaba al segundo

Verificado contra la BD real el 2026-08-01 con UPDATE e INSERT en
`BEGIN`/`ROLLBACK`, suplantando al proveedor con `set local role authenticated`
y sus claims de JWT.

**Fallo 1 — el guard del precio no resuelve su propio tipo (42704).**
`enforce_agreed_price_provider_only` (creado en `20260729210000`, hallazgo M-12)
lleva `SET search_path = ''` y dentro escribe `'admin'::app_role` **sin
calificar**. Con el search_path vacío ese tipo no se resuelve:

```
42704: type "app_role" does not exist
```

Falla para **cualquier** UPDATE que cambie `agreed_price`,
`agreed_hourly_rate` o `agreed_estimated_hours` — incluido el del propio
proveedor, que es a quien la comprobación pretendía dejar pasar. No falla solo
el atacante: falla todo el mundo, siempre. **El precio nunca llegó a
cambiar.**

Por qué sobrevivió tres días sin que nadie lo viera: plpgsql planifica cada
sentencia la primera vez que la **ejecuta**, y el `IF` interno solo se ejecuta
si alguna columna de precio cambió de verdad. El `IF` externo protege el 99% de
los UPDATE sobre `conversations` — el bump de `last_message_at` de cada mensaje
de chat—, así que el error solo aflora en el único flujo que toca el precio.

Barrido de la BD: es la **única** función con `search_path` vacío que referencia
`app_role` sin calificar. No es una clase de bug, es un caso aislado.

**Fallo 2 — el aviso al cliente ya no se puede insertar desde el cliente
(42501).** La misma migración quitó `'system'` de los kinds que `authenticated`
puede insertar en `conversation_messages` (hallazgo M-2: permitía falsificar
carteles de plataforma y saltarse el anti-flood):

```sql
AND kind = ANY (ARRAY['text','address','image','quick'])
AND sender_id = (select auth.uid())
```

`chat_screen.dart:906` sigue llamando `_sendRaw('system', body)` → la RLS lo
rechaza. Este fallo estaba escondido detrás del primero: aparece en cuanto se
arregla el trigger.

El comentario de `_openImproveOffer` (líneas 861-867) documenta la política
*anterior* ("la RLS de prod exige `sender_id = auth.uid()` para kind 'system'").
Quedó obsoleto el 29-jul.

### Por qué es peor que un mensaje de error feo

Con el trigger arreglado pero sin RPC, el flujo queda en dos llamadas HTTP
independientes: el `UPDATE` del precio pasaría, el `INSERT` del aviso no, y como
el `catch (_)` se salta el `_reload()`, la pantalla seguiría mostrando el precio
viejo. El precio cambiado, el cliente sin enterarse, y el proveedor creyendo que
no pasó nada. Por eso el fix no es solo "quitar el 42704": las dos escrituras
tienen que ir juntas.

### La web tiene la misma bomba, y peor

`src/routes/messages.$conversationId.tsx:916` hace
`await insertOptimistic({ kind: "system", body })` **sin comprobar el error**:
muestra "Oferta mejorada.", el precio cambia, y el aviso al cliente nunca
aparece. Falla en silencio.

El tercer emisor de `kind:'system'` es
`src/lib/sales-assistant-reply.server.ts:176`, que corre con `service_role` —
exento de RLS, no afectado.

### Decisión (PO, 2026-08-01): RPC nueva con migración

RPC `improve_offer_price(_conv_id uuid, _new_price numeric)` `SECURITY DEFINER`
que en una sola transacción:

- Verifica que quien llama es `provider_user_id` de esa conversación.
- Verifica que la conversación está `abierto`.
- Verifica que `_new_price > 0` y, si hay `agreed_price`, que sea menor.
- `UPDATE conversations SET agreed_price = _new_price`.
- `INSERT` del mensaje `kind='system'` con el texto del ahorro.

Es el patrón ya establecido en el proyecto (`try_unlock_*`,
`cancel_customer_request`, `credit_captured_payment`): la escritura de dinero es
atómica y vive en el servidor. No reabre M-2 — `authenticated` sigue sin poder
insertar `'system'` por PostgREST.

Descartado: mandar el aviso como `kind:'text'` (funciona hoy, pero lo pinta como
mensaje de persona y deja la falta de atomicidad intacta) y volver a permitir
`'system'` en la política (reabre la vulnerabilidad).

El texto del mensaje se mueve al servidor. Hoy vive duplicado en el cliente app
y en el cliente web con formatos de moneda distintos (`fmtRD` vs `formatRD`);
generarlo dentro de la RPC lo unifica.

### Alcance

Migración `20260801150000_improve_offer_price_rpc.sql`, que hace las dos cosas:
calificar el tipo en el trigger (`public.app_role`) y crear la RPC, con
`REVOKE EXECUTE ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated`.

- `types.ts` de la web: declarar la RPC bajo `Functions` (es manual).
- App: `improveOfferPrice` pasa a `supa.rpc(...)`; `_openImproveOffer` deja de
  llamar `_sendRaw`; el `catch (_)` mudo se sustituye por `reportError` +
  `improveOfferErrorCopy` (`domain/improve_offer_error.dart`, 5 tests), que
  muestra los rechazos P0001 tal cual y manda el resto al genérico.
- Web: `submitImproveOffer` pasa a la RPC; su error va a `toastDbError`, que ya
  deja pasar los mensajes legibles por `looksHuman`.
- Actualizar el comentario obsoleto de `chat_screen.dart:861-867`.

### Estado

Migración escrita y **verificada contra la BD real en `BEGIN`/`ROLLBACK`**
(6 casos: caso feliz, separador de miles, el cliente intentando bajar el precio,
el proveedor intentando subirlo, precio 0, conversación inexistente y sin
sesión). Nada persistió — comprobado después. Código de app y web listo:
app `flutter analyze` 0 y 611 tests; web `tsc` 0, lint 0 errores, 436 tests.

**Pendiente: aplicar la migración a producción.** Hasta entonces los clientes no
se pueden desplegar — llamarían a una RPC que no existe. El orden es migración
primero, deploy después.

---

## T1 — La tarjeta de "Interesado en producto" pierde su botón

`_InterestCard` (`inbox_screen.dart:936`) lleva un `FilledButton` verde que dice
"Abrir chat" cuando está desbloqueado y "Conversar · N créditos" cuando no.
`_RequestCard` (`inbox_screen.dart:752`) no lleva botón: se toca la tarjeta y se
entra al detalle, y el estado se comunica con un `StatusChip` ("Ya ofertaste",
"Aceptada", "Desbloqueado").

Se quita el botón de `_InterestCard` y en su lugar va un `StatusChip` en la
misma `Wrap` que la hora, igual que en `_RequestCard`. La tarjeta entera sigue
siendo tappable.

Chips elegidos:

- Desbloqueado → "Desbloqueado" con `Icons.lock_open` y
  `offerBadgeTone(context, 'unlocked')` (violeta), idéntico al de solicitud.
- Sin desbloquear → "N crédito(s)" con `Icons.lock_outline` y el tono `pending`
  (ámbar). El costo se conserva: era la única información útil que daba el
  botón, y ámbar es el color de "dinero esperando" en todo el proyecto.

`_onInterestAction` ya abría siempre el detalle primero (pedido PO del
2026-07-23, comentado en la línea 206) — no cambió nada ahí.

### Estado: HECHA (2026-08-01)

Tests de `inbox_screen_test.dart` actualizados primero, vistos fallar, y luego
el widget. Los dos que codificaban el botón ahora afirman lo contrario
(`find.byType(FilledButton)` → `findsNothing`, y ni rastro del copy
"Conversar"); los que tocaban el botón para abrir la hoja ahora tocan el título
de la tarjeta. App: analyze 0, 611 tests.

---

## T3 — La foto del detalle de solicitud se pliega al hacer scroll

`request_detail_screen.dart:1467` es un `Column` con un `Container` de altura
fija (`300 + topInset`) y un `Expanded(ListView)` debajo. La foto nunca se
mueve, así que el formulario de oferta —que es largo: precio, disponibilidad,
detalles de producto, hasta 4 fotos, aviso de costo— vive en poco más de un
tercio de la pantalla.

Pasa a `CustomScrollView` con `SliverAppBar(pinned: true, expandedHeight: 300)`
y la foto en el `flexibleSpace`, de forma que al bajar se encoge hasta una barra
fina y el contenido gana la pantalla.

Hay que preservar, porque todo esto vive hoy dentro del `Stack` del panel:

- El `GestureDetector` que abre el visor a pantalla completa (`showPhotoViewer`).
- La miniatura de la 2ª foto pegada al borde derecho.
- El fallback lila con ícono grande (`handyman` / `inventory_2`) cuando no hay
  fotos, y el `errorBuilder` equivalente.
- El botón atrás flotante (`_backFab`), que pasa a ser el `leading` del sliver.
- El `navBarReservedSpace(context)` del padding inferior.

Conviene extraerlo como widget propio reutilizable: T2 lo necesita igual.

### Estado: HECHA (2026-08-01)

Widget nuevo `features/shared/collapsing_photo_panel.dart` con 5 tests escritos
antes que él: alto expandido en reposo, que se encoja de verdad al bajar (no que
se mueva un poco), que `pinned` deje la barra visible en vez de desaparecer —si
llegara a 0 el usuario se queda sin salida—, que el atrás siga tocable plegado, y
el ícono de respaldo sin fotos.

Dos decisiones que salieron al implementarlo:

- `CollapseMode.none` en vez del `parallax` por defecto: con parallax el fondo se
  dibuja más alto que el espacio disponible y la miniatura de la 2ª foto se salía
  del recorte al plegarse.
- `_backFab` se renombró a `_backButton` y devuelve el botón **pelado**. Antes
  traía su propio `Padding` + `Align`, que en el `leading` de la barra no cabe
  (16 + 42 > 56). Ahora lo coloca cada sitio: el `leading` lo centra y la
  pantalla de carga lo sigue poniendo arriba a la izquierda.
- El `Expanded(ListView)` pasa a `SliverFillRemaining(hasScrollBody: false)` con
  un `Column` dentro. La hoja sigue rellenando la pantalla cuando el contenido es
  corto, que es lo que hacía el `Expanded`.
- Desaparece el `+ topInset` manual: `SliverAppBar` ya reserva la barra de estado.

---

## T4 — Reordenar el detalle: Datos del cliente → Información → Acción

Orden actual del `ListView` (`request_detail_screen.dart:1545` en adelante):
título → chip mayorista → escalera de cupos → detalles de mayoreo → bullets →
presupuesto → **datos del cliente** (`_customerRepCard`) → divider → acción.

Orden pedido: **datos del cliente → información → desbloqueo o enviar oferta**.

Se sube `_customerRepCard` a justo debajo del título.

**Decisión del PO (2026-08-01): el título y los chips de estado (mayorista,
escalera de cupos) se quedan arriba**, pegados al panel de la foto. Son la
identidad de la solicitud, no "información". El bloque de información queda con
el resto: detalles de mayoreo, bullets y presupuesto.

Mismo archivo que T3 — se pueden hacer en la misma sesión.

### Estado: HECHA (2026-08-01)

`_customerRepCard` subió a justo debajo de la escalera de cupos, y las tres
secciones se rotulan con `_sectionHeading` ("DATOS DEL CLIENTE" / "INFORMACIÓN",
versalita discreta como el 'Detalles' que ya existía) para que la organización
que pidió el PO se vea, no solo se intuya. El bloque de acción va tras el
`Divider` que ya estaba.

### ⚠️ Sin verificación automática

`ProviderRequestDetailScreen` llama a Supabase directo en su `initState`
(`requestById`, `customerReputation`, `peerVerificationBadges`,
`offerCountsForRequests`) y **no tiene seam inyectable**, a diferencia de
`ProviderInboxView` / `MyBusinessView` / `StatsView`, que sí separan la vista
para poder montarla sin red. Así que el panel plegable tiene tests pero **su
integración en esta pantalla y el reorden no**: se verificaron por lectura y por
compilación (`flutter analyze` 0, 616 tests, APK debug construido), no viendo la
pantalla.

Falta mirarla en el device con sesión de proveedor sobre una solicitud abierta:
que la foto se pliegue, que el atrás siga tocable plegado, que el formulario de
oferta tenga la pantalla, y que el teclado no rompa el scroll al enfocar un
campo.

Extraer un `ProviderRequestDetailView` inyectable —siguiendo el patrón que el
propio proyecto ya usa— es el arreglo de fondo, pero es una tarea aparte: son
1800 líneas y no debe colarse dentro de un cambio de layout.

---

## T2 — "Interesado en producto" pasa a pantalla completa

Hoy es un `showModalBottomSheet` al 70% de alto (`_showInterestDetailSheet`,
`inbox_screen.dart:227`) con el producto arriba, un `Spacer` y la acción abajo.

**Decisión del PO: pantalla completa, con la misma estructura que el detalle de
solicitud.** Es decir:

- Panel de foto del producto plegable (el widget de T3).
- **Badge "Desde tu tienda"** junto al título, para que se distinga de una
  solicitud del marketplace. Sustituye a la línea "Interesado en tu producto".
- El orden de T4: datos del cliente → información (producto y su mensaje) →
  acción.
- Abajo, la acción según estado: hold para desbloquear con la mascota, "saldo
  insuficiente — recargar", o "abrir chat".

### El WhatsApp

Hoy, en cuanto abres la hoja de un interés desbloqueado, `inbox_screen.dart:331`
pinta `'${firstName} · ${phone}'` en texto plano, centrado, sin ningún gate.

En ofertas eso nunca pasa: el teléfono está detrás de un botón explícito con
doble advertencia de que por WhatsApp **no hay devolución de créditos** si el
lead no responde (`_WhatsappReveal`, `unlock_flow.dart:464`, pedido PO del
2026-07-22). El chat es la vía primaria.

**Decisión del PO: replicar ese patrón.** Se reusa `_WhatsappReveal` tal cual.

Diferencia técnica a tener presente: en ofertas el revelado también está gateado
en servidor — `can_reveal_offer_whatsapp` comprueba que el cliente tenga
WhatsApp verificado y `reveal_offer_whatsapp` marca `whatsapp_revealed_at`. Para
intereses de producto **esa pareja de RPCs no existe**: solo
`get_unlocked_product_interest_contact`, que devuelve `first_name` y `phone`
directos una vez pagado.

El gate va **solo en UI**, sin migración: tapa la exposición, que es lo que
reportó el PO. Si `phone` viene `null`, el botón no se dibuja. La paridad de
servidor (marca de revelado + comprobación de WhatsApp verificado) queda como
seguimiento opcional, no bloqueante.

### Alcance

- Pantalla nueva (`features/provider/product_interest_detail_screen.dart`).
- Ruta en `go_router` y navegación desde `_onInterestAction`.
- `_showInterestDetailSheet` y `_interestDetailThumb` se retiran de
  `inbox_screen.dart`, que adelgaza bastante.

Depende de T3 (el panel plegable) y hereda el orden de T4.

### Estado: HECHA (2026-08-01)

`ProductInterestDetailScreen` + `ProductInterestDetailView` inyectable, con
**9 tests escritos antes** — esta vez sí hay cobertura de la pantalla, siguiendo
el patrón de `ProviderInboxView`/`MyBusinessView` en lugar de repetir el problema
de T3/T4. Cubren el badge, el orden de las tres secciones (comparando posiciones
verticales reales), la ficha de cliente, el hold, el caso de saldo insuficiente,
y sobre todo el bug reportado: **el teléfono no aparece en claro** ni con el
contacto cargado.

Dos hallazgos que cambiaron el plan:

- **La ficha del cliente sí se puede pintar.** `get_provider_inbox_unified` no
  devuelve `customer_id`, así que parecía que "datos del cliente" se quedaría
  vacío. Pero el proveedor SÍ puede leerlo de `product_interests`: la política de
  SELECT admite `auth.uid() = provider_user_id` y la columna está en el grant.
  Nueva `productInterestCustomerId` en `repos.dart` — **sin migración**.
- **`_customerRepCard` se extrajo a `features/shared/customer_rep_card.dart`**
  (`CustomerRepCard`). Era un método privado de 110 líneas dentro del detalle de
  solicitud; sin extraerlo, "igual que las demás solicitudes" habría sido una
  copia. Ahora las dos pantallas usan el mismo widget.
- `_WhatsappReveal` pasa a público `WhatsappReveal`, por lo mismo: la respuesta
  al "whatsapp expuesto" es reusar el gate de las ofertas, no escribir otro.

Limpieza que arrastró: al irse la hoja, el inbox se quedó sin usar el saldo
(`_balance`, `_loadBalance`, `_openWallet`, el parámetro `balanceFetch` y su
typedef) — todo eso lo carga ahora la pantalla nueva. Se retiró, y los dos tests
de inbox que probaban la hoja se movieron a los de la pantalla.

Se añadió además un test de navegación (tocar la tarjeta → push a
`/provider/interest/:id` con la fila en `extra`), **validado rompiendo el push a
propósito** para confirmar que lo caza.

App: analyze 0, 624 tests, APK debug construido.

---

## T5 — La tienda con el diseño de la web

### Por qué no se aplicó

No se perdió: se portó **una parte**. El commit `66d61d6` ("bloque de reputación
estilo web en la tienda del proveedor") trajo el bloque de confianza —rating,
trabajos completados, tiempo de respuesta, miembro-desde y sellos de
verificación— y eso sí está vivo en `provider_store_screen.dart`.

Lo que nunca se portó son las otras dos piezas del diseño web:

1. **El hero de portada.** La web usa `cover_url` como imagen editorial a lo
   ancho, con el bloque de identidad superpuesto en desktop y en flujo normal en
   móvil (`business.$id.tsx:603` y siguientes; ver el memo del 2026-07-21 sobre
   las dos pasadas del header móvil). La app **no lee `cover_url` en ningún
   sitio** — cero coincidencias en todo `lib/`.
2. **La ficha de detalles completa.** La web tiene `BusinessDetailsCard` con
   experiencia, año de fundación, número de empleados, zona de servicio,
   horario, idiomas, métodos de pago y garantía. La app muestra tres chips:
   categoría, zona y "mayorista" (`_DetailsRow`, `my_business_screen.dart`).

La razón de fondo es de alcance, no un olvido: el spec de *Mi tienda V1*
(2026-07-20) era explícitamente **solo lectura: detalles + productos + servicios
+ opiniones**, y el hero nunca estuvo en esa lista. El commit de reputación
cerró una parte de la brecha y el resto se quedó.

**No hace falta migración**: `cover_url` ya está en los grants de SELECT por
columna para `anon` y `authenticated`
(`20260710000004_reaffirm_final_business_grants.sql`).

### Alcance

Dos sub-tareas, una por pantalla. Comparten el widget de hero, así que **A va
primero**.

**T5A — Mi negocio** (`features/provider/my_business_screen.dart`, lo que ve el
proveedor). El typedef `StoreProfile` gana `coverUrl` y los campos de detalle;
`myBusinessProfile()` los selecciona; `_BusinessHeaderCard` se convierte en hero
con portada; `_DetailsRow` crece hasta la paridad con `BusinessDetailsCard`.

**T5B — Tienda pública** (`features/client/provider_store_screen.dart`, lo que
ve el cliente al tocar el nombre de un proveedor). Mismo hero. Ojo: la identidad
aquí llega por la RPC `businessPublicIdentity`, no por select directo — hay que
confirmar si devuelve `cover_url` y, si no, decidir entre extender la RPC o
leer la columna aparte (los grants lo permiten).

Es la tarea más grande de las seis: dos sesiones, o una larga.

### Estado: HECHA (2026-08-01)

Sin migración, como estaba previsto: las 15 columnas que hacían falta ya estaban
en los grants de SELECT para `anon` y `authenticated` — comprobado contra la BD.

Tres piezas nuevas:

- `domain/business_details.dart` — puro y con **18 tests**. Decide qué filas
  salen y con qué texto, espejo de `providerDetails.ts` + `BusinessDetailsCard.tsx`:
  orden de la web, experiencia solo si es > 0, fundación solo en negocios
  `formal`, singular/plural, códigos a etiqueta (y los desconocidos crudos, no
  descartados), y el resumen de horario con agrupación de días consecutivos a
  partir de tres. `currentYear` entra por parámetro para que "hace N años" se
  pueda probar.
- `features/shared/business_cover_hero.dart` — la portada. Sigue el tratamiento
  MÓVIL de la web (contenido en flujo normal sobre el scrim, no `absolute`), que
  es el que aplica en un teléfono. Sin portada, degradado de marca.
- `features/shared/business_details_card.dart` — la ficha. Si no hay ninguna
  fila no se dibuja el marco: un título con nada debajo parece un error de carga.

**T5A (Mi negocio).** `myBusinessProfile()` pasa a traer las 20 columnas;
`StoreProfile` gana `coverUrl`, `seals` y `raw`. `_BusinessHeaderCard`,
`_DetailsRow` y `_MetaChip` se retiran: categoría y ciudad son ahora el
subtítulo de la portada, y "Mayorista" es una fila de la ficha ("Ventas: Al por
mayor"). Nuevo helper `verificationSealsFrom` en repos, con la advertencia de
siempre: "Negocio verificado" sale del RNC, nunca del WhatsApp.

**T5B (tienda pública).** `BusinessIdentity` gana `coverUrl` y `raw`. El logo y
el nombre salen del bloque de confianza —los carga la portada, y repetirlos era
verlos dos veces seguidas—. El cuerpo pasa a un `CustomScrollView`: portada,
confianza, ficha y lista comparten scroll, porque como bloques fijos encima de
la lista no habría quedado sitio para los productos en un teléfono. Los sellos
salen de `_stats` y no de `_identity`: las marcas de verificación no están en
los grants por columna para un tercero.

App: analyze 0, **649** tests, APK debug construido.

Nota de test: la portada es bastante más alta que la cabecera que sustituyó, así
que en el viewport de 800x600 las secciones de abajo de Mi negocio ya no nacen
construidas. Tres tests ganaron un scroll previo — es el viewport, no un
cambio de comportamiento.

---

## Orden sugerido

1. **T6** — bug real en producción, y hay dinero de por medio.
2. **T1** — trivial, cierra una inconsistencia visible.
3. **T3 + T4** — misma sesión, mismo archivo.
4. **T2** — necesita el panel plegable de T3.
5. **T5A**, luego **T5B**.

T6 y T5 son independientes del resto: se pueden adelantar o retrasar sin
arrastrar nada.
