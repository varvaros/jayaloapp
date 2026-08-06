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
    final viejo = Object();
    takeUnsavedGuard(owner: viejo, check: () => false);
    takeUnsavedGuard(owner: owner, check: () => true);
    releaseUnsavedGuard(viejo);
    expect(hasUnsavedChanges(), isTrue,
        reason: 'el dueño viejo no debe poder soltar el registro del nuevo');
  });

  test('al morir la pantalla de ARRIBA, la de abajo recupera su guard', () {
    // El caso real que un solo hueco no cubría: el ＋ de la barra apila
    // crear-solicitud encima de CUALQUIER pantalla (p. ej. el alta de un
    // artículo de la tienda, a medio llenar). Al cerrarla, la de abajo sigue
    // viva y sucia — si su registro se hubiera perdido, el atrás del sistema y
    // el cambio de pestaña la descartarían en silencio.
    final abajo = Object();
    takeUnsavedGuard(
        owner: abajo, check: () => true, message: 'Perderás el artículo.');
    takeUnsavedGuard(owner: owner, check: () => false); // crear-solicitud
    expect(hasUnsavedChanges(), isFalse, reason: 'manda la de arriba');

    releaseUnsavedGuard(owner); // se cierra crear-solicitud
    expect(hasUnsavedChanges(), isTrue,
        reason: 'la de abajo vuelve a mandar, no queda desprotegida');
    addTearDown(() => releaseUnsavedGuard(abajo));
  });

  test('re-registrar el mismo dueño NO le roba el turno a la de arriba', () {
    // El detalle de oferta re-registra tras un await (`_prefillFromOffer`). Si
    // eso lo subiera al tope, le robaría el guard a la pantalla que el usuario
    // tiene delante — y el diálogo diría "esta oferta" estando en otra cosa.
    final abajo = Object();
    takeUnsavedGuard(owner: abajo, check: () => true, message: 'la oferta');
    takeUnsavedGuard(owner: owner, check: () => false, message: 'la de arriba');

    takeUnsavedGuard(owner: abajo, check: () => true, message: 'la oferta');
    expect(hasUnsavedChanges(), isFalse,
        reason: 'sigue mandando la de arriba, no la que re-registró');
    addTearDown(() => releaseUnsavedGuard(abajo));
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
