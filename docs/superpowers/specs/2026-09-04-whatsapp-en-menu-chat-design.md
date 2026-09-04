# «Ver WhatsApp del cliente» en el menú ⋮ del chat

**Fecha:** 2026-09-04 · **Aprobado por el PO** en chat (qué hace, estado deshabilitado,
alcance, gate del interés, arreglo de la hoja vieja).
**Repo:** `jayalo-app` (Flutter) · carril base `feat/fecha-pautada-app` (`cb32f10`) ·
rama `feat/whatsapp-en-menu-chat`.
**Servidor:** NO se toca. Cero migraciones, cero RPC nuevas, cero cambios de RLS.

## 1. Contexto medido

Todo lo de abajo está verificado contra el repo y contra PRODUCCIÓN (project `mfaiklvobnvgusbcssbx`),
no supuesto.

### 1.1 Dónde vive hoy el revelado

`WhatsappReveal` (`features/provider/unlock_flow.dart:519`) es el gate aprobado por el PO el
2026-07-22: aviso ámbar de que por WhatsApp se pierde la devolución de créditos + `HoldToConfirmButton`
«Mantén para ver WhatsApp» → `wa.me`. Sale en DOS sitios y en ninguno más:

1. `showOfferContactSheet` (`unlock_flow.dart:282`), la hoja que aparece justo después de pagar
   el desbloqueo y desde «Ver contacto» en el detalle de la solicitud
   (`features/provider/request_detail_screen.dart:1411` y `:2496`).
2. `product_interest_detail_screen.dart:430`, el detalle del interés de producto.

El ⋮ del chat (`features/chat/chat_screen.dart:50`, `chatMenuValues`) ofrece hoy exactamente:
`profile · complete · lost · funnel · report`. Nada de contacto.

El perfil del cliente NO es una salida: `customer_profile_screen.dart:27` lo dice en su propia
cabecera — «Sin CTA: es informativa; desbloquear sigue viviendo en la solicitud».

**Consecuencia:** el proveedor que cierra la hoja de contacto pierde la vía al WhatsApp salvo
volviendo a «Mis ofertas» → detalle de la oferta. Eso es lo que esta rama resuelve.

### 1.2 Dentro del chat el contacto YA está pagado

`get_or_create_conversation` (SECURITY DEFINER, verificada en prod) exige, para `kind='offer'`,
`po.status='accepted' AND po.unlocked_at IS NOT NULL AND po.unlock_revoked_at IS NULL`, y para
`kind='product_interest'`, `i.unlocked_at IS NOT NULL`. Si falta, lanza `Offer not eligible` /
`Interest not eligible`.

Por tanto **no existe un chat sin desbloqueo pagado**. Dentro del chat no hay nada que «desbloquear»
con créditos: lo que falta es REVELAR. El ⋮ no cobra nunca (decisión PO).

### 1.3 Pedir el teléfono es lo que quema la devolución

`get_unlocked_offer_contact` no es una lectura: en medio del cuerpo hace

    UPDATE public.provider_offers
    SET whatsapp_revealed_at = now()
    WHERE id = _offer_id AND whatsapp_revealed_at IS NULL;

Hoy `showOfferContactSheet` la llama **al abrirse la hoja**, antes de que el proveedor mantenga
pulsado nada. Es decir: **el derecho a la devolución de créditos se pierde por ABRIR una hoja, no
por ver el WhatsApp.** Bug preexistente. Copiarlo al ⋮ lo empeoraría (bastaría abrir el menú), así
que el diseño lo invierte y de paso arregla la hoja (aprobado por el PO).

`can_reveal_offer_whatsapp` en cambio es `STABLE SECURITY DEFINER` y no marca nada — se puede
llamar libremente.

### 1.4 La opción nace gris: el interruptor es del cliente

`can_reveal_offer_whatsapp` exige `pr.whatsapp_reveal_enabled = true` **y**
`av.whatsapp_verified_at IS NOT NULL`. Contra prod, 2026-09-04:

| medida | valor |
| --- | --- |
| ofertas aceptadas y desbloqueadas | 10 |
| de esas, con cliente con WhatsApp verificado | 9 |
| de esas, **revelables** (`can_reveal_offer_whatsapp`) | **0** |
| perfiles con `whatsapp_reveal_enabled = true` | 1 |
| ofertas con `whatsapp_revealed_at` | 0 |
| conversaciones totales / de oferta / de interés | 15 / 11 / 4 |

El cuello NO es la verificación: es `profiles.whatsapp_reveal_enabled`, que nace en `false`
(doctrina «WhatsApp nunca es la conversación», PO 2026-07-21) y solo el CLIENTE lo enciende en
Ajustes. La opción saldrá **gris en los 11 chats de oferta de hoy**. No es un fallo del cambio.

### 1.5 El agujero del interés de producto

`get_unlocked_product_interest_contact` es `STABLE` (no marca) pero devuelve `profiles.phone`
**sin mirar `whatsapp_reveal_enabled`**. Contra prod: de 5 intereses desbloqueados, 3 enseñarían
el teléfono de un cliente que nunca activó el interruptor.

Es preexistente (ya pasa en `product_interest_detail_screen`). El PO decidió que el ⋮ **sí** respete
el interruptor. Se puede sin migración: la política `Profiles: select` incluye una rama que permite
al proveedor leer la fila del cliente cuando existe un `product_interests` entre ambos con
`unlocked_at IS NOT NULL`, y `whatsapp_reveal_enabled` tiene `SELECT` concedido a `authenticated`
(comprobado en `information_schema.column_privileges`).

**Salvedad que hay que dejar escrita:** eso es una reja de UI, no del servidor. La RPC sigue siendo
permisiva. Ver §9 (tickets).

## 2. Objetivo

Que el proveedor pueda pedir el WhatsApp del cliente **desde el chat**, sin salir a otra pantalla,
con el mismo gate de siempre, y sin perder la devolución de créditos por abrir un menú.

## 3. No objetivos

Cobrar créditos desde el chat (imposible por §1.2), el lado del cliente (la tienda del proveedor ya
tiene su vía), chats cerrados, apretar la RPC del interés (ticket), iOS, cambios de servidor.

## 4. Decisiones del PO

| decisión | resuelto |
| --- | --- |
| qué hace la opción | revela, **sin cobro** |
| cuando no se puede | ítem **gris con el motivo debajo** (ni oculto ni activo) |
| alcance | oferta **e** interés, **solo con el chat abierto**, solo proveedor |
| interés | respeta `whatsapp_reveal_enabled` (reja de UI) |
| devolución | el teléfono se pide **después** del hold; se arregla también la hoja vieja |

## 5. El ítem del ⋮

Valor nuevo `'whatsapp'`, colocado **justo después de `'profile'`** (las dos son «cosas del
cliente»; cerrar el trato queda debajo, como hasta ahora).

| estado | rótulo | condición |
| --- | --- | --- |
| habilitado | **Ver WhatsApp del cliente** | proveedor · chat abierto · revelable |
| gris | **Ver WhatsApp del cliente** + subtítulo con el motivo | proveedor · chat abierto · no revelable |
| ausente | — | cliente, o chat cerrado |

Motivos del subtítulo:

- `El cliente prefiere solo el chat de Jayalo` — `whatsapp_reveal_enabled` apagado (el caso de hoy).
- `El cliente no dejó un teléfono` — solo intereses; `profiles.phone` vacío.
- `No pudimos comprobarlo` — la consulta falló (best-effort, ver §6).

`chatMenuValues` **sigue siendo pura**: gana un parámetro además de `isProvider` e `isOpen`. El
motivo lo decide una SEGUNDA función pura, `whatsappMenuReason(...)`, para no meter estado de red en
algo que los tests montan sin Supabase (mismo patrón que `canResolveReviewBusiness` y
`showsRatingSentNote`, ya en ese fichero).

Los `PopupMenuItem` de hoy llevan un `Text` suelto. Para el subtítulo se añade un helper local
`_menuItemChild(String label, {String? reason})` que devuelve el `Text` pelado cuando `reason` es
`null` — así los cinco ítems existentes se pintan **igual que ahora**.

## 6. Cuándo se consulta si se puede

En `_load()` de `_ChatScreenState`, **best-effort y solo si `_isProvider`**, con el mismo patrón que
`_peerBadges`: si la consulta falla, la pantalla se pinta igual y el ítem sale gris con
«No pudimos comprobarlo».

- `kind == 'offer'` → `canRevealOffer(source_id)` (`repos.dart:1646`). `STABLE`, no marca.
  Ese bool NO distingue «interruptor apagado» de «sin verificar», y traer esa distinción costaría
  una consulta más; **no se distingue**: si da `false` el motivo es siempre
  `El cliente prefiere solo el chat de Jayalo`. Es el caso de 9 de cada 10 ofertas reales.
  (Decisión de implementación, reversible.)
- `kind == 'product_interest'` → dos lecturas en paralelo, ambas sin efectos:
  `productInterestContact(source_id)` (¿hay teléfono?) y
  `profiles.select('whatsapp_reveal_enabled').eq('user_id', _conv['customer_id'])` (§1.5).

**Nunca en `itemBuilder`.** `PopupMenuButton` lo construye síncrono; una consulta ahí daría un menú
que parpadea o que sale vacío la primera vez.

El teléfono del interés queda en memoria tras esa lectura (la RPC lo devuelve junto al nombre) pero
**no se pinta en ningún sitio** hasta pasar el hold — igual que hoy hace la pantalla de detalle del
interés.

## 7. Al tocarlo

Hoja modal (`showModalBottomSheet` con `JayaloMotion.sheetRise`, como el resto de la app) que
contiene **el `WhatsappReveal` que ya existe**. Cero copy nuevo, cero variante paralela:

- `refundApplies: true` en ofertas (ahí la devolución existe desde el 2026-08-28).
- `refundApplies: false` en intereses (ahí no existe; el copy viejo sigue siendo verdad).

## 8. El cambio que impide quemar la devolución

`WhatsappReveal` pasa de `required String phone` a `required Future<String?> Function() loadPhone`.
Una sola forma de entregar el número, sin ambigüedad:

- ⋮ de oferta → `() => unlockedContact(offerId).then((c) => c.phone)`. La RPC que MARCA
  `whatsapp_revealed_at` corre **solo** cuando el proveedor ya mantuvo pulsado.
- ⋮ de interés y `product_interest_detail_screen` → `() async => phone` (ya lo tienen; su RPC no marca).

Si `loadPhone` devuelve `null` o lanza → snack «No pudimos abrir WhatsApp. Intenta de nuevo.» y el
aviso sigue en pantalla, sin cerrarse. Nunca un enlace de WhatsApp con el número en blanco.

### 8.1 La hoja vieja (`showOfferContactSheet`)

Deja de llamar `get_unlocked_offer_contact` al abrirse. Queda:

1. el gate `canRevealOffer` (ya era `STABLE`) → decide si se pinta el bloque de WhatsApp;
2. el **nombre** pasa a salir de `customerPublicProfile(customerId, offerId: id)`
   (`repos.dart:2809`), que revela nombre y foto con el MISMO contexto pagado y **no marca nada**;
3. para eso hace falta `customer_id` en la fila de la oferta.

`offerCols` (`repos.dart:283`) no lo trae. Se añade: `customer_id` tiene `SELECT` concedido a
`authenticated` (comprobado en `column_privileges`) y `my_offers_screen.dart:602` ya lo lee por su
cuenta, así que no es un dato nuevo ni un permiso nuevo. No hay fuga hacia el cliente: el cliente
que lee esas ofertas ES el `customer_id`.

Si `customerPublicProfile` falla, la hoja cae a los textos de siempre («Cliente» / «tu cliente»),
como ya hace hoy cuando `first_name` viene `null`.

## 9. Tickets que salen de aquí (NO entran en esta rama)

1. **RPC del interés permisiva.** `get_unlocked_product_interest_contact` devuelve el teléfono sin
   mirar `whatsapp_reveal_enabled` (3 de 5 casos reales). Fix real = migración con
   `can_reveal_interest_whatsapp` + apretar esa RPC, con sondas y las 4 revisiones. Tocar una RPC
   viva no cabe en una rama sin migración.
2. **Alinear `product_interest_detail_screen`** con la misma reja de UI de §6, para que las dos
   superficies no digan cosas distintas.

## 10. Pruebas

Todas de unidad/widget, sin Supabase (las funciones tocadas son puras o inyectables):

1. `test/chat_menu_roles_test.dart` (existente): `'whatsapp'` presente para proveedor + chat
   abierto; **ausente** para el cliente; **ausente** con el chat cerrado en los dos roles.
   Se conservan intactos los 8 tests que ya hay.
2. Test nuevo de `whatsappMenuReason`: los motivos de §5, cada uno con su entrada.
3. Widget test de `WhatsappReveal`: **`loadPhone` NO se llama al pintar** — es la prueba que fija el
   arreglo de la devolución y la que se rompería si alguien vuelve a adelantar la carga.
4. Widget test de `WhatsappReveal`: `loadPhone` que devuelve `null` → sale el snack y el aviso sigue
   montado.

## 11. Copy de la guía

`chat.menu.provider.v1` → **`chat.menu.provider.v2`** en `features/shared/onboarding_copy.dart:75`.
La convención está escrita en la cabecera del propio fichero: sin subir la versión, el texto nuevo
sería invisible para todo el que ya vio la guía.

Texto nuevo: «Aquí cierras el trato, ves el perfil del cliente, pides su WhatsApp y denuncias si
algo no cuadra.»

La clave del cliente (`chat.menu.client.v1`) NO cambia: para el cliente el menú es idéntico.

## 12. Riesgos y qué NO se verá

- **Nace gris en el 100% de los chats de hoy** (§1.4). Para el smoke hay que encender
  «que me contacten por WhatsApp» en un cliente de prueba desde Ajustes. Sin ese paso, el smoke solo
  puede comprobar el estado gris y su motivo.
- La reja del interés es de UI (§1.5). Un proveedor con la RPC a mano sigue pudiendo sacar el
  teléfono. Ticket 1 de §9.
- El ⋮ gana un sexto ítem para el proveedor. Sigue cabiendo sin scroll.

## 13. Entrega

Un solo carril. Al terminar: `flutter analyze` + la batería completa del carril base, APK con el
sello de build para el teléfono del PO, y smoke del PO antes de mergear a `feat/fecha-pautada-app`.
