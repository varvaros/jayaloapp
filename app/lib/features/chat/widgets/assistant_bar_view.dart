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
    // La RPC que cobra calcula el coste con GREATEST(1, …): un coste ≤ 0
    // NUNCA es legítimo, siempre significa que la respuesta no trajo el
    // precio. El precio no se inventa en el cliente — mejor no pintar nada
    // (como si aún no se supiera el estado) que un «Activar 🪙 0».
    if (s.perChatCost <= 0) return const AssistantBarView(AssistantBarKind.loading);
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

/// Traduce el `reason` cerrado que manda el servidor cuando `reply` no
/// contesta a algo que un proveedor entienda — nunca el identificador crudo.
/// Lista cerrada, ver `sales-assistant-reply.server.ts` en la web.
String assistantReplyReasonMessage(String? reason) {
  switch (reason) {
    case 'disabled':
      return 'No se generó respuesta: el asistente está apagado.';
    case 'inactive':
      return 'No se generó respuesta: el asistente no está activo en este chat.';
    case 'closed':
      return 'No se generó respuesta: la solicitud ya está cerrada.';
    case 'handover':
      return 'No se generó respuesta: el cliente pidió hablar con una persona.';
    case 'manual_takeover':
    case 'manual_takeover_during_delay':
      return 'No se generó respuesta: ya respondiste tú, así que el asistente se apartó.';
    case 'guardrail':
      return 'No se generó respuesta: el asistente se detuvo por seguridad. Revisa el chat.';
    case 'duplicate':
      return 'No se generó respuesta: ya se había respondido a este mensaje.';
    case 'empty':
    case 'empty_after_filter':
      return 'No se generó respuesta: el asistente no tuvo nada que decir.';
    case 'no_messages':
      return 'No se generó respuesta: todavía no hay mensajes del cliente.';
    case 'provider_last':
      return 'No se generó respuesta: el último mensaje ya es tuyo.';
    case 'superseded':
    case 'paused_during_delay':
      return 'No se generó respuesta: el chat cambió antes de que contestara.';
    case 'no_api_key':
      return 'No se generó respuesta: el asistente todavía no está configurado.';
    case 'insert_failed':
      return 'No se generó respuesta: no se pudo guardar la respuesta.';
    default:
      if (reason != null && reason.startsWith('gateway_')) {
        return 'No se generó respuesta: el proveedor de IA no respondió a tiempo.';
      }
      return 'No se generó respuesta.';
  }
}
