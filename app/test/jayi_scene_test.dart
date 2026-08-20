// La ilustración del intro: cada lámina tiene su ESCENA, y el fondo es el
// lienzo arena limpio de la maqueta — no la «Portada Jayi» a pantalla completa.
//
// El PO reportó exactamente esta regresión: las tres láminas enseñaban el mismo
// render 3D y encima quedaban dos titulares apilados (el claim fijo de la
// portada y el de la lámina). Los tests de abajo la fijan por los dos lados.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';
import 'package:jayalo_app/features/auth/jayi_scene.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:jayalo_app/features/auth/portada_jayi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Con las animaciones apagadas: `JayiScene` mueve un `Ticker` perpetuo y con
  /// ellas encendidas `pumpAndSettle` no asienta NUNCA.
  Widget app() => MaterialApp(
    home: const LoginScreen(),
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

  Finder scene(JayiSceneKind kind) => find.byWidgetPredicate(
    (w) => w is JayiScene && w.kind == kind,
    description: 'JayiScene($kind)',
  );

  testWidgets('lámina común: Jayi entre quien pide y quien vende', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(scene(JayiSceneKind.common), findsOneWidget);
  });

  testWidgets('el fondo es el lienzo limpio, NO la portada a pantalla completa', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.byType(PortadaJayi), findsNothing);
    // El claim fijo de la portada competía con el titular de la lámina: en la
    // lámina común se leían DOS titulares, uno encima del otro.
    expect(find.text('Todo comienza con una idea'), findsNothing);
    expect(find.text(kIntroCommon.headline), findsOneWidget);
  });

  testWidgets('cliente: ofertas que suben y luego el candado', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Busco algo'));
    await t.pumpAndSettle();
    expect(scene(JayiSceneKind.consumerOffers), findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(scene(JayiSceneKind.consumerLock), findsOneWidget);
  });

  testWidgets('proveedor: la bandeja y luego la moneda', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();
    expect(scene(JayiSceneKind.providerTray), findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(scene(JayiSceneKind.providerCoin), findsOneWidget);
  });

  testWidgets('cada lámina trae SU escena, no la misma repetida', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('Busco algo'));
    await t.pumpAndSettle();

    // La del cliente entró y la común NO se quedó pegada: si la ilustración
    // fuera un fondo compartido, este expect no distinguiría nada.
    expect(scene(JayiSceneKind.consumerOffers), findsOneWidget);
    expect(scene(JayiSceneKind.providerTray), findsNothing);
  });

  testWidgets('saltar sin elegir lado: la escena común también cierra', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();

    expect(await IntroRoleStore().read(), isNull);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(scene(JayiSceneKind.common), findsWidgets);
  });

  // Las cinco escenas se pintan de verdad: un radio negativo o un shader sobre
  // un Rect vacío revientan en `paint`, y eso no lo ve `flutter analyze`.
  for (final kind in JayiSceneKind.values) {
    testWidgets('$kind se pinta sin reventar', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(width: 220, child: JayiScene(kind: kind)),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(JayiScene), findsOneWidget);
    });
  }
}
