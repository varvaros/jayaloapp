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

/// Texto de `message` que NO está ya representado por un tile del detalle.
///
/// El detalle de la oferta pinta los datos estructurados como tarjetas con
/// ícono; debajo, `message` repetía esas mismas partes (las escribe
/// [composeOfferMessage] con los mismos datos) más el eventual texto libre que
/// la web todavía permite. Esta función quita solo las partes cuya etiqueta
/// coincide con un tile YA mostrado ([shownLabels], p. ej. {'Estado',
/// 'Garantía', 'Envío'}) y conserva todo lo demás — una parte estructurada sin
/// tile (oferta vieja sin columnas) sigue siendo la única fuente de ese dato y
/// no se pierde.
String freeTextFromOfferMessage(String message, Set<String> shownLabels) {
  // Partes SIN ':' que emite composeOfferMessage, por etiqueta de su tile.
  const literales = {
    'Envío gratis': 'Envío',
    'Instalación incluida': 'Instalación',
    'Requiere evaluación en sitio': 'Evaluación',
  };
  bool cubierta(String parte) {
    final porLiteral = literales[parte];
    if (porLiteral != null) return shownLabels.contains(porLiteral);
    final idx = parte.indexOf(': ');
    if (idx <= 0) return false;
    return shownLabels.contains(parte.substring(0, idx));
  }

  return message
      .split(' · ')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && !cubierta(p))
      .join(' · ');
}

/// Inverso de la condicion que escribe [composeOfferMessage].
///
/// La oferta NO guarda "Nuevo/Usado" en columna propia: viaja dentro de
/// `message` como la parte `Estado: <valor>`. Con el campo vuelto obligatorio,
/// editar una oferta sin esto obligaria al proveedor a volver a marcarlo en
/// cada pasada.
///
/// En la app el mensaje se arma solo con partes estructuradas unidas por
/// ' · ' (decision PO 2026-07-20, que quito la caja de texto libre). La WEB
/// todavia tiene esa caja y su texto acaba en la misma columna, asi que este
/// parser tiene que ser conservador y lo es: exige el prefijo 'Estado: '
/// exacto sobre una parte completa y solo acepta 'Nuevo' o 'Usado'. Un
/// proveedor tendria que escribir literalmente "Estado: Nuevo" como segmento
/// entre ' · ' para enganarlo, y el dano seria prellenar un valor plausible.
///
/// Devuelve '' si no reconoce nada: el peor caso deja el campo vacio y el
/// proveedor elige, que es exactamente lo que pasaba antes de esta funcion.
/// Nunca inventa un valor.
String conditionFromOfferMessage(String message) {
  const prefijo = 'Estado: ';
  for (final parte in message.split(' · ')) {
    final t = parte.trim();
    if (!t.startsWith(prefijo)) continue;
    final valor = t.substring(prefijo.length).trim();
    if (valor == 'Nuevo' || valor == 'Usado') return valor;
  }
  return '';
}
