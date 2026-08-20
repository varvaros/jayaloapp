// El carrusel de primera apertura dentro de `/login`: bifurca por rol, guarda
// la elección ANTES de que haya sesión y cierra con los accesos de siempre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Se monta con las animaciones del sistema APAGADAS por dos razones:
  /// 1. es una conducta que hay que respetar igual (`JayaloMotion.reduced`), y
  /// 2. la portada anima con un `Ticker` perpetuo — con ellas encendidas
  ///    `pumpAndSettle` no asienta NUNCA.
  Widget app() => MaterialApp(
        home: const LoginScreen(),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
          child: child!,
        ),
      );

  // Teléfono, no la ventana de 800x600 por defecto: en `flutter test` el texto
  // mide ~2× y los recuadros tienen que quedar donde se pueden tocar.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(420 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('primera apertura: lámina común y los DOS recuadros de rol',
      (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text(kIntroCommon.headline), findsOneWidget);
    expect(find.text(kIntroCommon.sub), findsOneWidget);
    expect(find.text('Busco algo'), findsOneWidget);
    expect(find.text('Vendo algo'), findsOneWidget);
    // Sin rol elegido no hay lámina de acceso a la que deslizarse.
    expect(find.text('Continuar con Google'), findsNothing);
  });

  testWidgets('tocar «Vendo algo» persiste la elección de proveedor',
      (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();

    expect(await IntroRoleStore().read(), IntroRole.provider);
  });

  testWidgets('proveedor: dos láminas después están los DOS accesos',
      (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('Vendo algo'));
    await t.pumpAndSettle();
    expect(find.text(kIntroSlides[IntroRole.provider]![0].headline),
        findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();

    expect(find.text('Ofertar es gratis. Solo pagas cuando ya te aceptaron.'),
        findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
  });

  testWidgets('con rol ya guardado arranca en la lámina de acceso',
      (t) async {
    // Quien ya eligió y vuelve a la app no se traga el intro otra vez.
    SharedPreferences.setMockInitialValues({
      IntroRoleStore.kKey: IntroRole.consumer.name,
    });
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
    expect(find.text('Busco algo'), findsNothing);
  });
}
