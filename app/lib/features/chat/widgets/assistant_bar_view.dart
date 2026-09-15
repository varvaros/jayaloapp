import '../../../core/assistant_client.dart';

/// Qué pinta la barra del asistente dado su estado. Pura y pública para poder
/// probar el contrato sin montar la pantalla — el mismo truco que
/// `chatMenuValues` usa para el ⋮ del chat.
///
/// Gemela de `src/lib/assistantBarView.ts` en la web: **la misma tabla**. Si
/// las dos dejan de coincidir, la app y la web dicen cosas distintas del mismo
/// chat.
enum AssistantBarKind { loading, disabled, off, on, paused }

class AssistantBarView {
  const AssistantBarView(this.kind, {this.cost = 0, this.handover = false});
  final AssistantBarKind kind;

  /// Solo tiene sentido en [AssistantBarKind.off].
  final int cost;

  /// El cliente pidió hablar con una persona. Solo en `on` y `paused`.
  final bool handover;
}

AssistantBarView assistantBarView(AssistantState? s) {
  if (s == null) return const AssistantBarView(AssistantBarKind.loading);
  // El chat INACTIVO manda sobre el maestro apagado: «Activar» ya lo reenciende
  // por su cuenta en el servidor, así que bloquear aquí sería un callejón sin
  // salida donde no lo hay.
  if (!s.active) {
    return AssistantBarView(AssistantBarKind.off, cost: s.perChatCost);
  }
  // Con el chat ya activo sí importa: el motor sale de vacío con el maestro
  // apagado. La barra ofrece encenderlo desde la propia app.
  if (!s.enabled) return const AssistantBarView(AssistantBarKind.disabled);
  if (s.paused) {
    return AssistantBarView(AssistantBarKind.paused, handover: s.handoverRequested);
  }
  return AssistantBarView(AssistantBarKind.on, handover: s.handoverRequested);
}
