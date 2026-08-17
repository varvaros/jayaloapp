import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';
import 'package:jayalo_app/features/chat/widgets/composer.dart';

/// Marcar "no concretado" ya NO es privilegio del proveedor: la RLS
/// (`Participants can update status`) y el grant por columna sobre `status`
/// siempre permitieron a los dos participantes; el gate era solo de UI.
/// "Marcar como completado" sí sigue siendo del proveedor: cierra el trato y
/// dispara la calificación.
void main() {
  test('el cliente puede marcar perdido pero no completado', () {
    final v = chatMenuValues(isProvider: false, isOpen: true);
    expect(v, contains('lost'));
    expect(v, isNot(contains('complete')));
  });

  test('el proveedor puede marcar perdido y completado', () {
    final v = chatMenuValues(isProvider: true, isOpen: true);
    expect(v, contains('lost'));
    expect(v, contains('complete'));
  });

  test('con el chat cerrado no hay cambios de estado', () {
    for (final isProvider in [true, false]) {
      final v = chatMenuValues(isProvider: isProvider, isOpen: false);
      expect(v, isNot(contains('lost')));
      expect(v, isNot(contains('complete')));
    }
  });

  test('denunciar está siempre disponible', () {
    for (final isProvider in [true, false]) {
      for (final isOpen in [true, false]) {
        expect(chatMenuValues(isProvider: isProvider, isOpen: isOpen),
            contains('report'));
      }
    }
  });

  test('el estado de embudo es solo del proveedor', () {
    expect(chatMenuValues(isProvider: true, isOpen: true), contains('funnel'));
    expect(chatMenuValues(isProvider: false, isOpen: true),
        isNot(contains('funnel')));
  });

  test('ver perfil del cliente es solo del proveedor, abierto o cerrado', () {
    // Mockup aprobado 2026-08-11: el perfil (anónimo o revelado) es de
    // CLIENTES; el cliente ya tiene su vía para ver la tienda del proveedor.
    for (final isOpen in [true, false]) {
      expect(chatMenuValues(isProvider: true, isOpen: isOpen),
          contains('profile'));
      expect(chatMenuValues(isProvider: false, isOpen: isOpen),
          isNot(contains('profile')));
    }
  });

  test('el cliente ve las DOS acciones de ubicacion, en orden', () {
    // Decision de producto (PO 2026-08-16): «Mi ubicacion actual» (GPS del
    // momento) y «Mi direccion guardada» son casos distintos y el usuario elige.
    // La actual va PRIMERA: es la que motivo la tanda.
    final labels =
        plusMenuItems(isProvider: false).map((i) => i.$3).toList();
    expect(labels, containsAllInOrder(
        ['Mi ubicación actual', 'Mi dirección guardada']));
  });

  test('el proveedor NO ve las acciones de ubicacion personal', () {
    // El proveedor manda la direccion de su LOCAL, que es otra accion.
    final acciones = plusMenuItems(isProvider: true).map((i) => i.$1).toList();
    expect(acciones, isNot(contains(PlusAction.sendCurrentLocation)));
    expect(acciones, isNot(contains(PlusAction.sendLocation)));
    expect(acciones, contains(PlusAction.sendAddress));
  });
}
