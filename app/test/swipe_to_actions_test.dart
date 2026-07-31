import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/swipe_to_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Contrato del swipe de la lista de solicitudes (pedido PO 2026-07-20):
/// arrastrar a la derecha revela las acciones y tocarlas dispara su callback.
void main() {
  Widget host(ValueNotifier<Object?> group, void Function(String) onTap) =>
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SwipeToActions(
                id: 'a',
                group: group,
                actions: [
                  SwipeAction(
                    icon: Icons.delete_outline,
                    label: 'Eliminar',
                    color: Colors.red,
                    onTap: () async => onTap('del'),
                  ),
                  SwipeAction(
                    icon: Icons.edit_outlined,
                    label: 'Editar',
                    color: Colors.blue,
                    onTap: () async => onTap('edit'),
                  ),
                ],
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Text('card'),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('cerrado: las acciones no se ven', (tester) async {
    await tester.pumpWidget(host(ValueNotifier(null), (_) {}));
    expect(find.text('Eliminar'), findsNothing);
    expect(find.text('Editar'), findsNothing);
  });

  testWidgets('arrastrar a la derecha revela Eliminar y Editar', (
    tester,
  ) async {
    await tester.pumpWidget(host(ValueNotifier(null), (_) {}));
    await tester.drag(find.text('card'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
  });

  testWidgets('tocar una acción dispara su callback', (tester) async {
    var got = '';
    await tester.pumpWidget(host(ValueNotifier(null), (v) => got = v));
    await tester.drag(find.text('card'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(got, 'del');
  });

  testWidgets('abrir un row cierra a los demás vía el group compartido', (
    tester,
  ) async {
    final group = ValueNotifier<Object?>(null);
    await tester.pumpWidget(host(group, (_) {}));
    await tester.drag(find.text('card'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(group.value, 'a'); // al abrir, se registra como el row abierto
    // Otro row abre → este debe cerrarse.
    group.value = 'otro';
    await tester.pumpAndSettle();
    expect(find.text('Eliminar'), findsNothing);
  });

  Widget blockedHost(String reason) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SwipeToActions(
                id: 'b',
                group: ValueNotifier<Object?>(null),
                actions: const [],
                blockedReason: reason,
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Text('card'),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('bloqueado: arrastrar revela el motivo', (tester) async {
    await tester.pumpWidget(blockedHost('Ya aceptaste una oferta'));
    expect(find.text('Ya aceptaste una oferta'), findsNothing);
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('card')));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(find.text('Ya aceptaste una oferta'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('bloqueado: al soltar SIEMPRE vuelve a cero', (tester) async {
    await tester.pumpWidget(blockedHost('Solicitud completada'));
    await tester.drag(find.text('card'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud completada'), findsNothing,
        reason: 'la franja bloqueada no puede quedarse abierta');
  });

  testWidgets('bloqueado: no reclama el slot del group', (tester) async {
    final group = ValueNotifier<Object?>(null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          SwipeToActions(
            id: 'b',
            group: group,
            actions: const [],
            blockedReason: 'Solicitud completada',
            child: const SizedBox(
                height: 80, width: double.infinity, child: Text('card')),
          ),
        ]),
      ),
    ));
    await tester.drag(find.text('card'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(group.value, isNull,
        reason: 'un row que nunca se queda abierto no debe cerrar a los demás');
  });

  group('auto-peek', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onboardingStore.reset(); // el store es un singleton: aislar cada test
    });

    Widget peekHost({ValueChanged<bool>? onPeekResolved}) => MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SwipeToActions(
                  id: 'p',
                  group: ValueNotifier<Object?>(null),
                  peekKey: 'requests.swipe.v1',
                  onPeekResolved: onPeekResolved,
                  actions: [
                    SwipeAction(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      color: Colors.red,
                      onTap: () async {},
                    ),
                  ],
                  child: const SizedBox(
                      height: 80, width: double.infinity, child: Text('card')),
                ),
              ],
            ),
          ),
        );

    testWidgets('la primera vez se asoma y marca la clave', (tester) async {
      await tester.pumpWidget(peekHost());
      await tester.pump(); // post-frame que dispara _maybePeek
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsOneWidget,
          reason: 'al asomarse, la franja debe verse');
      await tester.pumpAndSettle();
      expect(find.text('Eliminar'), findsNothing,
          reason: 'la pista se recoge sola');
      expect(onboardingStore.isDone('requests.swipe.v1'), isTrue);
    });

    testWidgets(
        'durante la salida la tarjeta pasa por una posición intermedia (no salta directo a 28)',
        (tester) async {
      await tester.pumpWidget(peekHost());
      final baseX = tester.getTopLeft(find.text('card')).dx;
      await tester.pump(); // post-frame que dispara _maybePeek
      await tester.pump(
          const Duration(milliseconds: 600)); // cumple la espera inicial

      var sawMid = false;
      for (var i = 0; i < 30 && !sawMid; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final delta = tester.getTopLeft(find.text('card')).dx - baseX;
        if (delta > 0 && delta < 28) sawMid = true;
      }
      expect(sawMid, isTrue,
          reason:
              'la salida debe animarse (0 → 28), no saltar directo al valor final');
    });

    testWidgets(
        'si el usuario arrastra durante el peek, la clave NO se marca (se puede ofrecer otra vez)',
        (tester) async {
      // `resolved` distingue "el mecanismo detectó la interrupción" de "la
      // continuación se quedó colgada": ambos casos dejan `isDone` en false
      // por igual, así que una aserción solo sobre `isDone` no prueba nada —
      // si el `await` interno nunca se resuelve (p. ej. sin `.orCancel`),
      // `onPeekResolved` tampoco se invoca nunca y `resolved` se queda en
      // `null`, no en `false`.
      bool? resolved;
      await tester.pumpWidget(
          peekHost(onPeekResolved: (completed) => resolved = completed));
      await tester.pump(); // post-frame que dispara _maybePeek
      await tester.pump(const Duration(milliseconds: 700)); // a mitad de la salida

      // Arrastre real del usuario mientras el peek sigue en curso.
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('card')));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(resolved, isFalse,
          reason:
              'el mecanismo debe resolver la interrupción como "no completada", no quedarse colgado');
      expect(onboardingStore.isDone('requests.swipe.v1'), isFalse,
          reason:
              'una pista cortada a medias no se le enseñó a nadie: debe poder ofrecerse otra vez');
    });

    testWidgets(
        'si el usuario toca la tarjeta para cerrarla durante el peek, la clave NO se marca',
        (tester) async {
      bool? resolved;
      await tester.pumpWidget(
          peekHost(onPeekResolved: (completed) => resolved = completed));
      await tester.pump(); // post-frame que dispara _maybePeek
      // 700 ms (a mitad de la salida) + 200 ms más para caer de lleno en el
      // sostenido (28 px estables): así el toque cae sobre la capa
      // transparente de "tocar para cerrar" (`if (_dx > 2)`) sin depender
      // de en qué punto exacto de la curva de salida estemos.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 200));

      // `warnIfMissed: false`: el toque debe caer sobre la capa transparente
      // de "tocar para cerrar" que se pinta ENCIMA de la tarjeta cuando está
      // abierta (por diseño — ver `_close`/el `Positioned.fill` en `build`),
      // no sobre el `Text('card')` en sí.
      await tester.tap(find.text('card'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(resolved, isFalse,
          reason:
              'un toque que cierra la tarjeta también corta el peek a medias: no se le enseñó el gesto a nadie');
      expect(onboardingStore.isDone('requests.swipe.v1'), isFalse,
          reason:
              'una pista cortada a medias no se le enseñó a nadie: debe poder ofrecerse otra vez');
    });

    testWidgets('con la clave ya marcada NO se asoma', (tester) async {
      await onboardingStore.markDone('requests.swipe.v1');
      await tester.pumpWidget(peekHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsNothing);
    });

    testWidgets('sin peekKey no se asoma nunca', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            SwipeToActions(
              id: 'q',
              group: ValueNotifier<Object?>(null),
              actions: [
                SwipeAction(
                  icon: Icons.delete_outline,
                  label: 'Eliminar',
                  color: Colors.red,
                  onTap: () async {},
                ),
              ],
              child: const SizedBox(
                  height: 80, width: double.infinity, child: Text('card')),
            ),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsNothing);
    });
  });
}
