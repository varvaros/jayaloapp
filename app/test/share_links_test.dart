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

    test('la tienda apunta a la vitrina — la excepción del guard de Play, que '
        'se sostiene porque la web la sirve sin superficies de pago', () {
      final s = shareForBusiness(id: 'biz-1', name: 'Ferretería La Económica')!;
      expect(s.url, '${AppConfig.siteUrl}/provider/business/biz-1');
    });
  });

  group('sin id no hay enlace que compartir', () {
    test('null y vacío devuelven null', () {
      expect(shareForRequest(id: null, title: 'x'), isNull);
      expect(shareForRequest(id: '', title: 'x'), isNull);
      expect(shareForProduct(id: null, name: 'x'), isNull);
      expect(shareForBusiness(id: '', name: 'x'), isNull);
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

    test('el proveedor comparte MI tienda; el cliente, SU tienda', () {
      final mia = shareForBusiness(id: 'b', name: 'Taller Pérez', own: true)!;
      final suya = shareForBusiness(id: 'b', name: 'Taller Pérez')!;
      expect(mia.text, contains('Mira mi tienda en Jayalo'));
      expect(suya.text, contains('Mira su tienda en Jayalo'));
    });

    test('sin título el mensaje sigue teniendo sentido', () {
      final s = shareForRequest(id: 'r', title: '   ')!;
      expect(s.text.startsWith('Mira esta solicitud'), isTrue);
      expect(s.text, contains(s.url));
    });

  });
}
