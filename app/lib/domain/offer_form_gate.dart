/// ¿El detalle de solicitud del proveedor pinta el FORMULARIO de la oferta, o
/// una de las tres cosas que lo sustituyen?
///
/// Regla pura, sin `BuildContext` ni estado: así se prueba de verdad, sin montar
/// una pantalla que necesita red y sesión. Mismo patrón que `offer_edit.dart`.
///
/// Es la negación EXACTA de las tres ramas que la preceden en la cadena del
/// `build` (`request_detail_screen.dart`):
///   1. `!editing && businessId == null` → CTA "completa tu negocio en la web"
///   2. `!offerChecked`                  → spinner
///   3. oferta existente que no sea edición de una PENDIENTE → tarjeta de estado
///
/// MANTENIMIENTO: `offer_edit.dart` (`canEditOfferInPlace`) reproduce la TERCERA
/// de esas condiciones para decidir si "Ver mi oferta" hace algo. Si tocas esta
/// regla, actualiza también aquella o el botón vuelve a quedar muerto.
bool offerFormVisible({
  required bool editing,
  required String? businessId,
  required bool offerChecked,
  required Map<String, dynamic>? existingOffer,
}) =>
    !(!editing && businessId == null) &&
    offerChecked &&
    !(existingOffer != null &&
        (!editing || existingOffer['status'] != 'pending'));
