/// Lógica pura de la tienda de créditos — port de `src/lib/creditShop.ts`
/// (web). La ESTRUCTURA es la misma; los números por crédito divergen a
/// propósito: cada tienda calcula el ahorro con el precio que su usuario
/// tiene delante (la web con el USD de PayPal, la app con el `rawPrice` de
/// Play vía [buildShopTiers]`.rawPrices`). Con el USD de la BD la app decía
/// "Ahorras 9%" siendo el ahorro real en pesos 10,5%, y con precios
/// psicológicos el signo puede invertirse.
///
/// Todo se deriva de los paquetes reales de `credit_packages`, nada
/// hardcodeado. El PRECIO que se pinta viene de Play (`ProductDetails.price`,
/// localizado y con impuestos), no de aquí.
library;

/// Créditos del desbloqueo MÁS BARATO de la escala 1-10 de `pricing-tiers.ts`
/// (nivel 1, hasta RD$3.000 = 1 crédito). Sostiene el "Hasta N clientes
/// desbloqueados" de la tarjeta: el tope honesto es créditos/este mínimo.
const int minCreditsPerUnlock = 1;

class ShopPackage {
  const ShopPackage({
    required this.id,
    required this.points,
    required this.priceUSD,
    this.label,
    this.playProductId,
  });

  final String id;
  final int points;
  final double priceUSD;
  final String? label;
  final String? playProductId;
}

class ShopTier {
  const ShopTier({
    required this.id,
    required this.points,
    required this.priceUSD,
    required this.label,
    required this.playProductId,
    required this.perCredit,
    required this.savingsPct,
    required this.maxUnlocks,
    required this.isBestValue,
    required this.isPopular,
  });

  final String id;
  final int points;
  final double priceUSD;
  final String? label;
  final String? playProductId;
  final double perCredit;

  /// % de ahorro contra el peor precio-por-crédito activo, calculado con la
  /// MISMA moneda que el precio pintado (Play si hay `rawPrices`, USD si no).
  /// Redondeado, nunca negativo.
  final int savingsPct;

  /// Tope de clientes desbloqueables: créditos / [minCreditsPerUnlock].
  /// La tarjeta lo pinta como "Hasta N clientes desbloqueados".
  final int maxUnlocks;
  final bool isBestValue;
  final bool isPopular;
}

/// Nombre corto para el chip de tier a partir del label del admin.
///
/// Los labels de producción son "Inicial — 10 puntos": el sufijo repite el
/// número que la tarjeta ya muestra en grande y dice "puntos" (término viejo;
/// la UI dice créditos). Solo se recorta cuando el sufijo trae dígitos, para
/// no mutilar un label legítimo como "Ahorro — el más pedido".
String? tierName(String? label) {
  final raw = (label ?? '').trim();
  if (raw.isEmpty) return null;
  final m = RegExp(r'^(.*?)\s*[—–-]\s*(.*)$').firstMatch(raw);
  final head = m?.group(1);
  final tail = m?.group(2) ?? '';
  final name = (head != null && head.isNotEmpty && RegExp(r'\d').hasMatch(tail))
      ? head.trim()
      : raw;
  return name.isEmpty ? null : name;
}

/// [rawPrices] es `playProductId -> ProductDetails.rawPrice`. Cuando llega,
/// TODA la economía por crédito (ahorro e insignia de mejor precio) se calcula
/// con esos precios — los que el usuario tiene delante, en su moneda — y los
/// paquetes sin precio de Play quedan fuera del cálculo: su tarjeta no se
/// pinta (el body filtra), así que tampoco pueden anclar el % de los demás.
/// Comparar razones dentro de la MISMA moneda no necesita conversión.
List<ShopTier> buildShopTiers(
  List<ShopPackage> packages, {
  Map<String, double>? rawPrices,
}) {
  final valid = packages.where((p) => p.points > 0 && p.priceUSD > 0).toList();
  if (valid.isEmpty) return const [];

  double? rawOf(ShopPackage p) {
    final raw = rawPrices?[p.playProductId];
    return (raw != null && raw > 0) ? raw : null;
  }

  // Con precios de Play, la economía se restringe a los paquetes que Play
  // conoce; sin ellos (web, o antes de cargar), USD para todos.
  final usePlay = valid.any((p) => rawOf(p) != null);
  double? perCredit(ShopPackage p) {
    if (!usePlay) return p.priceUSD / p.points;
    final raw = rawOf(p);
    return raw == null ? null : raw / p.points;
  }

  final priced = valid.where((p) => perCredit(p) != null).toList();
  final basePerCredit =
      priced.map((p) => perCredit(p)!).reduce((a, b) => a > b ? a : b);

  // Mejor precio: menor precio/crédito; a igualdad gana el paquete más grande.
  final best = priced.reduce((a, b) {
    if (perCredit(b)! < perCredit(a)!) return b;
    if (perCredit(b) == perCredit(a) && b.points > a.points) return b;
    return a;
  });

  final sorted = [...valid]..sort((a, b) => a.points.compareTo(b.points));
  return sorted.map((p) {
    final pc = perCredit(p);
    final savings =
        pc == null ? 0 : ((1 - pc / basePerCredit) * 100).round();
    return ShopTier(
      id: p.id,
      points: p.points,
      priceUSD: p.priceUSD,
      label: p.label,
      playProductId: p.playProductId,
      perCredit: pc ?? p.priceUSD / p.points,
      savingsPct: savings < 0 ? 0 : savings,
      maxUnlocks: p.points ~/ minCreditsPerUnlock,
      isBestValue: p.id == best.id,
      isPopular: RegExp('popular', caseSensitive: false).hasMatch(p.label ?? ''),
    );
  }).toList();
}
