import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';
import 'package:jayalo_app/features/shell/back_guard.dart';

/// Spec §5.3: el gesto ATRÁS de Android deshace UN paso dentro del creador de
/// solicitudes. `unsaved_guard.dart` gana un segundo gancho (pila por dueño,
/// como el de cambios sin guardar) y `BackGuard` lo consulta ANTES del aviso
/// de descarte. Los guards son singletons de módulo: cada test suelta lo suyo.
void main() {
  final owner = Object();
  tearDown(() {
    releaseBackStep(owner);
    releaseUnsavedGuard(owner);
  });

  group('tryBackStep', () {
    test('sin nada registrado no consume', () {
      expect(tryBackStep(), isFalse);
    });

    test('llama al paso registrado y devuelve lo que este diga', () {
      var llamadas = 0;
      takeBackStep(owner: owner, step: () {
        llamadas++;
        return true;
      });
      expect(tryBackStep(), isTrue);
      expect(llamadas, 1);
      takeBackStep(owner: owner, step: () => false);
      expect(tryBackStep(), isFalse);
    });

    test('soltar deja de consumir', () {
      takeBackStep(owner: owner, step: () => true);
      releaseBackStep(owner);
      expect(tryBackStep(), isFalse);
    });

    test('manda el TOPE; al morir la de arriba, la de abajo recupera el gesto', () {
      final abajo = Object();
      addTearDown(() => releaseBackStep(abajo));
      takeBackStep(owner: abajo, step: () => true);
      takeBackStep(owner: owner, step: () => false);
      expect(tryBackStep(), isFalse, reason: 'manda la de arriba');
      releaseBackStep(owner);
      expect(tryBackStep(), isTrue, reason: 'vuelve a mandar la de abajo');
    });

    test('re-registrar el mismo dueño lo actualiza EN SU SITIO', () {
      final abajo = Object();
      addTearDown(() => releaseBackStep(abajo));
      takeBackStep(owner: abajo, step: () => false);
      takeBackStep(owner: owner, step: () => true);
      takeBackStep(owner: abajo, step: () => false);
      expect(tryBackStep(), isTrue, reason: 'sigue mandando la de arriba');
    });

    test('soltar con OTRO dueño no toca el registro vigente', () {
      takeBackStep(owner: owner, step: () => true);
      releaseBackStep(Object());
      expect(tryBackStep(), isTrue);
    });
  });

  group('BackGuard', () {
    setUp(() => roleStore.value = RoleState.consumer);

    GoRouter router() => GoRouter(
          initialLocation: '/client',
          routes: [
            GoRoute(
                path: '/client',
                builder: (_, _) => const BackGuard(child: Text('home'))),
          ],
        );

    testWidgets('el paso registrado consume el gesto: ni diálogo ni salida',
        (tester) async {
      var pasos = 0;
      takeBackStep(owner: owner, step: () {
        pasos++;
        return true;
      });
      takeUnsavedGuard(owner: owner, check: () => true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pasos, 1);
      expect(find.text('¿Salir y descartar los cambios?'), findsNothing,
          reason: 'el paso va ANTES del aviso de cambios sin guardar');
      expect(find.text('¿Salir de Jayalo?'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('si el paso NO consume, sigue el flujo de hoy', (tester) async {
      takeBackStep(owner: owner, step: () => false);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // En el home, arriba del todo y sin cambios: confirmar salida de la app.
      expect(find.text('¿Salir de Jayalo?'), findsOneWidget);
    });

    testWidgets('sin consumir y con cambios sin guardar, pregunta si descartar',
        (tester) async {
      takeBackStep(owner: owner, step: () => false);
      takeUnsavedGuard(owner: owner, check: () => true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('¿Salir y descartar los cambios?'), findsOneWidget);
    });
  });
}
