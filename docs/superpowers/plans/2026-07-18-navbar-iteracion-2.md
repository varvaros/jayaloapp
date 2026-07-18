# Barra flotante iteración 2 — Plan de implementación (borrador para la próxima sesión)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.
> Este plan es deliberadamente MENOS literal que el de la iteración 1: las tareas del Catálogo
> dependen de leer código de la web que esta sesión no leyó a fondo. La próxima sesión debe
> (a) resolver las 3 preguntas abiertas del spec §9 con el PO, (b) elaborar el brief detallado
> de cada tarea leyendo las fuentes citadas, ANTES de dispatchar implementadores.

**Goal:** Aplicar el feedback del PO a la barra (tinte violeta + muesca), reorganizar los
destinos (avatar con menú, Mi negocio, Reputación al 4º del cliente) y construir el Catálogo de
proveedores con el flujo completo de interés + desbloqueo.

**Spec:** `docs/superpowers/specs/2026-07-18-navbar-iteracion-2-design.md`

**Base:** iteración 1 (`ef75b52..0602252`). 198 tests, analyze 0, instalada en el Redmi.

## Global Constraints (heredadas del plan de la iteración 1, verbatim)

- Movimiento: todo desde `JayaloMotion`; nada de `Duration(...)`/`Curves.…` sueltos; respetar `JayaloMotion.reduced(context)`.
- Color: todo del `ColorScheme` o `JayaloColors`/`JayaloStatus`. La barra usa los tokens del spec §2 EXACTOS.
- Widgets compartidos desde `brand_kit.dart`; `JayaloLoaderBlock` para cargas; `MetricTile` ya vive en `brand_kit.dart`.
- Copy en español dominicano sin jerga.
- Cada tarea: `flutter analyze` 0 + `flutter test` verde + commit propio revertible.
- **Backend:** cero cambios SALVO la posible RPC de registro de interés (spec §7) — si se confirma necesaria, va con migración + verificación de grants (REVOKE de PUBLIC, costo server-side, patrón del CLAUDE.md de jayalo-main) y se aplica a prod vía MCP con autorización del PO.
- Gotchas vigentes de la it. 1 (NO reintroducir): ScrollController propio por pantalla (nunca `homeScrollController` en pestañas nuevas); `setState` con bloque, no flecha; `navBarReservedSpace(context)` devuelve SOLO `MediaQuery.paddingOf(context).bottom`; `Semantics` con `excludeSemantics` debe llevar `onTap`; `activeIndex` -1 = ninguna pestaña.

## Fase A — Visual (sin cambios de navegación; entregable por sí sola)

### Task A1: Tinte violeta de la barra
- Modify: `lib/features/shell/floating_nav_bar.dart`, `test/floating_nav_bar_test.dart`
- Mapa exacto de tokens en el spec §2. El inactivo es el mismo tono atenuado (opacidad), no otro color. Tests: color del fondo de la píldora y del círculo en claro y oscuro (montar con `jayaloTheme(Brightness.…)` y leer los `Container`/`Material` decorados); actualizar los que asuman `surfaceContainerLowest`/`primary`.

### Task A2: Muesca cóncava
- Modify: `lib/features/shell/floating_nav_bar.dart`; test de golden opcional, mínimo un test de que el painter genera un path con la muesca (concavidad en el centro del borde superior).
- `CustomPainter` (o `ShapeBorder`) con el path de píldora + muesca circular alrededor del botón central, sombra siguiendo el path. Referencia conceptual: `CircularNotchedRectangle` de Material. El alto total NO cambia (no tocar `kNavBarReservedSpace` sin actualizar el test de coherencia `nav_bar_reserved_space_test.dart`).

## Fase B — Reorganización (depende de decidir la pregunta abierta 1 del spec)

### Task B1: Avatar en el AppBar con menú
- Create: `lib/features/shared/profile_avatar_button.dart` (+ test)
- Modify: las pantallas raíz que hoy ponen `actions: const [NotificationBell()]` → `[NotificationBell(), ProfileAvatarButton()]`.
- Menú por rol: cliente → Ajustes; proveedor → Estadísticas · Ajustes. Navega con `context.push`. Avatar: foto de perfil si existe (mirar cómo la trae la web / profiles.avatar_url) con fallback a inicial.

### Task B2: Nuevo mapa de destinos
- Modify: `lib/features/shell/nav_destinations.dart`, `test/nav_destinations_test.dart`
- Cliente: `/client` · `/catalog` | `/client/create` | `/messages` · `/client/reputation`.
- Proveedor: `/provider/offers` · `/provider/business` | `/provider` | `/messages` · (según decisión PO).
- `/settings` y `/provider/stats` dejan de ser destinos pero sus rutas siguen vivas (llegan por el avatar; `activeIndex` → -1 ahí, ya soportado). Actualizar los tests de mapa.

### Task B3: Pantalla "Mi negocio" v1 (`/provider/business`)
- Create: `lib/features/provider/my_business_screen.dart` (+ test), ruta en `router.dart`, datos en `repos.dart`.
- Contenido según la respuesta del PO a la pregunta abierta 2 (propuesta: nombre/logo, badge, saldo + recargar reutilizando el flujo ADR-0031, contacto; solo lectura).

## Fase C — Catálogo completo (lo grande; elaborar briefs leyendo la web)

### Task C0 (verificación, ANTES de codificar): contrato del interés
- Leer `jayalo-main/src/lib/product-interest.functions.ts`, `InterestConfirmDialog.tsx`, `products.$productId.tsx`, `ProviderInterestsSection.tsx` y las migraciones de `product_interests`/`try_unlock_product_interest`.
- Determinar: cómo se crea el interés (¿insert con RLS? ¿server fn con service role → hace falta RPC nueva?), qué columnas ve el cliente, qué dispara la notificación al proveedor. Si hace falta RPC: diseñarla con el patrón de seguridad del proyecto y pedir autorización al PO para la migración.

### Task C1: Listado del catálogo (`/catalog`)
- Create: `lib/features/client/catalog_screen.dart` (+ test), función de datos en `repos.dart` (productos publicados con negocio, paginación como la web), ruta.
- Filtro Producto/Servicio; tarjetas con foto/precio (`fmtRD`); búsqueda si la web la tiene en esa vista; `cascadeIn`, `JayaloCard`, EmptyState con guía.

### Task C2: Detalle de producto + "Me interesa"
- Create: `lib/features/client/product_detail_screen.dart` (+ test), ruta `/catalog/:id`.
- Fotos, precio, negocio, botón "Me interesa" → diálogo de confirmación (copy de la web) → registra el interés según lo verificado en C0. Estado ya-interesado idempotente.

### Task C3: Lado proveedor — interés en el inbox + desbloqueo
- Modify: `repos.dart` (`providerInbox` deja de filtrar `source == 'marketplace'`), `inbox_screen.dart` (tarjeta de interés de producto con su acción), pantalla/diálogo de desbloqueo llamando `try_unlock_product_interest` (mostrar costo con `pointsForOffer`-equivalente SOLO informativo; el cobro real lo decide la RPC).
- Tras desbloquear: mostrar el contacto igual que la web. Cuidado con saldo insuficiente → mensaje amable + ir a recargar.

### Task C4: E2E en device (con el PO)
- Barra teñida + muesca en claro/oscuro; avatar y su menú en ambos roles; Catálogo: navegar → detalle → interés con cuenta cliente; con cuenta proveedor: ver el interés, desbloquear (usar el paquete "test" de créditos), ver el contacto. Revisar los 5 puntos de la lista de la it. 1 que MIUI dejó pendientes (fondos de listas, composer, campana, chat, ambos roles).

## Revisión final
Review de rama completa (modelo más capaz) al terminar, como en la iteración 1 — allí aparecieron los 2 Critical que ninguna tarea vio.
