enum RequestPhase { waiting, withOffers, accepted, unlocked, completed, closed }

class OfferLite {
  const OfferLite({
    required this.status,
    this.unlockedAt,
    this.conversationClosed = false,
  });
  final String status; // pending | accepted | completed | rejected
  final DateTime? unlockedAt;

  /// La conversación de esta oferta tiene `closed_at` puesto. Solo existen
  /// conversaciones para ofertas aceptadas o completadas (verificado contra
  /// producción 2026-08-03), así que este dato solo llega con sentido ahí.
  /// Default `false`: los llamadores que no consultan conversaciones no
  /// cambian de comportamiento.
  final bool conversationClosed;
}

/// Réplica de la derivación de la web (src/routes/requests/$requestId.tsx
/// ~L1146-1164): completed si la solicitud está completed/closed o la oferta
/// aceptada está completed; CERRADA si esa oferta tiene su conversación cerrada
/// sin haberse completado; unlocked si la aceptada tiene unlocked_at; accepted
/// si hay aceptada; si no, por conteo de ofertas recibidas.
///
/// El ORDEN es parte del contrato: completar cierra la conversación, así que en
/// una completada se cumplen las dos condiciones a la vez y solo el orden las
/// distingue. `completed` va primero y gana siempre.
RequestPhase phaseForRequest({
  required String requestStatus,
  required List<OfferLite> offers,
}) {
  final accepted =
      offers.where((o) => o.status == 'accepted' || o.status == 'completed');
  final acceptedOffer = accepted.isEmpty ? null : accepted.first;
  final requestClosed = requestStatus == 'completed' || requestStatus == 'closed';
  final offerDone = acceptedOffer?.status == 'completed';
  if (requestClosed || offerDone) return RequestPhase.completed;
  // El trato murió: el chat se cerró (a mano, como "no concretado", o por el
  // cron de inactividad) sin que nadie lo diera por completado.
  if (acceptedOffer != null && acceptedOffer.conversationClosed) {
    return RequestPhase.closed;
  }
  if (acceptedOffer != null && acceptedOffer.unlockedAt != null) {
    return RequestPhase.unlocked;
  }
  if (acceptedOffer != null) return RequestPhase.accepted;
  return offers.isEmpty ? RequestPhase.waiting : RequestPhase.withOffers;
}
