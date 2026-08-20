import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  test('cada rol tiene exactamente 2 láminas propias', () {
    expect(kIntroSlides[IntroRole.consumer]!.length, 2);
    expect(kIntroSlides[IntroRole.provider]!.length, 2);
  });

  test('el realce es siempre subcadena del titular', () {
    final todas = [
      kIntroCommon,
      ...kIntroSlides[IntroRole.consumer]!,
      ...kIntroSlides[IntroRole.provider]!,
    ];
    for (final s in todas) {
      expect(s.headline.contains(s.highlight), isTrue,
          reason: 'realce "${s.highlight}" no está en "${s.headline}"');
    }
  });

  test('la lámina común nombra los dos lados', () {
    expect(kIntroCommon.headline,
        'Jayalo conecta a quien pide con quien vende, cerca de ti.');
  });

  test('el cierre del cliente lleva la privacidad con «aceptes»', () {
    expect(kIntroSlides[IntroRole.consumer]![1].sub,
        'Tus datos son privados: solo los proveedores que aceptes podrán ver tu contacto.');
  });

  test('el cierre del proveedor quita la objeción del costo', () {
    expect(kIntroSlides[IntroRole.provider]![1].headline,
        'Ofertar es gratis. Solo pagas cuando ya te aceptaron.');
  });

  test('ningún copy va vacío', () {
    final todas = [
      kIntroCommon,
      ...kIntroSlides[IntroRole.consumer]!,
      ...kIntroSlides[IntroRole.provider]!,
    ];
    for (final s in todas) {
      expect(s.headline.trim(), isNotEmpty);
      expect(s.sub.trim(), isNotEmpty);
      expect(s.highlight.trim(), isNotEmpty);
    }
  });
}
