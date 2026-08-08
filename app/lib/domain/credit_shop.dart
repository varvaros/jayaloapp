/// Lógica pura de la tienda de créditos — port de `src/lib/creditShop.ts`
/// (web). Los dos tienen que decir lo MISMO: si divergen, el mismo paquete
/// anuncia un ahorro distinto según dónde se mire.
///
/// Todo se deriva de los paquetes reales de `credit_packages`, nada
/// hardcodeado. El PRECIO que se pinta, en cambio, viene de Play
/// (`ProductDetails.price`, localizado y con impuestos), no de aquí.
library;

/// Créditos promedio por desbloqueo, usados para el estimado de contactos.
/// Punto medio de la escala 1-10 créditos de `pricing-tiers.ts`.
const int avgCreditsPerUnlock = 3;

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
    required this.contactsEstimate,
    required this.isBestValue,
    required this.isPopular,
  });

  final String id;
  final int points;
  final double priceUSD;
  final String? label;
  final String? playProductId;
  final double perCredit;

  /// % de ahorro contra el peor $/crédito activo. Redondeado, nunca negativo.
  final int savingsPct;

  /// ~contactos desbloqueables (créditos/3, mínimo 1).
  final int contactsEstimate;
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

List<ShopTier> buildShopTiers(List<ShopPackage> packages) {
  final valid = packages.where((p) => p.points > 0 && p.priceUSD > 0).toList();
  if (valid.isEmpty) return const [];

  double perCredit(ShopPackage p) => p.priceUSD / p.points;
  final basePerCredit = valid.map(perCredit).reduce((a, b) => a > b ? a : b);

  // Mejor precio: menor $/crédito; a igualdad gana el paquete más grande.
  final best = valid.reduce((a, b) {
    if (perCredit(b) < perCredit(a)) return b;
    if (perCredit(b) == perCredit(a) && b.points > a.points) return b;
    return a;
  });

  final sorted = [...valid]..sort((a, b) => a.points.compareTo(b.points));
  return sorted.map((p) {
    final pc = perCredit(p);
    final savings = ((1 - pc / basePerCredit) * 100).round();
    final contacts = (p.points / avgCreditsPerUnlock).round();
    return ShopTier(
      id: p.id,
      points: p.points,
      priceUSD: p.priceUSD,
      label: p.label,
      playProductId: p.playProductId,
      perCredit: pc,
      savingsPct: savings < 0 ? 0 : savings,
      contactsEstimate: contacts < 1 ? 1 : contacts,
      isBestValue: p.id == best.id,
      isPopular: RegExp('popular', caseSensitive: false).hasMatch(p.label ?? ''),
    );
  }).toList();
}
