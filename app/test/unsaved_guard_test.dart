import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';

void main() {
  final owner = Object();
  tearDown(() => releaseUnsavedGuard(owner));

  test('sin nada registrado no hay cambios sin guardar', () {
    expect(hasUnsavedChanges(), isFalse);
  });

  test('registrado y sucio dice que si', () {
    takeUnsavedGuard(owner: owner, check: () => true);
    expect(hasUnsavedChanges(), isTrue);
  });

  test('registrado y limpio dice que no', () {
    takeUnsavedGuard(owner: owner, check: () => false);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('soltar el registro lo deja en falso aunque estuviera sucio', () {
    takeUnsavedGuard(owner: owner, check: () => true);
    releaseUnsavedGuard(owner);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('se consulta en cada llamada, no se cachea', () {
    var sucio = false;
    takeUnsavedGuard(owner: owner, check: () => sucio);
    expect(hasUnsavedChanges(), isFalse);
    sucio = true;
    expect(hasUnsavedChanges(), isTrue);
  });

  test('soltar con OTRO dueño no toca el registro vigente', () {
    // El caso real: crear-solicitud se apila sobre el detalle del proveedor,
    // registra encima y al morir suelta. El registro del de abajo ya fue
    // pisado, pero un dueño viejo tampoco puede borrar al nuevo.
    final viejo = Object();
    takeUnsavedGuard(owner: viejo, check: () => false);
    takeUnsavedGuard(owner: owner, check: () => true);
    releaseUnsavedGuard(viejo);
    expect(hasUnsavedChanges(), isTrue,
        reason: 'el dueño viejo no debe poder soltar el registro del nuevo');
  });

  testWidgets('el dialogo usa el mensaje del guard registrado', (tester) async {
    takeUnsavedGuard(
      owner: owner,
      check: () => true,
      message: 'Perderás lo que escribiste en esta solicitud.',
    );
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    expect(find.text('Perderás lo que escribiste en esta solicitud.'),
        findsOneWidget);
    await tester.tap(find.text('Salir y descartar'));
    await tester.pumpAndSettle();
    expect(await futuro, isTrue);
  });

  testWidgets('sin mensaje registrado, el dialogo cae al generico',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    expect(find.text('Perderás lo que escribiste.'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(await futuro, isFalse);
  });

  testWidgets('el dialogo ofrece seguir editando y salir', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    expect(find.text('¿Salir y descartar los cambios?'), findsOneWidget);
    expect(find.text('Seguir editando'), findsOneWidget);
    await tester.tap(find.text('Salir y descartar'));
    await tester.pumpAndSettle();
    expect(await futuro, isTrue);
  });

  testWidgets('seguir editando devuelve false', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(await futuro, isFalse);
  });
}
