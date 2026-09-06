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
