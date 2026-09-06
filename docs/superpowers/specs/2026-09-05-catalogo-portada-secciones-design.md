# Catálogo de la app: portada por secciones con chips de categoría

**Fecha:** 2026-09-05 · **Aprobado por el PO** en chat («vamos con la 3, con el botón al por
mayor y los chips» → cuatro bloques + dos decisiones: «apruebo todo»).
**Mockup aprobado:** https://claude.ai/code/artifact/c4b6fc62-0d1f-4926-839c-c3d107e799f5
(tercer teléfono, «Camino 3 · elegido»). Memoria: `jayalo-mockup-catalogo-dos-caminos-2026-09-05`.
**Repo:** `jayalo-app` (Flutter) · carril base `feat/fecha-pautada-app` (`da311a9`) ·
rama `feat/catalogo-portada-secciones` · worktree `C:/Users/ac/Downloads/jayalo-app-catalogo`.
**Servidor:** NO se toca. Cero migraciones, cero RPC nuevas, cero cambios de grants ni RLS.
**Web:** NO se toca. Esta spec es solo de la app.

## 1. Por qué (lo que el PO sintió y lo que el código confirma)

El PO: «el catálogo es una sección que siento que no cuadra». Contra el código
(`features/client/catalog_screen.dart`, `shared/product_list_card.dart`,
`client/catalog_filter_sheet.dart`, `data/repos.dart`):

1. **La cabecera no sigue la gramática de las otras pestañas.** El segmentado Producto/Servicio
   ocupa el `leading` (donde las demás llevan el avatar), el título va `HeaderTitleAlign.end`
   (único caso de la app) y hay DOS segmentados apilados: el de mayoreo desaparece en Servicio,
   la cabecera cambia de alto y la rejilla salta.
2. **En la tarjeta manda el texto, no la foto.** Foto de 118 px fijos sobre ~165 px de ancho;
   el bloque de texto mide ≥144 px y apila cuatro tamaños micro (eyebrow 9,5 · estrellas 11 ·
   atributos 10 · precio 16). La tarjeta NO dice de quién es el producto (la web sí muestra la
   tienda y el sello «Tienda física»).
3. **La rejilla es plana.** 60 ítems por `created_at`, sin entrada por categoría. La web tiene
   categorías navegables desde el 08-31; la app solo las usa dentro de la hoja Filtrar.

## 2. Qué se construye

Una sola pestaña `/catalog` con **dos cuerpos** bajo la misma cabecera y la misma tira de chips:

- **Portada** (secciones apiladas) cuando NO hay ningún filtro activo.
- **Rejilla** (la de dos columnas de hoy, retocada) cuando hay filtro: categoría, «Al por
  mayor», búsqueda o «Ver todo».

### 2.1 Cabecera (`VioletHeader`)

Misma anatomía que las demás pestañas raíz:

| Ranura | Contenido |
|---|---|
| `leading` | `HeaderLeading` (avatar) como pestaña; `HeaderCircleButton` atrás cuando `Navigator.canPop` (apilada desde el menú del proveedor como «Otros proveedores») — la regla actual se conserva |
| `title` | «Catálogo», `HeaderTitleAlign.start`, `Flexible` con ellipsis |
| entre título y acciones | `HeaderSegmented` Producto/Servicio **compacto** (misma clase, padding reducido) |
| `actions` | `widget.actions` (por defecto `HeaderBell`) |
| `below` | UNA fila: buscador (`_HeaderSearchField`, sin cambios) + píldora Filtrar (`_FilterPill`, sin cambios) |

Se ELIMINA el segundo segmentado «Al detalle / Al por mayor» de la cabecera. Cambiar de kind
sigue limpiando categoría, rubro y mayoreo (comportamiento actual, test existente).
`CollapsibleHeader` (plegado al navegar) se conserva tal cual; la tira de chips NO forma parte
del header plegable: vive en el cuerpo y se desplaza con él.

### 2.2 Tira de chips (nueva, `CatalogChipStrip`)

Fila horizontal desplazable, sobre el fondo arena, padding `12 16 2`:

1. **Chip «Al por mayor»** (toggle, `FilterChip` con piel Jayalo: blanco con sombra cálida; activo
   = lila `accent` con tinta `accentFg`). **Solo en Producto** (paridad web: el mayoreo no aplica a
   servicios; hoy ya se oculta y se apaga al pasar a Servicio — se mantiene).
2. Separador vertical fino (1 px, `border`).
3. **Chip «Todo»** + un chip por categoría navegable: `categoriasNavegables(kCategories, vivas,
   seleccionada: _categoryId)` con `vivas = categoriasConCatalogo(kind)` (RPC `get_product_counts`,
   ya existente; `null` mientras carga ⇒ se muestran todas, igual que la hoja de filtros).
   Un solo chip activo a la vez. Tocar el chip activo NO lo desactiva (para volver a la portada se
   toca «Todo»).

Tocar una categoría hace `_applyFilter(categoryId: c.id)` (limpia rubro). El rubro sigue
eligiéndose SOLO en la hoja Filtrar; cuando hay rubro activo, la píldora Filtrar muestra el
nombre de la categoría como hoy y el chip de esa categoría se pinta activo.

### 2.3 Cuándo se ve cada cuerpo

```
rejilla ⇔ _categoryId != null || _wholesale || _search != null || _verTodo
portada ⇔ lo contrario
```

- `_verTodo` es un booleano nuevo que enciende «Ver todo» de «Recién publicados» (rejilla sin
  filtro, orden por fecha). Con `_verTodo` el chip «Todo» se pinta activo; tocarlo apaga
  `_verTodo` y vuelve a la portada. Cambiar de kind lo apaga.
- El buscador vacío (`_clearSearch`) vuelve a la portada si no hay otro filtro.
- El botón «Quitar filtro» del estado vacío limpia TODO (búsqueda, categoría, rubro, mayoreo,
  `_verTodo`) y vuelve a la portada.

### 2.4 Portada (nueva, `CatalogPortada`)

Se alimenta de la MISMA carga que hoy (`catalogProductsWithRatings(kind: _kind)`, 60 ítems por
`created_at` desc, con valoraciones) más UNA consulta por lote de negocios (§2.7). Sin consultas
por sección. Secciones, en este orden, cada una con cabecera `sec` (título 14 w600 `head`,
enlace «Ver todo» 11,5 w600 `primary` a la derecha cuando aplica):

| # | Sección | Contenido | «Ver todo» | Se oculta si |
|---|---|---|---|---|
| 1 | **Recién publicados** | carrusel horizontal con los **8** primeros ítems (`ProductCarouselCard`) | sí → `_verTodo = true` | < 1 ítem |
| 2 | **Tiendas** | tira horizontal de círculos (54 px) con logo o inicial + nombre a 2 líneas; negocios DISTINTOS de los 60 ítems en orden de aparición, máx. **12** | no (decisión PO: no existe lista de tiendas; no se crea) | < 1 negocio resuelto |
| 3 | **Por categoría** | rejilla 2 col de tiles (`CategoryTile`): pastilla lila con la inicial, nombre, «n artículo(s)» con `n` de `get_product_counts` para el kind; categorías navegables ordenadas por `n` desc, máx. **6** | no (cada tile ES el enlace: activa su chip) | `vivas == null` o vacío |
| 4..6 | **Carrusel por categoría** | una sección por cada una de las **3** categorías con más ítems ENTRE LOS 60 CARGADOS (no por el conteo global — así nunca sale un carrusel vacío); título = nombre de la categoría; hasta **8** ítems | sí → activa el chip de esa categoría | < 2 ítems (con uno solo ya está en Recién publicados) |

- Tocar un producto en cualquier carrusel: `GoRouter.of(context).push('/catalog/${id}')`, igual
  que la rejilla.
- Tocar un círculo de tienda: `context.push('/store/${businessId}')`, igual que «Ver tienda» en
  `product_detail_screen.dart:484`.
- Si los 60 ítems vienen vacíos: el `EmptyState` de hoy («Aún no hay artículos publicados…»),
  sin secciones.
- Pull-to-refresh (`JayaloRefresh`) y `cascadeIn` se conservan en ambos cuerpos.
- En **Servicio** la portada es idéntica (secciones 1-6 con `kind: servicio`); solo desaparece
  el chip de mayoreo.
- Padding inferior: `12 + navBarReservedSpace(context)`, como la rejilla.

### 2.5 Tarjetas

**`ProductGridCard` (rejilla, se MODIFICA):**
- Foto **cuadrada**: alto = ancho de la celda. La celda deja de tener `mainAxisExtent` fijo por
  escala tipográfica y pasa a `cellWidth + textBlock(scale)`, con `cellWidth = (ancho − 32 − 11) / 2`
  medido en el `build` (MediaQuery/LayoutBuilder). `catalogGridCardExtent` cambia de firma a
  `(BuildContext, double cellWidth)`; el test `product_list_card_test.dart` que vigila que el
  precio no se salga se adapta al nuevo bloque.
- Bloque de texto (caso peor): nombre a 2 líneas · línea de tienda · estrellas · precio.
  **Sale la eyebrow de categoría** (ya la dice el chip o la sección). **Sale la fila de atributos
  envío/estado/color** (decisión PO 2026-09-05; sustituye a la Variante A del 08-11 en la
  rejilla; los datos siguen en la ficha del producto, `product_detail_screen`).
- **Línea de tienda** (nueva): icono `storefront_outlined` 12 px + nombre del negocio 11 px
  `onSurfaceVariant`, y cuando `hasPhysicalLocation` un sufijo «· Tienda física» en la tinta
  (`ink`) del tono `requisito` de `brand.dart` (`requisitoLight`/`requisitoDark`, el MISMO que
  ya usa `PhysicalLocationBadge` para este sello — autodeclarado, nunca el verde `success`).
  Es texto, no píldora: en media tarjeta no cabe la píldora. Si el negocio no resolvió (§2.7),
  la línea NO se pinta y el bloque se encoge (no un «Proveedor» fantasma).
- Precio y estrellas: sin cambios de estilo (`_gridPrice`, `StarScore` 11 px).

**`ProductCarouselCard` (nueva, en `shared/product_list_card.dart`):** ancho 138, foto 96 de
alto (cover), nombre a 2 líneas 13 w600, línea de tienda (sin sello, por espacio), precio 15
w600 `primary`. Misma navegación que la rejilla. Sin estrellas ni atributos.

**`ProductListCard` (fila ancha, Mi negocio / tienda del proveedor): NO se toca.**

### 2.6 Hoja Filtrar y estado vacío

`catalog_filter_sheet.dart` NO cambia de comportamiento (decisión: fuera de alcance; la piel
Material de la hoja queda como ticket aparte). Único ajuste: al volver con
`CatalogFilterResult(categoryId, rubro)` el chip de esa categoría se pinta activo.

Estado vacío de la rejilla filtrada: el `EmptyState` de hoy («No hay artículos que coincidan con
tu filtro.» + «Quitar filtro»), con «Quitar filtro» limpiando también mayoreo y `_verTodo`.

### 2.7 Datos (todo existente en `repos.dart`)

| Dato | De dónde | Notas |
|---|---|---|
| 60 ítems + valoraciones | `catalogProductsWithRatings(kind, search, categoryId, rubro, wholesale)` | sin cambios |
| nombre, logo, `hasPhysicalLocation` por negocio | `businessesCardInfo(ids)` (lote, `.inFilter`) | `ids` = `business_id` distintos de los 60. Envuelta en `catchError(() => {})`: si falla, la portada pinta sin tienda y la rejilla sin la línea de tienda — **nunca la pantalla de error**. Mismo trato best-effort que las valoraciones |
| categorías con artículos + conteos | `get_product_counts` (RPC, `kind, category_id, n`) | HOY `categoriasConCatalogo(kind)` devuelve solo el `Set<String>`. Se añade `categoryCountsForKind(kind) → Map<String,int>?` (misma RPC, misma llamada; `categoriasConCatalogo` pasa a derivarse de ella para no llamar dos veces). `null` si la RPC falla ⇒ chips completos y sección «Por categoría» oculta |

`catalogProductCols` NO cambia. **No hay FK `provider_products → provider_businesses`** (verificado
2026-07-21, comentario en `catalogProducts`): por eso el negocio va en consulta aparte y NO como
embed — un embed revienta con PGRST200.

Coste de red por apertura de la pestaña: hoy 2 peticiones (productos + valoraciones) + 1 al
abrir Filtrar. Con esto: **4** (productos + valoraciones + negocios + conteos), las dos nuevas
en paralelo con las valoraciones. Cada filtro re-pide solo productos + valoraciones (+ negocios
de esos ítems); los conteos se piden una vez por kind y se cachean en el `State`.

### 2.8 Estados y errores

- Carga inicial: `JayaloLoaderBlock` como hoy.
- Error de la consulta de productos: `ErrorRetry` como hoy.
- Error de negocios o de conteos: degradan en silencio (§2.7). Sin toast.
- Sin red al tocar una tienda: lo maneja `ProviderStoreScreen`, fuera de alcance.
- Fuente del sistema en grande (hasta 1,8×): la celda de la rejilla crece con el bloque de texto
  (misma regla que hoy); las tarjetas de carrusel tienen alto por contenido (no fijo); los chips
  crecen en alto y la tira sigue siendo una fila desplazable.

### 2.9 Onboarding y copy

`onboardingCopy['client.catalog.v1']` («Aquí ves productos que los proveedores ofrecen en sus
tiendas.») sigue siendo cierto. No se cambia ni se sube a `.v2`.

## 3. Lo que NO cambia (para que nadie lo «arregle» de paso)

- La barra flotante y sus destinos (`nav_destinations.dart`).
- `ProductListCard`, `product_detail_screen.dart`, `provider_store_screen.dart`.
- La hoja Filtrar (solo el efecto visual del chip activo).
- El plegado completo de la cabecera al navegar (`CollapsibleHeader`).
- La ruta `/catalog?focus=1` (buscador enfocado desde Mis solicitudes).
- Destacados: siguen siendo solo web (decisión PO, `jayalo-destacados-catalogo-2026-08-20`).

## 4. Estructura de archivos

| Archivo | Acción |
|---|---|
| `features/client/catalog_screen.dart` | cabecera nueva, estado `_verTodo`, selector de cuerpo, alimenta chips y portada |
| `features/client/catalog_chip_strip.dart` | NUEVO: `CatalogChipStrip` (puro, recibe listas y callbacks) |
| `features/client/catalog_portada.dart` | NUEVO: `CatalogPortada` + `CategoryTile` + tira de tiendas (puro: recibe ítems, mapa de negocios, conteos y callbacks) |
| `features/shared/product_list_card.dart` | `ProductGridCard` retocada, `ProductCarouselCard` nueva, `catalogGridCardExtent(ctx, cellWidth)` |
| `data/repos.dart` | `categoryCountsForKind`; `categoriasConCatalogo` derivada |
| `core/brand.dart` | NO se toca: el tono `requisito` ya existe |

`catalog_screen.dart` (440 líneas) NO debe crecer: lo nuevo va en los dos archivos nuevos
(doctrina de archivos grandes: boy scout, nunca sprint de refactor).

## 5. Pruebas (widget tests, sin red — `CatalogFetch` inyectado + inyección nueva de
negocios y conteos en `CatalogView`)

Se adaptan en `catalog_screen_test.dart`:
- «sin apilar: no hay flecha de atrás, sí el segmentado» / «apilada: atrás + segmentado» (el
  segmentado cambia de ranura, el test debe seguir verde).
- «el toggle Al por mayor filtra el catálogo» → pasa a tocar el CHIP.
- «cambiar de kind limpia categoría y rubro» → además apaga mayoreo y `_verTodo`.

Nuevas:
1. Sin filtro ⇒ se ve «Recién publicados» y NO hay `GridView`.
2. Tocar un chip de categoría ⇒ `fetch` recibe `categoryId` y aparece la rejilla; tocar «Todo»
   vuelve a la portada.
3. «Ver todo» de Recién publicados ⇒ rejilla, `fetch` sin filtros; «Todo» activo; tocarlo vuelve.
4. En Servicio no existe el chip «Al por mayor».
5. La línea de tienda muestra el nombre y «Tienda física» solo cuando `hasPhysicalLocation`;
   sin negocio resuelto no se pinta.
6. Con 1 ítem: Recién publicados visible, carruseles por categoría ausentes.
7. Sección «Por categoría» ausente cuando los conteos son `null`.
8. `product_list_card_test.dart`: el precio no se recorta con `textScaler` 1,8 y celda de 160 px.

`ListView`/`GridView` largos: usar `scrollUntilVisible` antes de un `findsNothing` (gotcha
documentado 2026-09-04).

## 6. Entrega

- Un commit por tarea del plan; la rama entera es reversible con un `revert` del merge
  (doctrina de diseños reversibles).
- Cuatro agentes por cambio: analista + contraste ANTES de codificar cada tarea; verificador +
  certificador DESPUÉS (`po-regla-agente-verificador-por-cambio`).
- Gates: `flutter analyze` 0, suite completa verde (contar la línea base en la rama antes de
  la primera tarea), APK release con sello de build,
  **smoke del PO en el teléfono** antes de mergear a `feat/fecha-pautada-app`.
- El número de build es global entre worktrees: reservar el siguiente al compilar y anotar el
  carril (gotcha 2026-09-04).

## 7. Riesgos conocidos

- **Inventario pequeño:** con decenas de artículos el mismo producto aparece en «Recién
  publicados» y en su carrusel de categoría. Aceptado por el PO al elegir el camino 3.
- **Ancho de la cabecera a 360 px:** avatar 36 + título + segmentado compacto (~150) + campana 36
  caben con el título en `Flexible`; con fuente 1,8× el título puede truncar a «Catál…». Si en el
  smoke molesta, el segmentado baja a una segunda fila SOLO en escala ≥1,5 (decisión reservada
  al PO, no implementar por adelantado).
- **`get_product_counts` cuenta sin distinguir mayoreo:** los «n artículos» de los tiles no cambian
  con «Al por mayor» encendido; como con mayoreo el cuerpo es la rejilla y no la portada, no se
  ven a la vez. Documentarlo en el código.
