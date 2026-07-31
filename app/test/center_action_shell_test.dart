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
    takeCenterAction(_camera, Icons.photo_camera_outlined);
  }

  @override
  void dispose() {
    releaseCenterAction(_camera);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('crear solicitud');
}
