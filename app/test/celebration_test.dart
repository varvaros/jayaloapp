import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/celebration.dart';

/// Contrato de las celebraciones: cada una monta un overlay por el navigator
/// raíz y se auto-cierra al terminar la animación (no fija los píxeles del
/// confeti ni del candado).
void main() {
  Widget host(void Function(BuildContext) onTap) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: ElevatedButton(
                onPressed: () => onTap(c),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('aceptar: muestra el overlay y se auto-cierra', (tester) async {
    await tester.pumpWidget(host((c) => showAcceptCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump(); // dispara la ruta
    await tester.pump(const Duration(milliseconds: 200)); // entra el overlay
    expect(find.byKey(const ValueKey('celebration-accept')), findsOneWidget);

    await tester.pumpAndSettle(); // corre toda la animación + la salida
    expect(find.byKey(const ValueKey('celebration-accept')), findsNothing);
  });

  testWidgets('desbloquear: muestra el overlay y se auto-cierra',
      (tester) async {
    await tester.pumpWidget(host((c) => showUnlockCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('celebration-unlock')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration-unlock')), findsNothing);
  });

  testWidgets('tocar la pantalla salta la celebración', (tester) async {
    await tester.pumpWidget(host((c) => showAcceptCelebration(c)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('celebration-accept')), findsOneWidget);

    // Un toque en cualquier parte la descarta antes de tiempo.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration-accept')), findsNothing);
  });

  testWidgets(
      'hold: la mascota sigue el progreso REAL del botón, se desinfla al '
      'soltar y explota (PUM) al completar', (tester) async {
    final progress = ValueNotifier<double>(0);
    var confirmed = false;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: Stack(children: [
          Center(
            child: HoldToConfirmButton(
              progress: progress,
              onConfirmed: () async => confirmed = true,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(child: HoldMascotLayer(progress: progress)),
          ),
        ]),
      ),
    ));

    // La mascota está PRESENTE desde que abre la hoja (aún sin presionar) —
    // pedido PO 2026-07-22 ("que esté ahí desde que abre la ventana").
    expect(find.byType(JayaloMascotFace), findsOneWidget);

    // Mantener a mitad de camino: el botón ESCRIBE su progreso en el espejo
    // y la mascota lo sigue (misma señal, cero timers propios).
    final g = await tester
        .startGesture(tester.getCenter(find.byType(HoldToConfirmButton)));
    // Pump vacío: resuelve la arena de gestos (onTapDown) antes de saltar el
    // reloj — mismo gotcha documentado en brand_kit_test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(progress.value, greaterThan(.3));
    expect(find.byType(JayaloMascotFace), findsOneWidget);

    // Soltar antes de tiempo: el reverse del PROPIO botón la desinfla hasta
    // el reposo, sin confirmar nada (la mascota sigue presente, en reposo).
    await g.up();
    await tester.pump(); // primer tick del reverse (elapsed 0)
    await tester.pump(const Duration(milliseconds: 1500));
    expect(progress.value, 0);
    expect(find.byType(JayaloMascotFace), findsOneWidget);
    expect(confirmed, isFalse);

    // Hold completo: onConfirmed dispara y el PUM (560 ms) desvanece a la
    // mascota aunque el dedo siga puesto.
    final g2 = await tester
        .startGesture(tester.getCenter(find.byType(HoldToConfirmButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2600));
    expect(confirmed, isTrue);
    expect(progress.value, 1);
    await g2.up();
    await tester.pump(); // primer tick del PUM (elapsed 0)
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(JayaloMascotFace), findsNothing);
  });

  testWidgets(
      'hold: el cuerpo se INFLA con el progreso real — en reposo es el isotipo '
      'puro y va redondeándose hasta la esfera', (tester) async {
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: Stack(children: [
          Center(
            child: HoldToConfirmButton(
              progress: progress,
              onConfirmed: () async {},
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(child: HoldMascotLayer(progress: progress)),
          ),
        ]),
      ),
    ));

    double inflate() =>
        tester.widget<JayaloMascotFace>(find.byType(JayaloMascotFace)).inflate;

    // En reposo NO está inflada: dibuja el isotipo de la marca tal cual.
    expect(inflate(), 0);

    final g = await tester
        .startGesture(tester.getCenter(find.byType(HoldToConfirmButton)));
    // Pump vacío: el ticker entrega elapsed 0 en su primer tick (mismo gotcha
    // del test de arriba y de brand_kit_test).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    final mid = inflate();
    expect(mid, greaterThan(.4));

    // Sigue inflándose mientras el dedo aguanta, siempre dentro de 0..1.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(inflate(), greaterThan(mid));
    expect(inflate(), lessThanOrEqualTo(1));

    // Soltar la desinfla de vuelta al isotipo. El reverse recorre el mismo
    // camino que el avance, así que desde casi lleno hay que darle los 2.5 s
    // completos (con 1.5 s se queda a mitad de camino).
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2600));
    expect(inflate(), 0);
  });

  testWidgets(
      'la mascota fuera del hold NO se infla: el resto de las pantallas siguen '
      'viendo el isotipo de siempre', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: const Scaffold(body: Center(child: JayaloMascotFace(size: 92))),
    ));
    // La cara tiene un reloj en repeat(): pump cronometrado, NUNCA
    // pumpAndSettle (cuelga para siempre).
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        tester.widget<JayaloMascotFace>(find.byType(JayaloMascotFace)).inflate,
        0);
  });
}
