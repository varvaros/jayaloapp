# Catálogo por artículos en la app: proveedores, productos, servicios y paquetes

**Fecha:** 2026-09-08 · **Aprobado por el PO** en chat («ya está en la apk?» → «no» → «si», tras ver la
web en producción). **Espejo de la web**, spec
`jayalo-main/docs/superpowers/specs/2026-09-07-catalogo-por-articulos-design.md` (v2), desplegada en
jayalo.com el 2026-09-08 (`master` `1ad854a`). Mockup de la app aprobado dentro del artifact
https://claude.ai/code/artifact/1356fa35-05df-42f6-8e8f-aefdf37ab3f9 (teléfono derecho, «Artículos
v3 · orden PO»).
**Repo:** app (`jayalo-app`) · base tronco `feat/fecha-pautada-app` (`367b338`, 1.0.4+124) · rama
`feat/catalogo-articulos-app` · worktree `C:/Users/ac/Downloads/jayalo-app-articulos` (con
`key.properties` y `google-services.json` copiados).
**Servidor:** cero migraciones. Todo con tablas, columnas y RPC ya otorgadas a `anon`: `provider_products`,
`provider_packages` (lectura pública desde `20260809130000`), `provider_businesses`
(`name, logo_url, has_physical_location, description, city, business_verified_at, identity_verified_at`),
`get_product_counts`, `get_business_ratings`.
**Web:** NO se toca.

## 1. Por qué

La web ya enseña productos, servicios y paquetes en cuatro secciones; la app sigue con la portada del
09-05 (segmentado Producto/Servicio en la cabecera, «Recién publicados», «Tiendas», «Por categoría»,
carruseles por categoría) y **los paquetes no aparecen en su catálogo**. El PO quiere paridad. La
lógica pura ya está resuelta y probada en la web (`src/lib/catalogItem.ts`, `src/lib/proveedores.ts`)
y se traduce a Dart casi línea a línea.

## 2. Diseño

### 2.1 Dónde vive

Pestaña Catálogo del shell (`/catalog`, `CatalogScreen` → `CatalogView` en
`lib/features/client/catalog_screen.dart`). Misma anatomía de cabecera que las demás pestañas
(`VioletHeader`: avatar o atrás, título «Catálogo», campana; debajo buscador + «Filtrar»), que se pliega
al navegar. **Sale el `HeaderSegmented` Producto/Servicio de la cabecera**: el tipo pasa a una fila de
chips (§2.3). Doctrina de la app que manda sobre la web: **no hay banner «Crear solicitud» ni cierre
«Publicar solicitud»** — crear solicitud vive SOLO en el botón central de la barra flotante
(doctrina de la app, PO 2026-07-19). Tampoco entra el lateral: sus filtros van a la hoja «Filtrar» (§2.4).

### 2.2 Estado de la pantalla

`CatalogView` conserva `_search`, `_categoryId`, `_rubro`, `_wholesale`, `_counts` y gana:

| Campo | Tipo | Defecto | Papel |
|---|---|---|---|
| `_tipo` | `'todos' \| 'producto' \| 'servicio' \| 'paquete' \| 'proveedor'` | `'todos'` | pestaña de tipo |
| `_ciudad` | `String?` | `null` | filtro Ubicación |
| `_precioMin`, `_precioMax` | `int` | `0` (= sin filtro) | filtro Precio |
| `_soloVerificados`, `_conLocal` | `bool` | `false` | filtro Proveedor |

`_kind` y `_verTodo` **desaparecen**. Regla del cuerpo (sustituye a `_filtrado`):
`_verSecciones = _tipo == 'todos' && _search == null && !_wholesale`. Con `_verSecciones` se pintan las
cuatro secciones (§2.5); si no, la rejilla del tipo activo (§2.6). La categoría/rubro **no** quita las
secciones (paridad web: acotan las cuatro). El mayoreo sí: «Al por mayor» = rejilla directa de productos
mayoristas, sin paquetes (decisión C del 09-06).

### 2.3 Filas de chips (dentro de la lista, como hoy la tira)

1. **Tipo** (nueva, `CatalogTipoStrip`): «Todos · Productos · Servicios · Paquetes · Proveedores», con el
   conteo del conjunto cargado y filtrado entre paréntesis pequeños («Productos 7»). Estilo: la píldora de
   `CatalogChipStrip` con el activo en **tinta oscura** (`cs.onPrimaryContainer` de fondo, texto blanco,
   como la píldora «Filtrar») para distinguirla de las categorías, que siguen en lila. Tocar el activo no
   lo apaga; «Todos» vuelve a las secciones.
2. **Categorías** (la `CatalogChipStrip` de hoy): «Al por mayor» solo con `_tipo` ∈ {todos, producto};
   «Todo» y las categorías navegables con sus conteos. Conteos y navegables = **unión de ambos kinds**
   (`categoryCountsForKind('producto')` + `('servicio')` sumados por id, en una función pura
   `sumarConteos`). Con categoría activa, debajo los rubros como sub-chips (hoy solo están en la hoja;
   entran en la tira, misma píldora, tamaño 11).

### 2.4 Hoja «Filtrar» (`catalog_filter_sheet.dart`)

Gana tres bloques encima del acordeón de categorías, con `SectionHeader` de la app:

- **Ubicación**: `DropdownButtonFormField` con «Todas las ciudades» + ciudades distintas de los negocios
  cargados (`BusinessCardInfo.city`).
- **Precio**: dos campos numéricos «Desde RD$» / «Hasta RD$» (`filledField`), 0 = sin filtro; solo dígitos.
- **Proveedor**: dos `SwitchListTile` «Solo verificados» (`identityVerified || businessVerified`) y
  «Con local» (`hasPhysicalLocation`). «A domicilio» no entra (sin dato).

El acordeón de categorías pasa a la unión de kinds (`categoriasConCatalogo` para ambos, unidas) y sus
rubros a `rubrosForCategories` como hoy. `CatalogFilterResult` gana `ciudad`, `precioMin`, `precioMax`,
`soloVerificados`, `conLocal`; «Limpiar» pone todo a defecto. La píldora «Filtrar» muestra el nombre de
la categoría como hoy y, si hay otros filtros sin categoría, «Filtrar · n».

### 2.5 Secciones (`CatalogSecciones`, sustituye a `CatalogPortada`)

Orden **fijo** (decisión del PO): **Proveedores → Productos → Servicios → Paquetes**. Una sección vacía no
se pinta. `SeccionTitulo` gana el conteo tras el título («Productos 7», gris) y «Ver todos» (copy nuevo,
antes «Ver todo»).

| Sección | Contenido | Tope | «Ver todos» |
|---|---|---|---|
| Proveedores | fila horizontal de `_StoreCircle` (logo o inicial, nombre) **más una línea gris**: qué hace o «Tienda física» (teal) | 12 | → `_tipo = 'proveedor'` |
| Productos | carrusel de `ProductCarouselCard` (§2.7) | 8 | → `_tipo = 'producto'` |
| Servicios | ídem | 8 | → `_tipo = 'servicio'` |
| Paquetes | ídem, con lo incluido | 8 | → `_tipo = 'paquete'` |

Orden dentro de cada sección: `created_at` desc del servidor, y encima **con foto antes que sin foto**
(estable, `ordenarCatalogo`). No hay destacados en la app (decisión 08-20).

### 2.6 Rejillas («Ver todos», pestaña ≠ Todos, búsqueda, mayoreo)

- Producto / Servicio / Paquete: la rejilla de 2 columnas de hoy con `ProductGridCard` (§2.7); con
  búsqueda y `_tipo == 'todos'`, rejilla **mixta** de los tres con insignia de tipo.
- Proveedor: lista vertical de `ProveedorCard` (nueva, `JayaloCard`): logo redondo 44, nombre, «Verificado»
  en verde (`identityVerified || businessVerified`), qué hace (`description` recortada a 40 caracteres por
  palabra o la categoría dominante de sus artículos), «Tienda física» · ciudad, chevron. Toca → `/store/:id`.
- Con búsqueda, encima de la rejilla una fila de píldoras «Proveedores que coinciden:» (logo + nombre →
  `/store/:id`): negocios cuyo **nombre** coincide, por consulta best-effort `catalogBusinessesByName(term)`
  (`ilike` sobre `name`, término saneado de `%_,()*`, límite 5, error ⇒ `[]`), unidos a los proveedores de
  los artículos cargados cuyo nombre coincide. Sin loader.

### 2.7 Tarjetas (`shared/product_list_card.dart`)

`ProductGridCard` y `ProductCarouselCard` reciben el mismo mapa de ítem; los paquetes llegan ya mapeados
(§2.8). Cambios:

1. **Insignia de tipo** arriba a la izquierda de la foto, solo con `showTypeTag` (las rejillas y carruseles
   del catálogo la pasan; «Mi negocio» y la tienda no): «Producto» blanca con tinta de título, «Servicio»
   violeta con texto blanco (hoy no existe en la app; entra), «Paquete» tinta oscura (`cs.onPrimaryContainer`)
   con texto blanco. Fuente 9,5, mayúsculas, radio 999.
2. **Foto → logo del negocio → icono**: sin foto, el logo (`negocio.logoUrl`) redondo al 42 % centrado sobre
   lila (`cs.primaryContainer` degradado); sin logo, el placeholder de hoy.
3. **Paquete**: `ProductCarouselCard` pasa a foto **cuadrada** (`AspectRatio 1`, antes 96 apaisados) y ancho
   150; bajo el nombre, **lo incluido** (`items` unidos con « · », 2 líneas, 10,5 gris); precio con
   `catalogPriceLine` (0 ⇒ `price` null ⇒ «Consultar precio»). Toca → `/package/:id` (existe;
   `package_detail_screen.dart` con «Solicitar»). Producto/servicio siguen a `/catalog/:id`.
4. Línea de tienda: «Vendido por» no existe en la app (solo icono + nombre + «Tienda física»); se mantiene.
5. `catalogGridCardExtent` suma el alto de la línea de lo incluido cuando la rejilla es de paquetes (2 líneas
   de 10,5 ≈ 28 px); `product_list_card_test.dart` lo vigila.

### 2.8 Datos (`data/repos.dart`) y lógica pura (`features/client/catalog_articulos.dart`)

- `catalogProducts({String? kind, …})`: `kind` **nullable**; `null` ⇒ sin `.eq('kind')` (ambos). Con
  mayoreo, `kind` = `'producto'` siempre.
- `catalogPackages()` (nueva): `provider_packages` con `packageCols + ',created_at'`, `created_at` desc,
  límite 30, **best-effort** (`try/catch` ⇒ `[]`), tope 4 s como los negocios. Sin búsqueda en servidor: se
  filtra en cliente (`coincideBusqueda` sobre nombre, descripción e ítems).
- `paqueteComoItem(Map row) → Map` (pura): `kind: 'paquete'`, `image_urls: [image_url]` o `[]`,
  `items`, `price` = `null` si `<= 0`, `price_min/max` null, `category_id: ''`, `description`, `created_at`.
- `businessesCardInfo`: el select gana `description,city`; `BusinessCardInfo` gana `String? description`,
  `String? city`. `_StoreCircle`/`ProveedorCard` los usan.
- `catalogItemsWithRatings({kind, …})` (sustituye a `catalogProductsWithRatings`): productos+servicios
  (según `kind`) **y** paquetes, cada uno con la reputación de su negocio (`businessRatings` por lote, ids
  de ambos conjuntos). `CatalogFetch` pasa a `({String? kind, …})`; nueva firma inyectable
  `CatalogPackagesFetch` para tests.
- Puras, con `test()`: `paqueteComoItem`, `filtrarLateral(items, negocios, filtros)`, `ordenarCatalogo`,
  `seccionesCatalogo` (topes 8), `resumenConteos`, `ciudadesDe(negocios)`, `coincideBusqueda`,
  `esVerificado(negocio)`, `proveedoresDeItems(items, negocios)` (máx. 12, sin repetidos, orden de aparición,
  `queHace` con la misma prioridad que la web), `sumarConteos(a, b)`, `sanitizarIlike`.
- Los conteos de la fila de tipo y de los títulos son del **conjunto cargado y filtrado** (≤ 60 + 30), como
  en la web; los de la tira de categorías siguen siendo los globales de `get_product_counts`.

### 2.9 Búsqueda, vacío, error, carga

- Búsqueda (`_search`): productos/servicios en servidor como hoy; paquetes en cliente; rejilla mixta
  (§2.6) con la fila de proveedores que coinciden.
- Vacío: `EmptyState` de hoy; con cualquier filtro (tipo ≠ todos, categoría, rubro, búsqueda, mayoreo,
  ciudad, precio, verificados, local) el mensaje «No hay artículos que coincidan con tu filtro.» y «Quitar
  filtro» (pone TODO a defecto, incluido `_tipo`); en la pestaña Proveedores, «No hay proveedores que
  coincidan con tu filtro.». Sin filtro, el copy de hoy.
- Error: `ErrorRetry` solo si falla la consulta de productos; paquetes, negocios y nombres degradan en
  silencio. Carga: `JayaloLoaderBlock` como hoy. Pull-to-refresh recarga todo (incluidos paquetes y conteos).

### 2.10 Onboarding y copy

`onboardingCopy['client.catalog.v1']` (`shared/onboarding_copy.dart`): si algún paso nombra el segmentado
Producto/Servicio o «Recién publicados», se actualiza a la fila de tipo y las secciones. Copy literal:
«Todos», «Productos», «Servicios», «Paquetes», «Proveedores», «Ver todos», «Tienda física», «Verificado»,
«Consultar precio», «desde », «Ubicación», «Todas las ciudades», «Precio», «Desde RD$», «Hasta RD$»,
«Proveedor», «Solo verificados», «Con local», «Limpiar», «Proveedores que coinciden:», «Quitar filtro».

## 3. Lo que sale y lo que se mantiene

**Sale:** `HeaderSegmented` de la cabecera del catálogo; `CatalogPortada` («Recién publicados», «Tiendas»,
«Por categoría», carruseles por categoría) y `portadaCategorias`/`portadaCarruseles` con sus tests (se
reescriben como `CatalogSecciones` + `catalog_articulos.dart`); `_verTodo`; `_kind`.
**Se mantiene:** cabecera plegable, buscador, píldora «Filtrar», `CatalogChipStrip` (gana rubros), la
rejilla de 2 columnas, `ProductGridCard` en «Mi negocio»/tienda sin insignia, `/catalog/:id`, `/store/:bid`,
`/package/:id`, la barra flotante, el mayoreo, la guía de bienvenida.

## 4. Verificación

- `flutter analyze` 0 · suite verde (línea base del tronco a medir en la Task 0; el 09-06 eran 1918) ·
  `dart format`.
- Tests nuevos: puros (`catalog_articulos_test.dart`, ≥ 14 casos: paquete mapeado, precio 0, filtros con
  «Consultar» pasando, orden estable, topes, proveedores con `queHace`, unión de conteos, saneo ilike),
  widget (`catalog_secciones_test.dart`, viewport 400×1600: orden de títulos, sección vacía no se pinta,
  «Ver todos» cambia el cuerpo; `catalog_tipo_strip_test.dart`; `catalog_filter_sheet_test.dart` con los
  bloques nuevos; `product_list_card_test.dart` con insignia, lo incluido y logo como respaldo).
- APK release instalado en el teléfono del PO (`adb install -r`), captura con `adb exec-out screencap`
  (receta: `cmd statusbar collapse` → abrir → `input tap 400 2436` = pestaña Catálogo): secciones en
  orden, Chicha → `/package/:id`, servicio de aire con logo, «Filtrar» con los bloques nuevos, Proveedores.
  **Número de build:** leer el actual en `pubspec.yaml` (global entre worktrees) y subir +1 en el chore.
- Smoke del PO en el teléfono; AAB solo cuando lo pida.

## 5. Fuera de alcance

Banner y cierre con CTA (doctrina de la barra flotante); cercanía/distancia; «A domicilio»; favoritos;
categorías nuevas (Salud, Deporte, Educación: cambio de contenido en `domain/catalog.dart` + web + BD, en su
propio commit); periodicidad de planes («/ mes»); paginación de «Ver todos» (se pinta lo cargado).
