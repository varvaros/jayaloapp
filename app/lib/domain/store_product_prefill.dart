import 'offer_defaults.dart';

/// Resultado puro del prellenado de la oferta al elegir un ítem de "De mi
/// tienda" (Task 9). Cada campo `null` (o, para `colorsToAdd`, una lista
/// vacía) significa "no tocar" — mismo criterio que el mapeo original: sin
/// dato, sin escritura, para no pisar algo que el proveedor ya haya tecleado
/// antes de abrir el selector.
///
/// `offersShipping`/`offersInstallation`/`requiresEvaluation` son la
/// excepción: siempre se aplican (el ítem de tienda es la fuente de verdad
/// para esas tres casillas al elegir de la tienda, igual que antes de esta
/// tarea).
class StoreProductPrefill {
  const StoreProductPrefill({
    this.fixed,
    this.svcMode,
    this.price,
    this.priceMin,
    this.priceMax,
    this.condition,
    required this.offersShipping,
    required this.offersInstallation,
    required this.requiresEvaluation,
    this.hourlyRate,
    this.estimatedHours,
    this.availability,
    this.duration,
    this.shippingPrice,
    this.installationPrice,
    this.evaluationPrice,
    this.brand,
    this.warranty,
    this.delivery,
    this.colorsToAdd = const <String>[],
  });

  final bool? fixed;
  final int? svcMode;
  final String? price;
  final String? priceMin;
  final String? priceMax;
  final String? condition; // 'Nuevo' | 'Usado'
  final bool offersShipping;
  final bool offersInstallation;
  final bool requiresEvaluation;
  final String? hourlyRate;
  final String? estimatedHours;
  final String? availability;
  final String? duration;
  final String? shippingPrice;
  final String? installationPrice;
  final String? evaluationPrice;
  final String? brand;
  final String? warranty;
  final String? delivery;
  final List<String> colorsToAdd;
}

/// Convierte un valor cualquiera a texto para un `TextEditingController`,
/// tratando "ausente"/`null`/blanco como "sin dato" (`null`), igual que el
/// `setText` del brief de la Task 9.
String? _asFieldText(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Calcula qué escribir en el formulario de oferta al elegir `p` (una fila de
/// `provider_products`, con `storeProductCols` + `offer_defaults` — Task 6)
/// desde "De mi tienda". Puro: sin `BuildContext`, sin controllers, sin
/// Supabase — así se puede probar sin montar la pantalla (que sí necesita una
/// sesión de Supabase real desde `initState`).
///
/// `isService` decide si el `pricing_mode` del molde puede mover el índice de
/// servicio; `svcModes` es el mismo orden que usa la pantalla
/// (`_svcModes`, `request_detail_screen.dart`); `existingColors` evita
/// duplicar colores ya elegidos.
///
/// Precio/color/condición/booleanos (Task 6 y anteriores) se calculan igual
/// que siempre: eso es lo que fija el test de regresión de la Task 9 para un
/// ítem sin `offer_defaults`.
///
/// Marca y garantía: la COLUMNA real (`p['brand']`/`p['warranty']`) manda; el
/// jsonb `offer_defaults` es solo respaldo para ítems donde la columna venga
/// vacía (decisión Task 6 fix round 1, extendida aquí al prellenado de
/// oferta — el molde original del brief solo miraba el jsonb).
StoreProductPrefill computeStoreProductPrefill(
  Map<String, dynamic> p, {
  required bool isService,
  required List<String> svcModes,
  required List<String> existingColors,
}) {
  final price = p['price'] as num?;
  final min = p['price_min'] as num?;
  final max = p['price_max'] as num?;
  bool? fixed;
  int? svcMode;
  String? priceText;
  String? minText;
  String? maxText;
  if (price != null) {
    fixed = true;
    svcMode = 0;
    priceText = '$price';
  } else if (min != null && max != null) {
    fixed = false;
    svcMode = 1;
    minText = '$min';
    maxText = '$max';
  }

  final colorsToAdd = <String>[];
  final color = (p['color'] as String?)?.trim() ?? '';
  if (color.isNotEmpty && !existingColors.contains(color)) {
    colorsToAdd.add(color);
  }

  final cond = (p['condition'] as String?)?.trim();
  String? condition;
  if (cond == 'nuevo') condition = 'Nuevo';
  if (cond == 'usado') condition = 'Usado';

  final offersShipping = p['offers_shipping'] == true;
  final offersInstallation = p['offers_installation'] == true;
  final requiresEvaluation = p['requires_evaluation'] == true;

  final d = (p['offer_defaults'] as Map?)?.cast<String, dynamic>();

  if (d != null) {
    final mode = d[OfferDefaults.pricingMode] as String?;
    if (isService && mode != null) {
      final i = svcModes.indexOf(mode);
      if (i >= 0) svcMode = i;
    }
    for (final c in ((d[OfferDefaults.colors] as List?)?.cast<String>() ??
        const <String>[])) {
      if (!existingColors.contains(c) && !colorsToAdd.contains(c)) {
        colorsToAdd.add(c);
      }
    }
  }

  final brand = _asFieldText(p['brand']) ??
      (d == null ? null : _asFieldText(d[OfferDefaults.brand]));
  final warranty = _asFieldText(p['warranty']) ??
      (d == null ? null : _asFieldText(d[OfferDefaults.warranty]));

  return StoreProductPrefill(
    fixed: fixed,
    svcMode: svcMode,
    price: priceText,
    priceMin: minText,
    priceMax: maxText,
    condition: condition,
    offersShipping: offersShipping,
    offersInstallation: offersInstallation,
    requiresEvaluation: requiresEvaluation,
    hourlyRate: d == null ? null : _asFieldText(d[OfferDefaults.hourlyRate]),
    estimatedHours:
        d == null ? null : _asFieldText(d[OfferDefaults.estimatedHours]),
    availability:
        d == null ? null : _asFieldText(d[OfferDefaults.availability]),
    duration: d == null ? null : _asFieldText(d[OfferDefaults.duration]),
    shippingPrice:
        d == null ? null : _asFieldText(d[OfferDefaults.shippingPrice]),
    installationPrice:
        d == null ? null : _asFieldText(d[OfferDefaults.installationPrice]),
    evaluationPrice:
        d == null ? null : _asFieldText(d[OfferDefaults.evaluationPrice]),
    brand: brand,
    warranty: warranty,
    delivery: d == null ? null : _asFieldText(d[OfferDefaults.delivery]),
    colorsToAdd: colorsToAdd,
  );
}
