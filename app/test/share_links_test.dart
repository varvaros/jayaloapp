import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/share_links.dart';

void main() {
  group('ShareLinks', () {
    test('los enlaces apuntan a las rutas PUBLICAS de la web', () {
      // Espejo de `shareUrls` en `src/lib/share.ts`. Si una ruta cambia en la
      // web, este test se cae aqui — que es justo lo que queremos.
      expect(ShareLinks.request('r1'), 'https://jayalo.com/requests/r1');
      expect(ShareLinks.product('p1'), 'https://jayalo.com/products/p1');
      // La tienda NO tiene constructor aqui: vive bajo `/provider` en la web y
      // `no_link_out_test.dart` lo prohibe. Ver el comentario en share_links.
    });

    test('el enlace viaja DENTRO del texto, en su propia linea', () {
      // `ShareParams` no admite `text` y `uri` a la vez.
      expect(
        ShareLinks.mensaje('Mira esto', 'https://jayalo.com/products/p1'),
        'Mira esto\nhttps://jayalo.com/products/p1',
      );
    });

    test('un titulo vacio no deja comillas huerfanas con basura dentro', () {
      expect(ShareLinks.requestText('  Nevera  '),
          'Esta solicitud en Jayalo podría interesarte: "Nevera"');
      expect(ShareLinks.productText(null), 'Mira esto en Jayalo: ""');
    });

  });
}
