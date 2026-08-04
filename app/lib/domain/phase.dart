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
/// ~L1146-1164): completed si la solicitud está completed/closed o alguna
/// oferta aceptada está completed; CERRADA si TODAS las ofertas aceptadas
/// tienen su conversación cerrada sin haberse completado; unlocked si alguna
/// aceptada tiene unlocked_at; accepted si hay aceptada; si no, por conteo de
/// ofertas recibidas.
///
/// El ORDEN es parte del contrato: completar cierra la conversación, así que en
/// una completada se cumplen las dos condiciones a la vez y solo el orden las
/// distingue. `completed` va primero y gana siempre.
RequestPhase phaseForRequest({
  required String requestStatus,
  required List<OfferLite> offers,
}) {
  final acceptedOffers = offers
      .where((o) => o.status == 'accepted' || o.status == 'completed')
      .toList();
  final requestClosed = requestStatus == 'completed' || requestStatus == 'closed';
  final offerDone = acceptedOffers.any((o) => o.status == 'completed');
  if (requestClosed || offerDone) return RequestPhase.completed;

  // El modelo de negocio permite hasta 3 finalistas con oferta aceptada a la
  // vez (el trigger enforce_single_accepted_offer_per_request solo bloquea a
  // partir de la cuarta), y cada finalista tiene su propia conversación.
  // "Cerrada" exige que TODAS esas conversaciones estén muertas: si queda un
  // solo chat vivo, el cliente sigue negociando con alguien y la solicitud NO
  // está muerta — decirle "Cerrada" sería mentira. Además cancel_customer_
  // request en el backend exige lo mismo (todas las ofertas desbloqueadas con
  // el chat cerrado) antes de aceptar la cancelación: si aquí bastara con la
  // primera oferta aceptada de una lista sin orden garantizado, se ofrecería
  // "Eliminar" para una solicitud que la RPC luego rechazaría.
  if (acceptedOffers.isNotEmpty &&
      acceptedOffers.every((o) => o.conversationClosed)) {
    return RequestPhase.closed;
  }

  // No todas cerradas: el cliente sigue en contacto si CUALQUIER finalista
  // tiene el chat desbloqueado (unlocked_at puesto), no solo el primero de la
  // lista — es un OR entre finalistas, no "quien llegue primero".
  if (acceptedOffers.any((o) => o.unlockedAt != null)) {
    return RequestPhase.unlocked;
  }
  if (acceptedOffers.isNotEmpty) return RequestPhase.accepted;
  return offers.isEmpty ? RequestPhase.waiting : RequestPhase.withOffers;
}
