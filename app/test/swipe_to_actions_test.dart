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
}
