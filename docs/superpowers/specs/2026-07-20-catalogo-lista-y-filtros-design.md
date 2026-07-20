# Catálogo: lista con detalle + filtros (categoría/rubro/mayoreo) + reputación

**Fecha:** 2026-07-20
**Estado:** aprobado (diseño) — pendiente de plan de implementación
**Pantalla:** `lib/features/client/catalog_screen.dart` (pestaña `/catalog` del cliente; también
se apila como "Otros proveedores" desde el menú del proveedor).

## Contexto y objetivo

El Catálogo v1 (Task 6) es una rejilla de 2 columnas que solo muestra foto + nombre + precio, y
solo filtra por el toggle Producto/Servicio + búsqueda por texto. El PO pide dos cosas:

1. **Ver más detalle por producto.** Cambiar la rejilla por una **lista a todo el ancho** (una
   "tarjeta que respira" por fila, como el resto de la app) que muestre categoría, nombre
   completo, **reputación del proveedor**, descripción y precio grande. Referencia visual: la
   lista de resultados de Amazon (foto a la izquierda, detalles a la derecha), adaptada a los
   datos reales de Jayalo (no hay "comprados el mes pasado" ni "Agregar al carrito").
2. **Filtrar el catálogo.** Botón "Filtrar" → hoja con las ~40 categorías y sus rubros (paridad
   con la web `productHitsQ`), más un modo **"Al por mayor"** visible en el header.

El pulido de precios grandes / cero-blanco-muerto que originó esta sesión queda **subsumido** por
el nuevo layout de lista (el tratamiento del precio se conserva).

## 1. Layout de lista (VALIDADO en device)

Cada ítem es un `JayaloCard` horizontal (margen y sombra cálida estándar de la app):

- **Foto** a la izquierda, cuadrada 104×104, `ClipRRect` radius `kCardRadius-6`, con placeholder
  (`Icons.image_outlined`) y fundido de entrada (`frameBuilder`, 300 ms ease-out).
- **Columna derecha** (`Expanded`, `crossAxisAlignment.start`):
  1. **Categoría** — `categoryNameById(category_id)` en versalitas, 10.5px w600, `letterSpacing .8`,
     color `cs.primary`. Oculta si la categoría no resuelve.
  2. **Nombre** — 15px, `height 1.25`, w600, `jayaloHead`, máx. 2 líneas + ellipsis.
  3. **Reputación** (ver §2) — `★ + promedio(1 decimal) + (conteo)`. Oculta si el proveedor no
     tiene reseñas (no mostrar "0.0").
  4. **Descripción** — 12.5px, `height 1.3`, máx. 2 líneas + ellipsis. **Color:** debe cumplir
     contraste ≥4.5:1 sobre la tarjeta blanca; `onSurfaceVariant` (#847D8F ≈ 3.2:1) **no cumple**,
     usar `onSurface` (#4A4458) o un tono intermedio verificado. Oculta si no hay descripción.
  5. **Precio** (`_priceLine`) — 20px w700 `cs.primary`, `FittedBox scaleDown` para que un rango
     largo entre en una línea; "desde " como prefijo tenue; "Consultar precio" en gris
     (`onSurfaceVariant`) cuando no hay precio.
- La fila entera navega al detalle (`/catalog/:id`).

Contenedor: `ListView.builder` (no rejilla), `padding` top 8 / bottom `12 + navBarReservedSpace`.
La entrada en cascada (`cascadeIn`) se conserva.

## 2. Reputación del proveedor por fila

**Interfaz estable en el frontend** (requisito del PO: poder migrar a denormalizado sin tocar la
UI). Nueva función en `data/repos.dart`:

```dart
/// avg/count de reseñas por negocio. Hoy respaldada por una RPC por lote;
/// mañana puede leer una columna denormalizada sin cambiar esta firma ni la UI.
typedef BusinessRating = ({double avg, int count});
Future<Map<String, BusinessRating>> businessRatings(List<String> businessIds);
```

- **Implementación v1:** RPC `get_business_ratings(_business_ids uuid[])` (SECURITY DEFINER) que
  agrega `business_reviews` (avg(rating), count(*)) agrupado por `business_id`, para los ids de la
  página actual. **Una** query extra por página; se dispara tras cargar los productos con los
  `business_id` distintos y no nulos.
- **Escala:** la app muestra el promedio tal cual con `toStringAsFixed(1)` (igual que
  `stats_screen`/`reputation_screen`), no convierte a 5 estrellas.
- **Fuente del promedio:** `business_reviews` (por negocio), no `conversation_ratings` (por trato,
  por `user_id`) — el catálogo muestra un producto de un **negocio**. Confirmar en el plan que la
  RLS de `business_reviews` permite el agregado vía la RPC SECURITY DEFINER (leer solo avg/count,
  nunca reviewer_id).
- **Migración futura (fuera de alcance):** trigger que mantenga `avg_rating`/`reviews_count` en
  `provider_businesses` + backfill; entonces `businessRatings` lee esa columna (o el catálogo la
  incluye en su `select`) y se retira la RPC. La firma Dart no cambia.
- **Sin reseñas:** la fila oculta la estrella (v1). "Nuevo" como etiqueta queda para después.

## 3. Filtro por categoría/rubro (hoja)

**Botón "Filtrar":** píldora a la derecha del buscador (fila `below` del header), patrón
`WarmSearchField.onFilter` (ícono `tune`). Estados:
- Sin filtro: "Filtrar".
- Con filtro: muestra la categoría (o "Categoría · rubro") + ✕ que lo quita de un toque, sin abrir
  la hoja.

**Hoja** (`showModalBottomSheet`, nuevo `catalog_filter_sheet.dart`):
- Asa de arrastre, título "Filtrar", acción "Limpiar" (visible solo si hay filtro).
- Buscador "Buscar categoría…" que filtra las ~40 `kCategories` por nombre.
- Lista acordeón: tocar una categoría la expande y carga sus rubros
  (`rubrosForCategories([catId])`, ya existe). Fila "Todo {categoría}" aplica solo-categoría; cada
  rubro aplica categoría+rubro.
- **Selección única. Tocar = aplica y cierra.** La categoría/rubro activo queda marcado al reabrir.
- Motion: expand del acordeón 200 ms ease-out; respeta "reducir animaciones".

**Reglas de interacción/paridad:**
- Cambiar el toggle Producto/Servicio **limpia** categoría+rubro (parity `productHitsQ`).
- Elegir categoría nueva limpia el rubro previo.
- Estado vacío: cuando el filtro no da resultados, `EmptyState` con CTA "Quitar filtro" (además de
  "Quitar búsqueda").

## 4. "Al por mayor" (toggle en el header)

- **Segmentado `Al detalle / Al por mayor`** (`HeaderSegmented`, blanco sobre violeta) en la fila
  `below`, encima de la fila de búsqueda+Filtrar. El header suma tiers en el `below`: (1) fila
  superior **sin cambios** — (atrás si apilado) + segmentado Producto/Servicio + título + campana;
  (2) Al detalle/Al por mayor; (3) buscador + Filtrar.
- **La ranura leading NO se toca** (decisión PO 2026-07-20): el segmentado Producto/Servicio se
  queda arriba junto a la flecha de atrás; NO se restaura el avatar en el Catálogo (la campana y la
  navbar ya estaban presentes — se verificó en device que solo "faltaba" el avatar, y el PO lo deja
  así). Todo lo nuevo (Al por mayor, Filtrar) va en tiers del `below`.
- **Ortogonal:** se combina con kind y categoría; **no** resetea el filtro.
- **Efecto:** restringe el catálogo a productos de negocios mayoristas
  (`provider_businesses.is_wholesale = true`), igual que la pestaña mayoreo de la web.

## 5. Capa de datos

Extender `catalogProducts(...)` y el typedef `CatalogFetch` con parámetros **opcionales** (default
null/false → tests y el harness `dev/catalog_preview.dart` siguen compilando):

```dart
Future<List<Map<String,dynamic>>> catalogProducts({
  required String kind, String? search,
  String? categoryId, String? rubro, bool wholesale = false,
});
```

Filtros server-side, paridad `productHitsQ` (`routes/requests/index.tsx`):
- `if (categoryId != null) .eq('category_id', categoryId)`
- `if (rubro != null) .ilike('rubro', rubro)`
- `if (wholesale)` → `select` con `provider_businesses!inner(is_wholesale)` +
  `.eq('provider_businesses.is_wholesale', true)`.

Estado en `_CatalogViewState`: `_kind`, `_search`, `_categoryId`, `_rubro`, `_wholesale`. Cada
cambio re-dispara `_refetch()` (mismo patrón `.ignore()` ya documentado).

## Ya implementado en esta sesión (verificado en device)

- Layout de lista (§1) + contraste de la descripción.
- **Entrada de búsqueda desde Mis solicitudes:** el buscador "Buscar en Jayalo" de
  `my_requests_screen.dart` ya no muestra "próximamente" — abre el Catálogo (`context.push`) con
  `?focus=1` (buscador enfocado, teclado arriba). "Filtrar" abre el Catálogo; abrirá su hoja de
  filtros cuando exista (§3). Cableado con `autofocusSearch` en `CatalogScreen`/`CatalogView` +
  `?focus=1` en la ruta `/catalog`. Verificado E2E: buscar "54689" filtró a 1 resultado.

## Pendiente de implementar (plan)

- Reputación real por fila (§2): RPC `get_business_ratings` + `businessRatings(ids)`.
- Hoja de filtro categoría/rubro (§3) y el estado activo de la píldora Filtrar.
- Toggle Al detalle/Al por mayor (§4).
- Extensión de `catalogProducts` con `categoryId`/`rubro`/`wholesale` (§5).

## No-goals (v1)

- El buscador de la hoja empareja **nombres de categoría**, no rubros de todas las categorías a la
  vez (exigiría cargar los ~40 juegos de rubros). Los rubros se buscan expandiendo su categoría; la
  búsqueda de texto del catálogo ya cubre rubros sueltos.
- `kCategories` no trae `kind` → las 40 aparecen en Producto y en Servicio (la web las separa por
  kind vía la tabla `categories` de BD, hoy vacía en prod).
- Sin iconos por categoría (la web usa lucide; `kCategories` móvil es solo id+name). El rótulo va
  como texto.
- Reputación denormalizada (trigger + columna) — diferida; hoy RPC por lote tras la interfaz
  estable.
- Etiqueta "Nuevo" para proveedores sin reseñas — diferida.

## Verificación

- Por screenshots en el Redmi (harness `lib/dev/catalog_preview.dart`, ya cubre casos de borde:
  precio fijo/rango/desde/consultar, sin foto, proveedor sin reseñas). El harness se ejecuta con
  `flutter run -d <device> -t lib/dev/catalog_preview.dart`; no entra en producción.
- `flutter analyze` en 0 y la suite de widgets (`flutter test`) verde; si `catalogProducts` cambia
  de firma, actualizar los stubs de test que inyectan `CatalogFetch`.
- Contraste de la descripción verificado ≥4.5:1.
