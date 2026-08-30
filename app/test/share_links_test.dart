import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/config.dart';
import 'package:jayalo_app/domain/share_links.dart';

void main() {
  group('URLs canónicas de jayalo.com', () {
    test('la solicitud apunta a /requests/{id}', () {
      final s = shareForRequest(id: 'req-1', title: 'Nevera de dos puertas')!;
      expect(s.url, '${AppConfig.siteUrl}/requests/req-1');
      expect(s.text, contains(s.url));
      expect(s.text, contains('Nevera de dos puertas'));
    });

    test('el producto apunta a /products/{id}', () {
      final s = shareForProduct(id: 'prod-1', name: 'Taladro')!;
      expect(s.url, '${AppConfig.siteUrl}/products/prod-1');
    });
  });

  group('sin id no hay enlace que compartir', () {
    test('null y vacío devuelven null', () {
      expect(shareForRequest(id: null, title: 'x'), isNull);
      expect(shareForRequest(id: '', title: 'x'), isNull);
      expect(shareForProduct(id: null, name: 'x'), isNull);
    });
  });

  group('lo que NO se comparte', () {
    test('no existe forma de compartir la tienda: su URL viviría bajo '
        '/provider, que `no_link_out_test` prohíbe (PayPal en ese panel)', () {
      // Si algún día se añade `shareForBusiness`, este test deja de compilar y
      // obliga a leer el porqué antes de reintroducir el link-out.
      final fuente = File('lib/domain/share_links.dart').readAsStringSync();
      expect(fuente.contains('/provider'), isTrue,
          reason: 'el módulo debe seguir documentando POR QUÉ no se comparte');
      expect(fuente.contains(r"'/provider/business/$"), isFalse,
          reason: 'nadie debe volver a construir una URL /provider');
    });
  });

  group('el texto que viaja a la hoja', () {
    test('el título se colapsa a una línea', () {
      final s = shareForRequest(
        id: 'r',
        title: '  Pintar   apartamento\n de 3 habitaciones  ',
      )!;
      expect(s.text, contains('Pintar apartamento de 3 habitaciones'));
      expect(s.text.split('\n').first, 'Pintar apartamento de 3 habitaciones');
    });

    test('un título larguísimo se recorta con puntos suspensivos', () {
      final largo = 'a' * 200;
      final s = shareForRequest(id: 'r', title: largo)!;
      final cabecera = s.text.split('\n').first;
      expect(cabecera.length, lessThanOrEqualTo(80));
      expect(cabecera.endsWith('…'), isTrue);
    });

    test('sin título el mensaje sigue teniendo sentido', () {
      final s = shareForRequest(id: 'r', title: '   ')!;
      expect(s.text.startsWith('Mira esta solicitud'), isTrue);
      expect(s.text, contains(s.url));
    });

  });
}
