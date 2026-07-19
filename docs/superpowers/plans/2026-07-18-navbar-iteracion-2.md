# Barra flotante iteración 2 — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.
> Las 3 preguntas abiertas del spec §9 quedaron CERRADAS por el PO el 2026-07-18 (ver §0 de
> este plan). El contrato del interés (antigua Task C0) ya fue VERIFICADO leyendo la web — sus
> conclusiones están en la Task 5. No re-derivar nada de eso.

**Goal:** Aplicar el feedback del PO a la barra (tinte violeta + muesca), reorganizar los
destinos (avatar con menú, Mi negocio, Reputación al 4º del cliente, el proveedor también crea
solicitudes) y construir el Catálogo de proveedores con el flujo completo de interés +
desbloqueo.

**Spec:** `docs/superpowers/specs/2026-07-18-navbar-iteracion-2-design.md`

**Base:** iteración 1 (`ef75b52..0602252`) + `b065af2`. 198 tests, analyze 0, instalada en el Redmi.

## §0 — Decisiones del PO que cierran el spec §9 (2026-07-18)

1. **Barra del proveedor (orden EXACTO, el PO lo corrigió a propósito):**

   | Rol | 0 | 1 | 2 (centro) | 3 | 4 |
   |---|---|---|---|---|---|
   | **Cliente** | Mis solicitudes `/client` | Catálogo `/catalog` | ＋ Nueva solicitud `/client/create` | Mensajes `/messages` | Reputación `/client/reputation` |
   | **Proveedor** | **Solicitudes** `/provider` | Mis ofertas `/provider/offers` | ＋ Crear solicitud `/client/create` | Mensajes `/messages` | **Mi negocio** `/provider/business` |

   - **"Solicitudes" va PRIMERA**, razón textual del PO: *"la primera ventana de interés es las
     solicitudes sin responder que tenga de su rubro"*. Es `/provider` (hoy `ProviderInboxScreen`),
     que además es la pantalla de aterrizaje del proveedor (`redirectTarget` → `/provider`), así
     que el puesto 0 y el landing coinciden.
   - El **centro del proveedor DEJA de ser 🔍 "Ver solicitudes"** y pasa a ser **＋ "Crear
     solicitud"** (`/client/create`), igual que el cliente: *"habíamos olvidado que un proveedor
     también puede solicitar"*. Verificado: `redirectTarget` no restringe rutas por rol
     ("fuera de gate/onboarding se navega libre entre tabs"), así que `/client/create` ya es
     alcanzable por un proveedor sin tocar el router.
   - Estadísticas y Ajustes salen de la barra en ambos roles → menú del avatar.

2. **"Mi negocio" v1 = productos, servicios y trabajos realizados.** Cita del PO: *"ahí
   pondremos productos, servicios y trabajos realizados (los tenemos en estadísticas
   actualmente, lo movemos aquí)"*. Es un **MOVIMIENTO**, no una copia: esas piezas salen de
   `/provider/stats`.

3. **Registro del interés: hace falta backend nuevo** (verificado en el código de la web, ver
   Task 5). Es la única excepción al "cero backend" y va con migración propia.

## Global Constraints (heredadas de la it. 1, verbatim)

- Movimiento: todo desde `JayaloMotion`; nada de `Duration(...)`/`Curves.…` sueltos; respetar `JayaloMotion.reduced(context)`.
- Color: todo del `ColorScheme` o `JayaloColors`/`JayaloStatus`. La barra usa los tokens del spec §2 EXACTOS.
- Widgets compartidos desde `brand_kit.dart`; `JayaloLoaderBlock` para cargas; `MetricTile` ya vive en `brand_kit.dart`.
- Copy en español dominicano sin jerga.
- Cada tarea: `flutter analyze` 0 + `flutter test` verde + commit propio revertible.
- Gotchas vigentes de la it. 1 (NO reintroducir): ScrollController propio por pantalla (nunca `homeScrollController` en pestañas nuevas); `setState` con bloque, no flecha; `navBarReservedSpace(context)` devuelve SOLO `MediaQuery.paddingOf(context).bottom`; `Semantics` con `excludeSemantics` debe llevar `onTap`; `activeIndex` -1 = ninguna pestaña.

## Orden de ejecución

Las rutas nuevas (`/catalog`, `/provider/business`) deben EXISTIR antes de cablear el mapa de
destinos, así que **Task 8 (mapa) va después** de las pantallas que estrena. Fase A es
entregable por sí sola y no toca navegación.

---

### Task 1: Tinte violeta de la barra
- Modify: `lib/features/shell/floating_nav_bar.dart`, `test/floating_nav_bar_test.dart`
- Mapa exacto de tokens en el spec §2. El inactivo es el mismo tono atenuado (opacidad), no otro
  color. Tests: color del fondo de la píldora y del círculo en claro y oscuro (montar con
  `jayaloTheme(Brightness.…)` y leer los `Container`/`Material` decorados); actualizar los que
  asuman `surfaceContainerLowest`/`primary`. Verificar contraste WCAG del inactivo sobre el
  fondo teñido.

### Task 2: Muesca cóncava
- Modify: `lib/features/shell/floating_nav_bar.dart`; mínimo un test de que el painter genera un
  path con la muesca (concavidad en el centro del borde superior).
- `CustomPainter` (o `ShapeBorder`) con el path de píldora + muesca circular alrededor del botón
  central, sombra siguiendo el path. Referencia conceptual: `CircularNotchedRectangle` de
  Material. El alto total NO cambia (no tocar `kNavBarReservedSpace` sin actualizar el test de
  coherencia `nav_bar_reserved_space_test.dart`).

### Task 3: Avatar en el AppBar con menú
- Create: `lib/features/shared/profile_avatar_button.dart` (+ test)
- Modify: las pantallas raíz que hoy ponen `actions: const [NotificationBell()]` →
  `[NotificationBell(), ProfileAvatarButton()]`.
- Menú por rol: cliente → Ajustes; proveedor → Estadísticas · Ajustes. Navega con `context.push`.
  Avatar: foto de perfil si existe (`profiles.avatar_url`) con fallback a la inicial.

### Task 4: Pantalla "Mi negocio" (`/provider/business`) + vaciado de Estadísticas
- Create: `lib/features/provider/my_business_screen.dart` (+ test), ruta en `core/router.dart`.
- Modify: `lib/features/provider/stats_screen.dart` (de donde SALEN las piezas movidas).
- Contenido v1 (decisión PO §0.2): cabecera del negocio (logo, nombre, badge de verificación),
  **productos**, **servicios** y **trabajos realizados**.
  - Productos/servicios: hoy son el `CatalogCard` ("LO QUE OFRECES") de `stats_screen.dart`,
    alimentado por `providerCatalogCounts()`. Se mueve ENTERO a esta pantalla.
  - "Trabajos realizados": hoy es el `MetricTile` de `completed_count` (`providerStats()`) dentro
    de "CÓMO TE CALIFICAN". Se mueve aquí.
  - Reacomodar lo que queda en Estadísticas para que no quede una fila coja: "CÓMO TE CALIFICAN"
    se queda con la calificación + reseñas; el resto de métricas (clientes atendidos, facturado,
    créditos invertidos) mantiene su agrupación. Cuidar el estado vacío de `StatsView`, que hoy
    decide con `completed == 0 && reviews == 0`.
  - NO edición en v1 (se administra en jayalo.com; conservar ese copy).

### Task 5: Backend del interés — RPC `create_product_interest` (repo `jayalo-main`)
> ⚠️ Esta tarea NO es de la app: toca `C:\Users\ac\Downloads\jayalo-main\jayalo-main`, que
> despliega a jayalo.com al pushear a master. NO pushear sin autorización del PO.

**Hallazgo verificado (ya hecho, no re-investigar):**
- Registrar interés en la web NO es una RPC: es la server function `createProductInterest`
  (`src/lib/product-interest.functions.ts`), que corre con `supabaseAdmin` (service_role) y
  DERIVA `provider_user_id`/`business_id`/`product_name` leyendo `provider_products`, rechaza el
  auto-interés y es idempotente.
- La idempotencia real la da la BD: `UNIQUE (product_id, customer_id)` en la tabla.
- ⚠️ **Vulnerabilidad viva en la web**: existe un SEGUNDO camino que inserta DIRECTO desde el
  cliente — el flujo de paquetes en `src/routes/provider/business.$id.tsx` (~línea 1939) — con
  `provider_user_id`/`business_id`/`product_name` suministrados por el cliente. La política de
  INSERT (migración `20260709204142`) solo exige `customer_id = auth.uid()`, así que cualquier
  autenticado puede forjar intereses a nombre de un proveedor ajeno, que luego paga 1 crédito
  por desbloquear basura.

**Entregable (plan autorizado por el PO):**
1. Migración nueva con la RPC `create_product_interest(_product_id uuid, _message text)`
   SECURITY DEFINER: deriva provider/business/nombre del producto server-side, bloquea el
   auto-interés, captura `unique_violation` → devuelve `already_exists`. Patrón del CLAUDE.md de
   jayalo-main: `SET search_path = public`, `REVOKE EXECUTE FROM PUBLIC, anon`, `GRANT EXECUTE TO
   authenticated` (Supabase auto-otorga a anon/authenticated al crear la función — el REVOKE
   explícito es obligatorio).
2. **`REVOKE INSERT ON public.product_interests FROM anon, authenticated`** — mata la clase
   entera de ataque, no solo esta instancia. La server function (service_role) no se ve afectada.
3. Migrar el flujo de paquetes de la web a la RPC en el MISMO cambio (reemplazar el `.insert(...)`
   por `supabase.rpc('create_product_interest', ...)`), o se rompe. Verificar que el `pkId` de
   paquetes sea una fila de `provider_products` para que el lookup de la RPC lo resuelva.
4. Declarar la RPC en `src/integrations/supabase/types.ts` (regla del proyecto).
5. Check nuevo en `scripts/db-security-check.sql` que vigile que el INSERT no vuelva a otorgarse.
6. `npx tsc --noEmit` 0, `npx vitest run` verde, `npm run lint` 0.

**BLOQUEO CONOCIDO:** el conector MCP de Supabase NO está autorizado en esta sesión, así que la
migración NO se puede aplicar a prod desde aquí. Se entrega escrita y commiteada; aplicarla
requiere al PO (autorizar el conector, o aplicarla por el dashboard). Hasta que se aplique, la
Task 7 de la app queda escrita pero no verificable end-to-end.

### Task 6: Catálogo — listado (`/catalog`)
- Create: `lib/features/client/catalog_screen.dart` (+ test), ruta; función de datos en
  `lib/data/repos.dart` (productos publicados con su negocio, paginación al estilo de la web).
- Fuente de la web: la pestaña Catálogo de `src/routes/requests/index.tsx`.
- Filtro Producto/Servicio; tarjetas con foto/precio (`fmtRD`); búsqueda si la web la tiene en esa
  vista; `cascadeIn`, `JayaloCard`, `EmptyState` con guía.

### Task 7: Catálogo — detalle + "Me interesa" (`/catalog/:id`)
- Create: `lib/features/client/product_detail_screen.dart` (+ test), ruta.
- Fuentes de la web: `src/routes/products.$productId.tsx` (detalle) y
  `src/components/marketplace/InterestConfirmDialog.tsx` (el diálogo y su copy: cantidad,
  urgencia, marca/color, dirección para producto; "qué necesitas" + lugar + foto para servicio).
  Adaptar a móvil sin inventar campos.
- Registra el interés llamando la RPC de la Task 5. Estado "ya enviaste tu interés" idempotente.

### Task 8: Nuevo mapa de destinos
- Modify: `lib/features/shell/nav_destinations.dart`, `test/nav_destinations_test.dart`
- Los dos mapas EXACTOS de la tabla del §0.1, en ese orden.
- `/settings` y `/provider/stats` dejan de ser destinos pero sus rutas siguen vivas (se llega por
  el avatar; `activeIndex` → -1 ahí, ya soportado).
- Ojo con `activeIndex` y el prefijo más largo: `/provider` (puesto 0) es prefijo de
  `/provider/offers`, `/provider/business` y `/provider/stats` — la regla del prefijo más largo ya
  lo cubre, pero el test debe cubrir explícitamente los 4 casos ahora que `/provider` es lateral.

### Task 9: Lado proveedor — interés en el inbox + desbloqueo
- Modify: `lib/data/repos.dart` (`providerInbox()` deja de filtrar `source == 'marketplace'`, que
  hoy descarta los intereses que `get_provider_inbox_unified` ya devuelve), `inbox_screen.dart`
  (tarjeta de interés de producto con su acción), diálogo de desbloqueo llamando
  `try_unlock_product_interest` (el costo mostrado es SOLO informativo; el cobro lo decide la RPC).
- Tras desbloquear: mostrar el contacto como la web (`get_unlocked_product_interest_contact`) y
  abrir chat con `get_or_create_conversation(_kind:'product_interest', _source_id)`.
- Saldo insuficiente → mensaje amable + ir a recargar (flujo ADR-0031 ya existe).

### Task 10: E2E en device (con el PO)
- Barra teñida + muesca en claro/oscuro; avatar y su menú en ambos roles; el proveedor creando una
  solicitud desde el botón central; Catálogo: navegar → detalle → interés con cuenta cliente; con
  cuenta proveedor: ver el interés, desbloquear (usar el paquete "test" de créditos), ver el
  contacto. Revisar los 5 puntos que MIUI dejó pendientes en la it. 1 (fondos de listas, composer,
  campana, chat, ambos roles).

## Revisión final
Review de rama completa (modelo más capaz) al terminar, como en la iteración 1 — allí aparecieron
los 2 Critical que ninguna tarea individual vio.

## Deuda heredada de la it. 1 a resolver en esta tanda
- La barra aparece/desaparece **de golpe** al entrar/salir del chat, sin `JayaloMotion`, contra la
  doctrina de movimiento (Minor pendiente de la Task 7 de la it. 1). Candidata natural a la Task 2
  o a la revisión final.
