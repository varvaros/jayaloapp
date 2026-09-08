import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart';

NegocioCatalogo neg(
  String name, {
  bool local = false,
  bool verif = false,
  String? city,
  String? desc,
  String? logo,
}) => (
  name: name,
  logoUrl: logo,
  hasPhysicalLocation: local,
  verificado: verif,
  description: desc,
  city: city,
);
Map<String, dynamic> item(
  String id, {
  String? biz = 'b1',
  String? cat = 'electronica',
  String kind = 'producto',
  num? price = 100,
  num? min,
  List<String> fotos = const ['https://x/1.jpg'],
}) => {
  'id': id,
  'business_id': biz,
  'category_id': cat,
  'kind': kind,
  'price': price,
  'price_min': min,
  'price_max': null,
  'image_urls': fotos,
  'name': 'Artículo $id',
};

void main() {
  group('paqueteComoItem', () {
    final row = {
      'id': 'k1',
      'user_id': 'u',
      'business_id': 'b1',
      'name': 'Chicha',
      'description': '',
      'price': 3000,
      'items': ['4 chichas', '3 vasos'],
      'image_url': 'https://x/c.jpg',
      'created_at': '2026-08-09',
    };
    test('mapea al ítem del catálogo', () {
      final it = paqueteComoItem(row);
      expect(it['kind'], 'paquete');
      expect(it['image_urls'], ['https://x/c.jpg']);
      expect(it['items'], ['4 chichas', '3 vasos']);
      expect(it['category_id'], '');
      expect(it['price'], 3000);
    });
    test(
      'precio 0 pasa a null (Consultar precio) y sin foto image_urls vacío',
      () {
        final it = paqueteComoItem({...row, 'price': 0, 'image_url': null});
        expect(it['price'], isNull);
        expect(it['image_urls'], isEmpty);
      },
    );
  });

  test('tipoDeItem: kind nulo es producto', () {
    expect(tipoDeItem({'kind': null}), 'producto');
    expect(tipoDeItem({'kind': 'servicio'}), 'servicio');
    expect(tipoDeItem({'kind': 'paquete'}), 'paquete');
  });

  group('filtrarLateral', () {
    final negocios = {
      'b1': neg('getto', local: true, city: 'Santo Domingo Este'),
      'b2': neg('Dra', verif: true, city: 'Santiago'),
    };
    final a = item('a', price: 500);
    final b = item('b', biz: 'b2', price: null, min: 6000);
    final c = item('c', kind: 'paquete', price: null);
    test(
      'sin filtro devuelve todo',
      () => expect(
        filtrarLateral([a, b, c], negocios, kSinFiltros),
        hasLength(3),
      ),
    );
    test(
      'ciudad',
      () => expect(
        filtrarLateral(
          [a, b],
          negocios,
          (
            ciudad: 'Santiago',
            precioMin: 0,
            precioMax: 0,
            soloVerificados: false,
            conLocal: false,
          ),
        ).map((e) => e['id']),
        ['b'],
      ),
    );
    test(
      'ciudad con espacio final en la BD igual pasa el filtro recortado',
      () {
        final conEspacio = {
          ...negocios,
          'b2': neg('Dra', verif: true, city: 'Santiago '),
        };
        expect(
          filtrarLateral(
            [a, b],
            conEspacio,
            (
              ciudad: 'Santiago',
              precioMin: 0,
              precioMax: 0,
              soloVerificados: false,
              conLocal: false,
            ),
          ),
          hasLength(1),
        );
      },
    );
    test('precio usa price o price_min; Consultar siempre pasa', () {
      expect(
        filtrarLateral(
          [a, b, c],
          negocios,
          (
            ciudad: null,
            precioMin: 1000,
            precioMax: 0,
            soloVerificados: false,
            conLocal: false,
          ),
        ).map((e) => e['id']),
        ['b', 'c'],
      );
      expect(
        filtrarLateral(
          [a, b, c],
          negocios,
          (
            ciudad: null,
            precioMin: 0,
            precioMax: 1000,
            soloVerificados: false,
            conLocal: false,
          ),
        ).map((e) => e['id']),
        ['a', 'c'],
      );
    });
    test('verificados y con local', () {
      expect(
        filtrarLateral(
          [a, b],
          negocios,
          (
            ciudad: null,
            precioMin: 0,
            precioMax: 0,
            soloVerificados: true,
            conLocal: false,
          ),
        ).map((e) => e['id']),
        ['b'],
      );
      expect(
        filtrarLateral(
          [a, b],
          negocios,
          (
            ciudad: null,
            precioMin: 0,
            precioMax: 0,
            soloVerificados: false,
            conLocal: true,
          ),
        ).map((e) => e['id']),
        ['a'],
      );
    });
  });

  test('ordenarCatalogo: con foto antes que sin foto, estable', () {
    final r = ordenarCatalogo([
      item('s', fotos: const []),
      item('f1'),
      item('f2'),
      item('t', fotos: const []),
    ]);
    expect(r.map((e) => e['id']), ['f1', 'f2', 's', 't']);
  });

  test('seccionesCatalogo reparte por kind y recorta a kTopeCarrusel', () {
    final items = [
      for (var i = 0; i < 10; i++) item('p$i'),
      item('s1', kind: 'servicio'),
      item('k1', kind: 'paquete'),
    ];
    final s = seccionesCatalogo(items);
    expect(s.productos, hasLength(kTopeCarrusel));
    expect(s.servicios.map((e) => e['id']), ['s1']);
    expect(s.paquetes.map((e) => e['id']), ['k1']);
  });

  test('resumenConteos con singulares', () {
    expect(
      resumenConteos(productos: 7, servicios: 1, paquetes: 0, proveedores: 8),
      '7 productos · 1 servicio · 0 paquetes · 8 proveedores',
    );
    expect(
      resumenConteos(productos: 1, servicios: 0, paquetes: 1, proveedores: 1),
      '1 producto · 0 servicios · 1 paquete · 1 proveedor',
    );
  });

  test(
    'ciudadesDe: distintas, ordenadas, y la seleccionada nunca se pierde',
    () {
      final negocios = {
        'a': neg('x', city: 'Santo Domingo Este'),
        'b': neg('y', city: 'Santiago'),
        'c': neg('z', city: null),
      };
      expect(ciudadesDe(negocios), ['Santiago', 'Santo Domingo Este']);
      expect(ciudadesDe(negocios, seleccionada: 'La Romana'), [
        'La Romana',
        'Santiago',
        'Santo Domingo Este',
      ]);
    },
  );

  test('coincideBusqueda sin acentos ni mayúsculas', () {
    expect(coincideBusqueda('Instalación de aire', 'instalacion'), isTrue);
    expect(coincideBusqueda('Chicha', 'mouse'), isFalse);
    expect(coincideBusqueda('lo que sea', ''), isTrue);
  });

  test('sumarConteos une por id y tolera null', () {
    expect(sumarConteos({'a': 1, 'b': 2}, {'b': 3, 'c': 1}), {
      'a': 1,
      'b': 5,
      'c': 1,
    });
    expect(sumarConteos(null, {'a': 1}), {'a': 1});
    expect(sumarConteos(null, null), isEmpty);
  });

  test('sanitizarIlike quita comodines y operadores', () {
    expect(sanitizarIlike(' ge%t_to,(*) '), 'getto');
  });

  group('queHace y proveedoresDeItems', () {
    test(
      'descripción corta, recorte por palabra, categoría dominante, nada',
      () {
        expect(
          queHace('Electrónica y eventos', 'Salud'),
          'Electrónica y eventos',
        );
        expect(
          queHace(
            'Vendemos de todo para el hogar y también instalamos aires',
            'Hogar',
          ),
          'Vendemos de todo para el hogar y también…',
        );
        expect(queHace('', 'Salud y bienestar'), 'Salud y bienestar');
        expect(queHace(null, null), '');
      },
    );
    test(
      'negocios distintos en orden de aparición, verificado y categoría dominante; tope',
      () {
        final negocios = {
          'b1': neg('getto', local: true),
          'b2': neg('Dra', verif: true, city: 'Santiago'),
        };
        final ps = proveedoresDeItems([
          item('1', cat: 'salud'),
          item('2', biz: 'b2'),
          item('3', cat: 'electronica'),
          item('4', cat: 'electronica'),
        ], negocios);
        expect(ps.map((p) => p.id), ['b1', 'b2']);
        expect(ps[0].queHace, 'Electrónica');
        expect(ps[0].verificado, isFalse);
        expect(ps[1].verificado, isTrue);
        expect(ps[1].city, 'Santiago');
        final muchos = [for (var i = 0; i < 15; i++) item('i$i', biz: 'n$i')];
        final n = {for (var i = 0; i < 15; i++) 'n$i': neg('N$i')};
        expect(proveedoresDeItems(muchos, n), hasLength(kTopeProveedores));
      },
    );
    test('ignora ítems sin negocio resuelto', () {
      expect(proveedoresDeItems([item('x', biz: 'nope')], const {}), isEmpty);
    });
  });
}
