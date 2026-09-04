/// Qué pinta la tarjeta de solicitud de la bandeja del proveedor por SU
/// oferta a esa solicitud (pedido PO 2026-09-04): cuando te aceptaron y aún no
/// desbloqueaste el contacto, la tarjeta debe mostrar el mismo botón
/// «Conversar · N crédito(s)» que ya usa "Mis ofertas" (`startUnlockFlow` en
/// `unlock_flow.dart`) EN VEZ del chip pasivo "Aceptada" — el proveedor no
/// tiene que salir de la bandeja para arrancar el desbloqueo.
///
/// Decisión pura, sin BuildContext ni red, para poder probarla sin widgets:
/// mirror exacto del switch que ya vivía inline en `_InboxCard`
/// (`inbox_screen.dart`), con la misma regla de siempre — `unlocked_at` GANA
/// sobre el status (bug PO 2026-07-23, ver `myOfferedRequestStatuses` en
/// `data/repos.dart`).
enum InboxOfferAction {
  /// Sin oferta de este proveedor a esta solicitud (o rechazada/cancelada):
  /// no se pinta nada de estado.
  none,

  /// Oferta pendiente: chip "Ya ofertaste".
  offered,

  /// Aceptada y SIN desbloquear: el botón "Conversar · N crédito(s)".
  unlock,

  /// Contacto ya desbloqueado (o completada): chip "Desbloqueado".
  unlocked,
}

/// [status] es el status crudo de `provider_offers` ('pending', 'accepted',
/// 'completed', 'rejected', 'cancelled') o `null` si este proveedor no
/// ofertó. [unlocked] es `unlocked_at != null` de esa oferta.
InboxOfferAction inboxOfferActionFor({
  required String? status,
  required bool unlocked,
}) {
  // Unlocked_at gana SIEMPRE, sea cual sea el status (incluido un status que
  // en teoría no debería convivir con un contacto ya pagado).
  if (unlocked) return InboxOfferAction.unlocked;
  return switch (status) {
    'pending' => InboxOfferAction.offered,
    'accepted' || 'completed' => InboxOfferAction.unlock,
    _ => InboxOfferAction.none, // null, 'rejected', 'cancelled'
  };
}
