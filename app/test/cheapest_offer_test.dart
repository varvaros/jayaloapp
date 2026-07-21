import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/request_status_screen.dart'
    show cheapestOfferId;

// El badge "Más económica" solo debe aparecer cuando hay un ganador ÚNICO por
// precio efectivo. Si dos o más ofertas empatan en el precio más bajo (pedido
// PO 2026-07-21: "solo 2 ofertas y valen lo mismo → no mostrarlo"), no orienta
// nada y no se muestra.
Map<String, dynamic> offer(String id, {num? price, String status = 'pending'}) =>
    {'id': id, 'price': price, 'status': status};

void main() {
  test('gana la más barata cuando el mínimo es único', () {
    final id = cheapestOfferId([
      offer('a', price: 1200),
      offer('b', price: 900),
      offer('c', price: 1500),
    ]);
    expect(id, 'b');
  });

  test('una sola oferta NO lleva el badge (no hay con qué comparar)', () {
    expect(cheapestOfferId([offer('a', price: 1000)]), isNull);
  });

  test('una viva con precio + otras sin precio: sin comparación → null', () {
    final id = cheapestOfferId([
      offer('a', price: 1000),
      {'id': 'b', 'pricing_mode': 'needs_evaluation', 'status': 'pending'},
    ]);
    expect(id, isNull);
  });

  test('dos ofertas con el MISMO precio: sin ganador único → null', () {
    expect(
      cheapestOfferId([offer('a', price: 1000), offer('b', price: 1000)]),
      isNull,
    );
  });

  test('empate en el mínimo con una tercera más cara → null', () {
    expect(
      cheapestOfferId([
        offer('a', price: 800),
        offer('b', price: 800),
        offer('c', price: 1200),
      ]),
      isNull,
    );
  });

  test('las rechazadas no compiten por el badge', () {
    // c es más barata pero está rechazada: gana a (mínimo único entre vivas).
    final id = cheapestOfferId([
      offer('a', price: 1000),
      offer('b', price: 1200),
      offer('c', price: 700, status: 'rejected'),
    ]);
    expect(id, 'a');
  });

  test('una rechazada que empataría el mínimo no genera empate', () {
    // La rechazada a 900 se ignora: b queda como mínimo único frente a c.
    final id = cheapestOfferId([
      offer('a', price: 900, status: 'rejected'),
      offer('b', price: 900),
      offer('c', price: 1200),
    ]);
    expect(id, 'b');
  });

  test('ofertas sin precio numérico (a evaluar) se ignoran', () {
    // a no tiene precio; entre b y c (vivas con precio) gana la menor.
    final id = cheapestOfferId([
      {'id': 'a', 'pricing_mode': 'needs_evaluation', 'status': 'pending'},
      offer('b', price: 1100),
      offer('c', price: 1500),
    ]);
    expect(id, 'b');
  });

  test('el empate cuenta el envío (precio efectivo, no base)', () {
    // a: 900 + 100 envío = 1000; b: 1000 sin envío → empatan en efectivo.
    final id = cheapestOfferId([
      {
        'id': 'a',
        'price': 900,
        'offers_shipping': true,
        'shipping_price': 100,
        'status': 'pending',
      },
      offer('b', price: 1000),
    ]);
    expect(id, isNull);
  });
}
