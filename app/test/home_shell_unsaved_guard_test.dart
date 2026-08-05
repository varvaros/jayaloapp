import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shell/home_shell.dart';

/// El hueco que dejaba `unsaved_guard_test.dart`: ahí se prueba el STORE y el
/// diálogo por separado, pero la navbar era la única salida que NO preguntaba
/// (bug PO 2026-08-05: llenar una solicitud y tocar otra sección la tiraba en
/// silencio). Este arnés monta el shell real y toca pestañas de verdad.
void main() {
  setUp(() async {
    roleStore.value = RoleState.consumer;
    // Sin esto, el velo del spotlight `client.plus.v1` (HomeShell lo muestra
    // en `/client`) se come el PRIMER toque a la navbar y el test miente.
    onboardingStore.reset();
    await onboardingStore.markDone('client.plus.v1');
  });

  GoRouter router() => GoRouter(
        initialLocation: '/client',
        routes: [
          ShellRoute(
            builder: (_, _, child) => HomeShell(child: child),
            routes: [
              GoRoute(path: '/client', builder: (_, _) => const _Sucia()),
              GoRoute(
                  path: '/catalog', builder: (_, _) => const Text('catálogo')),
            ],
          ),
        ],
      );

  testWidgets('pestaña nueva con trabajo sin guardar pregunta antes de irse',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();

    expect(find.text('¿Salir y descartar los cambios?'), findsOneWidget);
    expect(find.text('sin guardar'), findsOneWidget,
        reason: 'mientras el diálogo pregunta, la pantalla sigue viva detrás');

    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('sin guardar'), findsOneWidget);
    expect(find.text('catálogo'), findsNothing,
        reason: 'seguir editando no debe navegar a ningún lado');
  });

  testWidgets('descartar desde el diálogo sí cambia de pestaña',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir y descartar'));
    await tester.pumpAndSettle();

    expect(find.text('catálogo'), findsOneWidget);
    expect(find.text('sin guardar'), findsNothing);
  });

  testWidgets('limpia, la pestaña cambia sin preguntar', (tester) async {
    _dirty = false;
    addTearDown(() => _dirty = true);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();

    expect(find.text('¿Salir y descartar los cambios?'), findsNothing);
    expect(find.text('catálogo'), findsOneWidget);
  });

  testWidgets('re-tocar la pestaña activa no pregunta: no hay nada que perder',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();

    // `/client` es la pestaña activa y también la ruta actual: el `go` a la
    // misma ruta es un no-op de go_router, así que preguntar sería mentir.
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    expect(find.text('¿Salir y descartar los cambios?'), findsNothing);
    expect(find.text('sin guardar'), findsOneWidget);
  });
}

/// Suciedad de módulo para que el test la manipule sin re-montar la pantalla.
bool _dirty = true;

/// Pantalla que registra su guard en `initState` y lo suelta en `dispose`,
/// exactamente como `CreateRequestScreen` y el detalle del proveedor.
class _Sucia extends StatefulWidget {
  const _Sucia();
  @override
  State<_Sucia> createState() => _SuciaState();
}

class _SuciaState extends State<_Sucia> {
  @override
  void initState() {
    super.initState();
    takeUnsavedGuard(
      owner: this,
      check: () => _dirty,
      message: 'Perderás lo que escribiste en esta solicitud.',
    );
  }

  @override
  void dispose() {
    releaseUnsavedGuard(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('sin guardar');
}
