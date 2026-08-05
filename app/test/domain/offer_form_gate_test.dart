import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_form_gate.dart';

void main() {
  const bid = 'b-1';

  test('sin negocio y sin editar: no hay formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: null, offerChecked: true, existingOffer: null),
        isFalse);
  });

  test('mientras se comprueba si ya ofertó: no hay formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: bid, offerChecked: false, existingOffer: null),
        isFalse);
  });

  test('sin oferta previa: formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: bid, offerChecked: true, existingOffer: null),
        isTrue);
  });

  test('con oferta ya enviada: tarjeta, no formulario', () {
    expect(
        offerFormVisible(
            editing: false,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'pending'}),
        isFalse);
  });

  test('editando una PENDIENTE: formulario', () {
    expect(
        offerFormVisible(
            editing: true,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'pending'}),
        isTrue);
  });

  test('una ACEPTADA no se edita nunca: tarjeta', () {
    expect(
        offerFormVisible(
            editing: true,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'accepted'}),
        isFalse);
  });
}
