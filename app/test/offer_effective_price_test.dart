import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/request_status_screen.dart'
    show offerEffectivePrice;

// El badge "Más económica" ordena por precio EFECTIVO = precio + envío
// (pedido PO). Estas pruebas fijan esa suma para que no vuelva a compararse
// solo por el precio base.
void main() {
  test('precio fijo sin envío = el precio base', () {
    expect(offerEffectivePrice({'price': 1000}), 1000);
  });

  test('suma el envío cuando el proveedor lo cobra', () {
    expect(
        offerEffectivePrice(
            {'price': 1000, 'offers_shipping': true, 'shipping_price': 250}),
        1250);
  });

  test('ignora el envío si offers_shipping es false', () {
    expect(
        offerEffectivePrice(
            {'price': 1000, 'offers_shipping': false, 'shipping_price': 250}),
        1000);
  });

  test('una oferta más cara en base puede ganar si la otra cobra envío', () {
    final a = offerEffectivePrice(
        {'price': 900, 'offers_shipping': true, 'shipping_price': 300}); // 1200
    final b = offerEffectivePrice({'price': 1000}); // 1000
    expect(b! < a!, isTrue);
  });

  test('rango usa el mínimo como base y le suma el envío', () {
    expect(
        offerEffectivePrice({
          'price_min': 800,
          'price_max': 1200,
          'offers_shipping': true,
          'shipping_price': 100
        }),
        900);
  });

  test('sin precio numérico (a evaluar) devuelve null', () {
    expect(offerEffectivePrice({'pricing_mode': 'needs_evaluation'}), isNull);
  });
}
