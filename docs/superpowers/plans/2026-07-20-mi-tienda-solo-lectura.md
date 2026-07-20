# Mi tienda (solo lectura) + botón "Editar en la web" — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir *Mi negocio* en el escaparate de solo lectura del propio negocio (detalles + productos + servicios + opiniones) y añadir un botón "Editar en la web" que abre la página de edición del negocio ya con la sesión iniciada (magic-link SSO).

**Architecture:** La mayor parte es Flutter (repo `jayalo-app`): funciones de lectura nuevas en `data/repos.dart`, un widget de tarjeta de producto extraído del catálogo para reusar, y el rediseño de `MyBusinessView`/`MyBusinessScreen`. Una pieza es web (repo `jayalo-main`): un endpoint HTTP nuevo `/api/app/business-editor-link` que valida el JWT de la app (patrón ADR-0032), verifica propiedad del negocio y devuelve un magic link de Supabase. El detalle del producto (`/catalog/:id`) **ya** oculta el CTA "Solicitar" para el dueño (`_CtaArea` con `data.isOwner`), así que reusarlo no requiere cambios.

**Tech Stack:** Flutter 3 + `supabase_flutter` + `go_router` + `http` + `url_launcher` (app); TanStack Start + Supabase + Zod + Vitest (web).

## Global Constraints

- **Paridad de DATOS con la web, estética de la app.** Los campos y su semántica salen de la web (`provider/business.$id.tsx`); la piel es la doctrina de mockups (tipografía ligera, cero negro, sin bordes duros, `JayaloCard`, header violeta, `cascadeIn`).
- **Solo lectura.** Ningún `insert`/`update`/`delete` desde la app en esta pieza. La edición vive en la web vía el magic button.
- **Reversibilidad** (doctrina "diseños reversibles"): el commit que rediseña `MyBusinessView` (Task 4) debe indicar en su mensaje el SHA que revierte a la tarjeta de conteo actual.
- **No tocar la navbar** (`floating_nav_bar.dart`, `nav_destinations.dart`): se entra por `/provider/business`, como hoy.
- **Reseñas anónimas:** nunca leer ni mostrar `reviewer_id` ni nombre del reseñador — solo `rating`, `comment`, `created_at`.
- **Verde en cada task:** `flutter analyze` en 0 y `flutter test` en verde (app); `npx tsc --noEmit` en 0 y `npx vitest run` en verde (web).
- **Trailer de commit:** terminar cada mensaje con `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Rama de trabajo (app):** `feat/mi-tienda-solo-lectura` (ya creada; el spec vive ahí). **Rama de trabajo (web):** crear `feat/business-editor-link` antes de la Task 5.

## Mapa de archivos

**App (`jayalo-app`, git root `C:/Users/ac/Downloads/jayalo-app`, código en `app/`):**
- Modificar: `app/lib/data/repos.dart` — funciones de lectura nuevas (`businessReviews`, `myStoreProducts`, `partitionStoreItems`, `parseBusinessReview`) y extensión de `myBusinessProfile`.
- Crear: `app/lib/features/shared/product_list_card.dart` — `ProductListCard` extraído de `_CatalogCard`.
- Modificar: `app/lib/features/client/catalog_screen.dart` — usar `ProductListCard`.
- Modificar: `app/lib/features/provider/my_business_screen.dart` — rediseño a escaparate + botón.
- Crear: `app/lib/core/editor_link_client.dart` — cliente HTTP del magic link.
- Modificar: `app/lib/core/config.dart` — `editorLinkEndpoint`.
- Tests: `app/test/repos_test.dart`, `app/test/product_list_card_test.dart` (nuevo), `app/test/my_business_screen_test.dart` (reescrito), `app/test/editor_link_client_test.dart` (nuevo).

**Web (`jayalo-main`, en `C:/Users/ac/Downloads/jayalo-main/jayalo-main`):**
- Crear: `src/lib/businessEditorLink.server.ts` — lógica pura (schema + builder de URL).
- Crear: `src/routes/api/app/business-editor-link.ts` — el endpoint.
- Test: `src/lib/businessEditorLink.server.test.ts` (nuevo).

---

## Task 1: `businessReviews` + `parseBusinessReview` (app)

**Files:**
- Modify: `app/lib/data/repos.dart` (añadir al final de la sección de reputación, tras `businessRatings`)
- Test: `app/test/repos_test.dart`

**Interfaces:**
- Produces:
  - `typedef BusinessReview = ({double rating, String? comment, DateTime createdAt});`
  - `BusinessReview parseBusinessReview(Map<String, dynamic> row)`
  - `Future<List<BusinessReview>> businessReviews(String businessId)`

- [ ] **Step 1: Escribir el test que falla** — añadir a `app/test/repos_test.dart`. NO añadir un `import ... show`: el archivo ya importa `repos.dart` completo (`repos_test.dart:2`), y un import con `show` dispararía el lint `unnecessary_import` → rompería `flutter analyze == 0`. Solo se añade el `group`:

```dart
// dentro de main() (repos.dart ya está importado en la cabecera):
  group('parseBusinessReview', () {
    test('mapea rating, comentario y fecha', () {
      final r = parseBusinessReview({
        'rating': 4,
        'comment': '  Excelente servicio  ',
        'created_at': '2026-07-01T12:00:00Z',
      });
      expect(r.rating, 4.0);
      expect(r.comment, 'Excelente servicio'); // recortado
      expect(r.createdAt.toUtc(), DateTime.utc(2026, 7, 1, 12));
    });

    test('comentario vacío o solo espacios queda null', () {
      expect(parseBusinessReview({'rating': 5, 'comment': '   '}).comment, isNull);
      expect(parseBusinessReview({'rating': 5, 'comment': null}).comment, isNull);
    });

    test('rating ausente cae a 0 y fecha inválida a epoch', () {
      final r = parseBusinessReview({'comment': 'x'});
      expect(r.rating, 0.0);
      expect(r.createdAt.millisecondsSinceEpoch, 0);
    });
  });
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `cd app && flutter test test/repos_test.dart`
Expected: FAIL — `parseBusinessReview` no está definida.

- [ ] **Step 3: Implementar** — añadir en `app/lib/data/repos.dart` (tras `businessRatings`, ~línea 1129):

```dart
// ── Opiniones con texto (Mi tienda) ────────────────────────────────────────
// Anónimas a propósito: solo rating/comment/created_at, NUNCA reviewer_id
// (misma restricción que `get_business_ratings`). La web lee estas mismas
// columnas client-side, así que la RLS de `business_reviews` ya las permite a
// `authenticated`; si un cambio de RLS lo bloqueara, mover a una RPC
// SECURITY DEFINER `get_business_reviews(_business_id)` sin cambiar esta firma.
typedef BusinessReview = ({double rating, String? comment, DateTime createdAt});

BusinessReview parseBusinessReview(Map<String, dynamic> row) {
  final raw = (row['comment'] as String?)?.trim() ?? '';
  return (
    rating: (row['rating'] as num?)?.toDouble() ?? 0,
    comment: raw.isEmpty ? null : raw,
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<List<BusinessReview>> businessReviews(String businessId) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('business_reviews')
        .select('rating,comment,created_at')
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(50),
  );
  return rows.map(parseBusinessReview).toList();
}
```

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `cd app && flutter test test/repos_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd app && flutter analyze
git add app/lib/data/repos.dart app/test/repos_test.dart
git commit -m "feat(tienda): businessReviews + parseBusinessReview (lectura de opiniones)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `myStoreProducts` + `partitionStoreItems` (app)

**Files:**
- Modify: `app/lib/data/repos.dart` (tras la sección del catálogo, ~línea 1088)
- Test: `app/test/repos_test.dart`

**Interfaces:**
- Produces:
  - `Future<List<Map<String, dynamic>>> myStoreProducts(String businessId)`
  - `(List<Map<String, dynamic>>, List<Map<String, dynamic>>) partitionStoreItems(List<Map<String, dynamic>> items)` — `(productos, servicios)`

- [ ] **Step 1: Escribir el test que falla** — añadir a `app/test/repos_test.dart` (sin `import ... show`: ver nota de la Task 1; `repos.dart` ya está importado, y el `show` dispararía `unnecessary_import`):

```dart
// dentro de main() (repos.dart ya está importado en la cabecera):
  group('partitionStoreItems', () {
    test('separa por kind: servicio a servicios, el resto a productos', () {
      final (prods, servs) = partitionStoreItems([
        {'id': '1', 'kind': 'producto'},
        {'id': '2', 'kind': 'servicio'},
        {'id': '3', 'kind': null}, // sin kind cuenta como producto
      ]);
      expect(prods.map((e) => e['id']), ['1', '3']);
      expect(servs.map((e) => e['id']), ['2']);
    });

    test('lista vacía devuelve dos listas vacías', () {
      final (prods, servs) = partitionStoreItems([]);
      expect(prods, isEmpty);
      expect(servs, isEmpty);
    });
  });
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `cd app && flutter test test/repos_test.dart`
Expected: FAIL — `partitionStoreItems` no definida.

- [ ] **Step 3: Implementar** — añadir en `app/lib/data/repos.dart` (tras `catalogProducts`):

```dart
// ── Mi tienda: productos/servicios del propio negocio (solo lectura) ────────
const storeProductCols =
    'id,name,description,price,price_min,price_max,image_urls,category_id,kind';

/// Todos los productos y servicios del propio negocio, más recientes primero.
/// Se separan por kind en la UI con [partitionStoreItems].
Future<List<Map<String, dynamic>>> myStoreProducts(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_products')
          .select(storeProductCols)
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(200),
    );

/// Parte una lista mezclada en (productos, servicios). `kind == 'servicio'` va a
/// servicios; cualquier otro valor (incluido null) cuenta como producto.
(List<Map<String, dynamic>>, List<Map<String, dynamic>>) partitionStoreItems(
    List<Map<String, dynamic>> items) {
  final productos = <Map<String, dynamic>>[];
  final servicios = <Map<String, dynamic>>[];
  for (final i in items) {
    (i['kind'] == 'servicio' ? servicios : productos).add(i);
  }
  return (productos, servicios);
}
```

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `cd app && flutter test test/repos_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd app && flutter analyze
git add app/lib/data/repos.dart app/test/repos_test.dart
git commit -m "feat(tienda): myStoreProducts + partitionStoreItems (catálogo propio)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Extraer `ProductListCard` (app)

Extrae el widget `_CatalogCard` (privado en `catalog_screen.dart`) a un widget público reutilizable, sin cambiar su apariencia ni comportamiento, para que Mi tienda lo use. La reputación por fila se **oculta sola** cuando el `item` no trae `avg_rating`/`reviews_count` (así Mi tienda no la muestra).

**Files:**
- Create: `app/lib/features/shared/product_list_card.dart`
- Modify: `app/lib/features/client/catalog_screen.dart` (borrar `_CatalogCard` y sus helpers privados `_ratingLine`/`_priceLine`/`_imagePlaceholder`; importar y usar `ProductListCard`)
- Test: `app/test/product_list_card_test.dart` (nuevo)

**Interfaces:**
- Produces: `class ProductListCard extends StatelessWidget { const ProductListCard({super.key, required Map<String, dynamic> item}); }` — fila que navega a `/catalog/${item['id']}`.

- [ ] **Step 1: Escribir el test que falla** — `app/test/product_list_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  testWidgets('muestra nombre y precio', (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'category_id': 'ferreteria',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.textContaining('2,500'), findsOneWidget);
  });

  testWidgets('sin avg_rating/reviews_count no dibuja la línea de reputación',
      (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
    })));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('con reputación dibuja la estrella', (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'avg_rating': 4.5,
      'reviews_count': 8,
    })));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `cd app && flutter test test/product_list_card_test.dart`
Expected: FAIL — no existe `product_list_card.dart`.

- [ ] **Step 3: Crear `ProductListCard`** — mover el cuerpo de `_CatalogCard` (líneas 350-525 de `catalog_screen.dart`) a `app/lib/features/shared/product_list_card.dart`, renombrando la clase a `ProductListCard` y su constructor a público. Imports necesarios en el archivo nuevo:

```dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import 'brand_kit.dart';
```

El cuerpo es idéntico al actual `_CatalogCard` (incluidos `_ratingLine`, `_priceLine`, `_imagePlaceholder` como métodos privados de la clase), solo cambia la declaración:

```dart
/// Fila del catálogo (foto + categoría + nombre + reputación + descripción +
/// precio) que navega a `/catalog/:id`. Extraída de `catalog_screen.dart` para
/// reusarse en "Mi tienda". La línea de reputación se oculta si el `item` no
/// trae `avg_rating`/`reviews_count` (Mi tienda no la pasa).
class ProductListCard extends StatelessWidget {
  const ProductListCard({super.key, required this.item});
  final Map<String, dynamic> item;

  // … (cuerpo idéntico a _CatalogCard: build + _ratingLine + _priceLine +
  //    _imagePlaceholder, sin cambios de lógica) …
}
```

- [ ] **Step 4: Actualizar `catalog_screen.dart`** — borrar la clase `_CatalogCard` completa y sus métodos; añadir `import '../shared/product_list_card.dart';`; cambiar el `itemBuilder` (línea ~276):

```dart
itemBuilder: (_, i) => ProductListCard(item: items[i]).cascadeIn(i),
```

**Además, eliminar 3 imports que quedan huérfanos** al mover `_CatalogCard` (sus únicos usos vivían dentro de esa clase; si no se borran, `unused_import` rompe `flutter analyze == 0`):
- `import 'package:go_router/go_router.dart';` (`context.push` solo estaba en `_CatalogCard`)
- `import '../../core/brand.dart';` (`jayaloHead` solo en `_CatalogCard`)
- `import '../../domain/money.dart';` (`fmtRD` solo en `_CatalogCard`)

**Conservar** `import '../../domain/catalog.dart';` (`categoryNameById` sigue usándose en el header, `:218`), `../shared/brand_kit.dart` (`cascadeIn`/`JayaloLoaderBlock`/`EmptyState`), y `dart:async` (`..ignore()`).

- [ ] **Step 5: Correr los tests (card nueva + catálogo no regresiona)**

Run: `cd app && flutter test test/product_list_card_test.dart test/catalog_screen_test.dart test/catalog_ratings_test.dart`
Expected: PASS en los tres.

- [ ] **Step 6: Analyze + commit**

```bash
cd app && flutter analyze
git add app/lib/features/shared/product_list_card.dart app/lib/features/client/catalog_screen.dart app/test/product_list_card_test.dart
git commit -m "refactor(catalogo): extrae ProductListCard reutilizable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Rediseñar *Mi negocio* como escaparate de solo lectura (app)

Reemplaza el cuerpo de `MyBusinessView` (tarjeta de conteo inerte) por el escaparate: detalles + productos + servicios + opiniones. Extiende `myBusinessProfile` con los campos de detalle. **Sin** botón de editar todavía (Task 6). Reescribe `my_business_screen_test.dart`.

**Files:**
- Modify: `app/lib/data/repos.dart` — extender `myBusinessProfile`.
- Modify: `app/lib/features/provider/my_business_screen.dart` — nuevo `MyBusinessView` + `_fetch`.
- Test: `app/test/my_business_screen_test.dart` (reescrito).

**Interfaces:**
- Consumes: `businessReviews`, `myStoreProducts`, `partitionStoreItems`, `businessRatings` (Tasks 1-2 y existente), `ProductListCard` (Task 3).
- Produces:
  - `myBusinessProfile()` ahora devuelve `({String id, String name, String? logoUrl, bool verified, String? categoryId, String? city, bool wholesale, String? description})?`
  - `StoreProfile` = ese mismo record (alias del typedef en la pantalla).
  - `MyBusinessView({required StoreProfile? business, required List<Map<String,dynamic>> productos, required List<Map<String,dynamic>> servicios, required List<BusinessReview> reviews, required BusinessRating? rating})`

- [ ] **Step 1: Extender `myBusinessProfile` en `repos.dart`** — cambiar el `select` y el record:

```dart
Future<
    ({
      String id,
      String name,
      String? logoUrl,
      bool verified,
      String? categoryId,
      String? city,
      bool wholesale,
      String? description,
    })?> myBusinessProfile() async {
  final uid = supa.auth.currentUser!.id;
  final biz = await supa
      .from('provider_businesses')
      .select(
          'id,name,logo_url,business_verified_at,category_id,city,is_wholesale,description')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (biz == null) return null;
  final logo = biz['logo_url'] as String?;
  final city = (biz['city'] as String?)?.trim();
  final desc = (biz['description'] as String?)?.trim();
  final cat = (biz['category_id'] as String?)?.trim();
  return (
    id: biz['id'] as String,
    name: (biz['name'] as String?) ?? '',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    verified: businessVerifiedFrom(biz),
    categoryId: (cat != null && cat.isNotEmpty) ? cat : null,
    city: (city != null && city.isNotEmpty) ? city : null,
    wholesale: biz['is_wholesale'] == true,
    description: (desc != null && desc.isNotEmpty) ? desc : null,
  );
}
```

- [ ] **Step 2: Escribir los tests que fallan** — reescribir `app/test/my_business_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessReview, BusinessRating;
import 'package:jayalo_app/features/provider/my_business_screen.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  const negocio = (
    id: 'biz-1',
    name: 'Ferretería Pérez',
    logoUrl: null,
    verified: true,
    categoryId: 'ferreteria',
    city: 'Santiago',
    wholesale: true,
    description: 'Todo en herramientas',
  );

  final unProducto = [
    {'id': 'p1', 'name': 'Taladro', 'price': 2500, 'kind': 'producto'}
  ];
  final unServicio = [
    {'id': 's1', 'name': 'Instalación', 'price': 800, 'kind': 'servicio'}
  ];
  final unaResena = [
    (rating: 5.0, comment: 'Muy bueno', createdAt: DateTime(2026, 7, 1))
  ];

  Widget view({
    List<Map<String, dynamic>> productos = const [],
    List<Map<String, dynamic>> servicios = const [],
    List<BusinessReview> reviews = const [],
    BusinessRating? rating,
  }) =>
      host(MyBusinessView(
        business: negocio,
        productos: productos,
        servicios: servicios,
        reviews: reviews,
        rating: rating,
      ));

  testWidgets('muestra nombre, verificación y detalles', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.textContaining('verificado'), findsOneWidget);
    expect(find.textContaining('Ferretería'), findsWidgets); // categoría
    expect(find.textContaining('Santiago'), findsOneWidget); // zona
    expect(find.text('Mayorista'), findsOneWidget); // chip mayorista
  });

  testWidgets('lista productos y servicios', (tester) async {
    await tester
        .pumpWidget(view(productos: unProducto, servicios: unServicio));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCTOS'), findsOneWidget);
    expect(find.text('SERVICIOS'), findsOneWidget);
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.text('Instalación'), findsOneWidget);
  });

  testWidgets('secciones vacías muestran aviso, no CTA de crear',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no tienes productos'), findsOneWidget);
    expect(find.textContaining('Aún no tienes servicios'), findsOneWidget);
    // Nunca ofrece crear (eso es V2/web).
    expect(find.textContaining('Crear'), findsNothing);
  });

  testWidgets('opiniones: promedio, conteo y texto de la reseña',
      (tester) async {
    await tester.pumpWidget(
        view(reviews: unaResena, rating: (avg: 4.8, count: 12)));
    await tester.pumpAndSettle();
    expect(find.text('OPINIONES'), findsOneWidget);
    expect(find.textContaining('4.8'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('Muy bueno'), findsOneWidget);
  });

  testWidgets('sin opiniones muestra aviso', (tester) async {
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no tienes opiniones'), findsOneWidget);
  });

  testWidgets('sin negocio muestra un aviso en vez de reventar',
      (tester) async {
    await tester.pumpWidget(host(const MyBusinessView(
        business: null,
        productos: [],
        servicios: [],
        reviews: [],
        rating: null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No encontramos tu negocio'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

Run: `cd app && flutter test test/my_business_screen_test.dart`
Expected: FAIL — la firma de `MyBusinessView` no coincide.

- [ ] **Step 4: Reescribir `my_business_screen.dart`.** Reemplazar el `typedef BusinessProfile`, el `_fetch` de `MyBusinessScreen`, y `MyBusinessView`/`_MyBusinessViewState` por lo siguiente (conservar `_BusinessHeaderCard` tal cual; borrar `CatalogCard`):

```dart
typedef StoreProfile = ({
  String id,
  String name,
  String? logoUrl,
  bool verified,
  String? categoryId,
  String? city,
  bool wholesale,
  String? description,
});

class _StoreData {
  const _StoreData(
      {required this.business,
      required this.productos,
      required this.servicios,
      required this.reviews,
      required this.rating});
  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;
}
```

`MyBusinessScreen._fetch`:

```dart
Future<_StoreData> _fetch() async {
  final business = await myBusinessProfile();
  if (business == null) {
    return const _StoreData(
        business: null,
        productos: [],
        servicios: [],
        reviews: [],
        rating: null);
  }
  final results = await Future.wait([
    myStoreProducts(business.id),
    businessReviews(business.id),
    businessRatings([business.id]),
  ]);
  final (productos, servicios) =
      partitionStoreItems(results[0] as List<Map<String, dynamic>>);
  final ratings = results[2] as Map<String, BusinessRating>;
  return _StoreData(
    business: business,
    productos: productos,
    servicios: servicios,
    reviews: results[1] as List<BusinessReview>,
    rating: ratings[business.id],
  );
}
```

El `build` del `MyBusinessScreen` cambia el `FutureBuilder<_StoreData>` para pasar los campos al `MyBusinessView` (mismo patrón que hoy, con `JayaloLoaderBlock`/`ErrorRetry`).

`MyBusinessView` (solo dibuja, `ScrollController` propio como antes):

```dart
class MyBusinessView extends StatefulWidget {
  const MyBusinessView({
    super.key,
    required this.business,
    required this.productos,
    required this.servicios,
    required this.reviews,
    required this.rating,
  });
  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  @override
  State<MyBusinessView> createState() => _MyBusinessViewState();
}

class _MyBusinessViewState extends State<MyBusinessView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    if (b == null) {
      return EmptyState(
        controller: _scroll,
        message: 'No encontramos tu negocio.\n\n'
            'Si el problema sigue, escríbenos desde Ajustes.',
      );
    }
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        _BusinessHeaderCard(business: b).cascadeIn(0),
        _DetailsRow(business: b).cascadeIn(1),
        const SectionHeader(text: 'PRODUCTOS'),
        ..._itemsOrEmpty(widget.productos, 'Aún no tienes productos.'),
        const SectionHeader(text: 'SERVICIOS'),
        ..._itemsOrEmpty(widget.servicios, 'Aún no tienes servicios.'),
        const SectionHeader(text: 'OPINIONES'),
        _ReviewsBlock(reviews: widget.reviews, rating: widget.rating),
      ],
    );
  }

  List<Widget> _itemsOrEmpty(List<Map<String, dynamic>> items, String empty) {
    if (items.isEmpty) return [_EmptyLine(text: empty)];
    return [for (final i in items) ProductListCard(item: i)];
  }
}
```

`_BusinessHeaderCard` requiere cambiar su tipo de parámetro de `BusinessProfile` a `StoreProfile` (solo el tipo; usa `business.name/logoUrl/verified`, que siguen existiendo). Añadir los widgets nuevos en el mismo archivo:

```dart
/// Fila de detalles bajo la cabecera: categoría, zona y chip mayorista.
class _DetailsRow extends StatelessWidget {
  const _DetailsRow({required this.business});
  final StoreProfile business;

  @override
  Widget build(BuildContext context) {
    final catName = categoryNameById(business.categoryId);
    final chips = <Widget>[
      if (catName != null) _MetaChip(icon: Icons.category_outlined, label: catName),
      if (business.city != null)
        _MetaChip(icon: Icons.place_outlined, label: business.city!),
      if (business.wholesale)
        _MetaChip(icon: Icons.inventory_2_outlined, label: 'Mayorista'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

/// Promedio + conteo (encabezado) y la lista de reseñas anónimas.
class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.reviews, required this.rating});
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (reviews.isEmpty) {
      return const _EmptyLine(text: 'Aún no tienes opiniones.');
    }
    return Column(children: [
      if (rating != null && rating!.count > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5A623)),
            const SizedBox(width: 4),
            Text(rating!.avg.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('(${rating!.count} ${rating!.count == 1 ? 'reseña' : 'reseñas'})',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        ),
      for (final r in reviews) _ReviewCard(review: r),
    ]);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final BusinessReview review;
  @override
  Widget build(BuildContext context) {
    return JayaloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            for (var i = 0; i < 5; i++)
              Icon(
                  i < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFF5A623)),
          ]),
          if (review.comment != null) ...[
            const SizedBox(height: 6),
            Text(review.comment!, style: const TextStyle(fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}
```

Añadir los imports que falten en `my_business_screen.dart`: `../shared/product_list_card.dart`, `../../domain/catalog.dart` (para `categoryNameById`), y `BusinessReview`/`BusinessRating` ya vienen de `../../data/repos.dart`.

**Consumidor a arreglar (si no, rompe `flutter test` Y `flutter analyze`):** `test/stats_screen_test.dart` importa `CatalogCard` de `my_business_screen.dart` (`show CatalogCard`) y asevera `expect(find.byType(CatalogCard), findsNothing)`. Al borrar `CatalogCard`, ese archivo no compila. Fix: quitar `CatalogCard` del `show` (dejar el resto del import) y borrar esa aserción; las aserciones por texto que ya tiene (`'LO QUE OFRECES'`, etc.) siguen cubriendo el contrato "esto se movió fuera de Estadísticas".

**Notas del análisis previo:**
- `category_id` y `description` de `provider_businesses` están confirmadas reales (aparecen en el `Row` de `provider_businesses` en `types.ts` de la web).
- Tras reescribir `_fetch`, `providerCatalogCounts` y `providerCompletedCount` (`repos.dart`) quedan sin consumidores. Son top-level públicas → NO disparan `unused_element` (analyze sigue en 0); dejarlas por ahora (código muerto inerte), no borrar en esta task para no ampliar el diff.

- [ ] **Step 5: Correr los tests para verificar que pasan**

Run: `cd app && flutter test test/my_business_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + suite completa + commit**

```bash
cd app && flutter analyze && flutter test
git add app/lib/data/repos.dart app/lib/features/provider/my_business_screen.dart app/test/my_business_screen_test.dart app/test/stats_screen_test.dart
git commit -m "feat(tienda): Mi negocio muestra el escaparate de solo lectura

Detalles + productos + servicios + opiniones. Sin edición (V2/web).
Revierte a la tarjeta de conteo con: git revert <este-sha>.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

(Al commitear, reemplazar `<este-sha>` no aplica — dejar la nota "git revert de este commit"; el requisito de reversibilidad se cumple con que TODO el rediseño va en este único commit.)

---

## Task 5: Endpoint `/api/app/business-editor-link` (web)

**Files:**
- Create: `src/lib/businessEditorLink.server.ts`
- Create: `src/lib/businessEditorLink.server.test.ts`
- Create: `src/routes/api/app/business-editor-link.ts`

**Interfaces:**
- Produces (para la app): `POST https://jayalo.com/api/app/business-editor-link` con header `Authorization: Bearer <jwt>` + `Origin: https://jayalo.com`, body `{ "businessId": "<uuid>" }` → `200 { "url": "<action_link>" }` | `400` payload | `401` sin sesión | `403` origin/propiedad.

- [ ] **Step 0: Crear la rama web**

```bash
cd C:/Users/ac/Downloads/jayalo-main/jayalo-main && git checkout -b feat/business-editor-link
```

- [ ] **Step 1: Escribir el test que falla** — `src/lib/businessEditorLink.server.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { buildEditorRedirectUrl, EditorLinkBody } from "./businessEditorLink.server";

describe("buildEditorRedirectUrl", () => {
  it("compone la ruta del negocio sin doble slash", () => {
    expect(buildEditorRedirectUrl("https://jayalo.com", "biz-1")).toBe(
      "https://jayalo.com/provider/business/biz-1",
    );
    expect(buildEditorRedirectUrl("https://jayalo.com/", "biz-1")).toBe(
      "https://jayalo.com/provider/business/biz-1",
    );
  });
});

describe("EditorLinkBody", () => {
  it("acepta un uuid", () => {
    const uuid = "11111111-1111-1111-1111-111111111111";
    expect(EditorLinkBody.parse({ businessId: uuid }).businessId).toBe(uuid);
  });
  it("rechaza un businessId no-uuid", () => {
    expect(() => EditorLinkBody.parse({ businessId: "x" })).toThrow();
  });
});
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `cd C:/Users/ac/Downloads/jayalo-main/jayalo-main && npx vitest run src/lib/businessEditorLink.server.test.ts`
Expected: FAIL — el módulo no existe.

- [ ] **Step 3: Implementar la lógica pura** — `src/lib/businessEditorLink.server.ts`:

```ts
import { z } from "zod";

export const EditorLinkBody = z.object({ businessId: z.string().uuid() });

/** URL de la página de edición del negocio (destino del magic link). */
export function buildEditorRedirectUrl(siteUrl: string, businessId: string): string {
  return `${siteUrl.replace(/\/$/, "")}/provider/business/${businessId}`;
}
```

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `cd C:/Users/ac/Downloads/jayalo-main/jayalo-main && npx vitest run src/lib/businessEditorLink.server.test.ts`
Expected: PASS.

- [ ] **Step 5: Escribir el endpoint** — `src/routes/api/app/business-editor-link.ts`:

```ts
// createFileRoute viene de @tanstack/react-router (NO @tanstack/react-start) —
// así lo importan las 5 rutas API existentes, incl. chat-stream.ts.
import { createFileRoute } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { extractBearerToken } from "@/lib/aiSession.server";
import { EditorLinkBody, buildEditorRedirectUrl } from "@/lib/businessEditorLink.server";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export const Route = createFileRoute("/api/app/business-editor-link")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        // Origin fail-closed (idéntico a /api/ai/chat-stream).
        const origin = request.headers.get("origin") ?? "";
        const allowedOrigins = [
          process.env.SITE_URL ?? "",
          "https://jayalo.com",
          "https://jallalo.com",
          "https://jayalo.net",
          "https://jallalo.net",
        ].filter(Boolean);
        if (!origin || !allowedOrigins.includes(origin)) return json({ error: "Forbidden" }, 403);

        // Valida el JWT de la app y obtiene el usuario (id + email).
        const token = extractBearerToken(request.headers.get("authorization"));
        if (!token) return json({ error: "No autenticado" }, 401);
        const { data: userData, error: userErr } = await supabase.auth.getUser(token);
        const user = userData?.user;
        if (userErr || !user?.email) return json({ error: "No autenticado" }, 401);

        let body: { businessId: string };
        try {
          body = EditorLinkBody.parse(await request.json());
        } catch {
          return json({ error: "Payload inválido" }, 400);
        }

        // El negocio debe ser del propio usuario (el enlace redirige ahí).
        const { data: biz } = await supabaseAdmin
          .from("provider_businesses")
          .select("id")
          .eq("id", body.businessId)
          .eq("user_id", user.id)
          .maybeSingle();
        if (!biz) return json({ error: "Forbidden" }, 403);

        const siteUrl = process.env.SITE_URL ?? "https://jayalo.com";
        const { data: link, error: linkErr } = await supabaseAdmin.auth.admin.generateLink({
          type: "magiclink",
          email: user.email,
          options: { redirectTo: buildEditorRedirectUrl(siteUrl, body.businessId) },
        });
        const actionLink = link?.properties?.action_link;
        if (linkErr || !actionLink) return json({ error: "No se pudo generar el enlace" }, 500);

        return json({ url: actionLink }, 200);
      },
    },
  },
});
```

- [ ] **Step 6: Typecheck + tests + commit + verificación manual**

```bash
cd C:/Users/ac/Downloads/jayalo-main/jayalo-main
npx tsc --noEmit && npx vitest run src/lib/businessEditorLink.server.test.ts
git add src/lib/businessEditorLink.server.ts src/lib/businessEditorLink.server.test.ts src/routes/api/app/business-editor-link.ts
git commit -m "feat(app-api): endpoint business-editor-link (magic-link SSO para editar en la web)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

Verificación manual antes de mergear/desplegar (no automatizable en local: el endpoint exige Origin y un JWT real):
1. Confirmar en Supabase Auth (dashboard → Authentication → URL Configuration) que `https://jayalo.com/**` está en **Redirect URLs**; si no, agregarlo (sin esto el verify del magic link rechaza el `redirect_to`).
2. Tras el deploy (push a `master` dispara el CI de la web), con un JWT de sesión real de un proveedor: `POST` con Origin `https://jayalo.com` y `{businessId}` propio → 200 con `url`; abrir esa `url` en un navegador limpio debe dejar la sesión iniciada en `/provider/business/{id}` con los botones de editar visibles. Probar además: sin Origin → 403; businessId ajeno → 403; sin Authorization → 401.

---

## Task 6: `EditorLinkClient` + botón "Editar en la web" (app)

**Files:**
- Create: `app/lib/core/editor_link_client.dart`
- Modify: `app/lib/core/config.dart` — `editorLinkEndpoint`.
- Modify: `app/lib/features/provider/my_business_screen.dart` — botón + handler.
- Test: `app/test/editor_link_client_test.dart` (nuevo), `app/test/my_business_screen_test.dart` (añadir test del botón).

**Interfaces:**
- Consumes: `MyBusinessView` (Task 4), `AppConfig.siteUrl`.
- Produces:
  - `AppConfig.editorLinkEndpoint`
  - `class EditorLinkClient { Future<String> fetchEditorUrl({required String businessId, required String accessToken}); }`
  - `EditorLinkException(int status, String message)`
  - `MyBusinessView` gana `final Future<void> Function()? onEditWeb;` (inyectable; el botón se muestra si `business != null`).

- [ ] **Step 1: Añadir el endpoint a `config.dart`** — tras `aiEndpoint`:

```dart
  static const editorLinkEndpoint = '$siteUrl/api/app/business-editor-link';
```

- [ ] **Step 2: Escribir el test del cliente que falla** — `app/test/editor_link_client_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:jayalo_app/core/editor_link_client.dart';

void main() {
  test('manda Bearer + Origin y devuelve la url', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({'url': 'https://jayalo.com/verify?x=1'}), 200);
    });
    final client = EditorLinkClient(inner: mock);
    final url = await client.fetchEditorUrl(businessId: 'biz-1', accessToken: 'tok');
    expect(url, 'https://jayalo.com/verify?x=1');
    expect(captured.headers['Authorization'], 'Bearer tok');
    expect(captured.headers['Origin'], 'https://jayalo.com');
    expect(jsonDecode(captured.body)['businessId'], 'biz-1');
  });

  test('lanza EditorLinkException en no-200', () async {
    final mock = MockClient((req) async =>
        http.Response(jsonEncode({'error': 'Forbidden'}), 403));
    final client = EditorLinkClient(inner: mock);
    expect(
      () => client.fetchEditorUrl(businessId: 'biz-1', accessToken: 'tok'),
      throwsA(isA<EditorLinkException>()),
    );
  });
}
```

- [ ] **Step 3: Correr el test para verificar que falla**

Run: `cd app && flutter test test/editor_link_client_test.dart`
Expected: FAIL — no existe `editor_link_client.dart`.

- [ ] **Step 4: Implementar** — `app/lib/core/editor_link_client.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class EditorLinkException implements Exception {
  EditorLinkException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'EditorLinkException($status): $message';
}

/// Pide a la web un magic link de un solo uso que deja la sesión iniciada y
/// redirige a la página de edición del negocio. Mismo patrón de llamada que
/// `AiClient` (Origin + Bearer del JWT de sesión).
class EditorLinkClient {
  EditorLinkClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<String> fetchEditorUrl({
    required String businessId,
    required String accessToken,
  }) async {
    final res = await _http.post(
      Uri.parse(AppConfig.editorLinkEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Origin': AppConfig.siteUrl,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'businessId': businessId}),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw EditorLinkException(
          res.statusCode, body['error']?.toString() ?? 'Error');
    }
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw EditorLinkException(res.statusCode, 'Respuesta inválida');
    }
    return url;
  }
}
```

- [ ] **Step 5: Correr el test del cliente para verificar que pasa**

Run: `cd app && flutter test test/editor_link_client_test.dart`
Expected: PASS.

- [ ] **Step 6: Añadir el botón a `MyBusinessView` + test.** Añadir a `MyBusinessView` el parámetro `final Future<void> Function()? onEditWeb;` (opcional) y dibujar el botón tras `_DetailsRow` cuando `business != null`:

```dart
// en el children del ListView, tras _DetailsRow(...).cascadeIn(1):
if (widget.onEditWeb != null)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: FilledButton.icon(
      onPressed: () => widget.onEditWeb!.call(),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: const Text('Editar en la web'),
    ),
  ),
```

Añadir el test en `app/test/my_business_screen_test.dart` (usa el helper `view` extendido con `onEditWeb`):

```dart
  testWidgets('el botón Editar en la web invoca el callback', (tester) async {
    var called = false;
    await tester.pumpWidget(host(MyBusinessView(
      business: negocio,
      productos: const [],
      servicios: const [],
      reviews: const [],
      rating: null,
      onEditWeb: () async => called = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar en la web'));
    await tester.pump();
    expect(called, isTrue);
  });
```

- [ ] **Step 7: Cablear el handler real en `MyBusinessScreen`.** Pasar `onEditWeb: _openEditor` al `MyBusinessView`, con:

```dart
Future<void> _openEditor(String businessId) async {
  final token = supa.auth.currentSession?.accessToken;
  if (token == null) {
    _toast('Inicia sesión de nuevo para editar.');
    return;
  }
  try {
    final url = await EditorLinkClient().fetchEditorUrl(
        businessId: businessId, accessToken: token);
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) _toast('No pudimos abrir el navegador.');
  } catch (_) {
    _toast('No se pudo abrir el editor. Intenta de nuevo.');
  }
}
```

Añadir imports: `package:url_launcher/url_launcher.dart`, `../../core/editor_link_client.dart`. `_toast` = helper con `ScaffoldMessenger` (copiar el patrón de `product_detail_screen.dart`). El `MyBusinessView` en el `build` del screen recibe `onEditWeb: () => _openEditor(data.business!.id)`.

- [ ] **Step 8: Analyze + suite completa + commit**

```bash
cd app && flutter analyze && flutter test
git add app/lib/core/editor_link_client.dart app/lib/core/config.dart app/lib/features/provider/my_business_screen.dart app/test/editor_link_client_test.dart app/test/my_business_screen_test.dart
git commit -m "feat(tienda): botón Editar en la web (magic-link SSO)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Verificación de cierre (device, tras Task 6)

Con la web ya desplegada (Task 5) y un proveedor real con productos/servicios/reseñas:
1. Abrir *Mi negocio* → ver detalles, productos, servicios y opiniones (con texto).
2. Tocar un producto → detalle `/catalog/:id` sin el CTA "Solicitar" (dice "Este es tu producto.").
3. Tocar "Editar en la web" → se abre el navegador y aterriza logueado en la página de edición con los botones de editar.
4. `flutter analyze` en 0 y `flutter test` en verde.

## Self-review (cobertura del spec)

- Detalles del negocio → Task 4 (`_DetailsRow` + `_BusinessHeaderCard`, `myBusinessProfile` extendida).
- Productos / Servicios → Tasks 2, 3, 4 (`myStoreProducts`, `partitionStoreItems`, `ProductListCard`).
- Opiniones (texto) → Tasks 1, 4 (`businessReviews`, `_ReviewsBlock`).
- Detalle propio sin "Me interesa" → ya existe (`_CtaArea` con `data.isOwner`), verificado en cierre paso 2.
- Botón "Editar en la web" + magic-link SSO → Tasks 5 (web) y 6 (app).
- RLS de `business_reviews` → nota en Task 1 (fallback RPC) + no expone `reviewer_id`.
- Redirect allowlist de Supabase Auth → Task 5 verificación manual #1.
- Reversibilidad → Task 4 commit único.
- Fuera de alcance (portfolio, paquetes, multi-negocio, feed) → no aparecen en ninguna task, correcto.
