/// Une los componentes de una dirección (de un Placemark) en una línea legible,
/// omitiendo vacíos y duplicados. Puro y testeable.
String formatPlacemarkAddress({
  String? street,
  String? subLocality,
  String? locality,
  String? administrativeArea,
}) {
  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [street, subLocality, locality, administrativeArea]) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty || seen.contains(v.toLowerCase())) continue;
    seen.add(v.toLowerCase());
    parts.add(v);
  }
  return parts.join(', ');
}
