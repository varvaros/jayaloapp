import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/portfolio_media.dart';

void main() {
  const foto = {'url': 'https://cdn/a.webp', 'kind': 'image'};
  const video = {
    'url': 'https://cdn/b.mp4',
    'kind': 'video',
    'poster': 'https://cdn/b.jpg',
    'duration': 42,
  };

  group('parseMedia', () {
    test('lee media cuando trae elementos', () {
      final m = parseMedia([foto, video], ['https://cdn/a.webp']);
      expect(m.length, 2);
      expect(m[1].kind, 'video');
      expect(m[1].poster, 'https://cdn/b.jpg');
      expect(m[1].duration, 42);
    });

    test('cae a image_urls cuando media esta vacio (filas viejas)', () {
      final m = parseMedia(const [], ['https://cdn/a.webp']);
      expect(m.length, 1);
      expect(m.first.kind, 'image');
      expect(m.first.url, 'https://cdn/a.webp');
    });

    test('descarta basura: sin url o con kind desconocido', () {
      final m = parseMedia([
        foto,
        {'kind': 'image'},
        {'url': 'x', 'kind': 'gif'},
        null,
      ], const []);
      expect(m.length, 1);
    });

    test('aguanta null en las dos columnas', () {
      expect(parseMedia(null, null), isEmpty);
    });
  });

  group('imagesOf — el espejo', () {
    test('devuelve SOLO las imagenes, en orden', () {
      expect(imagesOf(parseMedia([video, foto], const [])), ['https://cdn/a.webp']);
    });

    test('nunca deja pasar la URL de un video', () {
      expect(imagesOf(parseMedia([video], const [])), isEmpty);
    });
  });

  group('coverOf', () {
    test('de una imagen, su propia URL', () {
      final c = coverOf(parseMedia([foto], const []).first);
      expect(c.src, 'https://cdn/a.webp');
      expect(c.esVideo, isFalse);
    });

    test('de un video, su poster', () {
      final c = coverOf(parseMedia([video], const []).first);
      expect(c.src, 'https://cdn/b.jpg');
      expect(c.esVideo, isTrue);
    });

    test('de un video sin poster, src null — nunca el mp4', () {
      final sin = parseMedia([
        {'url': 'https://cdn/b.mp4', 'kind': 'video'},
      ], const []).first;
      final c = coverOf(sin);
      expect(c.src, isNull);
      expect(c.esVideo, isTrue);
    });
  });
}
