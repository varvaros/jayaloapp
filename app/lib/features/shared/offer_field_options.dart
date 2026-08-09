/// Opciones de campos del molde de oferta, compartidas por el formulario de
/// oferta (`request_detail_screen.dart`) y el editor de ítem de tienda
/// (`add_store_item_screen.dart`, Task 6) — para que las dos pantallas
/// ofrezcan EXACTAMENTE las mismas etiquetas.
library;

/// Presets de garantía — extraídos TAL CUAL de `request_detail_screen.dart`
/// (antes `_warrantyPresets`, paridad con `RequestRespondSection.tsx` de la
/// web). Cero cambio de comportamiento: el formulario de oferta sigue
/// mostrando las mismas once opciones, en el mismo orden.
const List<String> kWarrantyOptions = <String>[
  'Sin garantía',
  '3 días',
  '7 días',
  '15 días',
  '1 mes',
  '3 meses',
  '6 meses',
  '1 año',
  '2 años',
  '5 años',
  '10 años',
];

/// Estado del producto (Nuevo/Usado) — extraído TAL CUAL de
/// `request_detail_screen.dart` (antes `_conditionOptions`).
const List<String> kConditionOptions = <String>['Nuevo', 'Usado'];

/// Tiempo de entrega, en PLAZOS relativos (no fechas de calendario).
///
/// A diferencia de garantía y estado, esta lista NO existía como preset en
/// `request_detail_screen.dart`: ahí "Tiempo de entrega" es un
/// `showDatePicker` (`_pickDelivery`) que calcula "Hoy" / "1 día" / "N días"
/// contra la fecha de HOY — no hay una lista literal que extraer.
///
/// El editor de ítem de tienda (Task 6) no puede reusar ese selector: es una
/// PLANTILLA que se guarda una vez y se reusa en ofertas futuras, así que un
/// plazo calculado contra la fecha de creación del ítem quedaría vencido de
/// inmediato. Esta lista es una decisión propia de la Task 6 — se crea de
/// cero, con el mismo estilo de plazo relativo que ya produce
/// `_pickDelivery`. `request_detail_screen.dart` sigue con su
/// `showDatePicker`, sin tocar: cero cambio de comportamiento ahí.
const List<String> kDeliveryOptions = <String>[
  'A coordinar',
  'Mismo día',
  '1 día',
  '2-3 días',
  '1 semana',
  '2 semanas',
];
