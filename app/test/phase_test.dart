import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';

OfferLite o(String s, {DateTime? u, bool closed = false}) =>
    OfferLite(status: s, unlockedAt: u, conversationClosed: closed);

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

  test('cerrada: la conversación de la oferta aceptada murió sin completarse', () {
    // Hallazgo del PO 2026-08-03: el chat se cierra (a mano o por el cron de
    // inactividad) y la solicitud seguía pintándose como trato vivo.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('accepted', closed: true)]),
        RequestPhase.closed);
    // También con el desbloqueo hecho: "En contacto" ya no es verdad.
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', u: DateTime(2026), closed: true)
        ]),
        RequestPhase.closed);
  });

  test('completada gana siempre sobre cerrada', () {
    // Completar CIERRA la conversación, así que las dos condiciones se dan a la
    // vez: el orden de evaluación es lo único que las distingue.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('completed', closed: true)]),
        RequestPhase.completed);
    expect(
        phaseForRequest(
            requestStatus: 'completed', offers: [o('accepted', closed: true)]),
        RequestPhase.completed);
  });

  test('una conversación viva no cierra nada', () {
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('accepted')]),
        RequestPhase.accepted);
    // Una oferta NO aceptada no tiene conversación; aunque llegara el dato, la
    // solicitud sigue viva porque el cliente aún puede aceptar otra.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('pending'), o('rejected')]),
        RequestPhase.withOffers);
  });
}
