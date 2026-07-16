import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/pricing.dart';

void main() {
  test('tiers por límite superior (cascada, sin huecos)', () {
    expect(tierForPrice(0).points, 1);
    expect(tierForPrice(3000).points, 1);
    expect(tierForPrice(3000.5).points, 2); // caso fraccionario: NO salta al fallback
    expect(tierForPrice(3001).points, 2);
    expect(tierForPrice(5000).points, 2);
    expect(tierForPrice(8000).points, 3);
    expect(tierForPrice(12000).points, 4);
    expect(tierForPrice(18000).points, 5);
    expect(tierForPrice(25000).points, 6);
    expect(tierForPrice(32000).points, 7);
    expect(tierForPrice(40000).points, 8);
    expect(tierForPrice(50000).points, 9);
    expect(tierForPrice(50001).points, 10);
    expect(tierForPrice(999999).points, 10);
  });

  test('pointsForOffer: precio fijo > rango > por hora; 0 si nada', () {
    expect(pointsForOffer(price: 4000), 2);
    expect(pointsForOffer(priceMin: 3000, priceMax: 3001), 2); // avg 3000.5
    expect(pointsForOffer(pricingMode: 'hourly', hourlyRate: 2000, estimatedHours: 3), 3);
    expect(pointsForOffer(pricingMode: 'hourly', hourlyRate: 2500), 1); // 1h default
    expect(pointsForOffer(), 0);
    expect(pointsForOffer(price: 0), 0);
  });
}
