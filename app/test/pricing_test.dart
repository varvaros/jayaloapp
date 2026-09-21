import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/credit_shop.dart' show minCreditsPerUnlock;
import 'package:jayalo_app/domain/pricing.dart';

/// El modelo comercial del PO (2026-09-01, y el pitch lo fija como canónico):
/// 2 créditos por cada RD5.000 pesos de la oferta —unos RD$100—, con tope de 50.
/// Sustituye a la escala vieja de 10 tramos con tope de 10 créditos, que
/// cobraba cinco veces menos en las ofertas grandes.
void main() {
  group('creditosPorPrecio — 2 por cada RD5.000 pesos, tope 50', () {
    test('el primer tramo cubre todo lo que baja de RD5.000 pesos', () {
      expect(creditosPorPrecio(1), 2);
      expect(creditosPorPrecio(3000), 2);
      expect(creditosPorPrecio(5000), 2);
    });

    test('cada RD5.000 pesos empezado suma otros 2', () {
      expect(creditosPorPrecio(5001), 4);
      expect(creditosPorPrecio(10000), 4);
      expect(creditosPorPrecio(10001), 6);
      expect(creditosPorPrecio(25000), 10);
      expect(creditosPorPrecio(50000), 20);
      expect(creditosPorPrecio(100000), 40);
    });

    test('el tope son 50 créditos y no se pasa nunca', () {
      expect(creditosPorPrecio(125000), 50);
      expect(creditosPorPrecio(125001), 50);
      expect(creditosPorPrecio(10000000), 50);
    });

    test('sin precio no se cobra nada', () {
      expect(creditosPorPrecio(0), 0);
      expect(creditosPorPrecio(-100), 0);
    });
  });

  group('pointsForOffer — de dónde sale el precio', () {
    test('precio fijo manda', () {
      expect(pointsForOffer(price: 4000), 2);
      expect(pointsForOffer(price: 12000), 6);
    });

    test('con rango, el punto medio', () {
      expect(pointsForOffer(priceMin: 6000, priceMax: 8000), 4); // media 7000
    });

    test('por hora, tarifa × horas; sin horas se cuenta una', () {
      expect(
        pointsForOffer(pricingMode: 'hourly', hourlyRate: 2000, estimatedHours: 3),
        4, // 6000
      );
      expect(pointsForOffer(pricingMode: 'hourly', hourlyRate: 2500), 2);
    });

    test('sin nada de eso, 0', () {
      expect(pointsForOffer(), 0);
      expect(pointsForOffer(price: 0), 0);
    });
  });

  test('el desbloqueo más barato ya cuesta 2, y la tienda no puede prometer más', () {
    // `minCreditsPerUnlock` sostiene el «Hasta N clientes desbloqueados» de
    // las tarjetas de la tienda. Con la escala nueva el mínimo es 2: dejarlo
    // en 1 haría que un paquete de 10 prometiera 10 desbloqueos cuando de
    // verdad da 5.
    expect(minCreditsPerUnlock, 2);
    expect(creditosPorPrecio(1), minCreditsPerUnlock);
  });
}
