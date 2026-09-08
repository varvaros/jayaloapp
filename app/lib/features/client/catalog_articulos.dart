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
  return fotos is List &&
      fotos.isNotEmpty &&
      (fotos.first as String).trim().isNotEmpty;
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
  if (f.ciudad != null && (b?.city?.trim() ?? '') != f.ciudad) return false;
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
  return (
    productos: de('producto'),
    servicios: de('servicio'),
    paquetes: de('paquete'),
  );
}

String _plural(int n, String uno, String varios) =>
    '$n ${n == 1 ? uno : varios}';

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
List<String> ciudadesDe(
  Map<String, NegocioCatalogo> negocios, {
  String? seleccionada,
}) {
  final set = <String>{
    for (final b in negocios.values)
      if (b.city != null && b.city!.trim().isNotEmpty) b.city!.trim(),
    if (seleccionada != null && seleccionada.trim().isNotEmpty)
      seleccionada.trim(),
  };
  final lista = set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return lista;
}

const _acentos = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'ñ': 'n',
};

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
          queHace: queHace(
            b.description,
            dominante == null ? null : categoryNameById(dominante),
          ),
        );
      }(),
  ];
}
