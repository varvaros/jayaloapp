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

    // Decisión PO 2026-08-08: la tarjeta promete "Hasta X clientes
    // desbloqueados". El desbloqueo más barato de la escala 1-10 cuesta
    // 1 crédito, así que el tope honesto es créditos/1 = créditos.
    test('el tope de clientes desbloqueables es créditos/1', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.first.maxUnlocks, 10);
      expect(tiers.last.maxUnlocks, 200);
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

  // Decisión PO 2026-08-08 (salió de la revisión): el «Ahorras X%» se pintaba
  // pegado al precio de Play pero se calculaba con el USD de la BD. Con los
  // paquetes reales la tarjeta decía 9% siendo el ahorro real en pesos 10,5%;
  // con precios psicológicos la brecha crece y puede invertirse el signo.
  // Cuando hay `rawPrices` de Play, TODO el cálculo por crédito (ahorro e
  // insignia de mejor precio) sale de ahí.
  group('buildShopTiers con precios de Play', () {
    const a = ShopPackage(
        id: 'a', points: 10, priceUSD: 10, playProductId: 'creditos_10usd');
    const b = ShopPackage(
        id: 'b', points: 55, priceUSD: 50, playProductId: 'creditos_50usd');

    test('el ahorro sale del precio REAL de Play, no del USD de la BD', () {
      // En USD: 0.909/cr vs 1.00/cr => 9%. En RD\$ de Play: 650 y 3200 =>
      // 58.18/cr vs 65/cr => 10%. Lo que ve el usuario es RD\$.
      final tiers = buildShopTiers([a, b],
          rawPrices: {'creditos_10usd': 650, 'creditos_50usd': 3200});
      expect(tiers.last.savingsPct, 10,
          reason: 'con el USD de la BD diría 9%, y el precio pintado al lado '
              'es el de Play');
    });

    test('con precios psicológicos el signo puede invertirse: manda Play', () {
      // En USD el grande "ahorra" 9%; en RD\$ Play redondeó a 675 y 3900 =>
      // 67.5/cr vs 70.9/cr: el grande es PEOR por crédito.
      final tiers = buildShopTiers([a, b],
          rawPrices: {'creditos_10usd': 675, 'creditos_50usd': 3900});
      expect(tiers.last.savingsPct, 0,
          reason: 'anunciar ahorro donde no lo hay es el peor caso del bug');
      expect(tiers.first.savingsPct, 5); // 1 - 67.5/70.9 => 4.8 -> 5
    });

    test('la insignia de mejor precio se decide con los mismos precios', () {
      final tiers = buildShopTiers([a, b],
          rawPrices: {'creditos_10usd': 675, 'creditos_50usd': 3900});
      expect(tiers.firstWhere((t) => t.isBestValue).id, 'a',
          reason: 'insignia por USD y ahorro por Play en la misma tarjeta '
              'se contradirían');
    });

    test('un paquete sin precio de Play no ancla el ahorro ni gana insignia', () {
      // 'c' no está en la consola: la tarjeta ni se pinta (el body filtra),
      // así que tampoco puede ser la referencia del % de los demás.
      const c = ShopPackage(
          id: 'c', points: 5, priceUSD: 20, playProductId: 'creditos_20usd');
      final tiers = buildShopTiers([a, b, c],
          rawPrices: {'creditos_10usd': 650, 'creditos_50usd': 3200});
      expect(tiers.firstWhere((t) => t.id == 'b').savingsPct, 10);
      expect(tiers.firstWhere((t) => t.id == 'c').savingsPct, 0);
      expect(tiers.firstWhere((t) => t.id == 'c').isBestValue, isFalse);
    });

    test('sin rawPrices el cálculo USD sigue intacto (paridad web)', () {
      final tiers = buildShopTiers([a, b]);
      expect(tiers.last.savingsPct, 9);
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
