import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/assistant_client.dart';
import 'package:jayalo_app/features/chat/widgets/assistant_bar_view.dart';

AssistantState estado({
  bool active = false,
  bool paused = false,
  bool enabled = true,
  bool handover = false,
  int cost = 2,
}) =>
    AssistantState(
      active: active,
      paused: paused,
      handoverRequested: handover,
      enabled: enabled,
      perChatCost: cost,
    );

void main() {
  test('sin estado todavía no pinta nada', () {
    expect(assistantBarView(null).kind, AssistantBarKind.loading);
  });

  test('apagado: ofrece activar con el coste del servidor', () {
    final v = assistantBarView(estado());
    expect(v.kind, AssistantBarKind.off);
    expect(v.cost, 2);
  });

  test('el coste NO es un literal', () {
    expect(assistantBarView(estado(cost: 5)).cost, 5);
  });

  test('activo', () {
    final v = assistantBarView(estado(active: true));
    expect(v.kind, AssistantBarKind.on);
    expect(v.handover, false);
  });

  test('pausado gana a activo', () {
    expect(assistantBarView(estado(active: true, paused: true)).kind,
        AssistantBarKind.paused);
  });

  test('el cliente pidió humano se arrastra a los dos encendidos', () {
    expect(assistantBarView(estado(active: true, handover: true)).handover, true);
    expect(
        assistantBarView(estado(active: true, paused: true, handover: true))
            .handover,
        true);
  });

  test('con el chat activo, el maestro apagado gana a activo y a pausado', () {
    expect(assistantBarView(estado(enabled: false, active: true)).kind,
        AssistantBarKind.disabled);
    expect(
        assistantBarView(estado(enabled: false, active: true, paused: true))
            .kind,
        AssistantBarKind.disabled);
  });

  test('con el chat INACTIVO el maestro apagado NO bloquea', () {
    final v = assistantBarView(estado(enabled: false));
    expect(v.kind, AssistantBarKind.off);
    expect(v.cost, 2);
  });

  test('apagado sin coste válido: como si aún no se supiera (nunca un 0)', () {
    expect(assistantBarView(estado(cost: 0)).kind, AssistantBarKind.loading);
    expect(assistantBarView(estado(cost: -1)).kind, AssistantBarKind.loading);
  });

  test('el motivo de una no-respuesta se traduce, nunca el identificador crudo',
      () {
    expect(assistantReplyReasonMessage('handover'),
        contains('pidió hablar con una persona'));
    expect(assistantReplyReasonMessage('disabled'),
        contains('está apagado'));
    expect(assistantReplyReasonMessage('guardrail'), isNot(contains('guardrail')));
    expect(assistantReplyReasonMessage('gateway_500'),
        contains('proveedor de IA'));
    expect(assistantReplyReasonMessage('algo-nuevo-desconocido'),
        'No se generó respuesta.');
    expect(assistantReplyReasonMessage(null), 'No se generó respuesta.');
  });
}
