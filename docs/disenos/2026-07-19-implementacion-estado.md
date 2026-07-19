# Implementación de los mockups en la app — estado (2026-07-19)

Traslado de `docs/disenos/2026-07-19-mockups-app.html` (10 pantallas aprobadas
por el PO) al código Flutter. Doctrina que rige: `jayalo-doctrina-estetica-mockups`.

`flutter analyze` → 0 issues. `flutter test` → 314 pasando.

## Fundación (global, afecta TODAS las pantallas)

- **Paleta cálida "arena"** en tema CLARO (`core/brand.dart`): fondo `#F8F4EC`,
  tinta cuerpo `#4A4458`, títulos `#3E3560` (helper `jayaloHead`), acento lila,
  sombra cálida `rgba(93,72,38,.09)`. Cero negro. Es una **divergencia
  deliberada de la web** (que usa gris frío) — el único token idéntico entre app
  y web es el violeta de acción `#7147F2`. Tema OSCURO sin tocar (el PO aún no
  aprobó la pasada oscura cálida).
- **Tipografía ligera 400–600** (nunca 700) en el kit compartido y en las
  tarjetas de todas las pantallas.
- **Tarjetas sin borde que flotan por sombra cálida**, radio 20
  (`kCardRadius`), en `JayaloCard`/skeletons.
- **Header violeta** (`features/shared/violet_header.dart`): widget nuevo
  `VioletHeader` + `HeaderAvatar`, `HeaderBell`, `HeaderCircleButton`,
  `WarmSearchField`, `HeaderSegmented`, `HeaderPill`, `HeaderGreeting`.

## Pantallas con el rediseño aplicado

| Pantalla | Archivo | Qué se hizo |
|---|---|---|
| Home cliente | `client/my_requests_screen.dart` | Header violeta + saludo + buscador; sección "Tus solicitudes" |
| Notificaciones | `notifications/notifications_screen.dart` | Header violeta (atrás + píldora "N nuevas" + marcar todas); familias de color ya existían |
| Mensajes (lista) | `chat/conversations_screen.dart` | Header + **lista plana en contenedor blanco** con líneas finas (firma de la pantalla) |
| Catálogo | `client/catalog_screen.dart` | Header con segmento + buscador funcional; rejilla ya existía |
| Inbox proveedor | `provider/inbox_screen.dart` | Header con los DOS toggles (Para ti/Todas, tipo) |
| Mis estadísticas | `provider/stats_screen.dart` | Header atrás + título centrado |
| Mi negocio | `provider/my_business_screen.dart` | Header + métricas |
| Mis ofertas | `provider/my_offers_screen.dart` | Header + tarjetas ámbar del dinero |
| Mi reputación | `client/reputation_screen.dart` | Header + métricas |
| Crear solicitud | `client/create_request_screen.dart` | Header "Crear solicitud" + toggle Producto/Servicio + píldora "Al por mayor" |
| Chat | `chat/chat_screen.dart` + `widgets/bubbles.dart` | **Header violeta (sin redondeo inferior) + panel lila a pantalla completa** + burbujas re-teñidas (own lila claro, peer lila claro, ink oscuro). Realtime/envío intactos |
| Detalle solicitud (cliente) | `client/request_status_screen.dart` | **Panel ámbar con foto + hoja blanca** (título, "Desde", chips de detalles) + CTA "Ver N ofertas" → hoja de ofertas. Aceptar sigue por `showOfferSheet` (flujo intacto) |
| Detalle solicitud (proveedor) | `provider/request_detail_screen.dart` | Panel ámbar + hoja blanca con detalles + el formulario de "Hacer oferta" (lógica intacta) |
| Detalle de producto | `client/product_detail_screen.dart` | Sin AppBar: la foto manda + atrás flotante; tipografía ligera; form "Solicitar" intacto |

## ⛔ HUECOS DE LÓGICA (documentados, NO corregidos — instrucción del PO)

1. **Buscador + "Filtrar" del home NO funciona.** El mockup lo pinta, pero
   buscar/filtrar solicitudes propias es funcionalidad nueva que no existe en el
   backend ni en el estado de `my_requests_screen`. Se dibuja la barra (estética
   primero) y al tocar muestra "Buscar y filtrar: próximamente". **Decisión
   pendiente del PO: implementarlo o retirarlo del diseño.**
   (El buscador de **Catálogo** y **Mensajes** SÍ funciona — esos ya existían.)

2. **Catálogo y Mi negocio no están cableados como pestañas del shell.** El
   mockup los muestra en la navbar, pero el código sigue llegando a ellos por
   `push` a `/catalog` y `/provider/business` (ver `CatalogScreen` /
   `MyBusinessScreen`: "todavía no es una pestaña raíz"). Cableado pendiente
   (no se tocó `nav_destinations.dart`).

## Diferencias respecto al mockup (decisiones al implementar)

- **Aceptar oferta:** el mockup pone "Mantén para aceptar" (hold) POR oferta en
  la hoja. Se dejó el flujo real de aceptación (`showOfferSheet`: tocar oferta →
  aceptar/rechazar) para NO tocar la lógica de dinero — la hoja de ofertas es
  visual (tarjetas + chip "Más económica"), pero aceptar abre el sheet de
  siempre. Cambiar a hold-por-oferta es una tarea aparte que toca esa lógica.
- **Foto del detalle:** la solicitud del cliente ahora trae `image_urls` en el
  `select` (antes no se pedía). Si no hay fotos, el panel ámbar muestra el ícono
  de fase/tipo.
- **"Cancelar" del mockup en el detalle:** se implementó como **"Volver"** (no
  existe cancelar-solicitud como feature; no se inventó).

## Pendiente

- **Ajustes / login / onboarding:** sin mockup; heredan la paleta.
- **Modo oscuro cálido:** el PO aún no lo aprobó; el tema oscuro sigue en azul.

## Notas de coherencia

- **Invariante de navegación preservada:** cada pestaña raíz mantiene acceso a
  Notificaciones (campana) y al menú de perfil (avatar → Ajustes/Estadísticas)
  desde su header — antes vivían en el AppBar. El test I1 de Mensajes se
  actualizó al header.
- **La barra flotante NO se tocó** (`floating_nav_bar.dart` intacto). Sus dos
  tokens de color (`accent`/`accentFg`) se dejaron EXACTOS a los previos para
  que quede pixel-idéntica y su test de contraste WCAG 3:1 siga pasando; por eso
  el acento es `#F0EAFF/#3C1590` en vez del `#F1EAFE/#4B3B94` del mockup
  (diferencia imperceptible).
