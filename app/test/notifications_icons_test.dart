import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/notifications.dart';

void main() {
  test('los avisos de cierre de conversación tienen icono propio, no la campana', () {
    // Antes del 2026-08-03 estos carteles llegaban como `message_new`
    // ("Nuevo mensaje"); ahora tienen kind propio y no deben caer al fallback.
    expect(iconFor('conversation_completed'), Icons.check_circle_outline);
    expect(iconFor('conversation_closed_inactivity'), Icons.hourglass_disabled);
    // El aviso PREVIO ya existía y no cambia.
    expect(iconFor('conversation_inactivity_warning'), Icons.hourglass_bottom);
  });

  test('los kinds de conversación son de la familia system', () {
    expect(familyFor('conversation_completed'), NotifFamily.system);
    expect(familyFor('conversation_closed_inactivity'), NotifFamily.system);
  });
}
