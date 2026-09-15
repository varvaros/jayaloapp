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
}
