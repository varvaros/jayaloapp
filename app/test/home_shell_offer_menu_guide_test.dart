import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// Tutorial del menú en arco (`provider.offer_menu.v1`): la PRIMERA vez que
/// una pantalla registra un menú para el botón central, el shell debe
/// enseñar la guía anclada al botón — y no volver a hacerlo nunca.
const _copy =
    'Mientras redactas tu oferta, este botón abre un menú para añadir fotos: '
    'cámara, galería, tu tienda o tus trabajos.';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    roleStore.value = RoleState.provider;
    // NO llamar ensureLoaded(): el repo real (sin login en tests) suprimiría
    // el store; reset() deja `_suppressed = false`, que es lo que hace falta.
    onboardingStore.reset();
  });
  tearDown(() {
    centerAction.value = null;
    centerActionIcon.value = null;
    centerActionOwner.value = null;
    centerActionRoute.value = null;
    centerActionLabel.value = null;
    centerActionMenu.value = null;
  });

  GoRouter router() => GoRouter(
        initialLocation: '/provider',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(path: '/provider', builder: (_, _) => const Text('bandeja')),
              GoRoute(path: '/oferta', builder: (_, _) => const _TakesMenu()),
            ],
          ),
        ],
      );

  testWidgets('registrar el menú del centro enseña la guía una sola vez',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    expect(find.text(_copy), findsNothing,
        reason: 'sin menú registrado no hay nada que enseñar');

    GoRouter.of(tester.element(find.text('bandeja'))).push('/oferta');
    await tester.pumpAndSettle();
    expect(find.text(_copy), findsOneWidget,
        reason: 'el registro del menú debe disparar la guía');

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text(_copy), findsNothing);

    // Salir y volver a entrar: vista una vez, no se repite.
    GoRouter.of(tester.element(find.byType(_TakesMenu))).pop();
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('bandeja'))).push('/oferta');
    await tester.pumpAndSettle();
    expect(find.text(_copy), findsNothing,
        reason: 'la guía marcada como vista no debe reaparecer');
  });

  testWidgets('la guía no se muestra si la ruta dueña no es la visible',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    // Menú registrado por una ruta que NO está al frente (el frame de gracia
    // del dispose, o un registro rezagado): la guía no debe dispararse.
    void nada() {}
    takeCenterAction(
      owner: Object(),
      icon: Icons.auto_awesome,
      label: 'Añadir',
      route: '/otra-ruta',
      menu: [CenterMenuItem(icon: Icons.camera_alt, label: 'Cámara', onTap: nada)],
    );
    await tester.pumpAndSettle();

    expect(find.text(_copy), findsNothing);
  });
}

/// Pantalla que registra un MENÚ para el botón central en `initState` y lo
/// suelta en `dispose`, como hace la pantalla de la oferta.
class _TakesMenu extends StatefulWidget {
  const _TakesMenu();
  @override
  State<_TakesMenu> createState() => _TakesMenuState();
}

class _TakesMenuState extends State<_TakesMenu> {
  final Object _owner = Object();
  void _nada() {}

  @override
  void initState() {
    super.initState();
    takeCenterAction(
      owner: _owner,
      icon: Icons.auto_awesome,
      label: 'Añadir',
      route: '/oferta',
      menu: [
        CenterMenuItem(
            icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: _nada),
      ],
    );
  }

  @override
  void dispose() {
    releaseCenterAction(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('redactando oferta');
}
