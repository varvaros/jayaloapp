import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';

OfferLite o(String s, {DateTime? u}) => OfferLite(status: s, unlockedAt: u);

void main() {
  test('derivación de fases (misma semántica que la web)', () {
    expect(phaseForRequest(requestStatus: 'open', offers: []), RequestPhase.waiting);
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('pending')]),
        RequestPhase.withOffers);
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('accepted'), o('pending')]),
        RequestPhase.accepted);
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('accepted', u: DateTime(2026)), o('rejected')]),
        RequestPhase.unlocked);
    expect(
        phaseForRequest(requestStatus: 'completed', offers: [o('accepted')]),
        RequestPhase.completed);
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('completed')]),
        RequestPhase.completed);
    // rejected cuenta como oferta recibida (la web cuenta ofertas totales).
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('rejected')]),
        RequestPhase.withOffers);
  });
}
