import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/credit_shop.dart';

void main() {
  // Los 4 paquetes reales de producción.
  final packages = [
    const ShopPackage(id: 'a', points: 10, priceUSD: 10, label: 'Inicial — 10 puntos'),
    const ShopPackage(id: 'b', points: 55, priceUSD: 50, label: 'Popular — 55 puntos'),
    const ShopPackage(id: 'c', points: 110, priceUSD: 100, label: 'Pro — 110 puntos'),
    const ShopPackage(id: 'd', points: 200, priceUSD: 180, label: 'Max — 200 puntos'),
  ];

  group('buildShopTiers', () {
    test('ordena por créditos ascendente', () {
      final tiers = buildShopTiers(packages.reversed.toList());
      expect(tiers.map((t) => t.points), [10, 55, 110, 200]);
    });

    test('el ahorro se mide contra el PEOR \$/crédito y nunca es negativo', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.first.savingsPct, 0); // el de entrada ES el peor
      expect(tiers.last.savingsPct, 10); // 0.90 vs 1.00 => 10%
      expect(tiers.every((t) => t.savingsPct >= 0), isTrue);
    });

    test('a igualdad de \$/crédito, "mejor precio" es el paquete MÁS GRANDE', () {
      // Pro (110/\$100) y Popular (55/\$50) empatan a \$0.909; gana Max.
      final tiers = buildShopTiers(packages);
      expect(tiers.firstWhere((t) => t.isBestValue).points, 200);
      expect(tiers.where((t) => t.isBestValue).length, 1);
    });

    test('"Más popular" NO se inventa: solo si el label del admin lo dice', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.where((t) => t.isPopular).map((t) => t.points), [55]);
    });

    test('el estimado de contactos es créditos/3, mínimo 1', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.first.contactsEstimate, 3); // 10/3 = 3.33 -> 3
      expect(
        buildShopTiers([const ShopPackage(id: 'x', points: 1, priceUSD: 2)]).first.contactsEstimate,
        1,
      );
    });

    test('descarta paquetes con puntos o precio no positivos', () {
      final tiers = buildShopTiers([
        const ShopPackage(id: 'ok', points: 10, priceUSD: 10),
        const ShopPackage(id: 'sin-puntos', points: 0, priceUSD: 10),
        const ShopPackage(id: 'gratis', points: 10, priceUSD: 0),
      ]);
      expect(tiers.map((t) => t.id), ['ok']);
    });

    test('lista vacía devuelve lista vacía (no lanza)', () {
      expect(buildShopTiers([]), isEmpty);
    });
  });

  group('tierName', () {
    test('recorta el sufijo cuando repite el número', () {
      expect(tierName('Inicial — 10 puntos'), 'Inicial');
      expect(tierName('Pro — 110 puntos'), 'Pro');
    });

    test('NO mutila un label sin dígitos en el sufijo', () {
      expect(tierName('Ahorro — el más pedido'), 'Ahorro — el más pedido');
    });

    test('devuelve null si no hay label', () {
      expect(tierName(null), isNull);
      expect(tierName('   '), isNull);
    });
  });
}
