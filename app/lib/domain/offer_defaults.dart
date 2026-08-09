/// Claves canónicas del jsonb `provider_products.offer_defaults` (Task 6).
///
/// Las escribe el editor de ítem de tienda ([buildOfferDefaults]:
/// `add_store_item_screen.dart`); las leerá el prellenado de la oferta al
/// elegir un producto/servicio de la tienda (Task 9). Nada más las toca —
/// mantenerlas en un solo lugar evita que el nombre de una clave diverja
/// entre quien escribe y quien lee.
///
/// Puro, sin Flutter: es jsonb, no widgets.
class OfferDefaults {
  OfferDefaults._();

  static const pricingMode = 'pricing_mode'; // fixed|range|hourly|needs_evaluation
  static const hourlyRate = 'hourly_rate'; // num
  static const estimatedHours = 'estimated_hours'; // num
  static const availability = 'availability'; // String
  static const duration = 'duration'; // String
  static const shippingPrice = 'shipping_price'; // num
  static const installationPrice = 'installation_price'; // num
  static const evaluationPrice = 'evaluation_price'; // num
  static const brand = 'brand'; // String
  static const warranty = 'warranty'; // String (etiqueta del selector)
  static const delivery = 'delivery'; // String (etiqueta del selector)
  static const colors = 'colors'; // List<String>
}

/// Arma el jsonb `offer_defaults` con SOLO las claves que traen valor: sin
/// `null`, sin strings vacíos (tras `trim`) y sin listas vacías. Un editor
/// que deja todo en blanco escribe `{}`, no un mapa lleno de nulls — así el
/// prellenado de la Task 9 puede tratar "clave ausente" como "sin dato" sin
/// tener que distinguirlo de "el proveedor puso vacío a propósito".
///
/// Los valores `String` se guardan trimmeados.
Map<String, dynamic> buildOfferDefaults({
  String? pricingMode,
  num? hourlyRate,
  num? estimatedHours,
  String? availability,
  String? duration,
  num? shippingPrice,
  num? installationPrice,
  num? evaluationPrice,
  String? brand,
  String? warranty,
  String? delivery,
  List<String> colors = const [],
}) {
  final d = <String, dynamic>{};

  void putString(String key, String? v) {
    final t = v?.trim();
    if (t != null && t.isNotEmpty) d[key] = t;
  }

  void putNum(String key, num? v) {
    if (v != null) d[key] = v;
  }

  putString(OfferDefaults.pricingMode, pricingMode);
  putNum(OfferDefaults.hourlyRate, hourlyRate);
  putNum(OfferDefaults.estimatedHours, estimatedHours);
  putString(OfferDefaults.availability, availability);
  putString(OfferDefaults.duration, duration);
  putNum(OfferDefaults.shippingPrice, shippingPrice);
  putNum(OfferDefaults.installationPrice, installationPrice);
  putNum(OfferDefaults.evaluationPrice, evaluationPrice);
  putString(OfferDefaults.brand, brand);
  putString(OfferDefaults.warranty, warranty);
  putString(OfferDefaults.delivery, delivery);
  if (colors.isNotEmpty) d[OfferDefaults.colors] = colors;

  return d;
}
