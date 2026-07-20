# Catálogo: filtros + reputación — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cablear en el Catálogo móvil la reputación real del proveedor por fila, el filtro por categoría/rubro (hoja) y el modo "Al por mayor", extendiendo la query del catálogo — el layout de lista ya está en producción (commit `adde5bb`).

**Architecture:** La reputación llega por una RPC por lote (`get_business_ratings`) detrás de una interfaz Dart estable (`businessRatings(ids)`), y se fusiona con los productos en un wrapper (`catalogProductsWithRatings`). `catalogProducts` gana filtros opcionales (categoría/rubro/mayoreo) con paridad `productHitsQ` de la web. La `CatalogView` guarda el estado del filtro y lo re-dispara; el toggle de mayoreo vive en un tier del header y la categoría/rubro en un `showModalBottomSheet`.

**Tech Stack:** Flutter (Dart), Supabase (PostgREST + RPC SECURITY DEFINER), go_router.

## Global Constraints

- `flutter analyze` DEBE quedar en **0** (baseline del proyecto).
- La suite `flutter test` DEBE quedar **verde** (hoy 336).
- **Paridad con `productHitsQ`** (`jayalo-main/jayalo-main/src/routes/requests/index.tsx`): categoría = `eq('category_id', cat)`; rubro = `ilike('rubro', rubro)`; mayoreo = join `provider_businesses!inner(is_wholesale)` + `eq('provider_businesses.is_wholesale', true)`.
- **No romper el harness** `app/lib/dev/catalog_preview.dart` (inyecta su propio `fetch`).
- App fijada a **tema claro** (no diseñar oscuro).
- Verificación final **por screenshots en device** (Redmi `Z5VKWOLVKFZH6TKV`), con `adb` en `C:\Users\ac\AppData\Local\Android\Sdk\platform-tools\adb.exe`, corriendo `flutter run -d Z5VKWOLVKFZH6TKV -t lib/dev/catalog_preview.dart` (harness) o `-t lib/main.dart` (app real, sesión de proveedor ya persistida).
- Todos los comandos `flutter`/`git` se corren desde `C:\Users\ac\Downloads\jayalo-app\app` (Flutter) salvo git, que es la raíz `C:\Users\ac\Downloads\jayalo-app`.
- Mensajes de commit en español, estilo `feat:`/`fix:`, terminando con `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: RPC `get_business_ratings` (backend)

**Files:**
- Create: `supabase/migrations/20260720120000_get_business_ratings.sql`

**Interfaces:**
- Produces: RPC `get_business_ratings(_business_ids uuid[]) returns table(business_id uuid, avg_rating numeric, reviews_count integer)`, invocable por `authenticated`.

⚠️ **Esta task toca la BD real `mfaiklvobnvgusbcssbx`.** El repo guarda el SQL como control de versiones; aplicarlo requiere el MCP de Supabase (`apply_migration`/`execute_sql`) o el dashboard, con autorización explícita del usuario. No hay CLI de Supabase conectado.

- [ ] **Step 1: Escribir la migración**

Crear `supabase/migrations/20260720120000_get_business_ratings.sql`:

```sql
-- Reputación agregada por negocio para el catálogo (avg + conteo), por lote.
-- SECURITY DEFINER: agrega business_reviews sin exponer reviewer_id ni filas
-- individuales; solo devuelve promedio y conteo. Escala 1-10 (igual que
-- conversation_ratings / get_provider_reviews_summary), sin convertir a 5.
create or replace function public.get_business_ratings(_business_ids uuid[])
returns table (business_id uuid, avg_rating numeric, reviews_count integer)
language sql
security definer
set search_path = public
as $$
  select br.business_id,
         round(avg(br.rating)::numeric, 1) as avg_rating,
         count(*)::int                     as reviews_count
  from business_reviews br
  where br.business_id = any(_business_ids)
  group by br.business_id;
$$;

revoke all on function public.get_business_ratings(uuid[]) from anon;
grant execute on function public.get_business_ratings(uuid[]) to authenticated;
```

- [ ] **Step 2: Aplicar a la BD (con autorización del usuario)**

Vía MCP de Supabase, `apply_migration(project_id='mfaiklvobnvgusbcssbx', name='get_business_ratings', query=<contenido del archivo>)`. Si el MCP no está autorizado en la sesión, pausar y pedir al usuario que lo aplique por el dashboard (SQL editor).

- [ ] **Step 3: Verificar en la BD**

Vía MCP `execute_sql`:

```sql
select * from public.get_business_ratings(
  array(select id from provider_businesses limit 5)::uuid[]
);
```
Expected: 0+ filas, cada una con `business_id`, `avg_rating` (1 decimal) y `reviews_count` ≥ 1. Sin error de permisos.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260720120000_get_business_ratings.sql
git commit -m "feat: RPC get_business_ratings (reputación por lote para el catálogo)"
```

---

### Task 2: `businessRatings` + `mergeCatalogRatings` (Dart, TDD)

**Files:**
- Modify: `app/lib/data/repos.dart` (agregar al final de la sección de catálogo, tras `productDetail`)
- Test: `app/test/catalog_ratings_test.dart` (crear)

**Interfaces:**
- Consumes: RPC `get_business_ratings` (Task 1).
- Produces:
  - `typedef BusinessRating = ({double avg, int count});`
  - `Future<Map<String, BusinessRating>> businessRatings(List<String> businessIds)`
  - `List<Map<String,dynamic>> mergeCatalogRatings(List<Map<String,dynamic>> items, Map<String,BusinessRating> ratings)`

- [ ] **Step 1: Escribir el test de la fusión pura**

Crear `app/test/catalog_ratings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  test('mergeCatalogRatings inyecta avg/count por business_id', () {
    final items = [
      {'id': 'p1', 'business_id': 'b1', 'name': 'A'},
      {'id': 'p2', 'business_id': 'b2', 'name': 'B'},
      {'id': 'p3', 'business_id': null, 'name': 'C'},
    ];
    final ratings = {
      'b1': (avg: 8.7, count: 34),
    };
    final out = mergeCatalogRatings(items, ratings);

    expect(out[0]['avg_rating'], 8.7);
    expect(out[0]['reviews_count'], 34);
    // b2 sin rating: no se agregan claves (la estrella se oculta).
    expect(out[1].containsKey('avg_rating'), isFalse);
    // business_id nulo: intacto.
    expect(out[2].containsKey('avg_rating'), isFalse);
    // No muta la entrada original.
    expect(items[0].containsKey('avg_rating'), isFalse);
  });
}
```

- [ ] **Step 2: Correr el test (falla por símbolo inexistente)**

Run: `flutter test test/catalog_ratings_test.dart`
Expected: FAIL — `mergeCatalogRatings`/`BusinessRating` no definidos.

- [ ] **Step 3: Implementar en `repos.dart`**

Agregar tras `productDetail(...)`:

```dart
// ── Reputación del proveedor por lote (catálogo) ──────────────────────────

/// avg/count de reseñas de un negocio. Interfaz ESTABLE a propósito: hoy la
/// respalda la RPC por lote `get_business_ratings`; si mañana se denormaliza en
/// `provider_businesses`, esta firma y la UI que la consume no cambian.
typedef BusinessRating = ({double avg, int count});

/// Trae la reputación de varios negocios en UNA llamada. De-duplica ids y no
/// llama a la red con lista vacía.
Future<Map<String, BusinessRating>> businessRatings(
    List<String> businessIds) async {
  final ids = businessIds.toSet().toList();
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('get_business_ratings', params: {'_business_ids': ids}),
  );
  return {
    for (final r in rows)
      r['business_id'] as String: (
        avg: (r['avg_rating'] as num?)?.toDouble() ?? 0,
        count: (r['reviews_count'] as num?)?.toInt() ?? 0,
      ),
  };
}

/// Fusiona la reputación en cada item del catálogo por su `business_id`. Pura y
/// sin mutar la entrada: un negocio sin reseñas queda sin `avg_rating` (la
/// tarjeta oculta la estrella).
List<Map<String, dynamic>> mergeCatalogRatings(
    List<Map<String, dynamic>> items, Map<String, BusinessRating> ratings) {
  return [
    for (final it in items)
      if (it['business_id'] is String && ratings[it['business_id']] != null)
        {
          ...it,
          'avg_rating': ratings[it['business_id']]!.avg,
          'reviews_count': ratings[it['business_id']]!.count,
        }
      else
        it,
  ];
}
```

- [ ] **Step 4: Correr el test (pasa)**

Run: `flutter test test/catalog_ratings_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/repos.dart app/test/catalog_ratings_test.dart
git commit -m "feat: businessRatings + mergeCatalogRatings (reputación del catálogo)"
```

---

### Task 3: Wrapper de producción `catalogProductsWithRatings` + estrella real

**Files:**
- Modify: `app/lib/data/repos.dart` (tras `businessRatings`)
- Modify: `app/lib/features/client/catalog_screen.dart` (`CatalogScreen.build`)
- Test: `app/test/catalog_screen_test.dart` (agregar un caso)

**Interfaces:**
- Consumes: `catalogProducts` (existente), `businessRatings`, `mergeCatalogRatings` (Task 2).
- Produces: `Future<List<Map<String,dynamic>>> catalogProductsWithRatings({required String kind, String? search})` (los filtros llegan en Task 4).

- [ ] **Step 1: Test — la tarjeta muestra la estrella cuando el item trae rating**

Agregar en `app/test/catalog_screen_test.dart` (dentro de `main()`):

```dart
  testWidgets('la tarjeta muestra la reputación (★ + promedio + conteo)',
      (tester) async {
    final rated = {...fixedItem, 'avg_rating': 8.7, 'reviews_count': 34};
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search}) async => [rated],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('(34)'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
```

- [ ] **Step 2: Correr el test (pasa YA — la UI de la estrella existe desde `adde5bb`)**

Run: `flutter test test/catalog_screen_test.dart -n "reputación"`
Expected: PASS (confirma que `_ratingLine` ya renderiza; este test blinda la fila contra regresiones antes de cablear la fuente real).

- [ ] **Step 3: Implementar el wrapper en `repos.dart`**

Agregar tras `mergeCatalogRatings`:

```dart
/// Entrada de PRODUCCIÓN del catálogo: trae los productos y les fusiona la
/// reputación de su negocio en una segunda llamada por lote. La `CatalogView`
/// consume esto; los tests/harness inyectan su propio `fetch` con el rating ya
/// horneado, así que no tocan la red.
Future<List<Map<String, dynamic>>> catalogProductsWithRatings({
  required String kind,
  String? search,
}) async {
  final items = await catalogProducts(kind: kind, search: search);
  final ids = <String>{
    for (final it in items)
      if (it['business_id'] is String) it['business_id'] as String,
  }.toList();
  final ratings = await businessRatings(ids);
  return mergeCatalogRatings(items, ratings);
}
```

- [ ] **Step 4: Cablear `CatalogScreen` a usar el wrapper**

En `app/lib/features/client/catalog_screen.dart`, cambiar el `build` de `CatalogScreen`:

```dart
  @override
  Widget build(BuildContext context) => CatalogView(
      fetch: catalogProductsWithRatings, autofocusSearch: autofocusSearch);
```

- [ ] **Step 5: Analyze + tests**

Run: `flutter analyze lib/features/client/catalog_screen.dart lib/data/repos.dart` → `No issues found!`
Run: `flutter test test/catalog_screen_test.dart` → All tests passed.

- [ ] **Step 6: Commit**

```bash
git add app/lib/data/repos.dart app/lib/features/client/catalog_screen.dart app/test/catalog_screen_test.dart
git commit -m "feat: catálogo usa reputación real por lote (catalogProductsWithRatings)"
```

---

### Task 4: Filtros en `catalogProducts` + estado en `CatalogView`

**Files:**
- Modify: `app/lib/data/repos.dart` (`catalogProducts`, `catalogProductsWithRatings`)
- Modify: `app/lib/features/client/catalog_screen.dart` (`CatalogFetch`, `_CatalogViewState`)
- Test: `app/test/catalog_screen_test.dart` (recorders + caso nuevo)

**Interfaces:**
- Produces:
  - `CatalogFetch = Future<List<Map<String,dynamic>>> Function({required String kind, String? search, String? categoryId, String? rubro, bool wholesale})`
  - `catalogProducts({required String kind, String? search, String? categoryId, String? rubro, bool wholesale = false})`
  - Estado en `_CatalogViewState`: `String? _categoryId; String? _rubro; bool _wholesale = false;` y método `_applyFilter({String? categoryId, String? rubro})` + `_toggleWholesale(bool)`.

- [ ] **Step 1: Extender `catalogProducts` en `repos.dart`**

Reemplazar la firma y el cuerpo por:

```dart
Future<List<Map<String, dynamic>>> catalogProducts({
  required String kind,
  String? search,
  String? categoryId,
  String? rubro,
  bool wholesale = false,
}) async {
  // En mayoreo se une el negocio (inner) para poder exigir is_wholesale, igual
  // que `productHitsQ` de la web. El objeto embebido `provider_businesses` que
  // vuelve en cada fila es inofensivo (la tarjeta no lo lee).
  final cols = wholesale
      ? '$catalogProductCols,provider_businesses!inner(is_wholesale)'
      : catalogProductCols;
  var q = supa.from('provider_products').select(cols).eq('kind', kind);
  if (wholesale) q = q.eq('provider_businesses.is_wholesale', true);
  if (categoryId != null) q = q.eq('category_id', categoryId);
  if (rubro != null) q = q.ilike('rubro', rubro);
  final term = search?.trim();
  if (term != null && term.isNotEmpty) {
    final safe = sanitizeCatalogSearchTerm(term);
    q = q.or(
      'name.ilike.%$safe%,description.ilike.%$safe%,rubro.ilike.%$safe%',
    );
  }
  return List<Map<String, dynamic>>.from(
    await q.order('created_at', ascending: false).limit(60),
  );
}
```

- [ ] **Step 2: Propagar los filtros en `catalogProductsWithRatings`**

```dart
Future<List<Map<String, dynamic>>> catalogProductsWithRatings({
  required String kind,
  String? search,
  String? categoryId,
  String? rubro,
  bool wholesale = false,
}) async {
  final items = await catalogProducts(
      kind: kind,
      search: search,
      categoryId: categoryId,
      rubro: rubro,
      wholesale: wholesale);
  final ids = <String>{
    for (final it in items)
      if (it['business_id'] is String) it['business_id'] as String,
  }.toList();
  final ratings = await businessRatings(ids);
  return mergeCatalogRatings(items, ratings);
}
```

- [ ] **Step 3: Extender el typedef `CatalogFetch`**

En `catalog_screen.dart`:

```dart
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale});
```

- [ ] **Step 4: Estado de filtro en `_CatalogViewState` + pasarlo a `fetch`**

Añadir campos y actualizar cada llamada a `widget.fetch(...)` para incluir los filtros. En `_CatalogViewState`:

```dart
  String _kind = 'producto';
  String? _search;
  String? _categoryId;
  String? _rubro;
  bool _wholesale = false;
```

Reemplazar el `_load` inicial y `_refetch` para pasar los filtros:

```dart
  late Future<List<Map<String, dynamic>>> _load = widget.fetch(
      kind: _kind,
      search: _search,
      categoryId: _categoryId,
      rubro: _rubro,
      wholesale: _wholesale);

  void _refetch() {
    final next = widget.fetch(
        kind: _kind,
        search: _search,
        categoryId: _categoryId,
        rubro: _rubro,
        wholesale: _wholesale)
      ..ignore();
    setState(() => _load = next);
  }
```

Añadir los mutadores (los usan Task 5 y 6):

```dart
  void _applyFilter({String? categoryId, String? rubro}) {
    setState(() {
      _categoryId = categoryId;
      _rubro = rubro;
    });
    _refetch();
  }

  void _toggleWholesale(bool on) {
    setState(() => _wholesale = on);
    _refetch();
  }
```

- [ ] **Step 5: Actualizar los recorders del test al nuevo typedef**

En `app/test/catalog_screen_test.dart`, cada función `recorder`/`vacio`/`fallando`/`fixed`-`range` inline debe aceptar los named nuevos (con defaults). Ejemplo del recorder de "arranca en Producto":

```dart
    Future<List<Map<String, dynamic>>> recorder(
        {required String kind,
        String? search,
        String? categoryId,
        String? rubro,
        bool wholesale = false}) async {
      calls.add(kind);
      return [];
    }
```

Y las lambdas inline (p. ej. `fetch: ({required kind, search}) async => [fixedItem]`) pasan a
`fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async => [fixedItem]`.
Aplicar el mismo cambio a `vacio`, al recorder de kind=servicio, al de búsqueda, y a los de la task de "no desborda".

- [ ] **Step 6: Test — cambiar de kind limpia categoría/rubro (paridad web)**

Este comportamiento se implementa en el `onChanged` del segmentado. Añadir en el `onChanged` de `HeaderSegmented` de `CatalogView.build`:

```dart
                onChanged: (i) {
                  setState(() {
                    _kind = i == 0 ? 'producto' : 'servicio';
                    _categoryId = null; // cambiar de kind limpia el filtro
                    _rubro = null;
                  });
                  _refetch();
                },
```

Añadir el test (usa un recorder que capture los args):

```dart
  testWidgets('cambiar de kind limpia categoría y rubro', (tester) async {
    final seen = <Map<String, dynamic>>[];
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        seen.add({'kind': kind, 'categoryId': categoryId, 'rubro': rubro});
        return [];
      },
      actions: const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();

    expect(seen.last['kind'], 'servicio');
    expect(seen.last['categoryId'], isNull);
    expect(seen.last['rubro'], isNull);
  });
```

- [ ] **Step 7: Analyze + tests + commit**

Run: `flutter analyze` → 0. `flutter test test/catalog_screen_test.dart` → verde.

```bash
git add app/lib/data/repos.dart app/lib/features/client/catalog_screen.dart app/test/catalog_screen_test.dart
git commit -m "feat: catálogo acepta filtros categoría/rubro/mayoreo (paridad web)"
```

---

### Task 5: Toggle "Al detalle / Al por mayor" en el header

**Files:**
- Modify: `app/lib/features/client/catalog_screen.dart` (`CatalogView.build`, ranura `below` del `VioletHeader`)
- Test: `app/test/catalog_screen_test.dart`

**Interfaces:**
- Consumes: `_toggleWholesale(bool)` y `_wholesale` (Task 4), `HeaderSegmented` (`violet_header.dart`).

- [ ] **Step 1: Test — tocar "Al por mayor" pide el catálogo con wholesale=true**

```dart
  testWidgets('el toggle Al por mayor filtra el catálogo', (tester) async {
    final wholesaleSeen = <bool>[];
    await tester.pumpWidget(host(CatalogView(
      fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async {
        wholesaleSeen.add(wholesale);
        return [];
      },
      actions: const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al por mayor'));
    await tester.pumpAndSettle();

    expect(wholesaleSeen.last, isTrue);
  });
```

- [ ] **Step 2: Correr (falla: no existe el texto "Al por mayor")**

Run: `flutter test test/catalog_screen_test.dart -n "Al por mayor"` → FAIL.

- [ ] **Step 3: Envolver el `below` en un Column con el segmentado de mayoreo**

En `CatalogView.build`, reemplazar `below: _HeaderSearchField(...)` por un Column con el toggle encima del buscador:

```dart
            below: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: HeaderSegmented(
                    options: const ['Al detalle', 'Al por mayor'],
                    index: _wholesale ? 1 : 0,
                    onChanged: (i) => _toggleWholesale(i == 1),
                  ),
                ),
                const SizedBox(height: 10),
                _HeaderSearchField(
                  controller: _searchCtrl,
                  hint: 'Buscar en el catálogo',
                  autofocus: widget.autofocusSearch,
                  onSubmitted: _applySearch,
                  onClear: _clearSearch,
                ),
              ],
            ),
```

- [ ] **Step 4: Correr el test (pasa) + analyze**

Run: `flutter test test/catalog_screen_test.dart -n "Al por mayor"` → PASS.
Run: `flutter analyze` → 0.

- [ ] **Step 5: Verificar en device (harness)**

Correr el harness y screenshot; confirmar el segmentado bajo el toggle Producto/Servicio, sobre el buscador, sin desbordes.

```bash
flutter run -d Z5VKWOLVKFZH6TKV -t lib/dev/catalog_preview.dart
# adb ... exec-out screencap
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/client/catalog_screen.dart app/test/catalog_screen_test.dart
git commit -m "feat: toggle Al detalle/Al por mayor en el header del catálogo"
```

---

### Task 6: Hoja de filtro categoría/rubro + píldora "Filtrar"

**Files:**
- Create: `app/lib/features/client/catalog_filter_sheet.dart`
- Modify: `app/lib/features/client/catalog_screen.dart` (píldora Filtrar en la fila de búsqueda + estado vacío)
- Test: `app/test/catalog_filter_sheet_test.dart` (crear)

**Interfaces:**
- Consumes: `kCategories`/`categoryNameById` (`domain/catalog.dart`), `rubrosForCategories` (`data/repos.dart`), `_applyFilter`/`_categoryId`/`_rubro` (Task 4).
- Produces: `Future<CatalogFilterResult?> showCatalogFilterSheet(BuildContext, {String? categoryId, String? rubro})` con `class CatalogFilterResult { final String? categoryId; final String? rubro; const CatalogFilterResult(this.categoryId, this.rubro); }` (result `null` = no se cambió nada; un `CatalogFilterResult(null, null)` = "Limpiar").

- [ ] **Step 1: Escribir el widget de la hoja**

Crear `app/lib/features/client/catalog_filter_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/repos.dart' show rubrosForCategories;
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';

/// Resultado de la hoja: categoría (+ rubro) elegidos. `null` como retorno de
/// `showCatalogFilterSheet` = el usuario cerró sin cambiar. Un resultado con
/// ambos en null = "Limpiar".
class CatalogFilterResult {
  const CatalogFilterResult(this.categoryId, this.rubro);
  final String? categoryId;
  final String? rubro;
}

Future<CatalogFilterResult?> showCatalogFilterSheet(BuildContext context,
        {String? categoryId, String? rubro}) =>
    showModalBottomSheet<CatalogFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .85,
        child: _CatalogFilterSheet(categoryId: categoryId, rubro: rubro),
      ),
    );

class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({this.categoryId, this.rubro});
  final String? categoryId;
  final String? rubro;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _expanded; // categoría desplegada (acordeón)
  List<Map<String, dynamic>>? _rubros; // rubros de _expanded (lazy)

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Category> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kCategories;
    return kCategories.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _expand(String catId) async {
    setState(() {
      _expanded = _expanded == catId ? null : catId;
      _rubros = null;
    });
    if (_expanded != catId) return;
    final rows = await rubrosForCategories([catId]);
    if (mounted && _expanded == catId) setState(() => _rubros = rows);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFilter = widget.categoryId != null || widget.rubro != null;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(children: [
              Text('Filtrar',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: jayaloHead(context))),
              const Spacer(),
              if (hasFilter)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, const CatalogFilterResult(null, null)),
                  child: const Text('Limpiar'),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: filledField(context, 'Buscar categoría…'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in _filtered) ...[
                  ListTile(
                    title: Text(c.name),
                    trailing: Icon(_expanded == c.id
                        ? Icons.expand_less
                        : Icons.expand_more),
                    selected: widget.categoryId == c.id,
                    onTap: () => _expand(c.id),
                  ),
                  if (_expanded == c.id)
                    _RubroList(
                      categoryId: c.id,
                      categoryName: c.name,
                      rubros: _rubros,
                      selectedRubro:
                          widget.categoryId == c.id ? widget.rubro : null,
                      onAll: () =>
                          Navigator.pop(context, CatalogFilterResult(c.id, null)),
                      onRubro: (r) =>
                          Navigator.pop(context, CatalogFilterResult(c.id, r)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RubroList extends StatelessWidget {
  const _RubroList({
    required this.categoryId,
    required this.categoryName,
    required this.rubros,
    required this.selectedRubro,
    required this.onAll,
    required this.onRubro,
  });
  final String categoryId;
  final String categoryName;
  final List<Map<String, dynamic>>? rubros;
  final String? selectedRubro;
  final VoidCallback onAll;
  final ValueChanged<String> onRubro;

  @override
  Widget build(BuildContext context) {
    if (rubros == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: JayaloSpinner(size: 18),
        ),
      );
    }
    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        title: Text('Todo $categoryName'),
        selected: selectedRubro == null,
        onTap: onAll,
      ),
      for (final r in rubros!)
        ListTile(
          contentPadding: const EdgeInsets.only(left: 32, right: 16),
          title: Text(r['name'] as String),
          selected: selectedRubro == r['name'],
          onTap: () => onRubro(r['name'] as String),
        ),
    ]);
  }
}
```

(Nota: `JayaloSpinner` y `filledField` vienen de `brand_kit.dart` / `jayalo_loader.dart` — ya re-exportados por `brand_kit.dart`.)

- [ ] **Step 2: Test de la hoja (categorías + selección)**

Crear `app/test/catalog_filter_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_filter_sheet.dart';

void main() {
  testWidgets('lista categorías y "Todo {cat}" devuelve la categoría',
      (tester) async {
    CatalogFilterResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  result = await showCatalogFilterSheet(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // 'Ferretería' es una de las kCategories.
    expect(find.text('Ferretería'), findsOneWidget);
  });
}
```

(La carga de rubros pega a la red — no se testea aquí; el test cubre el render de categorías y el flujo de apertura. La selección "Todo {cat}" y rubros se validan a mano en device.)

- [ ] **Step 3: Correr el test**

Run: `flutter test test/catalog_filter_sheet_test.dart` → PASS. `flutter analyze lib/features/client/catalog_filter_sheet.dart` → 0.

- [ ] **Step 4: Píldora "Filtrar" en la fila del buscador**

En `catalog_screen.dart`, envolver el `_HeaderSearchField` en un Row con la píldora. Reemplazar en el Column del `below` (Task 5) el `_HeaderSearchField(...)` por:

```dart
                Row(children: [
                  Expanded(
                    child: _HeaderSearchField(
                      controller: _searchCtrl,
                      hint: 'Buscar en el catálogo',
                      autofocus: widget.autofocusSearch,
                      onSubmitted: _applySearch,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: _categoryId == null
                        ? 'Filtrar'
                        : (categoryNameById(_categoryId) ?? 'Filtrar'),
                    active: _categoryId != null,
                    onTap: _openFilter,
                    onClear:
                        _categoryId != null ? () => _applyFilter() : null,
                  ),
                ]),
```

Añadir el método `_openFilter` en `_CatalogViewState`:

```dart
  Future<void> _openFilter() async {
    final res = await showCatalogFilterSheet(context,
        categoryId: _categoryId, rubro: _rubro);
    if (res != null) _applyFilter(categoryId: res.categoryId, rubro: res.rubro);
  }
```

Y el widget `_FilterPill` (al final del archivo, junto a los otros privados):

```dart
class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.label,
      required this.active,
      required this.onTap,
      this.onClear});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.onPrimaryContainer,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.tune, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white)),
            ),
            if (active && onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
```

Importar la hoja arriba del archivo: `import 'catalog_filter_sheet.dart';`.

- [ ] **Step 5: Estado vacío contempla el filtro**

En el `EmptyState` del `FutureBuilder`, cambiar la condición del CTA para incluir el filtro:

```dart
                    return EmptyState(
                      controller: _scrollController,
                      message: (_search != null || _categoryId != null)
                          ? 'No hay artículos que coincidan con tu filtro.'
                          : 'Aún no hay artículos publicados en esta '
                              'categoría.\n\nVuelve más tarde: los '
                              'proveedores publican todos los días.',
                      ctaLabel: (_search != null || _categoryId != null)
                          ? 'Quitar filtro'
                          : null,
                      onCta: (_search != null || _categoryId != null)
                          ? () {
                              _searchCtrl.clear();
                              setState(() {
                                _search = null;
                                _categoryId = null;
                                _rubro = null;
                              });
                              _refetch();
                            }
                          : null,
                    );
```

- [ ] **Step 6: Analyze + tests + verificación en device**

Run: `flutter analyze` → 0. `flutter test` → verde.
Verificar en device (app real, sesión de proveedor): abrir Catálogo → Filtrar → elegir "Ferretería" → la lista se filtra y la píldora muestra "Ferretería" con ✕; tocar ✕ limpia. Screenshot.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/client/catalog_filter_sheet.dart app/lib/features/client/catalog_screen.dart app/test/catalog_filter_sheet_test.dart
git commit -m "feat: hoja de filtro categoría/rubro + píldora Filtrar en el catálogo"
```

---

## Notas de verificación final (tras Task 6)

- `flutter analyze` en 0 y `flutter test` verde (nuevos: `catalog_ratings_test.dart`, `catalog_filter_sheet_test.dart`, casos añadidos a `catalog_screen_test.dart`).
- En device (app real): estrella con reputación real en productos de negocios con reseñas; filtro por categoría/rubro; "Al por mayor" restringe a mayoristas; el buscador de Mis solicitudes sigue entrando al catálogo.
- La RPC `get_business_ratings` aplicada y verificada en `mfaiklvobnvgusbcssbx`.
