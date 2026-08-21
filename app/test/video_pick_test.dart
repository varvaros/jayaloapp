import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/video_pick.dart';

void main() {
  const oneMb = 1024 * 1024;

  group('validatePickedVideo', () {
    test('caso feliz → ok', () {
      final r = validatePickedVideo(durationSeconds: 30, sizeBytes: oneMb);
      expect(r, isA<VideoPickOk>());
    });

    test('exactamente 45 s y exactamente 10 MB → ok (límite inclusivo)', () {
      final r =
          validatePickedVideo(durationSeconds: 45, sizeBytes: 10 * oneMb);
      expect(r, isA<VideoPickOk>());
    });

    test('más de 45 s → error de duración', () {
      final r = validatePickedVideo(durationSeconds: 46, sizeBytes: oneMb);
      expect(r, isA<VideoPickError>());
      expect((r as VideoPickError).message,
          'El video no puede durar más de 45 segundos.');
    });

    test('más de 10 MB ya comprimido → error de tamaño', () {
      final r = validatePickedVideo(
          durationSeconds: 30, sizeBytes: 10 * oneMb + 1);
      expect(r, isA<VideoPickError>());
      expect((r as VideoPickError).message,
          'El video supera 10 MB. Usa uno más corto o liviano.');
    });

    test('la duración se chequea antes que el tamaño', () {
      final r = validatePickedVideo(
          durationSeconds: 60, sizeBytes: 20 * oneMb);
      expect((r as VideoPickError).message,
          'El video no puede durar más de 45 segundos.');
    });
  });
}
