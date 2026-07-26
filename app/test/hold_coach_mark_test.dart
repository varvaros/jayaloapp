import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/hold_tutorial_store.dart';

Widget _host(ValueNotifier<double> progress) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldCoachMark(
            gesture: 'accept',
            message: 'Mantén presionado para aceptar',
            tone: HoldToConfirmTone.free,
            progress: progress,
            child: HoldToConfirmButton(
              label: 'Mantener para aceptar',
              tone: HoldToConfirmTone.free,
              progress: progress,
              onConfirmed: () async {},
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // El singleton `holdTutorialStore` vive todo el proceso: sin este reset,
    // marcar el gesto en un test contaminaría los siguientes de este archivo.
    holdTutorialStore.reset();
  });

  // NOTA: la demo del coach-mark corre un `AnimationController.repeat()`
  // indefinido, así que `pumpAndSettle()` nunca se asienta (siempre hay un
  // frame pendiente) y lanza "pumpAndSettle timed out". Se usan `pump()`
  // explícitos: uno para que corra el postFrameCallback que mide el ancla y
  // muestra el overlay, y otro para que el `OverlayPortal`/`CompositedTransformFollower`
  // reflejen ese estado.
  testWidgets('muestra el recuadro cuando el gesto no se ha logrado',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mantén presionado para aceptar'), findsOneWidget);
  });

  testWidgets('al llegar progress a 1.0 marca el gesto y oculta el recuadro',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pump();
    await tester.pump();
    progress.value = 1.0;
    await tester.pump();
    await tester.pump();
    expect(holdTutorialStore.isDone('accept'), isTrue);
    expect(find.text('Mantén presionado para aceptar'), findsNothing);
  });

  testWidgets('tocar el velo descarta el recuadro sin marcar el gesto',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pump();
    await tester.pump();
    // El botón (ancho completo, centrado verticalmente) se solapa con el
    // centro geométrico del velo a pantalla completa, así que un tap en el
    // centro del velo (lo que haría `tester.tap` por defecto) golpearía el
    // botón en vez del velo. Se toca una esquina del velo, fuera de la franja
    // del botón, usando la misma key.
    final scrimCorner =
        tester.getTopLeft(find.byKey(const Key('holdCoachScrim'))) +
            const Offset(5, 5);
    await tester.tapAt(scrimCorner);
    await tester.pump();
    await tester.pump();
    expect(find.text('Mantén presionado para aceptar'), findsNothing);
    expect(holdTutorialStore.isDone('accept'), isFalse);
  });

  testWidgets('la demo se pausa mientras el usuario mantiene presionado',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pump();
    await tester.pump();
    // En reposo (progress == 0) la demo sobre el botón está presente…
    expect(find.byKey(const Key('holdCoachDemo')), findsOneWidget);
    expect(find.text('Mantén presionado para aceptar'), findsOneWidget);

    // …y se oculta mientras el usuario mantiene presionado de verdad, SIN
    // que el gesto se dé por completado (0.5 < 1.0).
    progress.value = 0.5;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('holdCoachDemo')), findsNothing);
    // El recuadro con el mensaje sigue visible — la pausa solo afecta la
    // demo sobre el botón, no el callout.
    expect(find.text('Mantén presionado para aceptar'), findsOneWidget);
    expect(holdTutorialStore.isDone('accept'), isFalse);
  });
}
