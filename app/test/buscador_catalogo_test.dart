import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/buscador_catalogo.dart';

/// Respuesta de `buscar_catalogo` tal y como la devuelve PostgREST: todo son
/// tipos de JSON (`List<dynamic>`, `num`), nunca los tipos de Dart que la
/// pantalla espera. Calcada de la que da prod para «cable» (migraciones
/// `20260920213736` + las tres del 09-21).
Map<String, dynamic> _respuesta({
  String termino = 'cable',
  String? corregidoA,
  String? motivo,
  List<dynamic> rubros = const [],
  List<dynamic> items = const [],
  int total = 0,
  List<dynamic> directos = const [],
  List<dynamic> vendedores = const [],
  List<dynamic> probables = const [],
}) => {
  'termino': termino,
  'corregido_a': corregidoA,
  'motivo': motivo,
  'rubros': rubros,
  'categorias': const [],
  'articulos': {
    'total': total,
    'pagina': 0,
    'por_pagina': 48,
    'items': items,
  },
  'negocios_directos': directos,
  'vendedores': vendedores,
  'negocios_probables': probables,
};

Map<String, dynamic> _articulo({
  String id = 'p1',
  String name = 'Cable USB',
  String businessId = 'b1',
}) => {
  'id': id,
  'name': name,
  'description': 'Cable de 2 metros',
  'price': 350,
  'price_min': null,
  'price_max': null,
  'kind': 'producto',
  'category_id': 'electronica',
  'rubro': 'Cables y conectores',
  'image_urls': <dynamic>['https://x/1.jpg'],
  'brand': null,
  'condition': 'nuevo',
  'business_id': businessId,
  'business_name': 'Ferretería Don Pepe',
  'created_at': '2026-09-20T10:00:00Z',
  'puntos': 70,
};

Map<String, dynamic> _negocio({
  String id = 'b1',
  String name = 'Ferretería Don Pepe',
  bool verificado = false,
  String? description = 'Ferretería del barrio',
}) => {
  'id': id,
  'name': name,
  'logo_url': null,
  'city': 'Santiago',
  'category_id': 'ferreteria',
  'offers': 'productos',
  'has_physical_location': true,
  'verificado': verificado,
  'description': description,
};

void main() {
  group('busquedaDeJson — artículos', () {
    test('trae los ítems con los tipos que pinta la tarjeta', () {
      final b = busquedaDeJson(
        _respuesta(items: [_articulo()], total: 1),
      );
      expect(b.items, hasLength(1));
      final it = b.items.single;
      expect(it['id'], 'p1');
      expect(it['name'], 'Cable USB');
      expect(it['kind'], 'producto');
      // `image_urls` llega como List<dynamic> y la tarjeta hace
      // `as List<String>`: sin el cast explícito revienta en tiempo de
      // ejecución, no al compilar.
      expect(it['image_urls'], isA<List<String>>());
      expect(it['image_urls'], ['https://x/1.jpg']);
      expect(b.total, 1);
    });

    test('un ítem sin fotos trae una lista vacía, nunca null', () {
      final sinFoto = _articulo()..['image_urls'] = null;
      final b = busquedaDeJson(_respuesta(items: [sinFoto], total: 1));
      expect(b.items.single['image_urls'], isA<List<String>>());
      expect(b.items.single['image_urls'], isEmpty);
    });
  });

  group('busquedaDeJson — rubros y corrección', () {
    test('conserva el orden que decidió el resolutor', () {
      final b = busquedaDeJson(
        _respuesta(
          rubros: [
            {
              'id': 'r9',
              'name': 'Cables y conectores',
              'category_id': 'electronica',
              'kind': 'producto',
              'puntos': 85,
              'via': 'producto',
            },
            {
              'id': 'r3',
              'name': 'Electricidad',
              'category_id': 'ferreteria',
              'kind': 'producto',
              'puntos': 60,
              'via': 'sinonimo',
            },
          ],
        ),
      );
      expect([for (final r in b.rubros) r.name], [
        'Cables y conectores',
        'Electricidad',
      ]);
      expect(b.rubros.first.id, 'r9');
      expect(b.rubros.first.categoryId, 'electronica');
    });

    test('«corregido_a» viaja tal cual para la línea de la pantalla', () {
      final b = busquedaDeJson(
        _respuesta(termino: 'libreta', corregidoA: 'libretas'),
      );
      expect(b.termino, 'libreta');
      expect(b.corregidoA, 'libretas');
    });
  });

  group('busquedaDeJson — negocios', () {
    test('el mapa por id junta directos, vendedores y probables', () {
      final b = busquedaDeJson(
        _respuesta(
          directos: [_negocio(id: 'b1')],
          vendedores: [_negocio(id: 'b2', name: 'Eléctrica RD')],
          probables: [_negocio(id: 'b3', name: 'Casa Cable')],
        ),
      );
      expect(b.negocios.keys, containsAll(['b1', 'b2', 'b3']));
      expect(b.negocios['b2']!.name, 'Eléctrica RD');
      expect(b.negocios['b1']!.city, 'Santiago');
      expect(b.negocios['b1']!.hasPhysicalLocation, isTrue);
    });

    test('el «verificado» único del RPC es identidad Y negocio, no whatsapp', () {
      final b = busquedaDeJson(_respuesta(directos: [_negocio(verificado: true)]));
      final n = b.negocios['b1']!;
      // El sello verde de la app = identidad O negocio (`negocioCatalogoDe`).
      // El RPC no distingue cuál de los dos trámites se completó y NO dice
      // nada de whatsapp, así que ese se queda en falso a propósito.
      expect(n.identityVerified, isTrue);
      expect(n.businessVerified, isTrue);
      expect(n.whatsappVerified, isFalse);
    });

    test('los directos salen como Proveedor con su línea gris', () {
      final b = busquedaDeJson(_respuesta(directos: [_negocio()]));
      expect(b.directos, hasLength(1));
      expect(b.directos.single.id, 'b1');
      expect(b.directos.single.queHace, 'Ferretería del barrio');
      expect(b.probables, isEmpty);
    });

    test('un probable sin descripción no inventa línea gris', () {
      final b = busquedaDeJson(
        _respuesta(probables: [_negocio(id: 'b3', description: null)]),
      );
      expect(b.probables.single.queHace, isEmpty);
    });

    test('un vendedor NO es un negocio directo: no sale en la tira', () {
      final b = busquedaDeJson(
        _respuesta(vendedores: [_negocio(id: 'b2')]),
      );
      expect(b.directos, isEmpty);
      expect(b.negocios.containsKey('b2'), isTrue);
    });
  });

  group('busquedaDeJson — respuesta corta', () {
    test('«termino_corto» no revienta y devuelve todo vacío', () {
      final b = busquedaDeJson(_respuesta(termino: 'c', motivo: 'termino_corto'));
      expect(b.motivo, 'termino_corto');
      expect(b.items, isEmpty);
      expect(b.rubros, isEmpty);
      expect(b.negocios, isEmpty);
      expect(b.total, 0);
    });
  });

  group('conPaquetesQueCasan — los paquetes no se pierden al buscar', () {
    Map<String, dynamic> paquete({
      String id = 'k1',
      String name = 'Combo cable + cargador',
      String? description,
      List<String> items = const [],
    }) => {
      'id': id,
      'user_id': 'u1',
      'business_id': 'b9',
      'name': name,
      'description': description,
      'price': 1200,
      'items': items,
      'image_url': null,
      'created_at': '2026-09-01T00:00:00Z',
    };

    test('un paquete cuyo NOMBRE casa se suma a los artículos del RPC', () {
      final out = conPaquetesQueCasan(
        [_articulo()],
        [paquete()],
        'cable',
      );
      expect(out, hasLength(2));
      expect(out.first['id'], 'p1', reason: 'los artículos del RPC van primero');
      expect(out.last['kind'], 'paquete');
      expect(out.last['image_urls'], isA<List<String>>());
    });

    test('casa por descripción y por un ítem suelto del paquete', () {
      final porDescripcion = conPaquetesQueCasan(
        const [],
        [paquete(description: 'Incluye un cable de red')],
        'cable',
      );
      expect(porDescripcion, hasLength(1));
      final porItem = conPaquetesQueCasan(
        const [],
        [paquete(name: 'Combo', items: const ['Cable HDMI'])],
        'cable',
      );
      expect(porItem, hasLength(1));
    });

    test('el que no casa se queda fuera, y las tildes no estorban', () {
      expect(
        conPaquetesQueCasan(const [], [paquete(name: 'Combo sillas')], 'cable'),
        isEmpty,
      );
      expect(
        conPaquetesQueCasan(
          const [],
          [paquete(name: 'Combo Instalación')],
          'instalacion',
        ),
        hasLength(1),
      );
    });
  });

  group('buscaPorRpc — cuándo manda el buscador nuevo', () {
    test('con término y sin filtros de servidor, manda la RPC', () {
      expect(buscaPorRpc(search: 'cable'), isTrue);
    });

    test('sin término no hay búsqueda que hacer', () {
      expect(buscaPorRpc(search: null), isFalse);
    });

    test('categoría, rubro o mayoreo devuelven el mando al camino viejo', () {
      // `buscar_catalogo` no acepta filtro de categoría/rubro/mayoreo, y
      // recortarlos en cliente mentiría sobre `total`.
      expect(buscaPorRpc(search: 'cable', categoryId: 'ferreteria'), isFalse);
      expect(buscaPorRpc(search: 'cable', rubro: 'Cables'), isFalse);
      expect(buscaPorRpc(search: 'cable', wholesale: true), isFalse);
    });
  });
}
