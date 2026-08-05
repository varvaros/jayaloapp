import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/core/create_request_nav.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// El hueco que dejaba `center_action_test.dart`: ahí se prueba el STORE por su
/// cuenta y la BARRA por la suya, pero nunca el camino completo —
/// pantalla que toma el botón → `HomeShell` → `FloatingNavBar`. El guard por
/// ubicación que decide si el ＋ se vuelve cámara vive justo en ese tramo sin
/// cubrir, así que un guard equivocado pasaba la suite entera y solo se veía
/// en device (bug PO: "el botón de + no se transforma en cámara").
void main() {
  setUp(() => roleStore.value = RoleState.consumer);
  tearDown(() {
    centerAction.value = null;
    centerActionIcon.value = null;
    centerActionOwner.value = null;
    centerActionRoute.value = null;
    centerActionLabel.value = null;
    centerActionMenu.value = null;
  });

  /// Pantalla que se apropia del centro en `initState` y lo suelta en
  /// `dispose`, exactamente como hace `CreateRequestScreen`.
  GoRouter router() => GoRouter(
        initialLocation: '/client',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                  path: '/client',
                  builder: (_, _) => const Text('mis solicitudes')),
              GoRoute(
                path: kCreateRequestRoute,
                builder: (_, _) => const _TakesCenter(),
              ),
            ],
          ),
        ],
      );

  IconData? centerIcon(WidgetTester tester) =>
      tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).centerIconOverride;

  testWidgets('dentro de crear solicitud el ＋ se vuelve CÁMARA (con push, '
      'que es el verbo real: `pushCreateRequestOnce`)', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    expect(centerIcon(tester), isNull,
        reason: 'fuera de la pantalla el centro es el ＋ de siempre');

    final ctx = tester.element(find.text('mis solicitudes'));
    GoRouter.of(ctx).push(kCreateRequestRoute);
    await tester.pumpAndSettle();

    expect(centerIcon(tester), Icons.photo_camera_outlined,
        reason: 'la pantalla al frente tomó el botón: debe pintarse su ícono');
  });

  testWidgets('al salir de la pantalla el ＋ vuelve a ser ＋', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('mis solicitudes'));
    GoRouter.of(ctx).push(kCreateRequestRoute);
    await tester.pumpAndSettle();
    expect(centerIcon(tester), Icons.photo_camera_outlined);

    GoRouter.of(tester.element(find.byType(_TakesCenter))).pop();
    await tester.pumpAndSettle();

    expect(centerIcon(tester), isNull,
        reason: 'soltado el botón, el centro vuelve a su ícono de destino');
  });

  testWidgets('una pantalla que NO es crear-solicitud también puede tomar el ＋',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/client',
      routes: [
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          routes: [
            GoRoute(path: '/client', builder: (_, _) => const Text('mis solicitudes')),
            GoRoute(path: '/otra', builder: (_, _) => const _TakesMenu()),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(centerIcon(tester), isNull);

    GoRouter.of(tester.element(find.text('mis solicitudes'))).push('/otra');
    await tester.pumpAndSettle();

    final bar = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
    expect(bar.centerIconOverride, Icons.library_add_outlined,
        reason: 'la compuerta ya no puede estar cableada a kCreateRequestRoute');
    expect(bar.centerLabelOverride, 'Cargar');
    expect(bar.centerMenuItems, isNotNull);
    expect(bar.centerMenuItems!.length, 1);
  });

  testWidgets('la etiqueta del centro sale del STORE, no del shell',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('mis solicitudes'))).push(kCreateRequestRoute);
    await tester.pumpAndSettle();

    expect(
        tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).centerLabelOverride,
        'Añadir foto',
        reason: 'crear-solicitud la registra ella misma; ya no está a fuego en home_shell');
  });
}

class _TakesCenter extends StatefulWidget {
  const _TakesCenter();
  @override
  State<_TakesCenter> createState() => _TakesCenterState();
}

class _TakesCenterState extends State<_TakesCenter> {
  // Tear-off guardado UNA vez, igual que `CreateRequestScreen`:
  // `releaseCenterAction` compara por identidad.
  void _camera() {}

  @override
  void initState() {
    super.initState();
    takeCenterAction(
      owner: _camera,
      icon: Icons.photo_camera_outlined,
      label: 'Añadir foto',
      route: kCreateRequestRoute,
      action: _camera,
    );
  }

  @override
  void dispose() {
    releaseCenterAction(_camera);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('crear solicitud');
}

/// Pantalla cualquiera —NO crear-solicitud— que registra un MENÚ.
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
      icon: Icons.library_add_outlined,
      label: 'Cargar',
      route: '/otra',
      menu: [
        CenterMenuItem(
            icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: _nada),
      ],
    );
  }

  @override
  void dispose() {
    releaseCenterAction(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('otra pantalla');
}
