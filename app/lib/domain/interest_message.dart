/// Construcción del mensaje de "Me interesa" — paridad EXACTA con
/// `buildMessage()` de la web (`src/components/marketplace/InterestConfirmDialog.tsx`).
///
/// El mensaje viaja como texto plano en `product_interests.message` y el
/// proveedor lo lee en la web tal cual — por eso las líneas (rótulo + orden)
/// deben verse IDÉNTICAS vengan de donde vengan. Todo aquí es puro (sin
/// Supabase) para poder testear los mismos casos que la web sin levantar red.
library;

/// `UrgencyKey` de la web: 4 opciones fijas, sin "otro" libre.
enum InterestUrgency { hoy, semana, mes, flexible }

extension InterestUrgencyText on InterestUrgency {
  /// `URGENCY_TEXT` de la web — texto que viaja DENTRO del mensaje.
  String get text => switch (this) {
        InterestUrgency.hoy => 'Hoy mismo',
        InterestUrgency.semana => 'Esta semana',
        InterestUrgency.mes => 'Este mes',
        InterestUrgency.flexible => 'Fecha flexible',
      };

  /// Etiqueta corta del chip (`URGENCIES[].label` de la web).
  String get chipLabel => switch (this) {
        InterestUrgency.hoy => 'Hoy',
        InterestUrgency.semana => 'Semana',
        InterestUrgency.mes => 'Este mes',
        InterestUrgency.flexible => 'Sin apuro',
      };
}

/// `COLORS` de la web — mismo orden y mismos labels (el swatch hex no
/// aplica aquí, solo pinta un puntito en el chip; ver `_colorSwatch` en la
/// pantalla).
class InterestColor {
  const InterestColor(this.key, this.label);
  final String key;
  final String label;
}

const List<InterestColor> interestColors = [
  InterestColor('negro', 'Negro'),
  InterestColor('blanco', 'Blanco'),
  InterestColor('gris', 'Gris'),
  InterestColor('rojo', 'Rojo'),
  InterestColor('azul', 'Azul'),
  InterestColor('verde', 'Verde'),
  InterestColor('amarillo', 'Amarillo'),
  InterestColor('otro', 'Otro'),
];

String? interestColorLabel(String? key) {
  if (key == null) return null;
  for (final c in interestColors) {
    if (c.key == key) return c.label;
  }
  return null;
}

/// Paridad `serviceLocationText` (el `useMemo` de la web).
String serviceLocationText({required bool atProvider, String address = ''}) {
  if (atProvider) return 'En el local del proveedor / a coordinar';
  final trimmed = address.trim();
  return trimmed.isEmpty ? 'A coordinar' : 'En mi dirección: $trimmed';
}

/// Paridad `buildMessage()` de la web, rama PRODUCTO. [colorKey] es la
/// `key` de [interestColors] (o null si no se eligió color).
String buildProductInterestMessage({
  required int quantity,
  required InterestUrgency urgency,
  String brand = '',
  String? colorKey,
  String address = '',
}) {
  final lines = <String>[
    'Cantidad: $quantity',
    'Cuándo quiere comprar: ${urgency.text}',
  ];
  final brandTrim = brand.trim();
  if (brandTrim.isNotEmpty) lines.add('Marca / preferencia: $brandTrim');
  final colorLabel = interestColorLabel(colorKey);
  if (colorLabel != null) lines.add('Color: $colorLabel');
  final addressTrim = address.trim();
  if (addressTrim.isNotEmpty) lines.add('Dirección de entrega: $addressTrim');
  return lines.join('\n');
}

/// Paridad `buildMessage()` de la web, rama SERVICIO. [need] se asume YA
/// validado por [canSubmitServiceInterest] — este builder no vuelve a
/// rechazar, solo compone el texto (misma separación de responsabilidades
/// que la web: `canSubmit` decide, `buildMessage` solo arma).
String buildServiceInterestMessage({
  required String need,
  required InterestUrgency urgency,
  required String locationText,
  String preferences = '',
  String? photoUrl,
}) {
  final lines = <String>[
    'Qué necesita: ${need.trim()}',
    'Cuándo lo necesita: ${urgency.text}',
    'Lugar: $locationText',
  ];
  final prefTrim = preferences.trim();
  if (prefTrim.isNotEmpty) lines.add('Preferencias: $prefTrim');
  if (photoUrl != null && photoUrl.isNotEmpty) lines.add('Foto: $photoUrl');
  return lines.join('\n');
}

/// Mínimo 15 caracteres (recortando espacios), igual que
/// `serviceNeed.trim().length >= 15` de la web.
bool canSubmitServiceInterest(String need) => need.trim().length >= 15;

/// El cliente recorta a 1000 antes de mandar (`message.slice(0, 1000)` de la
/// web) — el mensaje ya viene corto en la práctica, pero es el mismo tope.
String truncateInterestMessage(String message) =>
    message.length > 1000 ? message.substring(0, 1000) : message;
