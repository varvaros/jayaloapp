// Humo de la «PORTADA JAYI» (login): el asset resuelve, el widget pinta a lo
// largo del loop sin lanzar (incluido el instante del parpadeo), y la fuente
// del sistema en gigante no lo rompe (familia del bug 4e8cff1).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/portada_jayi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el asset jayi-hero.webp existe y resuelve del bundle', () async {
    final data = await rootBundle.load('assets/images/jayi-hero.webp');
    expect(data.lengthInBytes, greaterThan(100000)); // ~218 KB
    // Cabecera RIFF/WEBP: el fichero es un webp de verdad, no un placeholder.
    final head = data.buffer.asUint8List(0, 4);
    expect(String.fromCharCodes(head), 'RIFF');
  });

  Widget app({double textScale = 1.0, double bottomReserve = 170}) =>
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFFF8F4EC),
            child: PortadaJayi(bottomReserve: bottomReserve),
          ),
        ),
      );

  testWidgets('pinta a lo largo del loop sin lanzar (incl. parpadeo)',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    // Instantes clave: arranque, mitad del flote, el parpadeo del ciclo de
    // 6.4 s (cierra hacia t=2.69), y pasada la primera vuelta del vaivén.
    for (final ms in [0, 500, 2400, 2690, 2800, 5000, 13500]) {
      await tester.pump(Duration(milliseconds: ms == 0 ? 16 : ms));
      expect(tester.takeException(), isNull, reason: 't=$ms ms');
    }
    expect(find.text('Todo comienza con una idea'), findsOneWidget);
    expect(
        find.textContaining('proveedores verificados'), findsOneWidget);
  });

  testWidgets('con la fuente del sistema x2 no desborda ni lanza',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale: 2.0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    // La cabecera clampa a x1.3: el título sigue en una caja razonable.
    expect(find.text('Todo comienza con una idea'), findsOneWidget);
  });

  testWidgets('con animaciones desactivadas pinta un frame estático',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFFF8F4EC),
            child: const PortadaJayi(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
