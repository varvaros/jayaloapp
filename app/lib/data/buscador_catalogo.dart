/// El buscador del catálogo, el mismo que la web (`/buscar`).
///
/// La app buscaba con `like('search_norm', '%termino%')` sobre
/// `provider_products` (`repos.dart`, `catalogProducts`): sin vocabulario, sin
/// rubros y sin corrección de tecleo — «cable» traía la máquina de pelar «con
/// cable» y «lavadora» no traía nada. La web resolvió eso el 09-20/09-21 con
/// la RPC pública `buscar_catalogo`, que ya está VIVA en producción; aquí solo
/// se consume. No hace falta ninguna migración para esto.
///
/// Este fichero es la frontera: traduce el JSON de la RPC a los tipos que la
/// pantalla ya sabe pintar ([BusinessCardInfo], [Proveedor], y el mapa suelto
/// de cada artículo). [busquedaDeJson] es PURA a propósito — es lo que se
/// puede probar sin red.
library;

import '../features/client/catalog_articulos.dart' show Proveedor, queHace;
import 'repos.dart' show BusinessCardInfo, supa;

/// Un rubro que el resolutor dio por entendido («Entendido como» en la web).
/// Se pinta como chip: al tocarlo, el catálogo se filtra por él.
typedef RubroSugerido = ({
  String id,
  String name,
  String? categoryId,
  String? kind,
});

/// Todo lo que devuelve una búsqueda, ya traducido.
typedef BusquedaCatalogo = ({
  /// El término ya plegado por el servidor (minúsculas, sin tildes).
  String termino,

  /// Lo que el servidor entendió cuando corrigió el tecleo, o nulo.
  String? corregidoA,

  /// `termino_corto` cuando el término mide menos de 2 caracteres.
  String? motivo,
  List<RubroSugerido> rubros,
  List<Map<String, dynamic>> items,

  /// Cuántos artículos casaron (tapado a 200 por el servidor, a propósito).
  int total,

  /// Cabeceras de TODOS los negocios de la respuesta (directos, vendedores de
  /// los artículos y probables), por id — es lo que consume la tarjeta.
  Map<String, BusinessCardInfo> negocios,

  /// Negocios que casan con la búsqueda por sí mismos.
  List<Proveedor> directos,

  /// Negocios de la misma categoría que no casaron directamente.
  List<Proveedor> probables,
});

List<Map<String, dynamic>> _filas(dynamic v) => [
  for (final r in (v as List? ?? const []))
    Map<String, dynamic>.from(r as Map),
];

/// PostgREST entrega `text[]` como `List<dynamic>`, y la tarjeta hace
/// `as List<String>`: sin este cast el fallo sale en tiempo de EJECUCIÓN.
/// Un artículo sin fotos trae lista vacía, nunca nulo.
List<String> _fotos(dynamic v) => [
  for (final u in (v as List? ?? const [])) u as String,
];

/// La fila de artículo de la RPC con los tipos que espera la tarjeta.
///
/// La RPC no devuelve `user_id`, `offers_shipping`, `color` ni
/// `offer_defaults` (sí están en `catalogProductCols`). Medido el 09-21: no
/// los lee ninguna tarjeta del catálogo, y el detalle del producto vuelve a
/// consultar por id (`ProductDetailScreen(productId:)`), así que no falta
/// nada. `business_name` y `puntos` viajan de más: son inofensivos y ayudan a
/// depurar.
Map<String, dynamic> _articulo(Map<String, dynamic> row) => {
  ...row,
  'image_urls': _fotos(row['image_urls']),
};

/// El `verificado` único de la RPC contra los tres sellos de la app: el sello
/// verde de la app es «identidad O negocio» (`negocioCatalogoDe`) y la RPC no
/// distingue cuál de los dos trámites se completó, así que se encienden los
/// dos. De whatsapp la RPC no dice nada: se queda en falso.
BusinessCardInfo _cabecera(Map<String, dynamic> n) {
  final verificado = n['verificado'] == true;
  return (
    name: (n['name'] as String?) ?? '',
    logoUrl: n['logo_url'] as String?,
    whatsappVerified: false,
    identityVerified: verificado,
    businessVerified: verificado,
    hasPhysicalLocation: n['has_physical_location'] == true,
    description: n['description'] as String?,
    city: n['city'] as String?,
  );
}

Proveedor _proveedor(Map<String, dynamic> n) => (
  id: n['id'] as String,
  name: (n['name'] as String?) ?? '',
  logoUrl: n['logo_url'] as String?,
  hasPhysicalLocation: n['has_physical_location'] == true,
  city: n['city'] as String?,
  verificado: n['verificado'] == true,
  queHace: queHace(n['description'] as String?, null),
);

/// Traduce la respuesta cruda de `buscar_catalogo`. Pura: sin red.
BusquedaCatalogo busquedaDeJson(Map<String, dynamic> json) {
  final articulos = Map<String, dynamic>.from(
    (json['articulos'] as Map?) ?? const {},
  );
  final directos = _filas(json['negocios_directos']);
  final vendedores = _filas(json['vendedores']);
  final probables = _filas(json['negocios_probables']);
  return (
    termino: (json['termino'] as String?) ?? '',
    corregidoA: json['corregido_a'] as String?,
    motivo: json['motivo'] as String?,
    rubros: [
      for (final r in _filas(json['rubros']))
        (
          id: r['id'] as String,
          name: (r['name'] as String?) ?? '',
          categoryId: r['category_id'] as String?,
          kind: r['kind'] as String?,
        ),
    ],
    items: [for (final a in _filas(articulos['items'])) _articulo(a)],
    total: (articulos['total'] as num?)?.toInt() ?? 0,
    negocios: {
      for (final n in [...directos, ...vendedores, ...probables])
        n['id'] as String: _cabecera(n),
    },
    directos: [for (final n in directos) _proveedor(n)],
    probables: [for (final n in probables) _proveedor(n)],
  );
}

/// Llama a la RPC pública. `_por_pagina` va al TOPE del servidor (48): la
/// pantalla no pagina y hoy traía 60 de golpe con el LIKE, así que pedir 24
/// (el defecto de la RPC) acortaría la lista sin que nadie lo pidiera.
Future<BusquedaCatalogo> buscarCatalogo(
  String termino, {
  String? kind,
  String? ciudad,
  bool exacto = false,
}) async {
  final res = await supa.rpc(
    'buscar_catalogo',
    params: {
      '_q': termino,
      '_kind': kind,
      '_ciudad': ciudad,
      '_pagina': 0,
      '_por_pagina': 48,
      '_exacto': exacto,
    },
  );
  return busquedaDeJson(Map<String, dynamic>.from(res as Map));
}
