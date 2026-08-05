import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';

OfferLite o(String s, {DateTime? u, ClosedReason? closed}) =>
    OfferLite(status: s, unlockedAt: u, closedReason: closed);

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
            requestStatus: 'open', offers: [o('accepted', closed: ClosedReason.inactivity)]),
        RequestPhase.closed);
    // También con el desbloqueo hecho: "En contacto" ya no es verdad.
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', u: DateTime(2026), closed: ClosedReason.inactivity)
        ]),
        RequestPhase.closed);
  });

  test('completada gana siempre sobre cerrada', () {
    // Completar CIERRA la conversación, así que las dos condiciones se dan a la
    // vez: el orden de evaluación es lo único que las distingue.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('completed', closed: ClosedReason.inactivity)]),
        RequestPhase.completed);
    expect(
        phaseForRequest(
            requestStatus: 'completed', offers: [o('accepted', closed: ClosedReason.inactivity)]),
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

  test('cerrada exige que TODAS las aceptadas tengan la conversación cerrada', () {
    // El modelo permite hasta 3 finalistas con oferta aceptada a la vez, cada
    // uno con su propia conversación.

    // Una sola aceptada cerrada: sigue funcionando como antes.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('accepted', closed: ClosedReason.inactivity)]),
        RequestPhase.closed);

    // Dos finalistas y las dos conversaciones murieron: el trato sí está
    // muerto.
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', closed: ClosedReason.inactivity),
          o('accepted', closed: ClosedReason.inactivity),
        ]),
        RequestPhase.closed);

    // Dos finalistas, uno con el chat muerto y el otro vivo: el cliente
    // sigue negociando con el segundo, así que la solicitud NO está cerrada
    // (aquí cae en "accepted" porque ninguna de las dos tiene unlocked_at).
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', closed: ClosedReason.inactivity),
          o('accepted'),
        ]),
        isNot(RequestPhase.closed));
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', closed: ClosedReason.inactivity),
          o('accepted'),
        ]),
        RequestPhase.accepted);
  });

  test('la razón del cierre sale cuando todas las aceptadas coinciden', () {
    expect(
        closedReasonFor([o('accepted', closed: ClosedReason.inactivity)]),
        ClosedReason.inactivity);
    expect(
        closedReasonFor([
          o('accepted', closed: ClosedReason.notAgreed),
          o('accepted', closed: ClosedReason.notAgreed),
        ]),
        ClosedReason.notAgreed);
  });

  test('razones mezcladas → sin razón (el chip cae al genérico)', () {
    // Modelo de hasta 3 finalistas: un chat pudo morir por inactividad y otro
    // marcarse como no concretado. Ahí no hay una razón única que contar.
    expect(
        closedReasonFor([
          o('accepted', closed: ClosedReason.inactivity),
          o('accepted', closed: ClosedReason.notAgreed),
        ]),
        isNull);
  });

  test('sin cierre no hay razón', () {
    expect(closedReasonFor([o('accepted')]), isNull);
    expect(closedReasonFor([]), isNull);
  });
}
