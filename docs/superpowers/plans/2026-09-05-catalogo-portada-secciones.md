# Catálogo: portada por secciones — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir la pestaña Catálogo de la app en una portada por secciones (recién publicados, tiendas, categorías, carruseles) con una tira de chips de categoría y «Al por mayor», que pasa a la rejilla de dos columnas en cuanto hay un filtro; cabecera alineada con las demás pestañas y tarjeta con foto cuadrada y línea de tienda.

**Architecture:** `CatalogView` (ya existente, `features/client/catalog_screen.dart`) conserva el estado y la carga; gana un booleano `_verTodo`, un mapa de conteos por categoría y una segunda consulta por lote de negocios. El cuerpo se elige con una regla pura (`rejilla ⇔ hay filtro`). Lo nuevo vive en archivos nuevos y puros (reciben datos y callbacks, no tocan la red): `catalog_chip_strip.dart`, `catalog_portada_secciones.dart` (helpers puros), `catalog_portada.dart` (widgets). Las tarjetas comparten `storeLine` y `catalogPriceLine` en `shared/product_list_card.dart`.

**Tech Stack:** Flutter 3.44.6 (stable), Dart 3 records/patterns, `go_router`, `supabase_flutter` (solo a través de `data/repos.dart`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-05-catalogo-portada-secciones-design.md` (leerla entera antes de la Tarea 1).

## Global Constraints

- Repo `jayalo-app`, worktree **`C:/Users/ac/Downloads/jayalo-app-catalogo`**, rama `feat/catalogo-portada-secciones` (base `feat/fecha-pautada-app` @ `da311a9`). Todos los comandos se lanzan desde `C:/Users/ac/Downloads/jayalo-app-catalogo/app`.
- **Servidor NO se toca**: cero migraciones, cero RPC nuevas, cero grants. **Web NO se toca.**
- **No se tocan**: `nav_destinations.dart`, `ProductListCard`, `product_detail_screen.dart`, `provider_store_screen.dart`, la lógica de `catalog_filter_sheet.dart`, `CollapsibleHeader`, la ruta `/catalog?focus=1`, `onboarding_copy.dart`.
- Piel (doctrina PO 2026-07-19): pesos 400–600 (**nunca 700+ en lo nuevo**; el precio existente a `w700` se conserva tal cual), sin negro, tarjetas sin borde (sombra cálida), fotos `cover`, filtros discretos. Tinta de títulos = `jayaloHead(context)`; texto atenuado = `cs.onSurfaceVariant`.
- «Tienda física» va en la tinta `ink` del tono `requisito` (`JayaloStatus.requisitoLight/Dark`), **nunca** `JayaloColors.success` ni `Icons.verified`.
- Copys exactos: «Catálogo», «Producto», «Servicio», «Al por mayor», «Todo», «Recién publicados», «Tiendas», «Por categoría», «Ver todo», «Buscar en el catálogo», «Filtrar», «Tienda física», «1 artículo» / «n artículos», «Consultar precio», «desde ».
- Topes: 8 recientes · 12 tiendas · 6 tiles de categoría · 3 carruseles · 8 ítems por carrusel · un carrusel necesita ≥ 2 ítems.
- Regla del cuerpo: `rejilla ⇔ _categoryId != null || _wholesale || _search != null || _verTodo`.
- Cada tarea termina con `flutter analyze` en 0 y su test en verde, y con un commit. Mensajes de commit en español, sin acentos en el asunto (convención del repo: `feat(catalogo): …`), con el pie `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Gotcha de tests: un `findsNothing` sobre una lista larga pasa en falso si el ítem no llegó a construirse; en estos tests las listas son cortas (≤ 4 ítems) y caben en el viewport de 800×600 del test, así que no hace falta `scrollUntilVisible` salvo que se indique.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `lib/data/repos.dart` | `countsForKind` (pura) + `categoryCountsForKind` (RPC) ; `categoriasConCatalogo` derivada | 1 |
| `lib/features/shared/violet_header.dart` | `HeaderSegmented.compact` | 2 |
| `lib/features/shared/product_list_card.dart` | `ProductGridCard` (foto 1:1, línea de tienda, sin eyebrow ni atributos), `storeLine`, `catalogPriceLine`, `catalogGridCardExtent(ctx, cellWidth)`, `ProductCarouselCard` | 3, 4 |
| `lib/features/client/catalog_chip_strip.dart` | `CatalogChipStrip` (puro) | 5 |
| `lib/features/client/catalog_portada_secciones.dart` | helpers puros: `portadaTiendas`, `portadaCategorias`, `portadaCarruseles`, `articulosLabel` | 6 |
| `lib/features/client/catalog_portada.dart` | `CatalogPortada` + `SeccionTitulo`, `_StoreCircle`, `CategoryTile` | 7 |
| `lib/features/client/catalog_header_widgets.dart` | `CatalogSearchField`, `CatalogFilterPill` (movidos desde `catalog_screen.dart`, sin cambios) | 8 |
| `lib/features/client/catalog_screen.dart` | cabecera nueva, `_verTodo`, conteos, negocios, selector de cuerpo | 8 |
| `test/catalog_counts_test.dart`, `test/header_segmented_compact_test.dart`, `test/product_list_card_test.dart`, `test/product_carousel_card_test.dart`, `test/catalog_chip_strip_test.dart`, `test/catalog_portada_secciones_test.dart`, `test/catalog_portada_test.dart`, `test/catalog_screen_test.dart` | pruebas | 1–8 |

---

### Task 1: Conteos por categoría desde la RPC existente

**Files:**
- Modify: `lib/data/repos.dart:3996-4016` (función `categoriasConCatalogo`)
- Test: `test/catalog_counts_test.dart` (nuevo)

**Interfaces:**
- Consumes: `supa.rpc('get_product_counts')` → filas `{kind, category_id, n}` (ya existe en prod, `GRANT EXECUTE` a anon y authenticated).
- Produces:
  - `Map<String, int> countsForKind(List<Map<String, dynamic>> rows, String kind)` — pura.
  - `Future<Map<String, int>?> categoryCountsForKind(String kind)` — `null` si la RPC falla.
  - `Future<Set<String>?> categoriasConCatalogo(String kind)` — misma firma que hoy, ahora derivada.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/catalog_counts_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  final rows = <Map<String, dynamic>>[
    {'kind': 'producto', 'category_id': 'belleza', 'n': 2},
    {'kind': 'producto', 'category_id': 'electronica', 'n': 1},
    {'kind': 'servicio', 'category_id': 'plomeria', 'n': 4},
    // kind nulo cuenta como producto (mismo criterio que categoriasConCatalogo).
    {'kind': null, 'category_id': 'hogar', 'n': 3},
    // sin categoría: se ignora.
    {'kind': 'producto', 'category_id': null, 'n': 9},
  ];

  test('countsForKind agrupa por categoría solo el kind pedido', () {
    expect(countsForKind(rows, 'producto'),
        {'belleza': 2, 'electronica': 1, 'hogar': 3});
    expect(countsForKind(rows, 'servicio'), {'plomeria': 4});
  });

  test('countsForKind tolera n como num/String y lista vacía', () {
    expect(countsForKind(const [], 'producto'), isEmpty);
    expect(
        countsForKind([
          {'kind': 'producto', 'category_id': 'autos', 'n': 5.0},
        ], 'producto'),
        {'autos': 5});
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_counts_test.dart
```
Esperado: error de compilación `The function 'countsForKind' isn't defined`.

- [ ] **Step 3: Implementar**

En `lib/data/repos.dart`, sustituir la función `categoriasConCatalogo` (líneas 3996-4016, desde su doc-comment `/// Ids de categoría con artículos PUBLICADOS…` hasta el cierre `}`) por:

```dart
/// Pura: de las filas de la RPC `get_product_counts` (`kind, category_id, n`)
/// al mapa categoría → cantidad de artículos publicados del kind pedido. Un
/// `kind` nulo cuenta como 'producto' (fila legada); sin `category_id` se
/// ignora. Separada para probarse sin red.
Map<String, int> countsForKind(List<Map<String, dynamic>> rows, String kind) => {
      for (final r in rows)
        if ((r['kind'] ?? 'producto') == kind && r['category_id'] != null)
          r['category_id'] as String: (r['n'] as num?)?.toInt() ?? 0,
    };

/// Conteo de artículos publicados por categoría del kind dado ('producto' |
/// 'servicio'). Alimenta la tira de chips y la sección «Por categoría» de la
/// portada del catálogo. Sale de la RPC `get_product_counts` — agregado en
/// servidor, el mismo que usa la web para su sidebar. Ante cualquier error
/// devuelve `null`: el caller enseña la lista completa de categorías y oculta
/// la sección de conteos (degradar, nunca una pantalla vacía).
///
/// ⚠️ La RPC cuenta sin distinguir mayoreo: con «Al por mayor» encendido los
/// conteos no cambian. No se ven a la vez (con mayoreo el cuerpo es la rejilla).
Future<Map<String, int>?> categoryCountsForKind(String kind) async {
  try {
    final rows =
        List<Map<String, dynamic>>.from(await supa.rpc('get_product_counts'));
    return countsForKind(rows, kind);
  } catch (_) {
    return null;
  }
}

/// Ids de categoría con artículos PUBLICADOS del kind dado. Alimenta el
/// filtrado de categorías «navegables» de la hoja de filtros (decisión PO
/// 2026-08-31, paridad web). Derivada de [categoryCountsForKind]: `null` si la
/// RPC falla (el caller enseña la lista completa).
Future<Set<String>?> categoriasConCatalogo(String kind) async =>
    (await categoryCountsForKind(kind))?.keys.toSet();
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_counts_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/data/repos.dart app/test/catalog_counts_test.dart && git commit -m "feat(catalogo): conteos por categoria desde get_product_counts

countsForKind (pura) + categoryCountsForKind; categoriasConCatalogo pasa a
derivarse de ella. Sin RPC nueva.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `HeaderSegmented` compacto

**Files:**
- Modify: `lib/features/shared/violet_header.dart:654-712` (clase `HeaderSegmented`)
- Test: `test/header_segmented_compact_test.dart` (nuevo)

**Interfaces:**
- Produces: `HeaderSegmented({required options, required index, required onChanged, bool compact = false})`. Con `compact: true` el padding de cada segmento pasa de `12×5` a `10×4` y la fuente de `11` a `10.5`.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/header_segmented_compact_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: ColoredBox(color: Colors.deepPurple, child: child),
          ),
        ),
      );

  testWidgets('compact ocupa menos ancho que el normal con las mismas opciones',
      (tester) async {
    await tester.pumpWidget(host(HeaderSegmented(
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    final normal = tester.getSize(find.byType(HeaderSegmented)).width;

    await tester.pumpWidget(host(HeaderSegmented(
      compact: true,
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    final compact = tester.getSize(find.byType(HeaderSegmented)).width;

    expect(compact, lessThan(normal));
    // Sigue siendo tocable: cambiar de segmento avisa con el índice.
    var got = -1;
    await tester.pumpWidget(host(HeaderSegmented(
      compact: true,
      options: const ['Producto', 'Servicio'],
      index: 0,
      onChanged: (i) => got = i,
    )));
    await tester.tap(find.text('Servicio'));
    expect(got, 1);
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/header_segmented_compact_test.dart
```
Esperado: error de compilación `No named parameter with the name 'compact'`.

- [ ] **Step 3: Implementar**

En `lib/features/shared/violet_header.dart`, dentro de `class HeaderSegmented`:

Constructor y campos: sustituir
```dart
  const HeaderSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
```
por
```dart
  const HeaderSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  /// Versión estrecha para convivir en la fila del título con el avatar y la
  /// campana (Catálogo, 2026-09-05): padding 10×4 y fuente 10,5 en vez de 12×5
  /// y 11. Misma pista, mismos colores, mismo tic háptico.
  final bool compact;
```

Y en el `build`, sustituir
```dart
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
```
por
```dart
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
```
y
```dart
                    fontSize: 11,
```
por
```dart
                    fontSize: compact ? 10.5 : 11,
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/header_segmented_compact_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/shared/violet_header.dart app/test/header_segmented_compact_test.dart && git commit -m "feat(header): HeaderSegmented compact para la fila del titulo

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `ProductGridCard` con foto cuadrada y línea de tienda

**Files:**
- Modify: `lib/features/shared/product_list_card.dart:228-476` (constantes de la rejilla, `catalogGridCardExtent`, `ProductGridCard`)
- Modify: `lib/features/client/catalog_screen.dart:302-321` (la `GridView.builder`: solo el cálculo del `mainAxisExtent`, para que siga compilando)
- Test: `test/product_list_card_test.dart`
- Test: `test/catalog_screen_test.dart:146-183` (los dos tests de atributos)

**Interfaces:**
- Consumes: `BusinessCardInfo` (record en `data/repos.dart`: `name, logoUrl, whatsappVerified, identityVerified, businessVerified, hasPhysicalLocation`), `JayaloStatus.requisitoLight/Dark` (`core/brand.dart`), `StarScore`, `fmtRD`, `JayaloCard`, `JayaloNetworkImage`.
- Produces:
  - `ProductGridCard({required Map<String, dynamic> item, BusinessCardInfo? negocio})`.
  - `Widget? storeLine(BuildContext context, BusinessCardInfo? negocio, {bool sello = true})` — `null` sin negocio.
  - `Widget catalogPriceLine(ColorScheme cs, Map<String, dynamic> item, {required double size})`.
  - `double catalogGridCardExtent(BuildContext context, double cellWidth)`.
  - `Widget catalogImage(String? url, ColorScheme cs)` — foto `cover` con fundido o placeholder.

- [ ] **Step 1: Adaptar y ampliar el test de la tarjeta**

En `test/product_list_card_test.dart`:

1. Añadir el import:
```dart
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
```

2. En el grupo `ProductGridCard no desborda la celda de la rejilla`, sustituir la línea
```dart
                      height: catalogGridCardExtent(context),
```
por
```dart
                      height: catalogGridCardExtent(context, width),
```
y añadir `'avg_rating': 8.0, 'reviews_count': 1,` ya están; dejar `peor` como está (los atributos ya no se pintan, pero el fixture documenta el caso real).

3. Añadir al final de `main`, antes del `}` de cierre, este grupo:

```dart
  group('ProductGridCard: línea de tienda y forma', () {
    const negocioFisico = (
      name: 'Barbería El Conde',
      logoUrl: null,
      whatsappVerified: false,
      identityVerified: false,
      businessVerified: false,
      hasPhysicalLocation: true,
    );
    const negocioSinLocal = (
      name: 'Otaku Store RD',
      logoUrl: null,
      whatsappVerified: false,
      identityVerified: false,
      businessVerified: false,
      hasPhysicalLocation: false,
    );
    const item = {
      'id': 'p1',
      'name': 'Máquina de cortar pelo Remington',
      'category_id': 'belleza',
      'price': 1850,
      'offers_shipping': true,
      'condition': 'nuevo',
    };

    Widget celda(Widget child) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 160, height: 300, child: child),
            ),
          ),
        );

    testWidgets('con negocio y local pinta nombre y «Tienda física»',
        (tester) async {
      await tester.pumpWidget(celda(const ProductGridCard(
          item: item, negocio: negocioFisico)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Barbería El Conde'), findsOneWidget);
      expect(find.textContaining('Tienda física'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('sin local no pinta el sello', (tester) async {
      await tester.pumpWidget(celda(const ProductGridCard(
          item: item, negocio: negocioSinLocal)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Otaku Store RD'), findsOneWidget);
      expect(find.textContaining('Tienda física'), findsNothing);
    });

    testWidgets('sin negocio no pinta la línea (ni un «Proveedor» fantasma)',
        (tester) async {
      await tester.pumpWidget(celda(const ProductGridCard(item: item)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
      expect(find.textContaining('Proveedor'), findsNothing);
    });

    testWidgets('ya no pinta eyebrow de categoría ni atributos (PO 2026-09-05)',
        (tester) async {
      await tester.pumpWidget(celda(const ProductGridCard(item: item)));
      await tester.pumpAndSettle();
      expect(find.text('BELLEZA'), findsNothing);
      expect(find.text('Traslado'), findsNothing);
      expect(find.text('Nuevo'), findsNothing);
    });

    testWidgets('la foto es cuadrada: tan alta como ancha la tarjeta',
        (tester) async {
      await tester.pumpWidget(celda(const ProductGridCard(item: item)));
      await tester.pumpAndSettle();
      final foto = tester.getSize(find.byType(AspectRatio));
      expect(foto.width, 160);
      expect(foto.height, 160);
    });
  });
```

4. En `test/catalog_screen_test.dart`, BORRAR los dos tests de la Variante A:
   - `'la fila de atributos pinta envío/estado/color y calla cuando faltan (Variante A, PO 2026-08-11)'` (líneas 146-168)
   - `'sin atributos declarados no hay fila (ni icono suelto)'` (líneas 170-183)

   y en su lugar añadir:

```dart
  testWidgets(
      'la rejilla ya no pinta envío/estado/color (PO 2026-09-05: viven en la ficha)',
      (tester) async {
    final conAtributos = {
      ...fixedItem,
      'condition': 'nuevo',
      'offers_shipping': true,
      'offer_defaults': {
        'colors': ['Rojo', 'Azul'],
      },
    };
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [conAtributos],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Taladro inalámbrico'), findsOneWidget);
    expect(find.text('Traslado'), findsNothing);
    expect(find.text('Nuevo'), findsNothing);
    expect(find.text('Rojo, Azul'), findsNothing);
  });
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/product_list_card_test.dart
```
Esperado: error de compilación (`catalogGridCardExtent` con 2 argumentos, `negocio` desconocido).

- [ ] **Step 3: Implementar la tarjeta**

En `lib/features/shared/product_list_card.dart`:

1. Imports: quitar `import '../../domain/offer_defaults.dart';` (solo lo usaba la fila de atributos) y añadir
```dart
import '../../data/repos.dart' show BusinessCardInfo;
```
(`../../core/brand.dart` ya está importado: de ahí salen `JayaloStatus` y `jayaloHead`).

2. Sustituir TODO el bloque desde `/// Alto de la foto de [ProductGridCard]…` (línea 228, `const double _kGridImageHeight = 118;`) hasta el final del archivo por:

```dart
/// Padding vertical del bloque de texto de [ProductGridCard] (10 arriba + 12
/// abajo).
const double _kGridTextPadding = 22;

/// Alto del bloque de texto de [ProductGridCard] a escala 1, en el CASO PEOR:
/// nombre a 2 líneas + línea de tienda + reputación + precio, con sus huecos
/// (≈94 medidos; se toma 104 para dejar margen a la fuente del entorno de
/// test). `product_list_card_test.dart` vigila que siga alcanzando.
const double _kGridTextBlock = 104;

/// Alto de la celda de la rejilla del catálogo: la foto es CUADRADA (tan alta
/// como ancha la celda, [cellWidth]) y debajo va el bloque de texto, que crece
/// con la fuente del sistema. Antes la foto medía 118 fijos y el bloque de
/// texto la superaba (PO 2026-09-05: «manda el texto, no la foto»).
double catalogGridCardExtent(BuildContext context, double cellWidth) {
  // Escala tipográfica efectiva (Android 14 la aplica de forma no lineal, por
  // eso se mide sobre un tamaño representativo del bloque).
  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
  return cellWidth +
      _kGridTextPadding +
      _kGridTextBlock * scale.clamp(1.0, 1.8);
}

/// Foto de catálogo: `cover`, fundido suave al cargar (doctrina de
/// movimiento) y placeholder neutro sin foto o con error. Compartida por la
/// tarjeta de rejilla y la de carrusel.
Widget catalogImage(String? url, ColorScheme cs) {
  Widget placeholder() => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
      );
  if (url == null) return placeholder();
  return JayaloNetworkImage(
    url,
    fit: BoxFit.cover,
    frameBuilder: (_, child, frame, wasSync) => wasSync
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          ),
    errorBuilder: (_, _, _) => placeholder(),
  );
}

/// Línea «de quién es»: icono de tienda + nombre del negocio y, si declara
/// local y [sello] lo permite, el sufijo «· Tienda física» en la tinta teal
/// del tono `requisito` (AUTODECLARADO: nunca el verde de verificado — ver
/// `PhysicalLocationBadge`). Va como texto y no como píldora porque en media
/// tarjeta la píldora no cabe. `null` sin negocio: la tarjeta se encoge, no
/// inventa un «Proveedor» fantasma.
Widget? storeLine(BuildContext context, BusinessCardInfo? negocio,
    {bool sello = true}) {
  if (negocio == null) return null;
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final teal =
      (dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight).ink;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Icon(Icons.storefront_outlined, size: 12, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Flexible(
        child: Text.rich(
          TextSpan(
            text: negocio.name,
            style: TextStyle(
                fontSize: 11, height: 1.25, color: cs.onSurfaceVariant),
            children: [
              if (sello && negocio.hasPhysicalLocation)
                TextSpan(
                  text: ' · Tienda física',
                  style: TextStyle(color: teal, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]),
  );
}

/// Precio del catálogo a un [size] dado — misma semántica que [_priceLine] de
/// la fila ancha (fijo / rango / «desde» / «Consultar precio»). Un
/// [FittedBox] encoge un rango largo a una línea sin achicar los cortos.
Widget catalogPriceLine(ColorScheme cs, Map<String, dynamic> item,
    {required double size}) {
  final price = item['price'] as num?;
  final min = item['price_min'] as num?;
  final max = item['price_max'] as num?;
  final big = TextStyle(
    fontSize: size,
    height: 1,
    fontWeight: FontWeight.w700,
    color: cs.primary,
    letterSpacing: -.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  if (price == null && min == null) {
    return Text('Consultar precio',
        maxLines: 1,
        style: TextStyle(
            fontSize: size * .78,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant));
  }
  final Widget line;
  if (price != null) {
    line = Text(fmtRD(price), maxLines: 1, style: big);
  } else if (max != null) {
    // Guion simple con espacios: paridad EXACTA con `catalogPriceLabel` de la web.
    line = Text('${fmtRD(min)} - ${fmtRD(max)}', maxLines: 1, style: big);
  } else {
    line = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('desde ',
            style: TextStyle(
                fontSize: size * .72,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant)),
        Text(fmtRD(min), style: big),
      ],
    );
  }
  return Align(
    alignment: Alignment.centerLeft,
    child: FittedBox(
        fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: line),
  );
}

/// Tarjeta de REJILLA del catálogo (mockup aprobado PO 2026-09-05, camino 3):
/// foto CUADRADA arriba y debajo solo lo que decide un vistazo — nombre a 2
/// líneas, de quién es ([storeLine]), reputación si la hay y precio. La
/// categoría ya no viaja aquí (la dice el chip o la sección) ni los atributos
/// envío/estado/color (viven en la ficha del producto). [ProductListCard]
/// (fila ancha) sigue siendo la de «Mi negocio»/tienda del proveedor.
class ProductGridCard extends StatelessWidget {
  const ProductGridCard({super.key, required this.item, this.negocio});
  final Map<String, dynamic> item;

  /// Cabecera del negocio dueño del producto (nombre, local). `null` = no
  /// resolvió (consulta caída o negocio borrado): la línea no se pinta.
  final BusinessCardInfo? negocio;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;

    return JayaloCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      // Solo vive en el catálogo (shell): misma ruta que la fila ancha.
      onTap: () => GoRouter.of(context).push('/catalog/${item['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(kCardRadius)),
            child: AspectRatio(aspectRatio: 1, child: catalogImage(img, cs)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  ?storeLine(context, negocio),
                  if (avg > 0 && count > 0) ...[
                    const SizedBox(height: 3),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      // Estrellas a 11 px: en media tarjeta las cinco más el
                      // texto van justas — mirar primero en el smoke del device.
                      StarScore(score: avg, size: 11, showNumber: false),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                            '${StarScore.formatScore(avg)}/10 ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ),
                    ]),
                  ],
                  const Spacer(),
                  catalogPriceLine(cs, item, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

3. En `lib/features/client/catalog_screen.dart`, sustituir el bloque de la rejilla (desde el comentario `// Rejilla de tienda a 2 columnas…` hasta el `);` que cierra `GridView.builder`, líneas 298-321) por:

```dart
                  // Rejilla de tienda a 2 columnas (mockup aprobado PO
                  // 2026-08-10). La celda mide el ancho real para que la foto
                  // sea cuadrada (PO 2026-09-05).
                  return LayoutBuilder(builder: (context, box) {
                    final cellWidth = (box.maxWidth - 32 - 11) / 2;
                    return GridView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 10,
                          bottom: 12 + navBarReservedSpace(context)),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 11,
                        mainAxisExtent:
                            catalogGridCardExtent(context, cellWidth),
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) =>
                          ProductGridCard(item: items[i]).cascadeIn(i),
                    );
                  });
```

- [ ] **Step 4: Correr los tests y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/product_list_card_test.dart test/catalog_screen_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`. Si el grupo «no desborda» falla en `fuente ×2.0`, subir `_kGridTextBlock` de 8 en 8 (104 → 112 → 120) hasta que pase y dejar el valor final anotado en su doc-comment con la medida que salió.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/shared/product_list_card.dart app/lib/features/client/catalog_screen.dart app/test/product_list_card_test.dart app/test/catalog_screen_test.dart && git commit -m "feat(catalogo): tarjeta de rejilla con foto cuadrada y linea de tienda

Sale la eyebrow de categoria y la fila envio/estado/color (PO 2026-09-05,
sustituye a la Variante A del 08-11 en la rejilla). storeLine y
catalogPriceLine compartidos; la celda mide su ancho real.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `ProductCarouselCard`

**Files:**
- Modify: `lib/features/shared/product_list_card.dart` (añadir al final)
- Test: `test/product_carousel_card_test.dart` (nuevo)

**Interfaces:**
- Consumes: `catalogImage`, `storeLine`, `catalogPriceLine` (Tarea 3).
- Produces: `ProductCarouselCard({required Map<String, dynamic> item, BusinessCardInfo? negocio, double width = 138})`. Alto por contenido (sin extent fijo); se apila en un `Row` con `crossAxisAlignment: stretch` dentro de un `IntrinsicHeight`.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/product_carousel_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

void main() {
  const negocio = (
    name: 'TecnoCentro',
    logoUrl: null,
    whatsappVerified: false,
    identityVerified: false,
    businessVerified: false,
    hasPhysicalLocation: true,
  );
  const item = {
    'id': 'p3',
    'name': 'Audífonos inalámbricos con estuche de carga',
    'category_id': 'electronica',
    'price_min': 1200,
    'avg_rating': 8.4,
    'reviews_count': 6,
  };

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [child, child],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('mide 138 de ancho y pinta nombre, tienda (sin sello) y «desde»',
      (tester) async {
    await tester.pumpWidget(
        host(const ProductCarouselCard(item: item, negocio: negocio)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(ProductCarouselCard).first);
    expect(size.width, 138);
    expect(find.textContaining('Audífonos'), findsNWidgets(2));
    expect(find.textContaining('TecnoCentro'), findsNWidgets(2));
    // En el carrusel no cabe el sello: solo el nombre.
    expect(find.textContaining('Tienda física'), findsNothing);
    expect(find.text('desde '), findsNWidgets(2));
    expect(find.textContaining('1,200'), findsNWidgets(2));
    // Sin estrellas: el carrusel es de un vistazo.
    expect(find.byType(StarScore), findsNothing);
  });

  testWidgets('con la fuente al doble no desborda', (tester) async {
    await tester.pumpWidget(host(
        const ProductCarouselCard(item: item, negocio: negocio),
        scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/product_carousel_card_test.dart
```
Esperado: `Undefined name 'ProductCarouselCard'`.

- [ ] **Step 3: Implementar**

Añadir al FINAL de `lib/features/shared/product_list_card.dart`:

```dart
/// Tarjeta de CARRUSEL de la portada del catálogo (PO 2026-09-05): 138 de
/// ancho, foto apaisada de 96, nombre a 2 líneas, de quién es (sin sello: no
/// cabe) y precio. Sin estrellas ni atributos — es de un vistazo. Alto por
/// contenido: quien la apila la mete en un `Row` con `stretch` dentro de un
/// `IntrinsicHeight`, así todas las tarjetas de la fila miden igual.
class ProductCarouselCard extends StatelessWidget {
  const ProductCarouselCard(
      {super.key, required this.item, this.negocio, this.width = 138});
  final Map<String, dynamic> item;
  final BusinessCardInfo? negocio;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return SizedBox(
      width: width,
      child: JayaloCard(
        padding: EdgeInsets.zero,
        margin: EdgeInsets.zero,
        onTap: () => GoRouter.of(context).push('/catalog/${item['id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kCardRadius)),
              child: SizedBox(height: 96, child: catalogImage(img, cs)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  ?storeLine(context, negocio, sello: false),
                  const SizedBox(height: 6),
                  catalogPriceLine(cs, item, size: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/product_carousel_card_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/shared/product_list_card.dart app/test/product_carousel_card_test.dart && git commit -m "feat(catalogo): ProductCarouselCard para la portada

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `CatalogChipStrip`

**Files:**
- Create: `lib/features/client/catalog_chip_strip.dart`
- Test: `test/catalog_chip_strip_test.dart` (nuevo)

**Interfaces:**
- Consumes: `Category` (`domain/catalog.dart`, record `({String id, String name})`), `JayaloColors.warmShadow` (`core/brand.dart`).
- Produces:
```dart
class CatalogChipStrip extends StatelessWidget {
  const CatalogChipStrip({
    super.key,
    required List<Category> categorias,
    required String? categoryId,      // chip activo; null ⇒ «Todo» activo
    required ValueChanged<String> onCategory,
    required VoidCallback onTodo,
    bool? wholesale,                  // null ⇒ sin chip (Servicio)
    ValueChanged<bool>? onWholesale,  // recibe el NUEVO valor
  });
}
```

- [ ] **Step 1: Escribir el test que falla**

Crear `test/catalog_chip_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_chip_strip.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  const cats = [
    (id: 'belleza', name: 'Belleza'),
    (id: 'electronica', name: 'Electrónica'),
  ];

  testWidgets('pinta «Todo» y las categorías; tocar una avisa con su id',
      (tester) async {
    String? tocada;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      onCategory: (id) => tocada = id,
      onTodo: () {},
    )));
    expect(find.text('Todo'), findsOneWidget);
    expect(find.text('Belleza'), findsOneWidget);
    expect(find.text('Electrónica'), findsOneWidget);

    await tester.tap(find.text('Electrónica'));
    expect(tocada, 'electronica');
  });

  testWidgets('el chip activo lleva selected=true en semántica', (tester) async {
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: 'belleza',
      onCategory: (_) {},
      onTodo: () {},
    )));
    final belleza = tester.getSemantics(find.text('Belleza'));
    expect(belleza.hasFlag(SemanticsFlag.isSelected), isTrue);
    final todo = tester.getSemantics(find.text('Todo'));
    expect(todo.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('tocar «Todo» llama onTodo', (tester) async {
    var llamado = false;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: 'belleza',
      onCategory: (_) {},
      onTodo: () => llamado = true,
    )));
    await tester.tap(find.text('Todo'));
    expect(llamado, isTrue);
  });

  testWidgets('sin wholesale no hay chip de mayoreo (Servicio)', (tester) async {
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.text('Al por mayor'), findsNothing);
  });

  testWidgets('con wholesale el chip alterna y avisa con el nuevo valor',
      (tester) async {
    bool? nuevo;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      wholesale: false,
      onWholesale: (v) => nuevo = v,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.text('Al por mayor'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    await tester.tap(find.text('Al por mayor'));
    expect(nuevo, isTrue);

    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      wholesale: true,
      onWholesale: (v) => nuevo = v,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    await tester.tap(find.text('Al por mayor'));
    expect(nuevo, isFalse);
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_chip_strip_test.dart
```
Esperado: `Target of URI doesn't exist: 'package:jayalo_app/features/client/catalog_chip_strip.dart'`.

- [ ] **Step 3: Implementar**

Crear `lib/features/client/catalog_chip_strip.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/catalog.dart';

/// Tira de chips del catálogo (PO 2026-09-05, camino 3): «Al por mayor» como
/// toggle discreto al inicio (solo Producto), un separador, «Todo» y un chip
/// por categoría navegable. Pura: recibe las listas y avisa por callbacks —
/// quién filtra y qué cuerpo se pinta lo decide `CatalogView`.
///
/// Un solo chip activo a la vez. Tocar el activo NO lo apaga: para volver a
/// la portada se toca «Todo» (regla de la spec §2.2).
class CatalogChipStrip extends StatelessWidget {
  const CatalogChipStrip({
    super.key,
    required this.categorias,
    required this.categoryId,
    required this.onCategory,
    required this.onTodo,
    this.wholesale,
    this.onWholesale,
  });

  final List<Category> categorias;

  /// Categoría activa; `null` ⇒ «Todo» activo.
  final String? categoryId;
  final ValueChanged<String> onCategory;
  final VoidCallback onTodo;

  /// Estado del chip de mayoreo; `null` ⇒ el chip no existe (Servicio).
  final bool? wholesale;

  /// Recibe el NUEVO valor (ya alternado).
  final ValueChanged<bool>? onWholesale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mayoreo = wholesale;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(children: [
        if (mayoreo != null) ...[
          _Chip(
            label: 'Al por mayor',
            active: mayoreo,
            leading: mayoreo
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            onTap: () => onWholesale?.call(!mayoreo),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: cs.outlineVariant),
          const SizedBox(width: 8),
        ],
        _Chip(label: 'Todo', active: categoryId == null, onTap: onTodo),
        for (final c in categorias) ...[
          const SizedBox(width: 8),
          _Chip(
            label: c.name,
            active: categoryId == c.id,
            onTap: () => onCategory(c.id),
          ),
        ],
      ]),
    );
  }
}

/// Píldora: blanca con sombra cálida en reposo, lila de acento (`accent` /
/// `accentFg`, los mismos de la navbar) cuando está activa. Pesos 500-600,
/// fuente 11,5: los filtros son discretos, las tarjetas mandan (doctrina).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.leading,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active ? cs.primaryContainer : cs.surface;
    final fg = active ? cs.onPrimaryContainer : cs.onSurface;
    // MergeSemantics: un solo nodo (botón + etiqueta + seleccionado) para el
    // lector de pantalla, en vez de InkWell y Text por separado.
    return MergeSemantics(
      child: Semantics(
      selected: active,
      child: Material(
        color: bg,
        elevation: active ? 0 : 2,
        shadowColor: JayaloColors.warmShadow,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[
                Icon(leading, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: fg)),
            ]),
          ),
        ),
      ),
      ),
    );
  }
}
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_chip_strip_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`. Con `MergeSemantics`, `tester.getSemantics(find.text('Belleza'))` devuelve el nodo fusionado del chip (botón + etiqueta + `isSelected`). Si aun así el flag no aparece, envolver el `find.text` en `find.ancestor(of: find.text('Belleza'), matching: find.byType(MergeSemantics))` y volver a correr.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/client/catalog_chip_strip.dart app/test/catalog_chip_strip_test.dart && git commit -m "feat(catalogo): tira de chips de categoria con Al por mayor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Helpers puros de la portada

**Files:**
- Create: `lib/features/client/catalog_portada_secciones.dart`
- Test: `test/catalog_portada_secciones_test.dart` (nuevo)

**Interfaces:**
- Consumes: `kCategories`, `categoryNameById`, `categoriasNavegables` (`domain/catalog.dart`); `BusinessCardInfo` (`data/repos.dart`).
- Produces (todo top-level y puro):
```dart
const int kPortadaRecientes = 8;
const int kPortadaTiendas = 12;
const int kPortadaCategorias = 6;
const int kPortadaCarruseles = 3;
const int kPortadaItemsPorCarrusel = 8;

typedef CategoriaConteo = ({Category categoria, int n});
typedef CarruselCategoria = ({Category categoria, List<Map<String, dynamic>> items});

List<String> portadaTiendas(List<Map<String, dynamic>> items, Map<String, BusinessCardInfo> negocios);
List<CategoriaConteo> portadaCategorias(Map<String, int>? counts);
List<CarruselCategoria> portadaCarruseles(List<Map<String, dynamic>> items);
String articulosLabel(int n);
```

- [ ] **Step 1: Escribir el test que falla**

Crear `test/catalog_portada_secciones_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_portada_secciones.dart';

BusinessCardInfo biz(String name) => (
      name: name,
      logoUrl: null,
      whatsappVerified: false,
      identityVerified: false,
      businessVerified: false,
      hasPhysicalLocation: false,
    );

Map<String, dynamic> item(String id, {String? biz, String? cat}) => {
      'id': id,
      'name': 'Art $id',
      'business_id': biz,
      'category_id': cat,
    };

void main() {
  group('portadaTiendas', () {
    test('negocios distintos, en orden de aparición, solo los resueltos', () {
      final items = [
        item('1', biz: 'b1'),
        item('2', biz: 'b2'),
        item('3', biz: 'b1'),
        item('4', biz: 'b9'), // no resuelto
        item('5', biz: null),
      ];
      final negocios = {'b1': biz('Uno'), 'b2': biz('Dos')};
      expect(portadaTiendas(items, negocios), ['b1', 'b2']);
    });

    test('tope de 12', () {
      final items = [for (var i = 0; i < 20; i++) item('$i', biz: 'b$i')];
      final negocios = {for (var i = 0; i < 20; i++) 'b$i': biz('N$i')};
      expect(portadaTiendas(items, negocios).length, kPortadaTiendas);
    });
  });

  group('portadaCategorias', () {
    test('null ⇒ vacío (la sección se oculta)', () {
      expect(portadaCategorias(null), isEmpty);
    });

    test('ordena por n desc, ignora ids desconocidos y ceros, tope 6', () {
      final out = portadaCategorias({
        'belleza': 2,
        'electronica': 5,
        'hogar': 0,
        'inventada': 9,
        'autos': 1,
        'ropa': 3,
        'eventos': 3,
        'salud': 4,
        'pintura': 7,
      });
      expect(out.length, kPortadaCategorias);
      expect(out.first.categoria.id, 'pintura');
      expect(out.first.n, 7);
      expect(out.map((e) => e.categoria.id), isNot(contains('hogar')));
      expect(out.map((e) => e.categoria.id), isNot(contains('inventada')));
      // Empate 3-3 (ropa, eventos): gana la que va antes en kCategories (ropa).
      final ids = out.map((e) => e.categoria.id).toList();
      expect(ids.indexOf('ropa'), lessThan(ids.indexOf('eventos')));
    });
  });

  group('portadaCarruseles', () {
    test('solo categorías con ≥2 ítems, por tamaño desc, empate por aparición',
        () {
      final items = [
        item('1', cat: 'hogar'),
        item('2', cat: 'belleza'),
        item('3', cat: 'belleza'),
        item('4', cat: 'hogar'),
        item('5', cat: 'autos'), // solo uno: fuera
        item('6', cat: 'electronica'),
        item('7', cat: 'electronica'),
        item('8', cat: 'electronica'),
        item('9', cat: null),
      ];
      final out = portadaCarruseles(items);
      expect(out.map((c) => c.categoria.id), ['electronica', 'hogar', 'belleza']);
      expect(out.first.categoria.name, 'Electrónica');
      expect(out[1].items.map((i) => i['id']), ['1', '4']);
    });

    test('tope de 3 carruseles y 8 ítems por carrusel', () {
      final items = [
        for (final c in ['hogar', 'belleza', 'autos', 'ropa'])
          for (var i = 0; i < 10; i++) item('$c$i', cat: c),
      ];
      final out = portadaCarruseles(items);
      expect(out.length, kPortadaCarruseles);
      expect(out.first.items.length, kPortadaItemsPorCarrusel);
    });
  });

  test('articulosLabel pluraliza', () {
    expect(articulosLabel(1), '1 artículo');
    expect(articulosLabel(2), '2 artículos');
    expect(articulosLabel(0), '0 artículos');
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_portada_secciones_test.dart
```
Esperado: `Target of URI doesn't exist`.

- [ ] **Step 3: Implementar**

Crear `lib/features/client/catalog_portada_secciones.dart`:

```dart
/// Lógica PURA de la portada del catálogo (PO 2026-09-05, camino 3): qué
/// tiendas, qué categorías y qué carruseles salen de los 60 ítems ya cargados
/// y de los conteos de `get_product_counts`. Sin widgets ni red, para
/// probarse con `test()` a secas. Los topes son los de la spec §2.4.
library;

import '../../data/repos.dart' show BusinessCardInfo;
import '../../domain/catalog.dart';

const int kPortadaRecientes = 8;
const int kPortadaTiendas = 12;
const int kPortadaCategorias = 6;
const int kPortadaCarruseles = 3;
const int kPortadaItemsPorCarrusel = 8;

typedef CategoriaConteo = ({Category categoria, int n});
typedef CarruselCategoria = ({
  Category categoria,
  List<Map<String, dynamic>> items
});

/// Ids de negocio DISTINTOS de los ítems, en orden de aparición, solo los que
/// resolvieron en [negocios] (un negocio borrado o una consulta caída no
/// producen un círculo vacío). Tope [kPortadaTiendas].
List<String> portadaTiendas(
  List<Map<String, dynamic>> items,
  Map<String, BusinessCardInfo> negocios,
) {
  final out = <String>[];
  for (final it in items) {
    final id = it['business_id'];
    if (id is String && negocios.containsKey(id) && !out.contains(id)) {
      out.add(id);
      if (out.length == kPortadaTiendas) break;
    }
  }
  return out;
}

/// Categorías navegables con su conteo, ordenadas por conteo desc; a igual
/// conteo gana la que va antes en `kCategories` (orden estable a mano:
/// `List.sort` no garantiza estabilidad). Ids que no existen en `kCategories`
/// y conteos en cero se ignoran. `null` ⇒ vacío (la sección se oculta).
List<CategoriaConteo> portadaCategorias(Map<String, int>? counts) {
  if (counts == null) return const [];
  final vivas = categoriasNavegables(kCategories, counts.keys.toSet());
  final indexed = <(int, CategoriaConteo)>[
    for (var i = 0; i < vivas.length; i++)
      if ((counts[vivas[i].id] ?? 0) > 0)
        (i, (categoria: vivas[i], n: counts[vivas[i].id]!)),
  ];
  indexed.sort((a, b) {
    final byN = b.$2.n.compareTo(a.$2.n);
    return byN != 0 ? byN : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(kPortadaCategorias)) e.$2];
}

/// Un carrusel por cada una de las [kPortadaCarruseles] categorías con más
/// ítems ENTRE LOS CARGADOS (no por el conteo global: así nunca sale un
/// carrusel vacío). Una categoría necesita ≥ 2 ítems (con uno solo ya está en
/// «Recién publicados»). A igual tamaño gana la que apareció antes. Cada
/// carrusel lleva hasta [kPortadaItemsPorCarrusel] ítems en su orden original.
List<CarruselCategoria> portadaCarruseles(List<Map<String, dynamic>> items) {
  final porCat = <String, List<Map<String, dynamic>>>{};
  for (final it in items) {
    final c = it['category_id'];
    if (c is String) (porCat[c] ??= []).add(it);
  }
  final candidatas = <(int, String, List<Map<String, dynamic>>)>[];
  var orden = 0;
  for (final e in porCat.entries) {
    if (e.value.length >= 2 && categoryNameById(e.key) != null) {
      candidatas.add((orden, e.key, e.value));
    }
    orden++;
  }
  candidatas.sort((a, b) {
    final bySize = b.$3.length.compareTo(a.$3.length);
    return bySize != 0 ? bySize : a.$1.compareTo(b.$1);
  });
  return [
    for (final c in candidatas.take(kPortadaCarruseles))
      (
        categoria: (id: c.$2, name: categoryNameById(c.$2)!),
        items: c.$3.take(kPortadaItemsPorCarrusel).toList(),
      ),
  ];
}

/// «1 artículo» / «n artículos».
String articulosLabel(int n) => n == 1 ? '1 artículo' : '$n artículos';
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_portada_secciones_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/client/catalog_portada_secciones.dart app/test/catalog_portada_secciones_test.dart && git commit -m "feat(catalogo): helpers puros de la portada (tiendas, categorias, carruseles)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: `CatalogPortada` (widgets)

**Files:**
- Create: `lib/features/client/catalog_portada.dart`
- Test: `test/catalog_portada_test.dart` (nuevo)

**Interfaces:**
- Consumes: Tarea 6 (helpers), Tarea 4 (`ProductCarouselCard`), `JayaloCard`, `JayaloNetworkImage`, `navBarReservedSpace` (`shell/floating_nav_bar.dart`), `jayaloHead`.
- Produces:
```dart
class CatalogPortada extends StatelessWidget {
  const CatalogPortada({
    super.key,
    required List<Map<String, dynamic>> items,
    required Map<String, BusinessCardInfo> negocios,
    required Map<String, int>? counts,
    required VoidCallback onVerTodo,           // «Ver todo» de Recién publicados
    required ValueChanged<String> onCategory,  // tile o «Ver todo» de un carrusel → id
    required ValueChanged<String> onStore,     // círculo de tienda → business_id
    Widget? header,                            // la tira de chips, se desplaza con la lista
    ScrollController? controller,
  });
}
```
Los productos de los carruseles navegan solos (`ProductCarouselCard` hace `push('/catalog/:id')`).

- [ ] **Step 1: Escribir el test que falla**

Crear `test/catalog_portada_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_portada.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';

BusinessCardInfo biz(String name, {bool local = false}) => (
      name: name,
      logoUrl: null,
      whatsappVerified: false,
      identityVerified: false,
      businessVerified: false,
      hasPhysicalLocation: local,
    );

Map<String, dynamic> item(String id, {String? biz, String? cat}) => {
      'id': id,
      'name': 'Artículo $id',
      'business_id': biz,
      'category_id': cat,
      'price': 100,
    };

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  /// Viewport ALTO: la portada es un `ListView` perezoso y con 800×600 el
  /// carrusel por categoría (el último) no llega a construirse — un
  /// `findsNothing` pasaría en falso (gotcha 2026-09-04). Llamar al inicio
  /// de CADA test.
  void alto(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
  }

  final items = [
    item('1', biz: 'b1', cat: 'belleza'),
    item('2', biz: 'b2', cat: 'belleza'),
    item('3', biz: 'b1', cat: 'hogar'),
  ];
  final negocios = {'b1': biz('Barbería El Conde', local: true), 'b2': biz('Glam')};
  final counts = {'belleza': 2, 'hogar': 1};

  testWidgets('pinta las cuatro secciones y el header arriba', (tester) async {
    alto(tester);
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: negocios,
      counts: counts,
      onVerTodo: () {},
      onCategory: (_) {},
      onStore: (_) {},
      header: const Text('CHIPS'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('CHIPS'), findsOneWidget);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.text('Tiendas'), findsOneWidget);
    expect(find.text('Por categoría'), findsOneWidget);
    // Carrusel de la categoría con ≥2 ítems; hogar (1) no tiene carrusel.
    expect(find.text('Belleza'), findsWidgets); // tile + título de carrusel
    // Tiles con conteo.
    expect(find.text('2 artículos'), findsOneWidget);
    expect(find.text('1 artículo'), findsOneWidget);
    // Tiendas distintas (el nombre sale también en la línea de tienda de las
    // tarjetas, por eso `findsWidgets`; el círculo se comprueba por su inicial
    // en el último test).
    expect(find.text('Barbería El Conde'), findsWidgets);
    expect(find.text('Glam'), findsWidgets);
    // Recién publicados (3) + carrusel belleza (2) = 5 tarjetas de carrusel.
    expect(find.byType(ProductCarouselCard), findsNWidgets(5));
  });

  testWidgets('«Ver todo» de Recién publicados llama onVerTodo', (tester) async {
    alto(tester);
    var llamado = false;
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: negocios,
      counts: counts,
      onVerTodo: () => llamado = true,
      onCategory: (_) {},
      onStore: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    expect(llamado, isTrue);
  });

  testWidgets('tocar un tile o el «Ver todo» de un carrusel avisa con el id',
      (tester) async {
    alto(tester);
    final ids = <String>[];
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: negocios,
      counts: counts,
      onVerTodo: () {},
      onCategory: ids.add,
      onStore: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 artículo')); // tile de Hogar
    await tester.tap(find.text('Ver todo').last); // carrusel de Belleza
    expect(ids, ['hogar', 'belleza']);
  });

  testWidgets('tocar una tienda avisa con su business_id', (tester) async {
    alto(tester);
    String? tocada;
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: negocios,
      counts: counts,
      onVerTodo: () {},
      onCategory: (_) {},
      onStore: (id) => tocada = id,
    )));
    await tester.pumpAndSettle();
    // Se toca la INICIAL del círculo («G» de Glam): es única; el nombre
    // «Glam» sale además en las tarjetas.
    await tester.tap(find.text('G'));
    expect(tocada, 'b2');
  });

  testWidgets('con un solo ítem: Recién publicados sí, carruseles no',
      (tester) async {
    alto(tester);
    await tester.pumpWidget(host(CatalogPortada(
      items: [items.first],
      negocios: negocios,
      counts: counts,
      onVerTodo: () {},
      onCategory: (_) {},
      onStore: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.byType(ProductCarouselCard), findsOneWidget);
  });

  testWidgets('sin conteos no hay «Por categoría»; sin negocios no hay «Tiendas»',
      (tester) async {
    alto(tester);
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: const {},
      counts: null,
      onVerTodo: () {},
      onCategory: (_) {},
      onStore: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Por categoría'), findsNothing);
    expect(find.text('Tiendas'), findsNothing);
    expect(find.text('Recién publicados'), findsOneWidget);
  });

  testWidgets('sin logo el círculo lleva la inicial del negocio', (tester) async {
    alto(tester);
    await tester.pumpWidget(host(CatalogPortada(
      items: items,
      negocios: negocios,
      counts: counts,
      onVerTodo: () {},
      onCategory: (_) {},
      onStore: (_) {},
    )));
    await tester.pumpAndSettle();
    // «B»: el círculo de Barbería Y la pastilla del tile «Belleza».
    expect(find.text('B'), findsNWidgets(2));
    expect(find.text('G'), findsOneWidget); // solo el círculo de Glam
    expect(find.text('H'), findsOneWidget); // solo la pastilla del tile Hogar
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_portada_test.dart
```
Esperado: `Target of URI doesn't exist`.

- [ ] **Step 3: Implementar**

Crear `lib/features/client/catalog_portada.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show BusinessCardInfo;
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/product_list_card.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_portada_secciones.dart';

/// Portada del catálogo (PO 2026-09-05, camino 3): secciones apiladas sobre
/// los 60 ítems ya cargados — «Recién publicados», «Tiendas», «Por categoría»
/// y hasta tres carruseles por categoría. Pura: recibe datos y callbacks; no
/// pide nada a la red. Se pinta solo cuando NO hay filtro activo (la regla
/// vive en `CatalogView`). [header] es la tira de chips: va dentro de la
/// lista para desplazarse con ella.
class CatalogPortada extends StatelessWidget {
  const CatalogPortada({
    super.key,
    required this.items,
    required this.negocios,
    required this.counts,
    required this.onVerTodo,
    required this.onCategory,
    required this.onStore,
    this.header,
    this.controller,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;
  final Map<String, int>? counts;
  final VoidCallback onVerTodo;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onStore;
  final Widget? header;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final tiendas = portadaTiendas(items, negocios);
    final categorias = portadaCategorias(counts);
    final carruseles = portadaCarruseles(items);
    var i = 0;
    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
      children: [
        ?header,
        if (items.isNotEmpty) ...[
          SeccionTitulo('Recién publicados', onMore: onVerTodo)
              .cascadeIn(i++),
          _Carrusel(
            items: items.take(kPortadaRecientes).toList(),
            negocios: negocios,
          ).cascadeIn(i++),
        ],
        if (tiendas.isNotEmpty) ...[
          const SeccionTitulo('Tiendas').cascadeIn(i++),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final id in tiendas) ...[
                _StoreCircle(negocio: negocios[id]!, onTap: () => onStore(id)),
                const SizedBox(width: 14),
              ],
            ]),
          ).cascadeIn(i++),
        ],
        if (categorias.isNotEmpty) ...[
          const SeccionTitulo('Por categoría').cascadeIn(i++),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 56,
              ),
              itemCount: categorias.length,
              itemBuilder: (_, k) => CategoryTile(
                conteo: categorias[k],
                onTap: () => onCategory(categorias[k].categoria.id),
              ),
            ),
          ).cascadeIn(i++),
        ],
        for (final c in carruseles) ...[
          SeccionTitulo(c.categoria.name,
                  onMore: () => onCategory(c.categoria.id))
              .cascadeIn(i++),
          _Carrusel(items: c.items, negocios: negocios).cascadeIn(i++),
        ],
      ],
    );
  }
}

/// Cabecera de sección: título 14 w600 en tinta de título y, si hay [onMore],
/// «Ver todo» en violeta a la derecha.
class SeccionTitulo extends StatelessWidget {
  const SeccionTitulo(this.titulo, {super.key, this.onMore});
  final String titulo;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(children: [
        Expanded(
          child: Text(titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
        ),
        if (onMore != null)
          InkWell(
            onTap: onMore,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('Ver todo',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
            ),
          ),
      ]),
    );
  }
}

/// Fila horizontal de [ProductCarouselCard]. `IntrinsicHeight` + `stretch`:
/// todas las tarjetas de la fila miden lo que mida la más alta, sin extent
/// fijo (crece con la fuente del sistema).
class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.items, required this.negocios});
  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final it in items) ...[
                ProductCarouselCard(
                    item: it, negocio: negocios[it['business_id']]),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      );
}

/// Círculo de tienda: logo `cover` o la inicial sobre lila, y el nombre a dos
/// líneas debajo. Tocar abre la tienda del proveedor (lo decide el caller).
class _StoreCircle extends StatelessWidget {
  const _StoreCircle({required this.negocio, required this.onTap});
  final BusinessCardInfo negocio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inicial =
        negocio.name.trim().isEmpty ? '?' : negocio.name.trim()[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
              boxShadow: const [
                BoxShadow(
                    color: JayaloColors.warmShadow,
                    blurRadius: 14,
                    offset: Offset(0, 6)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: negocio.logoUrl == null
                ? Text(inicial,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer))
                : JayaloNetworkImage(negocio.logoUrl!,
                    width: 54, height: 54, fit: BoxFit.cover),
          ),
          const SizedBox(height: 5),
          Text(negocio.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface)),
        ]),
      ),
    );
  }
}

/// Tile de «Por categoría»: pastilla lila con la inicial, nombre y «n
/// artículos». `kCategories` no trae icono (es un mock portado de la web),
/// por eso la inicial.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.conteo, required this.onTap});
  final CategoriaConteo conteo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = conteo.categoria.name;
    return JayaloCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10)),
          child: Text(name[0].toUpperCase(),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
              Text(articulosLabel(conteo.n),
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Correr el test y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_portada_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`. Si el test de las cinco tarjetas falla por `cascadeIn` (la animación deja la opacidad en 0 pero el widget existe: `find.byType` cuenta igual), revisar que `pumpAndSettle` terminó; si el tile de 56 px desborda con la fuente del test, subir `mainAxisExtent` a 60.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/client/catalog_portada.dart app/test/catalog_portada_test.dart && git commit -m "feat(catalogo): CatalogPortada con recientes, tiendas, categorias y carruseles

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Cablear `CatalogView`: cabecera, chips, dos cuerpos

**Files:**
- Create: `lib/features/client/catalog_header_widgets.dart` (mover `_HeaderSearchField` → `CatalogSearchField` y `_FilterPill` → `CatalogFilterPill`, SIN cambios de comportamiento)
- Modify: `lib/features/client/catalog_screen.dart` (todo el archivo salvo `CatalogScreen`)
- Test: `test/catalog_screen_test.dart`

**Interfaces:**
- Consumes: Tareas 1–7. `businessesCardInfo(List<String>)` y `categoryCountsForKind(String)` de `data/repos.dart`. `HeaderLeading`, `HeaderSegmented(compact: true)`, `CollapsibleHeader`, `VioletHeader`.
- Produces:
```dart
typedef CatalogBusinessesFetch = Future<Map<String, BusinessCardInfo>> Function(List<String> businessIds);
typedef CatalogCountsFetch = Future<Map<String, int>?> Function(String kind);
typedef CatalogPage = ({List<Map<String, dynamic>> items, Map<String, BusinessCardInfo> negocios});

class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required CatalogFetch fetch,
    CatalogBusinessesFetch businesses = businessesCardInfo,
    CatalogCountsFetch counts = categoryCountsForKind,
    List<Widget> actions = const [HeaderBell()],
    bool autofocusSearch = false,
  });
}
```
`CatalogScreen` no cambia de firma.

- [ ] **Step 1: Adaptar y ampliar `test/catalog_screen_test.dart`**

1. Añadir imports:
```dart
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/catalog_portada.dart';
```

2. Debajo de `Future<List<Map<String, dynamic>>> vacio(...)` añadir los dobles de las dos consultas nuevas y un `host` de catálogo que las inyecta (para que los tests viejos no toquen la red):

```dart
  Future<Map<String, BusinessCardInfo>> sinNegocios(List<String> ids) async =>
      const {};
  Future<Map<String, int>?> sinConteos(String kind) async => null;

  /// `CatalogView` con las consultas de negocios y conteos dobladas: los
  /// tests que solo miran productos no deben tocar la red.
  Widget catalogo({
    required CatalogFetch fetch,
    CatalogBusinessesFetch businesses = sinNegocios,
    CatalogCountsFetch counts = sinConteos,
  }) =>
      host(CatalogView(
        fetch: fetch,
        businesses: businesses,
        counts: counts,
        actions: const [],
      ));
```
Y añadir el import de los typedefs (ya están en `catalog_screen.dart`, que el test importa).

3. Reemplazar TODAS las apariciones de `host(CatalogView(fetch: X, actions: const []))` y de
```dart
host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async => …,
      actions: const [],
    ))
```
por `catalogo(fetch: X)` / `catalogo(fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async => …)`. En el test «apilada (canPop)» el `CatalogView(fetch: vacio, actions: const [])` dentro del `MaterialPageRoute` pasa a `CatalogView(fetch: vacio, businesses: sinNegocios, counts: sinConteos, actions: const [])`.

4. Los tests `'la tarjeta muestra nombre y precio fijo'`, `'…rango de precio…'`, `'la tarjeta muestra la reputación…'`, `'la rejilla ya no pinta envío/estado/color…'` y `'la lista no desborda…'` miran la REJILLA, pero ahora con un solo ítem y sin filtro se pinta la PORTADA (donde el nombre también sale, en el carrusel). Para que sigan probando la rejilla, en cada uno de esos cinco tests insertar, justo después del primer `await tester.pumpAndSettle();`:
```dart
    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();
```
(`'la tarjeta muestra la reputación'` busca `find.byType(StarScore)`: solo la rejilla pinta estrellas, así que este paso es obligatorio ahí.)

5. Sustituir el test `'el toggle Al por mayor filtra el catálogo'` por:
```dart
  testWidgets('el chip Al por mayor filtra el catálogo y pasa a la rejilla',
      (tester) async {
    final wholesaleSeen = <bool>[];
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        wholesaleSeen.add(wholesale);
        return [fixedItem];
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);

    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();

    expect(wholesaleSeen.last, isTrue);
    expect(find.byType(CatalogPortada), findsNothing);
    expect(find.byType(SliverGrid), findsOneWidget);
  });
```

6. En el test `'en Servicio se oculta el toggle de mayoreo…'` quitar la línea `expect(find.text('Al detalle'), findsNothing);` (ese segmentado ya no existe en ningún kind) y cambiar `host(CatalogView(...))` por `catalogo(...)`.

7. Sustituir `'cambiar de kind limpia categoría y rubro'` por:
```dart
  testWidgets('cambiar de kind limpia categoría, rubro, mayoreo y Ver todo',
      (tester) async {
    final seen = <Map<String, dynamic>>[];
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        seen.add({'kind': kind, 'categoryId': categoryId, 'wholesale': wholesale});
        return [fixedItem];
      },
      counts: (_) async => {'ferreteria': 1},
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferretería').first); // el chip, no el tile
    await tester.pumpAndSettle();
    expect(seen.last['categoryId'], 'ferreteria');

    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(seen.last['kind'], 'servicio');
    expect(seen.last['categoryId'], isNull);
    expect(seen.last['wholesale'], isFalse);
    expect(find.byType(CatalogPortada), findsOneWidget);
  });
```

8. Añadir estos tests nuevos al final de `main`:

```dart
  testWidgets('sin filtro se ve la portada y no la rejilla', (tester) async {
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [fixedItem, rangeItem],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
  });

  testWidgets('tocar un chip de categoría filtra y pasa a la rejilla; «Todo» vuelve',
      (tester) async {
    final cats = <String?>[];
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        cats.add(categoryId);
        return [fixedItem];
      },
      counts: (_) async => {'ferreteria': 1, 'hogar': 2},
    ));
    await tester.pumpAndSettle();
    // El chip Y el tile de «Por categoría» dicen «Ferretería»; el chip va
    // primero en el árbol (cabecera de la lista).
    expect(find.text('Ferretería'), findsWidgets);

    await tester.tap(find.text('Ferretería').first);
    await tester.pumpAndSettle();
    expect(cats.last, 'ferreteria');
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.byType(CatalogPortada), findsNothing);

    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(cats.last, isNull);
    expect(find.byType(CatalogPortada), findsOneWidget);
  });

  testWidgets('«Ver todo» enseña la rejilla sin re-pedir ni filtrar; «Todo» vuelve',
      (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        llamadas++;
        expect(categoryId, isNull);
        expect(wholesale, isFalse);
        return [fixedItem];
      },
    ));
    await tester.pumpAndSettle();
    expect(llamadas, 1);

    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(llamadas, 1); // misma carga, otro cuerpo

    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);
    expect(llamadas, 1);
  });

  testWidgets('la rejilla pinta la tienda del negocio resuelto', (tester) async {
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [fixedItem],
      businesses: (ids) async => {
        'b1': (
          name: 'Ferretería Don Pepe',
          logoUrl: null,
          whatsappVerified: false,
          identityVerified: false,
          businessVerified: false,
          hasPhysicalLocation: true,
        ),
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ferretería Don Pepe'), findsOneWidget);
    expect(find.textContaining('Tienda física'), findsOneWidget);
  });

  testWidgets('si la consulta de negocios falla, el catálogo se pinta igual',
      (tester) async {
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async =>
          [fixedItem],
      businesses: (ids) async {
        await Future<void>.delayed(Duration.zero);
        throw Exception('caído');
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('Recién publicados'), findsOneWidget);
    expect(find.text('Tiendas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Quitar filtro» del estado vacío limpia todo y vuelve a la portada',
      (tester) async {
    var vez = 0;
    await tester.pumpWidget(catalogo(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        vez++;
        // Primera carga: hay artículos. Con filtro: nada.
        return wholesale ? [] : [fixedItem];
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay artículos que coincidan'), findsOneWidget);

    await tester.tap(find.text('Quitar filtro'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPortada), findsOneWidget);
    expect(vez, 3);
  });

  testWidgets('la cabecera lleva el título a la izquierda y el segmentado compacto',
      (tester) async {
    await tester.pumpWidget(catalogo(fetch: vacio));
    await tester.pumpAndSettle();
    final header = tester.widget<VioletHeader>(find.byType(VioletHeader));
    expect(header.title, 'Catálogo');
    expect(header.titleAlign, HeaderTitleAlign.start);
    final seg = tester.widget<HeaderSegmented>(kindSegmented());
    expect(seg.compact, isTrue);
    expect(find.text('Al detalle'), findsNothing);
  });
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_screen_test.dart
```
Esperado: errores de compilación (`businesses`/`counts` desconocidos, `CatalogBusinessesFetch` no definido).

- [ ] **Step 3: Mover el buscador y la píldora a su archivo**

Crear `lib/features/client/catalog_header_widgets.dart` con el contenido EXACTO de las clases `_HeaderSearchField` (líneas 327-386 de `catalog_screen.dart`) y `_FilterPill` (líneas 388-440), renombradas a `CatalogSearchField` y `CatalogFilterPill`, precedidas de:

```dart
import 'package:flutter/material.dart';
```

y con sus doc-comments actuales. (Renombrar también los constructores; no cambiar ni un parámetro.) Borrar ambas clases de `catalog_screen.dart`.

- [ ] **Step 4: Reescribir `CatalogView` en `catalog_screen.dart`**

Sustituir TODO el archivo `lib/features/client/catalog_screen.dart` por:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_chip_strip.dart';
import 'catalog_filter_sheet.dart';
import 'catalog_header_widgets.dart';
import 'catalog_portada.dart';

/// Signature de la fuente de datos del catálogo (paridad `productHitsQ` de la
/// web). Inyectada en [CatalogView] para poder probar la pantalla sin red —
/// mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale});

/// Cabecera de los negocios dueños de los ítems, por lote (nombre, logo, local).
/// Best-effort: si falla, la pantalla se pinta sin tienda.
typedef CatalogBusinessesFetch = Future<Map<String, BusinessCardInfo>> Function(
    List<String> businessIds);

/// Conteo de artículos por categoría del kind (RPC `get_product_counts`).
/// `null` = no llegó: chips completos y sin sección «Por categoría».
typedef CatalogCountsFetch = Future<Map<String, int>?> Function(String kind);

/// Una carga del catálogo: los ítems y la cabecera de sus negocios.
typedef CatalogPage = ({
  List<Map<String, dynamic>> items,
  Map<String, BusinessCardInfo> negocios
});

/// Pestaña Catálogo. `?focus=1` (desde el buscador de Mis solicitudes) abre
/// con el buscador enfocado.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, this.autofocusSearch = false});
  final bool autofocusSearch;

  @override
  Widget build(BuildContext context) => CatalogView(
      fetch: catalogProductsWithRatings, autofocusSearch: autofocusSearch);
}

/// Cabecera + tira de chips + UN cuerpo de dos posibles (PO 2026-09-05,
/// camino 3): la PORTADA por secciones cuando no hay filtro, la REJILLA de dos
/// columnas cuando lo hay (categoría, mayoreo, búsqueda o «Ver todo»).
/// StatefulWidget con su propio [ScrollController] (nunca
/// `homeScrollController`: el `AnimatedSwitcher` del shell y `BackGuard`
/// revientan si dos pantallas comparten un único controller).
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.fetch,
    this.businesses = businessesCardInfo,
    this.counts = categoryCountsForKind,
    this.actions = const [HeaderBell()],
    this.autofocusSearch = false,
  });

  final CatalogFetch fetch;
  final CatalogBusinessesFetch businesses;
  final CatalogCountsFetch counts;
  final List<Widget> actions;
  final bool autofocusSearch;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String _kind = 'producto';
  String? _search;
  String? _categoryId;
  String? _rubro;
  bool _wholesale = false;

  /// «Ver todo» de Recién publicados: la rejilla SIN filtro. Se apaga al tocar
  /// «Todo» o al cambiar de kind. No re-pide nada: misma carga, otro cuerpo.
  bool _verTodo = false;

  /// Conteos por categoría del kind activo; `null` mientras llegan o si la
  /// RPC falló. Se piden una vez por kind.
  Map<String, int>? _counts;

  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  /// Header plegado al navegar (pedido PO: TODO el header se esconde y queda
  /// la flecha — mismo gesto que Tus solicitudes).
  bool _headerHidden = false;

  /// Regla de la spec §2.3: con cualquier filtro se pinta la rejilla.
  bool get _filtrado =>
      _categoryId != null || _wholesale || _search != null || _verTodo;

  /// Esconde/muestra el header COMPLETO según la DIRECCIÓN del gesto (calco de
  /// `my_requests_screen`). Solo `UserScrollNotification` — ignora el relayout
  /// del propio colapso, que antes reabría el header solo (bug 2026-07-21).
  bool _onListScroll(ScrollNotification n) {
    if (n is! UserScrollNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && !_headerHidden) {
      setState(() => _headerHidden = true);
    } else if (n.direction == ScrollDirection.forward && _headerHidden) {
      setState(() => _headerHidden = false);
    }
    return false;
  }

  late Future<CatalogPage> _load = _fetchPage();

  /// Productos (+ valoraciones, ya horneadas por `fetch`) y, en una segunda
  /// llamada por lote, la cabecera de sus negocios. La segunda es un adorno:
  /// si falla, se sigue sin tienda — NUNCA se tira la pantalla a error.
  Future<CatalogPage> _fetchPage() async {
    final items = await widget.fetch(
        kind: _kind,
        search: _search,
        categoryId: _categoryId,
        rubro: _rubro,
        wholesale: _wholesale);
    final ids = <String>{
      for (final it in items)
        if (it['business_id'] is String) it['business_id'] as String,
    }.toList();
    final negocios = await widget
        .businesses(ids)
        .catchError((_) => <String, BusinessCardInfo>{});
    return (items: items, negocios: negocios);
  }

  void _loadCounts() {
    final kind = _kind;
    widget.counts(kind).then((c) {
      if (mounted && _kind == kind) setState(() => _counts = c);
    }, onError: (_) {});
  }

  // Bloque, no expresión: el mismo gotcha documentado en inbox_screen.dart —
  // `setState(() => _load = future)` hace que la closure DEVUELVA el Future.
  // `.ignore()`: si `next` falla ANTES del frame en que `FutureBuilder`
  // reengancha su listener, Dart lo reportaría como no manejado aunque la UI
  // sí lo muestre después vía `snapshot.hasError`.
  void _refetch() {
    final next = _fetchPage()..ignore();
    setState(() {
      _load = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  void _applySearch() {
    final term = _searchCtrl.text.trim();
    setState(() => _search = term.isEmpty ? null : term);
    _refetch();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _search = null);
    _refetch();
  }

  /// Mutador de categoría/rubro: reemplaza ambos a la vez porque un rubro
  /// siempre vive dentro de una categoría.
  void _applyFilter({String? categoryId, String? rubro}) {
    setState(() {
      _categoryId = categoryId;
      _rubro = rubro;
      _verTodo = false;
    });
    _refetch();
  }

  /// Chip «Todo»: quita categoría/rubro y apaga «Ver todo». Solo re-pide si
  /// había categoría (apagar «Ver todo» no cambia la carga).
  void _volverAPortada() {
    final habiaCategoria = _categoryId != null || _rubro != null;
    setState(() {
      _categoryId = null;
      _rubro = null;
      _verTodo = false;
    });
    if (habiaCategoria) _refetch();
  }

  /// «Quitar filtro» del estado vacío: limpia TODO y vuelve a la portada.
  void _quitarTodo() {
    _searchCtrl.clear();
    setState(() {
      _search = null;
      _categoryId = null;
      _rubro = null;
      _wholesale = false;
      _verTodo = false;
    });
    _refetch();
  }

  Future<void> _openFilter() async {
    final res = await showCatalogFilterSheet(context,
        kind: _kind, categoryId: _categoryId, rubro: _rubro);
    if (res != null) _applyFilter(categoryId: res.categoryId, rubro: res.rubro);
  }

  void _toggleWholesale(bool on) {
    setState(() => _wholesale = on);
    _refetch();
  }

  void _changeKind(int i) {
    setState(() {
      _kind = i == 0 ? 'producto' : 'servicio';
      _categoryId = null; // cambiar de kind limpia el filtro
      _rubro = null;
      _verTodo = false;
      _counts = null;
      // El mayoreo es SOLO de productos (paridad web).
      if (_kind == 'servicio') _wholesale = false;
    });
    _refetch();
    _loadCounts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _chips() => CatalogChipStrip(
        categorias: categoriasNavegables(kCategories, _counts?.keys.toSet(),
            seleccionada: _categoryId),
        categoryId: _categoryId,
        wholesale: _kind == 'producto' ? _wholesale : null,
        onWholesale: _toggleWholesale,
        onCategory: (id) => _applyFilter(categoryId: id),
        onTodo: _volverAPortada,
      );

  Widget _rejilla(CatalogPage page) => LayoutBuilder(builder: (context, box) {
        final cellWidth = (box.maxWidth - 32 - 11) / 2;
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _chips()),
            SliverPadding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: 12 + navBarReservedSpace(context)),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 11,
                  mainAxisSpacing: 11,
                  mainAxisExtent: catalogGridCardExtent(context, cellWidth),
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ProductGridCard(
                    item: page.items[i],
                    negocio: page.negocios[page.items[i]['business_id']],
                  ).cascadeIn(i),
                  childCount: page.items.length,
                ),
              ),
            ),
          ],
        );
      });

  Widget _portada(CatalogPage page) => CatalogPortada(
        controller: _scrollController,
        header: _chips(),
        items: page.items,
        negocios: page.negocios,
        counts: _counts,
        onVerTodo: () => setState(() => _verTodo = true),
        onCategory: (id) => _applyFilter(categoryId: id),
        onStore: (id) => context.push('/store/$id'),
      );

  Widget _vacio() => Column(children: [
        _chips(),
        Expanded(
          child: EmptyState(
            controller: _scrollController,
            message: _filtrado
                ? 'No hay artículos que coincidan con tu filtro.'
                : 'Aún no hay artículos publicados en esta '
                    'categoría.\n\nVuelve más tarde: los '
                    'proveedores publican todos los días.',
            ctaLabel: _filtrado ? 'Quitar filtro' : null,
            onCta: _filtrado ? _quitarTodo : null,
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) => OnboardingGuide(
        guideKey: 'client.catalog.v1',
        steps: onboardingCopy['client.catalog.v1']!,
        mode: OnboardingMode.welcome,
        child: Scaffold(
          body: Column(children: [
            // Misma anatomía que las demás pestañas: avatar (o atrás si viene
            // apilada como «Otros proveedores»), título a la izquierda,
            // segmentado compacto y campana; debajo, UNA fila con buscador y
            // Filtrar. Se pliega completo al navegar (PO 2026-07-21).
            CollapsibleHeader(
              hidden: _headerHidden,
              onReveal: () => setState(() => _headerHidden = false),
              child: VioletHeader(
                leading: const HeaderLeading(),
                title: 'Catálogo',
                actions: [
                  HeaderSegmented(
                    compact: true,
                    options: const ['Producto', 'Servicio'],
                    index: _kind == 'producto' ? 0 : 1,
                    onChanged: _changeKind,
                  ),
                  const SizedBox(width: 8),
                  ...widget.actions,
                ],
                below: Row(children: [
                  Expanded(
                    child: CatalogSearchField(
                      controller: _searchCtrl,
                      hint: 'Buscar en el catálogo',
                      autofocus: widget.autofocusSearch,
                      onSubmitted: _applySearch,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CatalogFilterPill(
                    label: _categoryId == null
                        ? 'Filtrar'
                        : (categoryNameById(_categoryId) ?? 'Filtrar'),
                    active: _categoryId != null,
                    onTap: _openFilter,
                    onClear: _categoryId != null ? _volverAPortada : null,
                  ),
                ]),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onListScroll,
                child: JayaloRefresh(
                  onRefresh: () async => _refetch(),
                  child: FutureBuilder<CatalogPage>(
                    future: _load,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const JayaloLoaderBlock();
                      }
                      if (snap.hasError) {
                        return ErrorRetry(onRetry: () async => _refetch());
                      }
                      final page = snap.data ??
                          (items: const <Map<String, dynamic>>[], negocios: const <String, BusinessCardInfo>{});
                      if (page.items.isEmpty) return _vacio();
                      return _filtrado ? _rejilla(page) : _portada(page);
                    },
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
```

- [ ] **Step 5: Correr los tests del catálogo y analyze**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test test/catalog_screen_test.dart test/catalog_onboarding_test.dart && flutter analyze
```
Esperado: `All tests passed!` y `No issues found!`.

Si `'la lista no desborda con un nombre largo…'` falla por desborde del `Row` de la cabecera a 390 px: NO tocar el segmentado; envolver el `HeaderSegmented` de `actions` en `Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: …))` y anotar el motivo en el comentario.

- [ ] **Step 6: Suite completa**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter test
```
Esperado: todo verde. Anotar el número total de tests (la línea `+N`) para el commit.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/lib/features/client/catalog_screen.dart app/lib/features/client/catalog_header_widgets.dart app/test/catalog_screen_test.dart && git commit -m "feat(catalogo): portada por secciones con chips y cabecera alineada

Una pestana, dos cuerpos: portada (recientes, tiendas, categorias,
carruseles) sin filtro; rejilla filtrada con categoria, mayoreo, busqueda
o Ver todo. Cabecera con avatar, titulo a la izquierda, segmentado compacto
y una sola fila de buscador+Filtrar. Negocios por lote (best-effort) y
conteos por kind. Buscador y pildora movidos a catalog_header_widgets.dart.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Verificación final, APK y memoria

**Files:**
- Modify: `app/pubspec.yaml` (solo `version:` build number)
- Memoria: `C:/Users/ac/.claude/projects/C--Users-ac-Downloads-jayalo-main/memory/jayalo-mockup-catalogo-dos-caminos-2026-09-05.md` y `MEMORY.md`

**Interfaces:** ninguna nueva.

- [ ] **Step 1: Gates completos**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter analyze && flutter test
```
Esperado: `No issues found!` y `All tests passed!`.

- [ ] **Step 2: Elegir el número de build**

El número de build es GLOBAL entre worktrees (gotcha 2026-09-04). Leer el índice de memoria `MEMORY.md` y `git log --all --oneline -20 | grep chore` para ver el mayor `+N` usado (a fecha de la spec: +117 en `jayalo-app-guia`). Usar el siguiente. Editar en `app/pubspec.yaml` la línea `version: 1.0.4+116` → `version: 1.0.4+<N>`.

- [ ] **Step 3: Compilar el APK release**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && flutter build apk --release --obfuscate --split-debug-info=symbols/1.0.4+<N>
```
Esperado: `√ Built build/app/outputs/flutter-apk/app-release.apk`. Comprobar el sello de build:

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo/app && "$LOCALAPPDATA/Android/Sdk/build-tools/$(ls "$LOCALAPPDATA/Android/Sdk/build-tools" | tail -1)/aapt" dump badging build/app/outputs/flutter-apk/app-release.apk | grep -o "versionCode='[0-9]*'"
```
Esperado: `versionCode='<N>'`.

**NO instalar en el teléfono**: en el device solo cabe una versión y hoy lleva un APK de otro carril pendiente de smoke. Instalarlo es decisión del PO.

- [ ] **Step 4: Commit del build**

```bash
cd C:/Users/ac/Downloads/jayalo-app-catalogo && git add app/pubspec.yaml && git commit -m "chore(app): 1.0.4+<N> — catalogo con portada por secciones

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 5: Actualizar la memoria**

Añadir al final de `jayalo-mockup-catalogo-dos-caminos-2026-09-05.md`:

```markdown
## Implementado (fecha)
Rama `feat/catalogo-portada-secciones` en `jayalo-app-catalogo`, commits <lista>, suite <N> verde,
analyze 0, APK 1.0.4+<N> en `build/app/outputs/flutter-apk/app-release.apk` **SIN instalar**
(el teléfono lleva otro carril). Falta: smoke PO (portada, chips, mayoreo, «Ver todo», tienda,
fuente grande, Servicio) → merge a `feat/fecha-pautada-app`.
```

Y en `MEMORY.md` cambiar la línea del catálogo a:

```markdown
- 🚀✅🔴 **[Catálogo: portada por secciones (09-05)](jayalo-mockup-catalogo-dos-caminos-2026-09-05.md)** — IMPLEMENTADO en `jayalo-app-catalogo` (`feat/catalogo-portada-secciones`), APK +<N> compilado SIN instalar, sin mergear. Falta smoke PO
```

---

## Self-review (hecho al escribir el plan)

**Cobertura de la spec:** §2.1 cabecera → T2 + T8 · §2.2 chips → T5 + T8 · §2.3 regla → T8 (`_filtrado`, `_verTodo`, `_volverAPortada`, `_quitarTodo`) · §2.4 portada y topes → T6 + T7 · §2.5 tarjetas → T3 + T4 · §2.6 hoja Filtrar (chip activo tras la hoja: `_applyFilter` desde `_openFilter` fija `_categoryId`, y el chip se pinta por `categoryId == c.id`) → T8 · §2.7 datos → T1 + T8 · §2.8 estados → T8 (`_vacio`, `ErrorRetry`, `catchError`) · §2.9 onboarding intacto (test `catalog_onboarding_test.dart` en T8 paso 5) · §3 no-cambios: ningún task toca esos archivos · §6 entrega → T9.

**Placeholders:** ninguno; los únicos «si falla…» son instrucciones de ajuste con valores concretos.

**Consistencia de nombres:** `countsForKind`/`categoryCountsForKind` (T1, T8) · `HeaderSegmented.compact` (T2, T8) · `storeLine`, `catalogPriceLine`, `catalogImage`, `catalogGridCardExtent(context, cellWidth)` (T3, T4, T8) · `ProductCarouselCard` (T4, T7) · `CatalogChipStrip` params (T5, T8) · `portadaTiendas/portadaCategorias/portadaCarruseles/articulosLabel`, `CategoriaConteo`, `CarruselCategoria` (T6, T7) · `CatalogPortada` params (T7, T8) · `CatalogSearchField`/`CatalogFilterPill` (T8).
