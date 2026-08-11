import 'package:flutter_test/flutter_test.dart';

import 'package:jayalo_app/features/shared/new_offers_popup.dart';

void main() {
  group('newOffersCopy', () {
    test('cliente con una oferta habla en singular', () {
      final c = newOffersCopy(esProveedor: false, count: 1);
      expect(c.titulo, contains('ofertas nuevas'));
      expect(c.detalle, contains('Un proveedor'));
      expect(c.cta, 'Ver ofertas');
    });

    test('cliente con varias ofertas dice cuántas', () {
      final c = newOffersCopy(esProveedor: false, count: 3);
      expect(c.detalle, contains('3 proveedores'));
    });

    test('proveedor con una aceptada celebra en singular', () {
      final c = newOffersCopy(esProveedor: true, count: 1);
      expect(c.titulo, contains('SÍ'));
      expect(c.detalle, contains('Un cliente'));
      expect(c.cta, 'Ver mis ofertas');
    });

    test('proveedor con varias aceptadas dice cuántas', () {
      final c = newOffersCopy(esProveedor: true, count: 4);
      expect(c.detalle, contains('4 clientes'));
    });
  });
}
