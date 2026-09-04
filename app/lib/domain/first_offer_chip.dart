/// Chip «¡Haz la primera oferta!» de la bandeja del proveedor (pedido PO
/// 2026-09-04): cuando una solicitud del marketplace todavía no tiene NINGUNA
/// oferta, la tarjeta invita a ser el primero. Desaparece solo en cuanto
/// llega la primera oferta (de cualquier proveedor).
///
/// Mismo copy que `providerSlotSignal(_, 0)` en `finalist_slots.dart` —
/// intencional, no duplicado por descuido: esa función pinta el banner del
/// DETALLE y esta decide el chip de la LISTA, con su propia fuente de datos
/// (`offers_count` de la fila, no `offerCountsForRequests`).
const String firstOfferChipText = '¡Haz la primera oferta!';

/// ¿Se pinta el chip en esta tarjeta?
///
/// - `offersCount == null` → desconocido (falló la lectura best-effort):
///   NUNCA se muestra, para no prometer «sé el primero» sobre una solicitud
///   que en realidad ya tiene ofertas.
/// - `hasMyOffer == true` → este proveedor ya ofertó; invitarlo a "ser el
///   primero" no tiene sentido.
/// - `isMarketplace == false` → tarjetas de interés de tienda ('source' ==
///   'store'): no son solicitudes del marketplace y no llevan `offers_count`.
/// - En cualquier otro caso, solo cuando el conteo es exactamente 0.
bool showFirstOfferChip({
  required int? offersCount,
  required bool hasMyOffer,
  required bool isMarketplace,
}) {
  if (offersCount == null) return false;
  if (hasMyOffer) return false;
  if (!isMarketplace) return false;
  return offersCount == 0;
}
