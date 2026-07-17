import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/image_pick.dart';

void main() {
  const oneMb = 1024 * 1024;

  group('validatePickedImage', () {
    test('caso feliz → ok', () {
      final r = validatePickedImage(
          sizeBytes: oneMb, path: '/tmp/foto.jpg', currentCount: 0, maxCount: 2);
      expect(r, isA<ImagePickOk>());
    });

    test('extensión permitida sin importar mayúsculas → ok', () {
      for (final ext in ['jpg', 'JPG', 'jpeg', 'PNG', 'webp', 'WEBP']) {
        final r = validatePickedImage(
            sizeBytes: oneMb,
            path: '/tmp/foto.$ext',
            currentCount: 0,
            maxCount: 5);
        expect(r, isA<ImagePickOk>(), reason: 'ext $ext debería pasar');
      }
    });

    test('formato no permitido → error con copy de la web', () {
      final r = validatePickedImage(
          sizeBytes: oneMb, path: '/tmp/foto.gif', currentCount: 0, maxCount: 2);
      expect(r, isA<ImagePickError>());
      expect((r as ImagePickError).message,
          'Formato no permitido. Usa JPG, PNG o WEBP.');
    });

    test('sin extensión → error de formato', () {
      final r = validatePickedImage(
          sizeBytes: oneMb, path: '/tmp/foto', currentCount: 0, maxCount: 2);
      expect(r, isA<ImagePickError>());
    });

    test('tamaño > 5 MB → error con copy de la web', () {
      final r = validatePickedImage(
          sizeBytes: 5 * oneMb + 1,
          path: '/tmp/foto.jpg',
          currentCount: 0,
          maxCount: 2);
      expect(r, isA<ImagePickError>());
      expect((r as ImagePickError).message,
          'La imagen supera 5 MB. Usa una más liviana.');
    });

    test('exactamente 5 MB → ok (límite inclusivo como la web)', () {
      final r = validatePickedImage(
          sizeBytes: 5 * oneMb,
          path: '/tmp/foto.jpg',
          currentCount: 0,
          maxCount: 2);
      expect(r, isA<ImagePickOk>());
    });

    test('ya en el tope → error de cantidad (plural)', () {
      final r = validatePickedImage(
          sizeBytes: oneMb, path: '/tmp/foto.jpg', currentCount: 2, maxCount: 2);
      expect(r, isA<ImagePickError>());
      expect((r as ImagePickError).message, 'Puedes subir hasta 2 fotos.');
    });

    test('tope de 1 → mensaje en singular', () {
      final r = validatePickedImage(
          sizeBytes: oneMb, path: '/tmp/foto.jpg', currentCount: 1, maxCount: 1);
      expect((r as ImagePickError).message, 'Puedes subir hasta 1 foto.');
    });

    test('el tope se chequea antes que formato/tamaño', () {
      // archivo inválido Y ya en el tope → gana el mensaje de cantidad
      final r = validatePickedImage(
          sizeBytes: 9 * oneMb,
          path: '/tmp/foto.gif',
          currentCount: 5,
          maxCount: 5);
      expect((r as ImagePickError).message, 'Puedes subir hasta 5 fotos.');
    });
  });
}
