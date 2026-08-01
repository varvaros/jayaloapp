import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

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
}
