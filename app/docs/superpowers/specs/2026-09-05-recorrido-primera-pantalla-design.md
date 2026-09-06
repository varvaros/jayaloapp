# Recorrido de la primera pantalla, por rol

**Fecha:** 2026-09-05 · **Estado:** aprobado por el PO (orden y textos propuestos en sesión; créditos
anclados en la monedita `HeaderSaldo`, decisión PO) · **Base:** `2026-09-05-guia-mas-notable-design.md`.

## Pedido del PO

«En la primera pantalla no solo debe explicar el header, sino las solicitudes, el botón de +, los
créditos, el "Para ti / Todas", "Productos / Servicios", y de la barra "tienda, chat, ofertas". Para el
cliente también.» «Tus créditos es en la monedita al lado de notificaciones.»

## Motor (`onboarding_guide.dart`)

1. `OnboardingStep` gana `anchorKey` (GlobalKey opcional) y `tapThrough` (bool). Un paso con
   `anchorKey` mide ese widget; sin él, usa el ancla del guide como hasta ahora. Al cambiar de paso el
   hueco se desliza de un ancla a la otra (`RectTween`, `JayaloMotion.base`) y el texto se funde. Si el
   ancla de un paso no existe o no es visible, el paso se muestra centrado sin hueco (no se salta).
2. Con más de un paso, la cabecera «PASO n DE N» sale sola. Desaparecen `tourIndex`/`tourLength` y el
   `tapThrough` a nivel de guide (pasa al paso).
3. «Saltar» marca el recorrido entero como visto. Tocar fuera lo cierra por esta vez (igual que hoy).
4. `TourAnchors`: GlobalKeys compartidas (`plus`, `saldo`, `nav(route)`) para que un recorrido declarado
   en una pantalla ancle elementos del shell (botón `+`, ítems de la barra) y del encabezado (monedita).
   `FloatingNavBar` recibe una key por ítem (por `route`).

## Recorridos (claves nuevas; los usuarios actuales los ven una vez)

**`client.home_tour.v1`** (pantalla Solicitudes del cliente, no embebida), 7 pasos:

| # | Ancla | Texto |
|---|---|---|
| 1 | Buscador | Busca productos y tiendas de los proveedores. |
| 2 | Píldora «Mis solicitudes» | Aquí quedan tus solicitudes y en qué van. |
| 3 | Píldora «Todas las solicitudes» | Y en esta pestaña ves qué están pidiendo otros usuarios. |
| 4 | Botón `+` (tapThrough) | Con este botón creas una nueva solicitud. Los proveedores te responden con ofertas. |
| 5 | Barra · Catálogo | Productos y tiendas de los proveedores, para comprar sin pedir. |
| 6 | Barra · Mensajes | Aquí coordinas con el proveedor cuando aceptas su oferta. |
| 7 | Barra · Reputación | Tus estadísticas como comprador. |

**`provider.inbox_tour.v1`** (Solicitudes para ti), 8 pasos:

| # | Ancla | Texto |
|---|---|---|
| 1 | Primera tarjeta de la lista | Aquí llegan las solicitudes de personas que buscan lo que ofreces. |
| 2 | «Para ti · Todas» | Para ti: solicitudes de tu rubro. Todas: de cualquier rubro. |
| 3 | «Todo · Productos · Servicios» | Filtra por lo que piden: productos o servicios. |
| 4 | Botón `+` | Con este botón también pides tú, como comprador. |
| 5 | Monedita (`HeaderSaldo`) | Estos son tus créditos; tócalos para recargar. Ofertar es gratis: solo desbloquean el contacto de un cliente que aceptó. |
| 6 | Barra · Mis ofertas | Tus ofertas y en qué van. |
| 7 | Barra · Mensajes | Aquí coordinas con el cliente cuando acepta tu oferta. |
| 8 | Barra · Mi negocio | Tu tienda, tus trabajos y tus estadísticas. |

Se retiran las guías sueltas que absorben: `client.plus.v1`, `client.my_requests.v1`,
`client.others_requests.v1`, `provider.requests_list.v1`. Se conservan `profile.menu.v1` (el avatar,
sale después), `provider.offer_menu.v1`, `wallet.credits.v1` y el resto.

## Tests

Motor: cambio de paso re-mide y desplaza el hueco; paso con ancla ausente → centrado; «PASO 2 DE 3»
automático; `tapThrough` por paso; anclas del shell medibles desde una guía de pantalla. Pantallas: cada
recorrido muestra su primer paso y avanza por sus anclas. Suite completa verde.

## Reversión

Un commit aislado; `git revert <sha>`.
