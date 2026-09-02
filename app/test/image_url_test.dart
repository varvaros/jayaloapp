import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/image_url.dart';

/// Replica UNO A UNO los casos de `src/lib/imageUrl.test.ts` de la web, igual
/// que `contact_info_test.dart` replica los suyos. Las dos superficies piden
/// las fotos al mismo transformador, así que si una reescribe la URL distinto
/// que la otra tenemos dos comportamientos y un solo nombre.
///
/// Medido contra produccion el 2026-09-02 sobre este mismo objeto:
///   object/public             image/jpeg   526.720 B
///   render/image ?width=200   image/webp    60.330 B
///   render/image ?width=40    image/webp    11.332 B
void main() {
  const host = 'https://mfaiklvobnvgusbcssbx.supabase.co';
  const objeto =
      'business-logos/e01993f1-9e0d-451c-afed-3ee52dc09349/covers/db0e22e3-fd9d-4f2b-b7bf-c3935b424762-1786310241925.jpg';
  const publica = '$host/storage/v1/object/public/$objeto';

  group('transformedImageUrl', () {
    test('cambia object/public por render/image/public y pide el ancho', () {
      final url = Uri.parse(transformedImageUrl(publica, width: 200));

      expect(url.path, '/storage/v1/render/image/public/$objeto');
      expect(url.queryParameters['width'], '200');
    });

    test('conserva el host y la ruta completa del objeto, con sus carpetas', () {
      final url = Uri.parse(transformedImageUrl(publica, width: 96));

      expect(url.origin, host);
      expect(url.path.endsWith(objeto), isTrue);
    });

    test('usa calidad 80 por defecto', () {
      final url = Uri.parse(transformedImageUrl(publica, width: 200));

      expect(url.queryParameters['quality'], '80');
    });

    test('respeta la calidad explicita cuando se pide', () {
      final url = Uri.parse(transformedImageUrl(publica, width: 200, quality: 60));

      expect(url.queryParameters['quality'], '60');
    });

    // Limite documentado de Supabase: 1-2500. Fuera de ese rango la peticion
    // falla, y aqui un fallo es una foto que no aparece.
    test('recorta el ancho al techo de 2500', () {
      final url = Uri.parse(transformedImageUrl(publica, width: 4000));

      expect(url.queryParameters['width'], '2500');
    });

    test('sube el ancho al suelo de 1 y nunca pide 0 ni negativo', () {
      expect(
        Uri.parse(transformedImageUrl(publica, width: 0)).queryParameters['width'],
        '1',
      );
      expect(
        Uri.parse(transformedImageUrl(publica, width: -10)).queryParameters['width'],
        '1',
      );
    });

    // Las URL ajenas salen INTACTAS: es lo que permite meter esto dentro de
    // `JayaloNetworkImage` sin mirar de donde sale cada foto.
    test('devuelve intacta una URL que no es de Supabase Storage', () {
      const google = 'https://lh3.googleusercontent.com/a/ACg8ocK=s96-c';

      expect(transformedImageUrl(google, width: 200), google);
    });

    test('devuelve intacta una cadena vacia sin reventar', () {
      expect(transformedImageUrl('', width: 200), '');
    });

    test('devuelve intacta una cadena que no es una URL', () {
      expect(transformedImageUrl('no soy una url', width: 200), 'no soy una url');
    });

    // Bucket privado: en las URL firmadas las opciones viajan EMBEBIDAS en el
    // token, asi que reescribir la ruta rompe la firma.
    test('devuelve intacta una URL firmada de bucket privado', () {
      const firmada =
          '$host/storage/v1/object/sign/business-id-docs/x/cedula.jpg?token=abc.def';

      expect(transformedImageUrl(firmada, width: 200), firmada);
    });

    test('conserva los parametros que ya traia la URL original', () {
      final url = Uri.parse(transformedImageUrl('$publica?t=1787087717877', width: 200));

      expect(url.queryParameters['t'], '1787087717877');
      expect(url.queryParameters['width'], '200');
    });

    test('es idempotente: reescribir cambia el ancho, no la ruta', () {
      final unaVez = transformedImageUrl(publica, width: 200);
      final url = Uri.parse(transformedImageUrl(unaVez, width: 400));

      expect(url.path, '/storage/v1/render/image/public/$objeto');
      expect(url.queryParameters['width'], '400');
    });
  });
}
