# Menú del avatar ampliado (proveedor) — diseño

Fecha: 2026-07-20

## Problema

Un proveedor no tiene ningún camino en la UI para llegar a varias pantallas
que **ya existen** en el router pero no están en su navbar ni en su menú:

- `/client` — **Mis solicitudes** (las que él mismo pide como comprador). Hoy
  el único acceso es el botón "Ver mis solicitudes" de la pantalla de éxito al
  crear una solicitud; después no hay forma de volver.
- `/client/reputation` — **Reputación** (de comprador; `get_customer_reputation`).
  Relevante para el proveedor que también pide: las advertencias de "baja tu
  reputación como comprador" (al eliminar una solicitud) apuntan aquí.
- `/catalog` — el **catálogo del marketplace** (todos los productos/servicios
  publicados; vista de comprador). En el menú del proveedor se etiqueta
  **"Otros proveedores"** para que se entienda que es lo que ofrecen los demás,
  NO su propio catálogo (sus productos viven en "Mi negocio", `/provider/business`,
  ya en su navbar).
- **Créditos / wallet** — el proveedor gasta créditos para desbloquear
  contactos, pero no puede ver su saldo ni recargar salvo dentro de las hojas
  de desbloqueo.

La navbar de proveedor está **cerrada por doctrina del PO** (iteración 2, orden
vinculante, exactamente 5 slots: 2 + centro + 2). No se toca. El lugar correcto
para "lo que salió de la barra" es el **menú del avatar** (`openProfileMenu`),
que ya hospeda Estadísticas y Ajustes bajo ese mismo criterio.

## Alcance

**Dentro:** ampliar `openProfileMenu` en
`app/lib/features/shared/profile_avatar_button.dart` con las entradas de arriba,
más un encabezado con saldo de créditos. Añadir una flecha de atrás condicional
a las 3 pantallas-pestaña cuando se abren apiladas.

**Fuera (spec aparte):** "cambiar de negocio si tiene varios". El modelo NO
soporta multi-negocio hoy — `myBusinessId`, `myBusinessName`, `myBusinessProfile`,
wallet y productos hacen todos `.eq('user_id', uid).limit(1)` (agarran el primer
negocio). Un cambiador real exige listar negocios, persistir un "negocio activo"
y enhebrarlo por cada query que usa `myBusinessId()`. Es un proyecto propio.

## Diseño

### Menú (drawer lateral izquierdo, 264px — igual que hoy)

Role-aware, como ya es `openProfileMenu` (`roleStore.value`).

**Proveedor:**

1. **Encabezado** (nuevo): foto/inicial + nombre desde `profileStore`, y debajo
   una **banda de créditos RESALTADA** — el saldo **"N créditos"** en número
   grande y violeta sobre una banda teñida, con un **"+"** violeta al lado para
   recargar (abre el wallet externo). Los créditos son el core del negocio, por
   eso se destacan. El saldo se obtiene con `walletBalance()` al abrir el menú,
   **best-effort**: si falla o aún no cargó, la banda muestra "Créditos" sin
   número pero el "+" sigue disponible (recargar nunca queda inalcanzable). No se
   cachea en un store nuevo — una llamada por apertura del menú, aceptable.
2. **Ítems**, en este orden (agrupación implícita: primero "yo como comprador",
   luego "mi negocio", luego cuenta; separadas por un `Divider` sutil, sin
   encabezados de sección):
   - Mis solicitudes → `/client`
   - Reputación → `/client/reputation`
   - Otros proveedores → `/catalog` *(el catálogo del marketplace, renombrado
     para el proveedor: lo que ofrecen los demás, no su propio negocio)*
   - — divider —
   - Estadísticas → `/provider/stats` *(ya existía)*
   - Recargar créditos → wallet externo *(se conserva junto al "+" de la banda:
     recargar es el core del negocio, la redundancia es deliberada)*
   - — divider —
   - Ajustes → `/settings` *(ya existía)*

**Consumidor:** sin cambios respecto a hoy (solo Ajustes). Ya alcanza
Solicitudes/Catálogo/Reputación por su navbar y no usa créditos.

### Navegación

Los ítems de ruta cierran el drawer (`Navigator.pop`) y navegan con
`context.push(route)` — igual que el `openProfileMenu` actual. Push (no go)
para que las pantallas se apilen sobre la pestaña del proveedor y el atrás
vuelva a donde estaba.

"Recargar créditos" NO es una ruta: replica el patrón ADR-0031 de
`inbox_screen._openWallet` — intenta `createWalletLoginLink()` y abre el
resultado con `launchUrl(..., LaunchMode.externalApplication)`; si falla, un
fallback a `AppConfig.walletUrl`. El pago SIEMPRE ocurre fuera de la app. Para
no duplicar, se extrae ese helper a un punto reutilizable (ver Componentes).

### Flecha de atrás condicional

`Mis solicitudes` (`MyRequestsScreen`), `Reputación` (`ReputationScreen`) y
`Catálogo` (`CatalogScreen`) son pantallas-pestaña: usan `VioletHeader` con
`leading: const HeaderAvatar()` y no tienen flecha de atrás. Empujadas desde el
menú, el proveedor debe poder volver con una flecha visible (no solo el gesto de
sistema).

Mecanismo: un widget `HeaderLeading` (nuevo, en `profile_avatar_button.dart` o
`violet_header.dart`) que decide en `build`:

- Si `context.canPop()` (extensión de go_router; hay algo apilado en el
  Navigator anidado) → un `BackButton`/`IconButton(Icons.arrow_back)` que hace
  `context.pop()`.
- Si no → `const HeaderAvatar()` (comportamiento actual).

Las 3 pantallas cambian `leading: const HeaderAvatar()` por
`leading: const HeaderLeading()`. Auto-ajustable:

- Consumidor entrando por navbar (`go`) → `canPop` false → avatar (sin cambios).
- Proveedor entrando por el menú (`push`) → `canPop` true → flecha de atrás.

## Componentes

- `openProfileMenu(context)` — reescrito: encabezado + lista role-aware. Recibe/
  lee el saldo. Mantiene el drawer lateral y su animación (`emphasized`, `page`).
- `_walletBalanceForMenu()` o similar — obtención best-effort del saldo al abrir
  (o se hace inline en `openProfileMenu` antes de `showGeneralDialog`).
- `openExternalWallet(context)` — helper extraído del patrón de
  `inbox_screen._openWallet` (createWalletLoginLink → launchUrl externo →
  fallback AppConfig.walletUrl → snack si falla). Reutilizado por el menú y, si
  se quiere, por `inbox_screen` (opcional, no requerido por esta tarea).
- `HeaderLeading` — leading condicional (atrás vs avatar) para las pantallas-
  pestaña.

## Manejo de errores

- `walletBalance()` falla → se omite el chip de créditos; el resto del menú
  funciona.
- `createWalletLoginLink()` falla → fallback a `AppConfig.walletUrl`; si el
  `launchUrl` también falla → snack "No se pudo abrir el navegador…" (idéntico a
  inbox).
- Sin sesión / rol transitorio → el menú ya es role-aware; el consumidor ve el
  menú mínimo.

## Pruebas

- Widget test de `openProfileMenu`: como proveedor aparecen Mis solicitudes,
  Reputación, Catálogo, Estadísticas, Recargar, Ajustes; como consumidor solo
  Ajustes. Inyectar un `walletBalance` fake para no tocar red.
- Test del chip de créditos: con saldo → muestra "N créditos"; con fetch que
  lanza → no muestra número y no revienta.
- Test de `HeaderLeading`: con un Navigator que puede popear → renderiza el
  botón de atrás; sin nada apilado → renderiza `HeaderAvatar`.
- Verificación E2E en device (Redmi): como proveedor, abrir el menú, entrar a
  Mis solicitudes, volver con la flecha; recargar abre el navegador externo.

## Reversibilidad

Un solo commit. Revertirlo restaura el menú de dos ítems (Estadísticas +
Ajustes) y el `leading: HeaderAvatar` de las 3 pantallas. No toca datos, router,
ni navbar.
