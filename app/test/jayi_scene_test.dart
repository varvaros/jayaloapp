// La ilustración del intro: UN SOLO Jayi, fuera del carrusel, que cambia de
// POSE según la lámina. El fondo es el lienzo arena limpio de la maqueta — no
// la «Portada Jayi» a pantalla completa.
//
// El PO reportó exactamente esa regresión: las láminas enseñaban el mismo
// render 3D y encima quedaban dos titulares apilados (el claim fijo de la
// portada y el de la lámina). Los tests de abajo la fijan por los dos lados.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/jayi_scene.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:jayalo_app/features/auth/portada_jayi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Con las animaciones apagadas: `JayiScene` mueve un `Ticker` perpetuo y con
  /// ellas encendidas `pumpAndSettle` no asienta NUNCA. Y sin `splashFactory`
  /// el ripple de Material sigue corriendo reloj FAKE tras cada toque, ajeno a
  /// `disableAnimations` — ver `login_intro_carousel_test.dart`.
  Widget app({int credits = 5}) => MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: LoginScreen(fetchWelcomeCredits: () async => credits),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
      child: child!,
    ),
  );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(420 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  JayiPose poseOnScreen(WidgetTester t) =>
      t.widget<JayiScene>(find.byType(JayiScene)).pose;

  testWidgets('hay UN SOLO Jayi y vive fuera del carrusel', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(JayiScene), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(JayiScene),
      ),
      findsNothing,
    );
    expect(poseOnScreen(t), JayiPose.open);
  });

  testWidgets('cliente: pulgar arriba y luego libre — el MISMO widget cambia '
      'de pose', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    final antes = t.state(find.byType(JayiScene));
    await t.tap(find.text('Soy un cliente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.thumbsUp);
    expect(
      identical(t.state(find.byType(JayiScene)), antes),
      isTrue,
      reason: 'no se remonta',
    );
    // El «Siguiente» de la reacción es fantasma: inerte hasta `introHint`.
    await t.pump(JayaloMotion.introHint + const Duration(milliseconds: 1));
    await t.pump();
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.free);
  });

  testWidgets('proveedor: pulgar, etiqueta y moneda', (t) async {
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await t.pumpAndSettle();
    await t.tap(find.text('Soy un proveedor'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.thumbsUp);
    // El «Siguiente» de la reacción es fantasma: inerte hasta `introHint`.
    await t.pump(JayaloMotion.introHint + const Duration(milliseconds: 1));
    await t.pump();
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.priceTag);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.coin);
  });

  testWidgets('saltar sin elegir: el cierre neutro sigue con los brazos '
      'abiertos', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.open);
  });

  testWidgets(
    'el fondo es el lienzo limpio, NO la portada a pantalla completa',
    (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      expect(find.byType(PortadaJayi), findsNothing);
      // El claim fijo de la portada competía con el titular de la lámina: se
      // leían DOS titulares, uno encima del otro.
      expect(find.text('Todo comienza con una idea'), findsNothing);
      // El titular de la pregunta entra palabra a palabra, así que se comprueba
      // por su apoyo, que sí es un `Text` entero.
      expect(find.text(introSlideFor(IntroStep.ask).sub), findsOneWidget);
    },
  );

  // Las cinco poses se pintan de verdad: un radio negativo o un shader sobre
  // un Rect vacío revientan en `paint`, y eso no lo ve `flutter analyze`.
  for (final pose in JayiPose.values) {
    testWidgets('$pose se pinta sin reventar', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(width: 200, child: JayiScene(pose: pose)),
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byType(JayiScene), findsOneWidget);
    });
  }
}
