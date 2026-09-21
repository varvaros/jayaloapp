/// Lo que cuesta desbloquear el contacto de una oferta.
///
/// Modelo comercial del PO (2026-09-01, fijado como canónico en el pitch):
/// **2 créditos por cada RD$5.000 de la oferta** —unos RD$100 al precio de
/// los paquetes— **con tope de 50 créditos**. Es una comisión plana de
/// ~2% del negocio, que deja de crecer a partir de RD$125.000.
///
/// Sustituye (2026-09-21) a la escala de 10 tramos con tope de 10 créditos,
/// que no era lineal y cobraba hasta CINCO VECES menos en las ofertas
/// grandes: una de RD$100.000 pagaba 10 créditos (0,5%) en vez de 40 (2%).
///
/// Dos consecuencias medidas de la escala nueva, las dos a propósito:
///   • el desbloqueo más barato pasa de 1 crédito a 2 (ver
///     `minCreditsPerUnlock` en `credit_shop.dart`, que sostiene el
///     «Hasta N clientes» de la tienda);
///   • sobre los 19 desbloqueos que ya existían en producción se habrían
///     cobrado 66 créditos en vez de 43 (+53%). Los cobros YA HECHOS no se
///     tocan: viven en `provider_offers.points_charged`.
library;

/// Cada cuántos pesos sube el precio del desbloqueo.
const double kTramoRD = 5000;

/// Cuántos créditos cuesta cada tramo empezado.
const int kCreditosPorTramo = 2;

/// Más allá de esto el desbloqueo no encarece (RD$125.000 en adelante).
const int kTopeCreditos = 50;

/// SOLO para mostrar el costo en la UI. El cobro REAL lo calcula la RPC
/// `try_unlock_offer` en el servidor (regla de seguridad del proyecto: el
/// cliente nunca decide lo que se cobra). Idéntica a `creditosPorOferta` de
/// la web y a la SQL autoritativa `points_for_price_rd`.
int creditosPorPrecio(double? priceRD) {
  if (priceRD == null || priceRD <= 0) return 0;
  // Tramo EMPEZADO, no cumplido: RD$5.001 ya son dos tramos. Y mínimo uno,
  // para que cualquier oferta con precio cueste algo.
  final tramos = (priceRD / kTramoRD).ceil();
  final n = (tramos < 1 ? 1 : tramos) * kCreditosPorTramo;
  return n > kTopeCreditos ? kTopeCreditos : n;
}

/// Costo fijo de desbloquear un interés de producto (Task 9) — paridad con
/// `PRODUCT_INTEREST_COST` de la web (`ProviderInterestsSection.tsx`). A
/// diferencia de [pointsForOffer] (variable según el precio de la oferta),
/// el interés no lleva precio adjunto — es un contacto de comprador — así
/// que el costo mostrado SIEMPRE es 1. El cobro real lo calcula
/// `try_unlock_product_interest` server-side.
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
  if (price != null && price > 0) return creditosPorPrecio(price);
  if (priceMin != null && priceMax != null && priceMax >= priceMin) {
    return creditosPorPrecio((priceMin + priceMax) / 2);
  }
  if (pricingMode == 'hourly' && hourlyRate != null && hourlyRate > 0) {
    final hours = (estimatedHours != null && estimatedHours > 0)
        ? estimatedHours
        : 1.0;
    return creditosPorPrecio(hourlyRate * hours);
  }
  return 0;
}
