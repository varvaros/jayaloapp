class PricingTier {
  const PricingTier(this.minRD, this.maxRD, this.points);
  final double minRD;
  final double? maxRD; // null = sin tope
  final int points;
}

/// Idéntica a `PRICING_TIERS` de la web (src/mocks/pricing-tiers.ts) y a la SQL
/// autoritativa `points_for_price_rd`. Cascada por límite SUPERIOR.
const pricingTiers = <PricingTier>[
  PricingTier(0, 3000, 1),
  PricingTier(3001, 5000, 2),
  PricingTier(5001, 8000, 3),
  PricingTier(8001, 12000, 4),
  PricingTier(12001, 18000, 5),
  PricingTier(18001, 25000, 6),
  PricingTier(25001, 32000, 7),
  PricingTier(32001, 40000, 8),
  PricingTier(40001, 50000, 9),
  PricingTier(50001, null, 10),
];

PricingTier tierForPrice(double priceRD) => pricingTiers.firstWhere(
    (t) => t.maxRD == null || priceRD <= t.maxRD!,
    orElse: () => pricingTiers.last);

int _pointsForPrice(double? priceRD) =>
    (priceRD == null || priceRD <= 0) ? 0 : tierForPrice(priceRD).points;

/// Costo fijo de desbloquear un interés de producto (Task 9) — paridad con
/// `PRODUCT_INTEREST_COST` de la web (`ProviderInterestsSection.tsx`). A
/// diferencia de `pointsForOffer` (variable según el precio de la oferta),
/// el interés no lleva precio adjunto — es un contacto de comprador — así
/// que el costo mostrado SIEMPRE es 1. El cobro real lo calcula
/// `try_unlock_product_interest` server-side; esta constante es solo para
/// mostrar el costo en la UI (misma regla que `pointsForOffer`).
const productInterestUnlockCost = 1;

/// SOLO para mostrar el costo en la UI. El cobro real lo calcula la RPC
/// `try_unlock_offer` server-side (regla de seguridad del proyecto).
int pointsForOffer({
  double? price,
  double? priceMin,
  double? priceMax,
  String? pricingMode,
  double? hourlyRate,
  double? estimatedHours,
}) {
  if (price != null && price > 0) return _pointsForPrice(price);
  if (priceMin != null && priceMax != null && priceMax >= priceMin) {
    return _pointsForPrice((priceMin + priceMax) / 2);
  }
  if (pricingMode == 'hourly' && hourlyRate != null && hourlyRate > 0) {
    final hours = (estimatedHours != null && estimatedHours > 0) ? estimatedHours : 1.0;
    return _pointsForPrice(hourlyRate * hours);
  }
  return 0;
}
