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

### Causa raíz

La migración `20260729210000_security_medium_rls_fixes.sql` (hallazgo M-2 del
scan del 29-jul) reescribió la política INSERT de `conversation_messages` y
quitó `'system'` de la lista de kinds permitidos, porque permitía a un usuario
falsificar carteles de plataforma y saltarse el trigger anti-flood:

```sql
AND kind = ANY (ARRAY['text','address','image','quick'])
AND sender_id = (select auth.uid())
```

`chat_screen.dart:906` sigue llamando `_sendRaw('system', body)`. Ese INSERT
viola el `WITH CHECK` → `PostgrestException` → el `catch (_)` de la línea 910
muestra el mensaje genérico.

El comentario de `_openImproveOffer` (líneas 861-867) documenta la política
*anterior* ("la RLS de prod exige `sender_id = auth.uid()` para kind 'system'").
Quedó obsoleto el 29-jul y nadie lo revisó — hay que actualizarlo.

### Por qué es peor que un mensaje de error feo

`improveOfferPrice` (`repos.dart:1590`) corre **antes** del `_sendRaw` y son dos
llamadas HTTP independientes:

1. El `UPDATE` de `agreed_price` **sí se aplica**. Nada lo bloquea: el grant por
   columna existe (`20260615032752`), la política `Participants can update
   status` deja pasar a ambos participantes, el trigger
   `enforce_agreed_price_provider_only` permite al proveedor, y
   `enforce_archive_own_side` sale por la vía rápida (`20260801140000`).
2. El INSERT del mensaje revienta.
3. El `catch` se salta el `_reload()`, así que la pantalla **sigue mostrando el
   precio viejo**.

Resultado: el precio cambió en la BD, el cliente no se enteró, y el proveedor
cree que no pasó nada. Si lo reintenta, la validación "el nuevo precio debe ser
menor al actual" lo compara contra un precio que él cree que sigue vigente.

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

- Migración nueva: la RPC + `REVOKE EXECUTE ... FROM anon` + `GRANT EXECUTE ...
  TO authenticated`.
- `types.ts` de la web: declarar la RPC bajo `Functions` (es manual).
- App: `improveOfferPrice` pasa a `supa.rpc(...)`; `_openImproveOffer` deja de
  llamar `_sendRaw`; el `catch (_)` mudo se sustituye por
  `reportSwallowedDbError` + un mensaje que distinga fallo de red de rechazo.
- Web: `submitImproveOffer` pasa a la RPC; se le comprueba el error.
- Actualizar el comentario obsoleto de `chat_screen.dart:861-867`.
- Verificar en prod con `BEGIN; ... ROLLBACK;` antes de aplicar.

---

## T1 — La tarjeta de "Interesado en producto" pierde su botón

`_InterestCard` (`inbox_screen.dart:936`) lleva un `FilledButton` verde que dice
"Abrir chat" cuando está desbloqueado y "Conversar · N créditos" cuando no.
`_RequestCard` (`inbox_screen.dart:752`) no lleva botón: se toca la tarjeta y se
entra al detalle, y el estado se comunica con un `StatusChip` ("Ya ofertaste",
"Aceptada", "Desbloqueado").

Se quita el botón de `_InterestCard` y en su lugar va un `StatusChip` con el
mismo criterio de color que las de solicitud. La tarjeta entera sigue siendo
tappable.

`_onInterestAction` ya abre siempre el detalle primero (pedido PO del
2026-07-23, comentado en la línea 206) — no cambia.

**Ojo:** hay tests de widget que buscan el texto 'Abrir chat' en la lista; hay
que reapuntarlos al detalle.

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

---

## Orden sugerido

1. **T6** — bug real en producción, y hay dinero de por medio.
2. **T1** — trivial, cierra una inconsistencia visible.
3. **T3 + T4** — misma sesión, mismo archivo.
4. **T2** — necesita el panel plegable de T3.
5. **T5A**, luego **T5B**.

T6 y T5 son independientes del resto: se pueden adelantar o retrasar sin
arrastrar nada.
