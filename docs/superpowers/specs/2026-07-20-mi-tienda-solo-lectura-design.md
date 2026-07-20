# Mi tienda: escaparate de solo lectura + botón "Editar en la web" (magic-link SSO)

**Fecha:** 2026-07-20
**Estado:** aprobado (diseño) — pendiente de plan de implementación
**Pantalla (app):** `lib/features/provider/my_business_screen.dart` (ruta `/provider/business`).
**Repos afectados:** `jayalo-app` (Flutter, la mayor parte) y `jayalo-main` (web: una server
function nueva para el magic link).

## Contexto y objetivo

El siguiente gran bloque era la "Tienda del proveedor" con **edición en la app** (crear/editar/
borrar productos, servicios y trabajos realizados). El PO decidió que esa edición es un cambio
demasiado grande y la difiere a **V2**. Para esta entrega:

> "Que por ahora solo se muestre la tienda las cosas principales de la web —detalles, productos,
> servicios, opiniones— pero no se edite."

Y, en vez de reconstruir los formularios en la app, un **"magic button"** que lleve a editar **en
la web**, donde la edición ya existe y funciona (`/provider/business/$id`, gated por `isOwner`).

Objetivo de esta pieza (V1):

1. **Mi negocio** deja de ser una tarjeta de conteo inerte y pasa a mostrar el **escaparate real**
   del propio negocio, **solo lectura**: detalles + productos + servicios + opiniones.
2. Un botón **"Editar en la web"** que abre la página de edición del negocio en el navegador
   **ya con la sesión iniciada** (magic-link SSO), sin duplicar formularios en la app.

Es la vista de **solo el negocio propio** (un solo negocio, el primero de `myBusinessProfile()`),
alcanzada **desde Mi negocio**. No es una tienda pública de terceros ni toca el flujo de
desbloqueo por créditos.

## Alcance

**Dentro (V1):**
- Detalles del negocio (solo lectura).
- Lista de productos propios (`provider_products` `kind=producto`).
- Lista de servicios propios (`provider_products` `kind=servicio`).
- Opiniones: agregado (promedio + nº) y lista de reseñas con texto (`business_reviews`).
- Botón "Editar en la web" con magic-link SSO.

**Fuera (V2 / piezas aparte, ya acordado):**
- Toda **edición nativa** en la app (crear/editar/borrar). Vive en la web vía el magic button.
- **Trabajos realizados** (`provider_portfolio_items`) y **paquetes** (`provider_packages`): la
  tabla existe, pero no estaban en la lista del PO. Fáciles de sumar como secciones nuevas después.
- **Multi-negocio**: opera sobre el primer negocio de `myBusinessProfile()`, como hoy.
- El **feed anónimo/aleatorio** al catálogo (pieza E del bloque original).

## Parte 1 — App: "Mi tienda" (solo lectura)

`MyBusinessScreen` mantiene su estructura (VioletHeader "Mi negocio" + `FutureBuilder` +
`_refetch`), pero `MyBusinessView` deja de dibujar la `CatalogCard` inerte y el `MetricTile` de
"trabajos realizados" y pasa a dibujar el escaparate, de arriba a abajo. Todo con la estética
actual (JayaloCard, `cascadeIn`, header violeta, sin bordes duros).

### 1.1 Detalles del negocio

Reusa `_BusinessHeaderCard` (logo, nombre, chip "Negocio verificado") y **añade** los datos
principales que la web muestra en `BusinessDetailsCard`, todos de solo lectura:

- **Categoría** — `categoryNameById(category_id)`.
- **Zona** — `city` (y/o `sector`/`service_area` si aplica; el plan fija cuál).
- **Mayorista** — chip si `is_wholesale`.
- (Opcional) **Descripción** del negocio (`description`) si no está vacía.

El copy "se administran desde jayalo.com" se retira (lo reemplaza el botón "Editar en la web").

### 1.2 Productos y 1.3 Servicios

Dos secciones (`SectionHeader` "PRODUCTOS" / "SERVICIOS"), cada una una lista de los ítems propios.
Reusa el **mismo ítem de lista horizontal del catálogo** (`2026-07-20-catalogo-lista-y-filtros`):
foto 104×104 con placeholder + fundido, nombre, precio (`_priceLine`), descripción a 2 líneas.
La reputación por fila del catálogo **no aplica aquí** (es tu propio negocio; el promedio va en
Opiniones).

- Si una sección está vacía → estado vacío discreto ("Aún no tienes productos" / "…servicios"),
  **no** un CTA de crear (la creación es V2 / web).
- **Tap en un ítem** → navega al detalle existente `/catalog/:id` (estilo landing), **ocultando el
  botón "Me interesa"** cuando el producto es del propio usuario (ver §1.5).

### 1.4 Opiniones

- **Encabezado**: promedio (1 decimal) + nº de reseñas, vía `businessRatings([businessId])` que ya
  existe (RPC `get_business_ratings`). Si 0 reseñas → estado vacío ("Aún no tienes opiniones").
- **Lista** de reseñas (hasta ~50, más recientes primero): estrellas/rating, comentario, fecha.
  **Anónimas** (nunca `reviewer_id` ni nombre), igual que la web.

### 1.5 Detalle del producto propio (ocultar "Me interesa")

`ProductDetailScreen` (`/catalog/:id`) hoy muestra el CTA "Me interesa" (flujo de cliente). Para el
dueño no tiene sentido. Se añade una rama `isOwner` (el `user_id` del producto == usuario actual)
que **oculta** ese CTA (y cualquier acción de cliente) dejando el resto de la landing intacto. Es
la única modificación a una pantalla existente fuera de Mi negocio.

### 1.6 Botón "Editar en la web" (magic-link SSO)

Botón destacado en Mi tienda (arriba, bajo los detalles). Al tocarlo:

1. Llama a `openBusinessEditorLink()` (nueva en `data/repos.dart`): hace `POST` a la server
   function de la web (§ Parte 2) con el header `Authorization: Bearer <access_token de la sesión
   Supabase de la app>` y el `businessId`. Devuelve una **URL de acción** (magic link).
2. Abre esa URL con `launchUrl(uri, mode: LaunchMode.externalApplication)` (el navegador del
   sistema; `url_launcher` ya está en la app). El navegador verifica el enlace → queda con la
   sesión iniciada → redirige a `/provider/business/{businessId}` → el usuario ve los botones de
   editar.
3. Estados: spinner mientras se pide el enlace; `toastDbError` si falla; mensaje claro si
   `launchUrl` devuelve `false` (sin navegador).

**No** se usa WebView (la app ya se quemó con el WebView en MIUI, ADR-0032). Es el navegador
externo, que además trae el gestor de contraseñas del usuario.

### 1.7 Capa de datos nueva (`data/repos.dart`)

Todo de solo lectura salvo la llamada al magic link:

```dart
/// Productos y servicios del propio negocio (paridad con el select de la
/// página de negocio de la web), agrupables por kind en la UI.
Future<List<Map<String, dynamic>>> myStoreProducts(String businessId);

/// Reseñas con texto de un negocio (anónimas: rating, comment, created_at;
/// NUNCA reviewer_id). Ver nota de RLS abajo.
typedef BusinessReview = ({double rating, String? comment, DateTime createdAt});
Future<List<BusinessReview>> businessReviews(String businessId);

/// Pide a la web un magic link de un solo uso que deja la sesión iniciada y
/// redirige a la página de edición del negocio. Devuelve la URL a abrir.
Future<String> openBusinessEditorLink(String businessId);
```

Se reutilizan `myBusinessProfile()` (extendida con `category_id`, `city`, `is_wholesale`,
`description`) y `businessRatings()`.

## Parte 2 — Web: server function del magic link (`jayalo-main`)

Nueva server function (`src/lib/*.functions.ts`, p. ej. `business-editor-link.functions.ts`),
patrón `createServerFn` + validación de JWT calcada de `aiSession.server.ts` (ADR-0032):

1. Lee `Authorization: Bearer <jwt>` (reusa `extractBearerToken`) y valida con
   `supabase.auth.getUser(jwt)` → obtiene `user` (id + email). Sin usuario válido → 401.
2. **Verifica propiedad**: `provider_businesses` con `id = businessId AND user_id = user.id`. Si no
   es dueño → 403. (Defensa: el enlace solo redirige a un negocio propio.)
3. Genera el enlace con `supabaseAdmin.auth.admin.generateLink({ type: 'magiclink', email:
   user.email, options: { redirectTo: `${SITE_URL}/provider/business/${businessId}` } })` y
   devuelve `properties.action_link`.

Notas:
- `generateLink` **no envía correo**; se usa la URL devuelta directamente (mismo mecanismo que
  `e2e/session.ts`).
- El enlace se emite **solo para el email del propio llamador autenticado**, un solo uso,
  expiración corta → no permite iniciar sesión como otra persona.
- `supabaseAdmin` y `SITE_URL` ya existen en el runtime del worker.
- CORS/consumo desde la app: definir cómo la app llama la server function (fetch directo al
  endpoint de TanStack Start con el header Bearer). El plan fija la URL y el manejo de CORS.

## RLS y verificaciones (para el plan, no código de diseño)

1. **`business_reviews` legible por el dueño.** La web lee `id,rating,comment,created_at` client-
   side directo, así que probablemente `authenticated` puede hacer ese `SELECT`. **Preferencia:**
   select directo de esas columnas (mirror de la web) **si** la RLS/grants lo permiten sin exponer
   `reviewer_id`. **Si no**, añadir una RPC `get_business_reviews(_business_id uuid)` SECURITY
   DEFINER que devuelva solo `rating, comment, created_at` (consistente con `get_business_ratings`).
   El plan decide leyendo la política real.
2. **Allowlist de redirect URLs de Supabase Auth**: confirmar que `https://jayalo.com/**` (o el
   path `/provider/business/*`) está permitido, o `generateLink`/el verify fallará al redirigir.
3. **`provider-products`**: `myStoreProducts` solo lee `image_urls` (URLs firmadas a 10 años que la
   web ya guardó); no sube nada. Sin cambios de storage.

## Estética

Doctrina de mockups vigente (tipografía ligera, cero negro, sin bordes, header violeta,
`JayaloCard` con sombra cálida, `cascadeIn`). El ítem de producto/servicio es **el mismo** del
catálogo para no inventar un segundo tratamiento. El botón "Editar en la web" usa el violeta de
marca; ícono de enlace externo (`Icons.open_in_new`) para señalar que sale de la app.

## Reversibilidad

Un commit por el rediseño de `MyBusinessView` (doctrina "diseños reversibles"): el spec del
commit debe decir qué SHA revierte a la tarjeta de conteo actual. La server function de la web y
la rama `isOwner` de `ProductDetailScreen` son aditivas (no rompen nada existente).

## Riesgos y decisiones abiertas

- **La edición ocurre en el navegador del móvil, no en la app.** Aceptado como "escape hatch"; la
  web es responsive. Es explícitamente el trade-off que evita reconstruir formularios (V2).
- **Magic link de un solo uso**: si el navegador lo pre-carga o se reusa, falla y hay que
  reintentar. Comportamiento estándar; el copy de error debe invitar a reintentar.
- **RLS de `business_reviews`**: resuelta en el plan (select directo vs RPC nueva).
- **Trabajos realizados / paquetes**: fuera por decisión del PO; reevaluar en V2 junto con la
  edición.
