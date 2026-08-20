// El intro de primera apertura sale UNA SOLA VEZ POR TELÉFONO (PO 2026-08-20).
// Con la marca puesta, `/login` vuelve al login clásico: la Portada Jayi (el
// Jayi 3D sobre el pattern de isotipos) y los accesos, sin carrusel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_seen_store.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:jayalo_app/features/auth/portada_jayi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Animaciones del sistema APAGADAS: tanto la escena de cada lámina como la
  /// Portada Jayi animan con un `Ticker` perpetuo y `pumpAndSettle` no
  /// asentaría nunca. Ambas respetan `JayaloMotion.reduced`.
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

  testWidgets('sin marca: sale el carrusel, NO la Portada Jayi', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text('Busco algo'), findsOneWidget);
    expect(find.text('Saltar'), findsOneWidget);
    expect(find.byType(PortadaJayi), findsNothing);
  });

  testWidgets('con la marca: login clásico con Portada Jayi y accesos', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({IntroSeenStore.kKey: true});
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.byType(PortadaJayi), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
    // Nada del carrusel: ni recuadros de rol, ni «Saltar», ni puntos.
    expect(find.text('Busco algo'), findsNothing);
    expect(find.text('Vendo algo'), findsNothing);
    expect(find.text('Saltar'), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('quedarse en la lámina de elección NO deja la marca', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    // Quien mata la app aquí no ha visto el intro: debe volver a salirle.
    expect(await IntroSeenStore().read(), isFalse);
  });

  testWidgets('«Saltar» sin rol llega a los accesos y deja la marca', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(await IntroSeenStore().read(), isTrue);
  });

  testWidgets('elegir rol y avanzar hasta los accesos deja la marca', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();
    // Lámina de contenido del proveedor: todavía no ha terminado el intro.
    expect(await IntroSeenStore().read(), isFalse);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(await IntroSeenStore().read(), isTrue);
  });

  testWidgets('volver atrás desde los accesos NO borra la marca', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    // Deslizar de vuelta a la lámina de elección: la marca ya está escrita y
    // nada la retira — el intro se dio por visto en cuanto se llegó al final.
    await t.drag(find.byType(PageView), const Offset(400, 0));
    await t.pumpAndSettle();

    expect(find.text('Busco algo'), findsOneWidget);
    expect(await IntroSeenStore().read(), isTrue);
  });
}
