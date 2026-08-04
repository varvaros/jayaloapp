import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

/// Pedido PO 2026-08-03: una solicitud cuya conversación se cerró sin
/// completarse debe salir "Cerrada", apagada como la completada pero SIN el
/// violeta — el violeta es para el trato que terminó bien.
///
/// La Task 7 le añade a este fichero el grupo de widget tests, con sus imports.
void main() {
  test('el chip dice "Cerrada", sin conteo de ofertas', () {
    final (icon, label) = phaseChip(RequestPhase.closed, 3);
    expect(label, 'Cerrada');
    expect(icon, Icons.lock_outline);
    // No es "done_all": ese es el de completada y confundirlas es justo el bug.
    expect(icon, isNot(Icons.done_all));
  });

  test('permisos: cerrada se puede borrar pero no editar', () {
    expect(blockedDeleteReasonForPhase(RequestPhase.closed), isNull);
    expect(blockedEditReasonForPhase(RequestPhase.closed), isNotNull);
  });

  test('permisos: las demás fases no cambian', () {
    for (final p in [RequestPhase.waiting, RequestPhase.withOffers]) {
      expect(blockedDeleteReasonForPhase(p), isNull);
      expect(blockedEditReasonForPhase(p), isNull);
    }
    for (final p in [
      RequestPhase.accepted,
      RequestPhase.unlocked,
      RequestPhase.completed
    ]) {
      expect(blockedDeleteReasonForPhase(p), isNotNull);
      expect(blockedEditReasonForPhase(p), isNotNull);
    }
  });
}
