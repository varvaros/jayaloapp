library;

import 'money.dart' show fmtRD;

/// El mensaje al cliente de una oferta ya NO es un campo de texto libre
/// (decisión PO 2026-07-20: se quita la caja para no invitar al proveedor a
/// dejar su teléfono y saltarse el desbloqueo pagado — [[jayalo-doctrina-tiendas-y-canal-interno]]).
/// Se arma desde los datos ESTRUCTURADOS de la oferta. Puede quedar vacío: la
/// columna `provider_offers.message` es NOT NULL con default ''.
String composeOfferMessage({
  required bool isService,
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  String availabilityNote = '',
  String estimatedDuration = '',
  String brand = '',
  List<String> colors = const [],
  String warranty = '',
  String deliveryTime = '',
  String condition = '',
}) {
  final parts = <String>[];
  if (!isService) {
    // Detalles del producto (estado/marca/color/garantía/entrega) — paridad web.
    if (condition.trim().isNotEmpty) parts.add('Estado: ${condition.trim()}');
    if (brand.trim().isNotEmpty) parts.add('Marca: ${brand.trim()}');
    if (colors.isNotEmpty) parts.add('Color: ${colors.join(', ')}');
    if (warranty.trim().isNotEmpty) parts.add('Garantía: ${warranty.trim()}');
    if (deliveryTime.trim().isNotEmpty) {
      parts.add('Entrega: ${deliveryTime.trim()}');
    }
    if (offersShipping) {
      parts.add((shippingPrice != null && shippingPrice > 0)
          ? 'Envío: ${fmtRD(shippingPrice)}'
          : 'Envío gratis');
    }
    if (offersInstallation) {
      parts.add((installationPrice != null && installationPrice > 0)
          ? 'Instalación: ${fmtRD(installationPrice)}'
          : 'Instalación incluida');
    }
    if (requiresEvaluation) {
      parts.add((evaluationPrice != null && evaluationPrice > 0)
          ? 'Evaluación: ${fmtRD(evaluationPrice)}'
          : 'Requiere evaluación en sitio');
    }
  } else {
    if (availabilityNote.trim().isNotEmpty) {
      parts.add('Disponibilidad: ${availabilityNote.trim()}');
    }
    if (estimatedDuration.trim().isNotEmpty) {
      parts.add('Duración: ${estimatedDuration.trim()}');
    }
    if (requiresEvaluation) parts.add('Requiere evaluación en sitio');
  }
  return parts.join(' · ');
}
