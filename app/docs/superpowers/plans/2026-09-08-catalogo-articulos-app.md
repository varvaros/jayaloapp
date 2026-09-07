# Catálogo por artículos (app) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En la pestaña Catálogo de la app, sustituir la portada por secciones del 09-05 por el catálogo por artículos ya desplegado en la web: fila de chips de tipo (Todos · Productos · Servicios · Paquetes · Proveedores) en lugar del segmentado de la cabecera, hoja «Filtrar» con Ubicación/Precio/Proveedor, cuerpo en cuatro secciones en orden fijo Proveedores → Productos → Servicios → Paquetes con «Ver todos», y los paquetes dentro del catálogo por primera vez. Sin banner ni cierre con CTA (doctrina de la barra flotante).

**Architecture:** La lógica pura (mapeo de paquete, filtros, orden, secciones, proveedores, unión de conteos, saneo) vive en `lib/features/client/catalog_articulos.dart` con `test()` a secas — traducción de `src/lib/catalogItem.ts` y `src/lib/proveedores.ts` de la web. `data/repos.dart` gana `catalogPackages()` (best-effort), `catalogBusinessesByName()`, `catalogItemsWithRatings()` y `description`/`city` en `BusinessCardInfo`; `catalogProducts` acepta `kind` nulo. La vista: `CatalogTipoStrip` nuevo, `CatalogChipStrip` con rubros, `CatalogFilterSheet` con tres bloques nuevos, `CatalogSecciones` (sustituye a `CatalogPortada`) + `ProveedorCard`, tarjetas con insignia/logo/lo incluido, y `CatalogView` recableada. Todo inyectable para tests (mismo patrón `CatalogFetch`).

**Tech Stack:** Flutter (Dart 3.12, `flutter_test`, `go_router`, `supabase_flutter`), tokens en `core/brand.dart`, kit en `features/shared/brand_kit.dart`. Suite con `flutter test`; APK release con `flutter build apk --release`; instalación por `adb`.

**Spec:** `app/docs/superpowers/specs/2026-09-08-catalogo-articulos-app-design.md` (aprobada por el PO).

## Global Constraints

- Repo app `jayalo-app`, **worktree `C:/Users/ac/Downloads/jayalo-app-articulos`**, rama `feat/catalogo-articulos-app` sobre el tronco `feat/fecha-pautada-app` `367b338` (1.0.4+124). Todo se ejecuta desde `C:/Users/ac/Downloads/jayalo-app-articulos/app`. **Cero migraciones. No se toca la web.**
- Gates de cada tarea: `flutter analyze` → 0 issues · `flutter test` → todo verde (línea base medida en la Task 0) · `dart format --set-exit-if-changed lib test` limpio. Tests de widget con viewport 400×1600 cuando el cuerpo es un `ListView` (gotcha: un `findsNothing` sobre una lista perezosa pasa en falso).
- Un commit por tarea, mensajes en español con prefijo `feat(app):`/`refactor(app):`/`test(app):`/`chore(app):`/`docs(app):` y la línea `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Orden de secciones **fijo**: Proveedores → Productos → Servicios → Paquetes. Topes: Proveedores **12**, cada carrusel **8**. Sección vacía no se pinta. Sin destacados en la app.
- Doctrina de la app: **sin banner «Crear solicitud» ni cierre «Publicar solicitud»** (la solicitud vive en el «+» de la barra flotante); tipografía 400–600 (700 solo en precios); tarjetas sin borde (`JayaloCard`); nada de negro; «Tienda física» en el teal de `JayaloStatus.requisito*` (autodeclarado), «Verificado» en `JayaloColors.success` (lo verifica Jayalo). La barra flotante no se toca.
- Copy literal: «Todos», «Productos», «Servicios», «Paquetes», «Proveedores», «Ver todos», «Tienda física», «Verificado», «Consultar precio», «desde », «Ubicación», «Todas las ciudades», «Precio», «Desde RD$», «Hasta RD$», «Proveedor», «Solo verificados», «Con local», «Limpiar», «Proveedores que coinciden:», «Quitar filtro», «No hay artículos que coincidan con tu filtro.», «No hay proveedores que coincidan con tu filtro.», «Producto», «Servicio», «Paquete».
- `provider_packages.price` es NOT NULL DEFAULT 0: **0 = sin precio** ⇒ «Consultar precio». Paquete: sin `category_id` ni `rubro`; con categoría/rubro activos no sale ninguno.
- Los conteos de la fila de tipo y de los títulos son del **conjunto cargado y filtrado** (≤ 60 productos/servicios + 30 paquetes); los de la tira de categorías siguen siendo los globales de `get_product_counts` (unión de kinds).
- `catalog_screen.dart` (439 líneas) crece como mucho ~80; lo nuevo va a ficheros nuevos. No se refactoriza fuera del alcance.
- El número de build es GLOBAL entre worktrees: leer `pubspec.yaml` antes del chore y subir +1 (hoy 124 → 125).

## Mapa de ficheros

| Fichero | Acción | Responsabilidad |
|---|---|---|
| `lib/features/client/catalog_articulos.dart` (+ `test/catalog_articulos_test.dart`) | Crear | lógica pura: `paqueteComoItem`, `tipoDeItem`, `FiltrosLateral`, `filtrarLateral`, `esVerificado`, `tieneFoto`, `ordenarCatalogo`, `seccionesCatalogo`, `resumenConteos`, `ciudadesDe`, `coincideBusqueda`, `sumarConteos`, `sanitizarIlike`, `Proveedor`, `queHace`, `proveedoresDeItems`, `kTopeCarrusel`, `kTopeProveedores` |
| `lib/data/repos.dart` | Modificar | `BusinessCardInfo` + `description`/`city`; `catalogProducts(kind nullable)`; `catalogPackages()`; `catalogBusinessesByName()`; `catalogItemsWithRatings()`; `categoryCountsUnion()` |
| `lib/features/shared/product_list_card.dart` (+ test) | Modificar | insignia de tipo, logo como respaldo, lo incluido, ruta por tipo, carrusel cuadrado 150 |
| `lib/features/client/catalog_tipo_strip.dart` (+ test) | Crear | fila «Todos · Productos · Servicios · Paquetes · Proveedores» con conteos |
| `lib/features/client/catalog_chip_strip.dart` (+ test) | Modificar | mayoreo condicionado por tipo; fila de rubros |
| `lib/features/client/catalog_filter_sheet.dart` (+ test) | Modificar | bloques Ubicación/Precio/Proveedor; resultado ampliado; categorías = unión |
| `lib/features/client/catalog_secciones.dart` (+ test) | Crear | cuatro secciones, `SeccionTitulo` con conteo, `_StoreCircle` con línea, `ProveedorCard`, `ProveedoresCoinciden` |
| `lib/features/client/catalog_screen.dart` (+ test) | Modificar | estado `_tipo` + filtros, fetchers, cabecera sin segmentado, cuerpo (secciones / rejilla / lista de proveedores), vacío |
| `lib/features/shared/onboarding_copy.dart` | Modificar | copy de `client.catalog.v1` |
| `lib/features/client/catalog_portada.dart`, `catalog_portada_secciones.dart`, `test/catalog_portada_test.dart`, `test/catalog_portada_secciones_test.dart` | Borrar | portada del 09-05 |
| `pubspec.yaml`, `CLAUDE.md` | Modificar | chore +125; nota del catálogo |

---

### Task 0: Línea base

**Files:** ninguno (solo medir).

- [ ] **Step 1:** `flutter analyze` → anotar «No issues found». `flutter test --reporter=compact 2>&1 | tail -3` → anotar el conteo (el 09-06 el tronco tenía 1918). `grep ^version: pubspec.yaml` → `1.0.4+124`.
- [ ] **Step 2:** Escribir ambos números en `.superpowers/sdd/progress.md` (git-ignored) del worktree.

---

### Task 1: Lógica pura (`catalog_articulos.dart`)

**Files:**
- Create: `lib/features/client/catalog_articulos.dart`
- Test: `test/catalog_articulos_test.dart`

**Interfaces:**
- Consumes: `BusinessCardInfo` de `data/repos.dart` (todavía sin `description`/`city`: en esta tarea se leen con `??` desde un `Map<String, dynamic>` de negocio crudo **no** — ver nota); `categoryNameById` de `domain/catalog.dart`.
- Nota de orden: `BusinessCardInfo` gana `description`/`city` en la Task 2. Para que esta tarea compile sola, `queHace`/`proveedoresDeItems`/`ciudadesDe`/`filtrarLateral` reciben los negocios como `Map<String, NegocioCatalogo>` donde `NegocioCatalogo` es un record **definido aquí** con los campos que el catálogo necesita; la Task 2 añade la conversión `BusinessCardInfo → NegocioCatalogo` (`negocioCatalogoDe`).
- Produces (todo exportado):

```dart
typedef NegocioCatalogo = ({
  String name, String? logoUrl, bool hasPhysicalLocation, bool verificado,
  String? description, String? city,
});
typedef Proveedor = ({
  String id, String name, String? logoUrl, bool hasPhysicalLocation,
  String? city, bool verificado, String queHace,
});
typedef FiltrosLateral = ({String? ciudad, int precioMin, int precioMax, bool soloVerificados, bool conLocal});
const FiltrosLateral kSinFiltros = (ciudad: null, precioMin: 0, precioMax: 0, soloVerificados: false, conLocal: false);
const int kTopeCarrusel = 8;
const int kTopeProveedores = 12;
Map<String, dynamic> paqueteComoItem(Map<String, dynamic> row);
String tipoDeItem(Map<String, dynamic> it); // 'producto' | 'servicio' | 'paquete'
bool tieneFoto(Map<String, dynamic> it);
List<Map<String, dynamic>> filtrarLateral(List<Map<String, dynamic>> items, Map<String, NegocioCatalogo> negocios, FiltrosLateral f);
List<Map<String, dynamic>> ordenarCatalogo(List<Map<String, dynamic>> items); // con foto antes que sin foto, estable
({List<Map<String, dynamic>> productos, List<Map<String, dynamic>> servicios, List<Map<String, dynamic>> paquetes}) seccionesCatalogo(List<Map<String, dynamic>> items);
String resumenConteos({required int productos, required int servicios, required int paquetes, required int proveedores});
List<String> ciudadesDe(Map<String, NegocioCatalogo> negocios, {String? seleccionada});
bool coincideBusqueda(String texto, String q);
Map<String, int> sumarConteos(Map<String, int>? a, Map<String, int>? b);
String sanitizarIlike(String term);
String queHace(String? description, String? categoriaDominante);
List<Proveedor> proveedoresDeItems(List<Map<String, dynamic>> items, Map<String, NegocioCatalogo> negocios, {int tope = kTopeProveedores});
```

- [ ] **Step 1: Test** — `test/catalog_articulos_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart';

NegocioCatalogo neg(String name, {bool local = false, bool verif = false, String? city, String? desc, String? logo}) => (
  name: name, logoUrl: logo, hasPhysicalLocation: local, verificado: verif, description: desc, city: city,
);
Map<String, dynamic> item(String id, {String? biz = 'b1', String? cat = 'electronica', String kind = 'producto', num? price = 100, num? min, List<String> fotos = const ['https://x/1.jpg']}) => {
  'id': id, 'business_id': biz, 'category_id': cat, 'kind': kind, 'price': price, 'price_min': min, 'price_max': null, 'image_urls': fotos, 'name': 'Artículo $id',
};

void main() {
  group('paqueteComoItem', () {
    final row = {'id': 'k1', 'user_id': 'u', 'business_id': 'b1', 'name': 'Chicha', 'description': '', 'price': 3000, 'items': ['4 chichas', '3 vasos'], 'image_url': 'https://x/c.jpg', 'created_at': '2026-08-09'};
    test('mapea al ítem del catálogo', () {
      final it = paqueteComoItem(row);
      expect(it['kind'], 'paquete');
      expect(it['image_urls'], ['https://x/c.jpg']);
      expect(it['items'], ['4 chichas', '3 vasos']);
      expect(it['category_id'], '');
      expect(it['price'], 3000);
    });
    test('precio 0 pasa a null (Consultar precio) y sin foto image_urls vacío', () {
      final it = paqueteComoItem({...row, 'price': 0, 'image_url': null});
      expect(it['price'], isNull);
      expect(it['image_urls'], isEmpty);
    });
  });

  test('tipoDeItem: kind nulo es producto', () {
    expect(tipoDeItem({'kind': null}), 'producto');
    expect(tipoDeItem({'kind': 'servicio'}), 'servicio');
    expect(tipoDeItem({'kind': 'paquete'}), 'paquete');
  });

  group('filtrarLateral', () {
    final negocios = {'b1': neg('getto', local: true, city: 'Santo Domingo Este'), 'b2': neg('Dra', verif: true, city: 'Santiago')};
    final a = item('a', price: 500);
    final b = item('b', biz: 'b2', price: null, min: 6000);
    final c = item('c', kind: 'paquete', price: null);
    test('sin filtro devuelve todo', () => expect(filtrarLateral([a, b, c], negocios, kSinFiltros), hasLength(3)));
    test('ciudad', () => expect(filtrarLateral([a, b], negocios, (ciudad: 'Santiago', precioMin: 0, precioMax: 0, soloVerificados: false, conLocal: false)).map((e) => e['id']), ['b']));
    test('precio usa price o price_min; Consultar siempre pasa', () {
      expect(filtrarLateral([a, b, c], negocios, (ciudad: null, precioMin: 1000, precioMax: 0, soloVerificados: false, conLocal: false)).map((e) => e['id']), ['b', 'c']);
      expect(filtrarLateral([a, b, c], negocios, (ciudad: null, precioMin: 0, precioMax: 1000, soloVerificados: false, conLocal: false)).map((e) => e['id']), ['a', 'c']);
    });
    test('verificados y con local', () {
      expect(filtrarLateral([a, b], negocios, (ciudad: null, precioMin: 0, precioMax: 0, soloVerificados: true, conLocal: false)).map((e) => e['id']), ['b']);
      expect(filtrarLateral([a, b], negocios, (ciudad: null, precioMin: 0, precioMax: 0, soloVerificados: false, conLocal: true)).map((e) => e['id']), ['a']);
    });
  });

  test('ordenarCatalogo: con foto antes que sin foto, estable', () {
    final r = ordenarCatalogo([item('s', fotos: const []), item('f1'), item('f2'), item('t', fotos: const [])]);
    expect(r.map((e) => e['id']), ['f1', 'f2', 's', 't']);
  });

  test('seccionesCatalogo reparte por kind y recorta a kTopeCarrusel', () {
    final items = [for (var i = 0; i < 10; i++) item('p$i'), item('s1', kind: 'servicio'), item('k1', kind: 'paquete')];
    final s = seccionesCatalogo(items);
    expect(s.productos, hasLength(kTopeCarrusel));
    expect(s.servicios.map((e) => e['id']), ['s1']);
    expect(s.paquetes.map((e) => e['id']), ['k1']);
  });

  test('resumenConteos con singulares', () {
    expect(resumenConteos(productos: 7, servicios: 1, paquetes: 0, proveedores: 8), '7 productos · 1 servicio · 0 paquetes · 8 proveedores');
    expect(resumenConteos(productos: 1, servicios: 0, paquetes: 1, proveedores: 1), '1 producto · 0 servicios · 1 paquete · 1 proveedor');
  });

  test('ciudadesDe: distintas, ordenadas, y la seleccionada nunca se pierde', () {
    final negocios = {'a': neg('x', city: 'Santo Domingo Este'), 'b': neg('y', city: 'Santiago'), 'c': neg('z', city: null)};
    expect(ciudadesDe(negocios), ['Santiago', 'Santo Domingo Este']);
    expect(ciudadesDe(negocios, seleccionada: 'La Romana'), ['La Romana', 'Santiago', 'Santo Domingo Este']);
  });

  test('coincideBusqueda sin acentos ni mayúsculas', () {
    expect(coincideBusqueda('Instalación de aire', 'instalacion'), isTrue);
    expect(coincideBusqueda('Chicha', 'mouse'), isFalse);
    expect(coincideBusqueda('lo que sea', ''), isTrue);
  });

  test('sumarConteos une por id y tolera null', () {
    expect(sumarConteos({'a': 1, 'b': 2}, {'b': 3, 'c': 1}), {'a': 1, 'b': 5, 'c': 1});
    expect(sumarConteos(null, {'a': 1}), {'a': 1});
    expect(sumarConteos(null, null), isEmpty);
  });

  test('sanitizarIlike quita comodines y operadores', () {
    expect(sanitizarIlike(' ge%t_to,(*) '), 'getto');
  });

  group('queHace y proveedoresDeItems', () {
    test('descripción corta, recorte por palabra, categoría dominante, nada', () {
      expect(queHace('Electrónica y eventos', 'Salud'), 'Electrónica y eventos');
      expect(queHace('Vendemos de todo para el hogar y también instalamos aires', 'Hogar'), 'Vendemos de todo para el hogar y también…');
      expect(queHace('', 'Salud y bienestar'), 'Salud y bienestar');
      expect(queHace(null, null), '');
    });
    test('negocios distintos en orden de aparición, verificado y categoría dominante; tope', () {
      final negocios = {'b1': neg('getto', local: true), 'b2': neg('Dra', verif: true, city: 'Santiago')};
      final ps = proveedoresDeItems([item('1', cat: 'salud'), item('2', biz: 'b2'), item('3', cat: 'electronica'), item('4', cat: 'electronica')], negocios);
      expect(ps.map((p) => p.id), ['b1', 'b2']);
      expect(ps[0].queHace, 'Electrónica');
      expect(ps[0].verificado, isFalse);
      expect(ps[1].verificado, isTrue);
      expect(ps[1].city, 'Santiago');
      final muchos = [for (var i = 0; i < 15; i++) item('i$i', biz: 'n$i')];
      final n = {for (var i = 0; i < 15; i++) 'n$i': neg('N$i')};
      expect(proveedoresDeItems(muchos, n), hasLength(kTopeProveedores));
    });
    test('ignora ítems sin negocio resuelto', () {
      expect(proveedoresDeItems([item('x', biz: 'nope')], const {}), isEmpty);
    });
  });
}
```

- [ ] **Step 2:** `flutter test test/catalog_articulos_test.dart` → FAIL (no existe el fichero).

- [ ] **Step 3: Implementar** — `lib/features/client/catalog_articulos.dart`

```dart
/// Lógica PURA del catálogo por artículos (PO 2026-09-07/08), traducción de
/// `src/lib/catalogItem.ts` y `src/lib/proveedores.ts` de la web. Sin widgets
/// ni red, para probarse con `test()` a secas. Un paquete (`provider_packages`)
/// se mapea al MISMO mapa de ítem que consumen las tarjetas: `kind: 'paquete'`,
/// `items`, la foto única en `image_urls`.
library;

import '../../domain/catalog.dart';

typedef NegocioCatalogo = ({
  String name,
  String? logoUrl,
  bool hasPhysicalLocation,
  bool verificado,
  String? description,
  String? city,
});

typedef Proveedor = ({
  String id,
  String name,
  String? logoUrl,
  bool hasPhysicalLocation,
  String? city,
  bool verificado,
  /// Línea gris bajo el nombre: descripción corta, o la categoría dominante, o nada.
  String queHace,
});

typedef FiltrosLateral = ({
  String? ciudad,
  /// 0 = sin filtro.
  int precioMin,
  int precioMax,
  bool soloVerificados,
  bool conLocal,
});

const FiltrosLateral kSinFiltros = (
  ciudad: null,
  precioMin: 0,
  precioMax: 0,
  soloVerificados: false,
  conLocal: false,
);

const int kTopeCarrusel = 8;
const int kTopeProveedores = 12;
const int _kMaxQueHace = 40;

/// `provider_packages.price` es NOT NULL DEFAULT 0: el 0 significa «sin precio».
Map<String, dynamic> paqueteComoItem(Map<String, dynamic> row) {
  final foto = (row['image_url'] as String?)?.trim();
  final price = row['price'] as num?;
  return {
    'id': row['id'],
    'user_id': row['user_id'],
    'business_id': row['business_id'],
    'name': row['name'] ?? '',
    'description': row['description'],
    'price': price != null && price > 0 ? price : null,
    'price_min': null,
    'price_max': null,
    'image_urls': foto == null || foto.isEmpty ? <String>[] : <String>[foto],
    'category_id': '',
    'kind': 'paquete',
    'items': (row['items'] as List?)?.cast<String>() ?? const <String>[],
    'created_at': row['created_at'],
  };
}

String tipoDeItem(Map<String, dynamic> it) {
  final k = it['kind'];
  return k == 'servicio' || k == 'paquete' ? k as String : 'producto';
}

bool tieneFoto(Map<String, dynamic> it) {
  final fotos = it['image_urls'];
  return fotos is List && fotos.isNotEmpty && (fotos.first as String).trim().isNotEmpty;
}

num? _precioDe(Map<String, dynamic> it) =>
    (it['price'] as num?) ?? (it['price_min'] as num?);

List<Map<String, dynamic>> filtrarLateral(
  List<Map<String, dynamic>> items,
  Map<String, NegocioCatalogo> negocios,
  FiltrosLateral f,
) {
  return [
    for (final it in items)
      if (_pasa(it, negocios[it['business_id']], f)) it,
  ];
}

bool _pasa(Map<String, dynamic> it, NegocioCatalogo? b, FiltrosLateral f) {
  if (f.ciudad != null && (b?.city ?? '') != f.ciudad) return false;
  if (f.soloVerificados && b?.verificado != true) return false;
  if (f.conLocal && b?.hasPhysicalLocation != true) return false;
  final p = _precioDe(it);
  // «Consultar» (sin precio) pasa siempre: no se puede juzgar lo que no se sabe.
  if (p != null) {
    if (f.precioMin > 0 && p < f.precioMin) return false;
    if (f.precioMax > 0 && p > f.precioMax) return false;
  }
  return true;
}

/// Con foto antes que sin foto, ESTABLE sobre el orden de llegada
/// (`created_at` desc del servidor). `List.sort` no es estable: se indexa.
List<Map<String, dynamic>> ordenarCatalogo(List<Map<String, dynamic>> items) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final ga = tieneFoto(a.$2) ? 0 : 1;
    final gb = tieneFoto(b.$2) ? 0 : 1;
    return ga != gb ? ga.compareTo(gb) : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

({
  List<Map<String, dynamic>> productos,
  List<Map<String, dynamic>> servicios,
  List<Map<String, dynamic>> paquetes,
})
seccionesCatalogo(List<Map<String, dynamic>> items) {
  List<Map<String, dynamic>> de(String k) =>
      items.where((it) => tipoDeItem(it) == k).take(kTopeCarrusel).toList();
  return (productos: de('producto'), servicios: de('servicio'), paquetes: de('paquete'));
}

String _plural(int n, String uno, String varios) => '$n ${n == 1 ? uno : varios}';

String resumenConteos({
  required int productos,
  required int servicios,
  required int paquetes,
  required int proveedores,
}) => [
  _plural(productos, 'producto', 'productos'),
  _plural(servicios, 'servicio', 'servicios'),
  _plural(paquetes, 'paquete', 'paquetes'),
  _plural(proveedores, 'proveedor', 'proveedores'),
].join(' · ');

/// Ciudades distintas de los negocios, ordenadas. La SELECCIONADA nunca se
/// oculta: si desapareciera, el filtro seguiría aplicado sin control visible.
List<String> ciudadesDe(Map<String, NegocioCatalogo> negocios, {String? seleccionada}) {
  final set = <String>{
    for (final b in negocios.values)
      if (b.city != null && b.city!.trim().isNotEmpty) b.city!.trim(),
    if (seleccionada != null && seleccionada.trim().isNotEmpty) seleccionada.trim(),
  };
  final lista = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return lista;
}

const _acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};

String _normalizar(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_acentos[ch] ?? ch);
  }
  return b.toString();
}

/// Búsqueda en cliente (paquetes, nombres de proveedor): sin acentos ni mayúsculas.
bool coincideBusqueda(String texto, String q) {
  final t = _normalizar(q.trim());
  if (t.isEmpty) return true;
  return _normalizar(texto).contains(t);
}

/// Unión de los conteos por categoría de ambos kinds (`get_product_counts`).
Map<String, int> sumarConteos(Map<String, int>? a, Map<String, int>? b) {
  final out = <String, int>{...?a};
  b?.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
  return out;
}

/// Sin comodines ni operadores de PostgREST (`*` también es comodín en ilike).
String sanitizarIlike(String term) =>
    term.replaceAll(RegExp(r'[%_,()*]'), '').trim();

String queHace(String? description, String? categoriaDominante) {
  final d = description?.trim() ?? '';
  if (d.isNotEmpty) {
    if (d.length <= _kMaxQueHace) return d;
    final corte = d.substring(0, _kMaxQueHace + 1).lastIndexOf(' ');
    return '${d.substring(0, corte > 0 ? corte : _kMaxQueHace).trimRight()}…';
  }
  return categoriaDominante ?? '';
}

/// Proveedores «con algún artículo» en el conjunto actual, en orden de
/// aparición (= reciente primero). La categoría dominante se cuenta sobre
/// TODOS los ítems del negocio aunque luego solo salgan [tope].
List<Proveedor> proveedoresDeItems(
  List<Map<String, dynamic>> items,
  Map<String, NegocioCatalogo> negocios, {
  int tope = kTopeProveedores,
}) {
  final orden = <String>[];
  final porNegocio = <String, List<Map<String, dynamic>>>{};
  for (final it in items) {
    final id = it['business_id'];
    if (id is! String || !negocios.containsKey(id)) continue;
    if (!porNegocio.containsKey(id)) {
      porNegocio[id] = [];
      orden.add(id);
    }
    porNegocio[id]!.add(it);
  }
  return [
    for (final id in orden.take(tope))
      () {
        final b = negocios[id]!;
        final conteo = <String, int>{};
        for (final it in porNegocio[id]!) {
          final c = it['category_id'];
          if (c is String && c.isNotEmpty) conteo[c] = (conteo[c] ?? 0) + 1;
        }
        String? dominante;
        var max = 0;
        for (final e in conteo.entries) {
          if (e.value > max) {
            max = e.value;
            dominante = e.key;
          }
        }
        return (
          id: id,
          name: b.name.trim(),
          logoUrl: b.logoUrl,
          hasPhysicalLocation: b.hasPhysicalLocation,
          city: (b.city?.trim().isEmpty ?? true) ? null : b.city!.trim(),
          verificado: b.verificado,
          queHace: queHace(b.description, dominante == null ? null : categoryNameById(dominante)),
        );
      }(),
  ];
}
```

- [ ] **Step 4:** `flutter test test/catalog_articulos_test.dart` → PASS (≥ 14 tests). `flutter analyze` 0. `dart format lib/features/client/catalog_articulos.dart test/catalog_articulos_test.dart`.
- [ ] **Step 5: Commit** — `git add lib/features/client/catalog_articulos.dart test/catalog_articulos_test.dart && git commit -m "feat(app): lógica pura del catálogo por artículos — paquete como ítem, filtros, secciones, proveedores" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"`.

---

### Task 2: Datos (`repos.dart`)

**Files:**
- Modify: `lib/data/repos.dart` (`BusinessCardInfo` ~3319, `businessesCardInfo` ~3334, `catalogProducts` ~3200, `catalogProductsWithRatings` ~3934, `packageCols` ~3579, `categoryCountsForKind` ~4100)
- Test: `test/catalog_repos_puro_test.dart` (solo lo puro: `negocioCatalogoDe`, `mergeCatalogRatings` con paquetes)

**Interfaces (produce):**
- `BusinessCardInfo` gana `String? description, String? city` (select de `businessesCardInfo` añade `description,city`). **Todos los literales `(name: …, hasPhysicalLocation: …)` del código y de los tests** que construyen un `BusinessCardInfo` deben añadir `description: null, city: null` (grep `hasPhysicalLocation:` en `lib/` y `test/`).
- `NegocioCatalogo negocioCatalogoDe(BusinessCardInfo b)` → `(name, logoUrl, hasPhysicalLocation, verificado: b.identityVerified || b.businessVerified, description, city)` (en `repos.dart`, importando `catalog_articulos.dart`).
- `catalogProducts({String? kind, …})`: `kind == null` ⇒ sin `.eq('kind', …)`.
- `Future<List<Map<String, dynamic>>> catalogPackages()`: `provider_packages`, `'$packageCols,created_at'`, `.order('created_at', ascending: false).limit(30)`, mapeado con `paqueteComoItem`; `try/catch` ⇒ `[]`; `.timeout(4 s)` ⇒ `[]`.
- `Future<List<Proveedor>> catalogBusinessesByName(String term)`: `sanitizarIlike(term)`; vacío ⇒ `[]`; `provider_businesses` select `id,name,logo_url,has_physical_location,description,city,business_verified_at,identity_verified_at` `.ilike('name', '%$t%').limit(5)` (sin `suspended_at`: no está en `BusinessCardInfo`; si el select falla por la columna `has_physical_location`, hacer como `businessesPhysicalLocation`: pedirla aparte); `try/catch` ⇒ `[]`; mapea a `Proveedor` con `queHace(description, null)`.
- `Future<List<Map<String, dynamic>>> catalogItemsWithRatings({String? kind, String? search, String? categoryId, String? rubro, bool wholesale = false, bool conPaquetes = true})`: productos/servicios (`catalogProducts`) + (si `conPaquetes && !wholesale && categoryId == null && rubro == null`) `catalogPackages()` filtrados en cliente por `search` (`coincideBusqueda` sobre `name`, `description` y cada `items`); reputación por lote de los negocios de ambos (`businessRatings`, `catchError` ⇒ `{}`); `mergeCatalogRatings` sobre la lista completa. Devuelve productos+servicios seguidos de paquetes.
- `Future<Map<String, int>?> categoryCountsUnion()`: una sola llamada a `get_product_counts` → `sumarConteos(countsForKind(rows,'producto'), countsForKind(rows,'servicio'))`; error ⇒ `null`.
- `Future<Set<String>?> categoriasConCatalogoTodas()` → `(await categoryCountsUnion())?.keys.toSet()`.

- [ ] **Step 1: Test** — `test/catalog_repos_puro_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart';

void main() {
  test('negocioCatalogoDe: verificado = identidad o negocio', () {
    const b = (name: 'getto', logoUrl: null, whatsappVerified: true, identityVerified: false, businessVerified: true, hasPhysicalLocation: true, description: 'Electrónica', city: 'SDE');
    final n = negocioCatalogoDe(b);
    expect(n.verificado, isTrue);
    expect(n.city, 'SDE');
    expect(n.description, 'Electrónica');
    expect(n.hasPhysicalLocation, isTrue);
  });
  test('mergeCatalogRatings también hornea la reputación en un paquete', () {
    final k = paqueteComoItem({'id': 'k', 'business_id': 'b1', 'name': 'Chicha', 'price': 3000, 'items': const [], 'image_url': null});
    final out = mergeCatalogRatings([k], {'b1': (avg: 9.0, count: 2)});
    expect(out.single['avg_rating'], 9.0);
    expect(out.single['kind'], 'paquete');
  });
}
```

- [ ] **Step 2:** `flutter test test/catalog_repos_puro_test.dart` → FAIL (campos/funciones inexistentes).
- [ ] **Step 3: Implementar** los puntos de «Interfaces» en `repos.dart`. Comentarios en español, junto a cada función, con el mismo tono del fichero (best-effort, por qué). `catalogProductsWithRatings` se conserva como `catalogItemsWithRatings(kind: kind, conPaquetes: false)` para no romper otros llamadores (grep `catalogProductsWithRatings`).
- [ ] **Step 4:** `flutter analyze` 0 · `flutter test` verde (todos los literales de `BusinessCardInfo` actualizados) · `dart format`.
- [ ] **Step 5: Commit** — `feat(app): paquetes y negocios por nombre en el catálogo, BusinessCardInfo con descripción y ciudad, productos sin kind`.

---

### Task 3: Tarjetas (`product_list_card.dart`)

**Files:**
- Modify: `lib/features/shared/product_list_card.dart`
- Test: `test/product_list_card_test.dart` (añadir casos)

**Interfaces (produce):**
- `ProductGridCard({item, negocio, showTypeTag = false})`, `ProductCarouselCard({item, negocio, width = 150, showTypeTag = false})`.
- `Widget catalogImage(String? url, ColorScheme cs, {String? logoUrl})`: sin `url`, si `logoUrl` ⇒ logo redondo al 42 % centrado sobre `cs.primaryContainer`; si no, placeholder de hoy.
- `Widget catalogTypeBadge(BuildContext, String tipo)`: «Producto» (`cs.surface` fondo, `jayaloHead` tinta), «Servicio» (`cs.primary` fondo, blanco), «Paquete» (`cs.onPrimaryContainer` fondo, blanco); texto 9.5 w600 mayúsculas, radio 999, padding 8×2, sombra `warmShadow`. Se pinta en un `Stack` sobre la foto, `Positioned(left: 8, top: 8)`.
- Ruta al tocar: `tipoDeItem(item) == 'paquete'` ⇒ `/package/${id}`; si no, la de hoy.
- Lo incluido (solo paquete, `items` no vacío): `Text(items.join(' · '), maxLines: 2, 10.5/11, cs.onSurfaceVariant)` bajo el nombre, en ambas tarjetas.
- `ProductCarouselCard`: foto `AspectRatio(1)` (antes `SizedBox(height: 96)`), `width` 150 por defecto.
- `catalogGridCardExtent(context, cellWidth, {bool conIncluido = false})`: suma 28 × escala cuando `conIncluido`.

- [ ] **Step 1: Tests** (añadir a `product_list_card_test.dart`):

```dart
  testWidgets('ProductGridCard: insignia solo con showTypeTag; paquete pinta lo incluido', (tester) async {
    final paquete = {'id': 'k1', 'name': 'Chicha', 'kind': 'paquete', 'price': 3000, 'image_urls': <String>[], 'items': ['4 chichas', '3 vasos']};
    await tester.pumpWidget(host(SizedBox(width: 180, height: 320, child: ProductGridCard(item: paquete))));
    await tester.pumpAndSettle();
    expect(find.text('PAQUETE'), findsNothing);
    expect(find.textContaining('4 chichas · 3 vasos'), findsOneWidget);
    await tester.pumpWidget(host(SizedBox(width: 180, height: 320, child: ProductGridCard(item: paquete, showTypeTag: true))));
    await tester.pumpAndSettle();
    expect(find.text('PAQUETE'), findsOneWidget);
  });
  testWidgets('sin foto y con logo del negocio, la foto de respaldo es el logo', (tester) async {
    const negocio = (name: 'getto', logoUrl: 'https://x/logo.png', whatsappVerified: false, identityVerified: false, businessVerified: false, hasPhysicalLocation: false, description: null, city: null);
    await tester.pumpWidget(host(SizedBox(width: 180, height: 300, child: ProductGridCard(item: const {'id': 'p', 'name': 'Aire', 'kind': 'servicio', 'price_min': 6000, 'image_urls': <String>[]}, negocio: negocio, showTypeTag: true))));
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.text('SERVICIO'), findsOneWidget);
  });
```

(Las imágenes de red no cargan en test: basta con que NO aparezca el icono de placeholder cuando hay logo.)

- [ ] **Step 2:** `flutter test test/product_list_card_test.dart` → FAIL.
- [ ] **Step 3: Implementar.** Mantener los comentarios de decisión existentes. `Stack` con `clipBehavior: Clip.none` no hace falta: la insignia va dentro de la foto.
- [ ] **Step 4:** `flutter analyze` 0 · `flutter test` verde (revisar `catalog_portada_test.dart`, que usa `ProductCarouselCard` con la foto de 96: si mide alturas, ajustar el número allí, no la tarjeta) · `dart format`.
- [ ] **Step 5: Commit** — `feat(app): la tarjeta del catálogo pinta paquetes, insignia de tipo y el logo del negocio sin foto`.

---

### Task 4: Fila de tipo y rubros en la tira (`catalog_tipo_strip.dart`, `catalog_chip_strip.dart`)

**Files:**
- Create: `lib/features/client/catalog_tipo_strip.dart`; Test: `test/catalog_tipo_strip_test.dart`
- Modify: `lib/features/client/catalog_chip_strip.dart`; Test: `test/catalog_chip_strip_test.dart`

**Interfaces (produce):**
- `CatalogTipoStrip({required String tipo, required Map<String, int> conteos, required ValueChanged<String> onTipo})` — `conteos` con claves `todos|producto|servicio|paquete|proveedor`. Cinco píldoras en `SingleChildScrollView` horizontal, padding `fromLTRB(16, 12, 16, 0)`; activa: fondo `cs.onPrimaryContainer`, texto blanco; inactiva: blanca con sombra (misma `_Chip` que la tira, extraída a `shared/catalog_chip.dart` como `CatalogChip({label, active, onTap, leading, dark = false})` para no duplicarla). Etiqueta «Productos 7» con el número a 10 w500 y opacidad .7. `MergeSemantics` + `selected`.
- `CatalogChipStrip` gana `rubros: List<String>`, `rubro: String?`, `onRubro: ValueChanged<String?>`: con `categoryId != null && rubros.isNotEmpty`, una segunda fila (padding top 8) con «Todo <categoría>» + un chip por rubro (fuente 11); tocar el activo lo quita (`onRubro(null)`).

- [ ] **Step 1: Tests**

```dart
// test/catalog_tipo_strip_test.dart
testWidgets('cinco chips con conteo, el activo oscuro, y avisa al tocar', (tester) async {
  String? tocado;
  await tester.pumpWidget(host(CatalogTipoStrip(tipo: 'todos', conteos: const {'todos': 14, 'producto': 7, 'servicio': 5, 'paquete': 3, 'proveedor': 8}, onTipo: (t) => tocado = t)));
  for (final l in ['Todos', 'Productos', 'Servicios', 'Paquetes', 'Proveedores']) expect(find.text(l), findsOneWidget);
  expect(find.text('7'), findsOneWidget);
  await tester.tap(find.text('Paquetes'));
  expect(tocado, 'paquete');
});
// test/catalog_chip_strip_test.dart (añadir)
testWidgets('con categoría y rubros pinta la fila de rubros y avisa', (tester) async {
  String? r = 'x';
  await tester.pumpWidget(host(CatalogChipStrip(categorias: const [(id: 'salud', name: 'Salud')], categoryId: 'salud', rubros: const ['Medicina general', 'Odontología'], rubro: null, onRubro: (v) => r = v, onCategory: (_) {}, onTodo: () {})));
  expect(find.text('Odontología'), findsOneWidget);
  await tester.tap(find.text('Odontología'));
  expect(r, 'Odontología');
});
```

- [ ] **Step 2:** tests → FAIL. **Step 3:** implementar. **Step 4:** `flutter analyze` 0 · `flutter test` verde (los llamadores de `CatalogChipStrip` — `catalog_screen.dart` y tests — reciben `rubros: const []`, `rubro: null`, `onRubro: (_) {}` hasta la Task 7) · `dart format`.
- [ ] **Step 5: Commit** — `feat(app): fila de chips de tipo y rubros en la tira de categorías`.

---

### Task 5: Hoja «Filtrar» (`catalog_filter_sheet.dart`)

**Files:**
- Modify: `lib/features/client/catalog_filter_sheet.dart`; Test: `test/catalog_filter_sheet_test.dart`

**Interfaces (produce):**
- `CatalogFilterResult` gana `String? ciudad, int precioMin, int precioMax, bool soloVerificados, bool conLocal` (constructor con nombrados y defectos; `const CatalogFilterResult.limpio()`).
- `showCatalogFilterSheet(context, {String? categoryId, String? rubro, required List<String> ciudades, required FiltrosLateral filtros, Future<Set<String>?> Function() categoriasVivas = categoriasConCatalogoTodas})` — desaparece `kind`.
- Bloques, en este orden, encima del buscador de categorías: `SectionHeader(text: 'UBICACIÓN')` + `DropdownButtonFormField<String?>` («Todas las ciudades» = `null`, `filledField(context, 'Ciudad')`); `SectionHeader('PRECIO')` + dos `TextField` numéricos (`keyboardType: number`, `FilteringTextInputFormatter.digitsOnly`, `filledField` «Desde RD$» / «Hasta RD$»); `SectionHeader('PROVEEDOR')` + `SwitchListTile` «Solo verificados» y «Con local». Debajo, `SectionHeader('CATEGORÍAS')` y lo de hoy. Botón inferior «Aplicar» (`FilledButton`, ancho completo, `SafeArea`) que devuelve el resultado con la categoría/rubro seleccionados en el acordeón **o los que venían**; tocar un rubro sigue cerrando la hoja al instante (como hoy) devolviendo también los otros filtros. «Limpiar» ⇒ `CatalogFilterResult.limpio()`.

- [ ] **Step 1: Test** (añadir a `catalog_filter_sheet_test.dart`, siguiendo el `host` y la apertura que ya usa ese fichero):

```dart
testWidgets('los bloques nuevos viajan en el resultado y Limpiar los apaga', (tester) async {
  CatalogFilterResult? res;
  await tester.pumpWidget(host(Builder(builder: (ctx) => TextButton(onPressed: () async {
    res = await showCatalogFilterSheet(ctx, ciudades: const ['Santiago'], filtros: kSinFiltros, categoriasVivas: () async => null);
  }, child: const Text('abrir')))));
  await tester.tap(find.text('abrir')); await tester.pumpAndSettle();
  expect(find.text('Ubicación'), findsOneWidget); expect(find.text('Precio'), findsOneWidget); expect(find.text('Proveedor'), findsOneWidget);
  await tester.tap(find.text('Solo verificados')); await tester.pump();
  await tester.enterText(find.widgetWithText(TextField, 'Desde RD$'), '5000');
  await tester.tap(find.text('Aplicar')); await tester.pumpAndSettle();
  expect(res!.soloVerificados, isTrue); expect(res!.precioMin, 5000); expect(res!.ciudad, isNull);
});
```

(Si `SectionHeader` pinta en mayúsculas, buscar por `textContaining` sin distinguir mayúsculas o por el texto tal como se pinta.)

- [ ] **Step 2:** FAIL. **Step 3:** implementar (tests existentes del fichero: actualizar la firma sin `kind`). **Step 4:** gates. **Step 5: Commit** — `feat(app): la hoja Filtrar gana Ubicación, Precio y Proveedor y devuelve todos los filtros`.

---

### Task 6: Secciones y tarjeta de proveedor (`catalog_secciones.dart`)

**Files:**
- Create: `lib/features/client/catalog_secciones.dart`; Test: `test/catalog_secciones_test.dart`

**Interfaces (produce):**
- `CatalogSecciones({required List<Map<String, dynamic>> items, required Map<String, BusinessCardInfo> negocios, required List<Proveedor> proveedores, required ({int productos, int servicios, int paquetes, int proveedores}) conteos, required ValueChanged<String> onVerTodos, required ValueChanged<String> onStore, Widget? header, ScrollController? controller})` — `ListView` con `?header` arriba, secciones en orden Proveedores → Productos → Servicios → Paquetes (`seccionesCatalogo(items)`), `padding.bottom = 12 + navBarReservedSpace`.
- `SeccionTitulo(titulo, {int? n, VoidCallback? onMore})` (movida desde `catalog_portada.dart`, gana `n`: gris 11.5 w500 tras el título; el enlace dice «Ver todos»).
- `_StoreCircle` (movida) gana `linea: String?` (qué hace o «Tienda física» en teal si no hay qué hace; 9.5 gris, 1 línea).
- `ProveedorCard({required Proveedor p, required VoidCallback onTap})` — `JayaloCard` fila: logo 44 (o inicial), nombre 14 w600, «Verificado» 11 w600 `JayaloColors.success` con `Icons.verified` 13 si `verificado`, `queHace` 12 gris si no vacío, fila «Tienda física» (teal) · ciudad 11, chevron a la derecha.
- `ProveedoresCoinciden({required List<Proveedor> proveedores, required ValueChanged<String> onStore})` — `Wrap` de píldoras (logo 20 + nombre 12 w600), etiqueta «Proveedores que coinciden:»; `SizedBox.shrink()` si vacío.
- Carruseles: `SingleChildScrollView` horizontal + `IntrinsicHeight`/`stretch` (como `_Carrusel` de hoy) con `ProductCarouselCard(showTypeTag: true, width: 150)`.

- [ ] **Step 1: Test** — `test/catalog_secciones_test.dart` (viewport 400×1600 con la función `alto()` de `catalog_portada_test.dart`):

```dart
testWidgets('cuatro secciones en orden fijo, con conteo y Ver todos; sección vacía no se pinta', (tester) async {
  alto(tester);
  final items = [item('p1'), item('s1', kind: 'servicio')]; // sin paquetes
  final negocios = {'b1': biz('getto', local: true)};
  final proveedores = proveedoresDeItems(items, {'b1': negocioCatalogoDe(negocios['b1']!)});
  String? verTodos;
  await tester.pumpWidget(host(CatalogSecciones(items: items, negocios: negocios, proveedores: proveedores, conteos: (productos: 1, servicios: 1, paquetes: 0, proveedores: 1), onVerTodos: (t) => verTodos = t, onStore: (_) {})));
  await tester.pumpAndSettle();
  final titulos = tester.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && ['Proveedores', 'Productos', 'Servicios', 'Paquetes'].contains(w.data))).map((t) => t.data).toList();
  expect(titulos, ['Proveedores', 'Productos', 'Servicios']);
  await tester.tap(find.text('Ver todos').at(2));
  expect(verTodos, 'servicio');
});
testWidgets('ProveedorCard pinta Verificado y Tienda física', (tester) async {
  await tester.pumpWidget(host(ProveedorCard(p: (id: 'b', name: 'Dra', logoUrl: null, hasPhysicalLocation: true, city: 'Santiago', verificado: true, queHace: 'Medicina general'), onTap: () {})));
  expect(find.text('Verificado'), findsOneWidget);
  expect(find.textContaining('Tienda física'), findsOneWidget);
  expect(find.text('Medicina general'), findsOneWidget);
});
```

- [ ] **Step 2:** FAIL. **Step 3:** implementar (no borrar aún `catalog_portada.dart`: la Task 7 lo hace). **Step 4:** gates. **Step 5: Commit** — `feat(app): secciones Proveedores/Productos/Servicios/Paquetes con tarjeta de proveedor`.

---

### Task 7: Cableado de `CatalogView` y borrado de la portada

**Files:**
- Modify: `lib/features/client/catalog_screen.dart`, `lib/features/shared/onboarding_copy.dart`, `test/catalog_screen_test.dart`
- Delete: `lib/features/client/catalog_portada.dart`, `lib/features/client/catalog_portada_secciones.dart`, `test/catalog_portada_test.dart`, `test/catalog_portada_secciones_test.dart`

**Cambios en `CatalogView`:**
1. Firmas inyectables: `CatalogFetch` pasa a `({String? kind, String? search, String? categoryId, String? rubro, bool wholesale, bool conPaquetes})` y por defecto `catalogItemsWithRatings`; `CatalogCountsFetch` pasa a `Future<Map<String, int>?> Function()` con defecto `categoryCountsUnion`; nuevo `CatalogNamesFetch = Future<List<Proveedor>> Function(String term)` con defecto `catalogBusinessesByName`.
2. Estado: fuera `_kind`, `_verTodo`; entran `_tipo = 'todos'`, `_filtros = kSinFiltros`. `_verSecciones => _tipo == 'todos' && _search == null && !_wholesale`. `_fetchPage` pide `kind: _wholesale ? 'producto' : null, conPaquetes: !_wholesale && _categoryId == null && _rubro == null` y además, si `_search != null`, `widget.names(_search!)` (best-effort, `catchError` ⇒ `[]`) → `CatalogPage` gana `nombres: List<Proveedor>`.
3. Derivados en `build` (funciones puras): `negociosCat = {for (e in page.negocios.entries) e.key: negocioCatalogoDe(e.value)}`; `hits = ordenarCatalogo(filtrarLateral(page.items, negociosCat, _filtros))`; `proveedores = proveedoresDeItems(hits, negociosCat, tope: 90)`; `conteos`; `hitsDeTipo` (por `tipoDeItem`, todos si `_tipo == 'todos'`); `hayQuePintar = _tipo == 'proveedor' ? proveedores.isNotEmpty : hitsDeTipo.isNotEmpty`; `ciudades = ciudadesDe(negociosCat, seleccionada: _filtros.ciudad)`; `coinciden` = `page.nombres` + proveedores de los ítems cuyo nombre coincide con `_search`, sin repetidos.
4. Cabecera: fuera `HeaderSegmented` y su `SizedBox`; `actions: widget.actions`. Píldora «Filtrar»: etiqueta = nombre de categoría, o «Filtrar · n» con n = filtros del lateral activos, o «Filtrar»; `onClear` limpia categoría/rubro; `_openFilter` pasa `ciudades`, `_filtros` y aplica el resultado completo.
5. `_chips()` = `Column(children: [CatalogTipoStrip(tipo: _tipo, conteos: {...}, onTipo: _setTipo), CatalogChipStrip(... wholesale: _tipo == 'todos' || _tipo == 'producto' ? _wholesale : null, rubros: _categoryId == null ? [] : rubrosDe(_categoryId) …)])`. Los rubros vienen de `rubrosForCategories([_categoryId])` cargados al elegir categoría (estado `_rubros`, best-effort).
6. Cuerpo: `_verSecciones ? CatalogSecciones(header: _chips(), items: hits, …, onVerTodos: _setTipo, onStore: (id) => context.push('/store/$id')) : _tipo == 'proveedor' ? _listaProveedores(proveedores) : _rejilla(hitsDeTipo)`; la rejilla usa `ProductGridCard(showTypeTag: true)` y `catalogGridCardExtent(context, cellWidth, conIncluido: _tipo == 'paquete')`; con `_search != null`, `ProveedoresCoinciden` encima de la rejilla (como `SliverToBoxAdapter`).
7. Vacío: `!hayQuePintar` ⇒ `_vacio()` con el copy por tipo; `_filtrado` pasa a `_tipo != 'todos' || _categoryId != null || _rubro != null || _search != null || _wholesale || _filtros != kSinFiltros`; `_quitarTodo` resetea también `_tipo` y `_filtros`. `_setTipo` no re-pide (misma carga); `_toggleWholesale` sí.
8. `onboarding_copy.dart`: `'client.catalog.v1'` → «Aquí ves productos, servicios y paquetes que los proveedores ofrecen en sus tiendas.»
9. `catalog_screen_test.dart`: quitar `kindSegmented()` y los tests del toggle; `vacio` con la nueva firma (`String? kind`, `bool conPaquetes = true`); añadir: «con ítems de los tres tipos pinta las cuatro secciones en orden», «Ver todos de Paquetes deja la rejilla de paquetes», «Proveedores muestra la lista», «Quitar filtro vuelve a Todos». Viewport 400×1600.

- [ ] **Step 1:** Escribir/ajustar los tests de `catalog_screen_test.dart` → FAIL. **Step 2:** implementar 1–8 y borrar los cuatro ficheros de la portada (`git rm`); `grep -rn "catalog_portada\|CatalogPortada\|HeaderSegmented" lib test` solo debe encontrar `HeaderSegmented` en `violet_header.dart` y en pantallas que no son el catálogo. **Step 3:** `flutter analyze` 0 · `flutter test` verde · `dart format`; `catalog_screen.dart` ≤ 520 líneas. **Step 4: Commit** — `feat(app): catálogo por artículos — chips de tipo, filtros, secciones y paquetes en la pestaña Catálogo`.

---

### Task 8: APK, captura, docs

**Files:** `pubspec.yaml`, `CLAUDE.md` (del repo app, sección catálogo).

- [ ] **Step 1:** `flutter analyze` 0 · `flutter test --reporter=compact | tail -3` (anotar) · `dart format --set-exit-if-changed lib test`.
- [ ] **Step 2:** `grep ^version: pubspec.yaml` → subir el build en +1 (`1.0.4+125` si sigue en 124) y commit `chore(app): 1.0.4+125 — catálogo por artículos`.
- [ ] **Step 3:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; `aapt dump badging … | grep versionCode` = 125. Copiar a `C:/Users/ac/Downloads/jayalo-1.0.4+125-catalogo-articulos.apk`.
- [ ] **Step 4:** Si hay un teléfono en `adb devices`: `adb install -r` → `adb shell dumpsys package com.jayalo.app | grep versionCode` → abrir la app, `adb shell cmd statusbar collapse`, `adb shell input tap 400 2436` (pestaña Catálogo en 1220×2712) → `adb exec-out screencap -p > catalogo-125.png` y una segunda captura tras tocar «Paquetes». Si no hay teléfono, dejar el APK en Descargas y decirlo.
- [ ] **Step 5:** `CLAUDE.md` (app): sustituir el bloque de la portada del 09-05 por: «Catálogo por artículos (PO 2026-09-08, espejo de la web): `catalog_articulos.dart` (puro), `catalog_tipo_strip.dart`, `catalog_secciones.dart`; secciones en orden fijo Proveedores → Productos → Servicios → Paquetes; paquetes vía `catalogPackages()` best-effort mapeados con `paqueteComoItem` (`kind: 'paquete'`, precio 0 = Consultar); filtros del lateral web en la hoja Filtrar; sin banner ni cierre con CTA (la solicitud vive en el «+»).» Commit `docs(app): CLAUDE.md — catálogo por artículos`.
- [ ] **Step 6:** `git push -u origin feat/catalogo-articulos-app`. NO mergear al tronco: lo decide el PO tras el smoke.

---

## Self-review

- **Cobertura de la spec:** §2.1 cabecera sin segmentado → T7.4; §2.2 estado → T7.2; §2.3 chips → T4 + T7.5; §2.4 hoja → T5; §2.5 secciones → T6 + T7.6; §2.6 rejillas y proveedores → T6 + T7.6; §2.7 tarjetas → T3; §2.8 datos y puro → T1 + T2; §2.9 búsqueda/vacío → T7.3/7.7; §2.10 onboarding → T7.8; §3 borrado → T7; §4 verificación → T8. Sin banner/cierre: por omisión deliberada (restricción global).
- **Consistencia de nombres:** `paqueteComoItem`, `tipoDeItem`, `filtrarLateral`, `ordenarCatalogo`, `seccionesCatalogo`, `resumenConteos`, `ciudadesDe`, `coincideBusqueda`, `sumarConteos`, `sanitizarIlike`, `queHace`, `proveedoresDeItems`, `NegocioCatalogo`, `Proveedor`, `FiltrosLateral`, `kSinFiltros`, `kTopeCarrusel`, `kTopeProveedores` (T1) — usados así en T2, T5, T6, T7. `negocioCatalogoDe`, `catalogPackages`, `catalogBusinessesByName`, `catalogItemsWithRatings`, `categoryCountsUnion`, `categoriasConCatalogoTodas` (T2) — usados en T5 y T7. `showTypeTag`, `catalogImage(logoUrl:)`, `catalogTypeBadge`, `catalogGridCardExtent(conIncluido:)` (T3) — usados en T6/T7. `CatalogChip` compartido (T4) — usado por ambas tiras. `CatalogFilterResult` ampliado y `showCatalogFilterSheet` sin `kind` (T5) — usado en T7.
- **Deuda declarada:** la búsqueda de paquetes es en cliente sobre 30; los conteos de tipo son del conjunto cargado; sin paginación de «Ver todos».
