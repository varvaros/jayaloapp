/// ¿Se puede editar esta oferta EN SITIO, desde la propia tarjeta del detalle
/// de la solicitud? (pedido PO 2026-08-03: "Ver mi oferta").
///
/// Reproduce, sin defaults, la compuerta de
/// `_offerFormVisible` en `request_detail_screen.dart`, que es la que decide si se pinta el
/// formulario en vez de la tarjeta. Si esta función dijera que sí donde la
/// compuerta dice que no, el botón quedaría muerto.
///
/// `unlocked_at` gana sobre el status, igual que en la tarjeta (bug PO
/// 2026-07-23): una oferta con el contacto ya desbloqueado no se edita aunque
/// su status siguiera en 'pending'.
bool canEditOfferInPlace(Map<String, dynamic> offer) =>
    offer['unlocked_at'] == null && offer['status'] == 'pending';
