enum RequestPhase { waiting, withOffers, accepted, unlocked, completed }

class OfferLite {
  const OfferLite({required this.status, this.unlockedAt});
  final String status; // pending | accepted | completed | rejected
  final DateTime? unlockedAt;
}

/// Réplica de la derivación de la web (src/routes/requests/$requestId.tsx
/// ~L989-1010): completed si la solicitud está completed/closed o la oferta
/// aceptada está completed; unlocked si la aceptada tiene unlocked_at;
/// accepted si hay aceptada; si no, por conteo de ofertas recibidas.
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
  if (acceptedOffer != null && acceptedOffer.unlockedAt != null) {
    return RequestPhase.unlocked;
  }
  if (acceptedOffer != null) return RequestPhase.accepted;
  return offers.isEmpty ? RequestPhase.waiting : RequestPhase.withOffers;
}
