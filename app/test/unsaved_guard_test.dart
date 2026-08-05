import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';

void main() {
  tearDown(() => setUnsavedGuard(null));

  test('sin nada registrado no hay cambios sin guardar', () {
    expect(hasUnsavedChanges(), isFalse);
  });

  test('registrado y sucio dice que si', () {
    setUnsavedGuard(() => true);
    expect(hasUnsavedChanges(), isTrue);
  });

  test('registrado y limpio dice que no', () {
    setUnsavedGuard(() => false);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('quitar el registro lo deja en falso aunque estuviera sucio', () {
    setUnsavedGuard(() => true);
    setUnsavedGuard(null);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('se consulta en cada llamada, no se cachea', () {
    var sucio = false;
    setUnsavedGuard(() => sucio);
    expect(hasUnsavedChanges(), isFalse);
    sucio = true;
    expect(hasUnsavedChanges(), isTrue);
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
