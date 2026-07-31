import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/swipe_to_actions.dart';

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
}
