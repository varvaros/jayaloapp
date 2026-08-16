/// Calle y número de un `Placemark`, con respaldo. Puro y testeable.
///
/// `thoroughfare` (nombre de la calle) + `subThoroughfare` (número) es lo que
/// queremos, pero NO siempre viene: en varios Android el plugin deja
/// `thoroughfare` vacío y mete la línea de la calle en `street`. Sin este
/// respaldo el campo se quedaría en blanco justo donde el código anterior —que
/// leía `street`— sí lo llenaba.
///
/// El orden importa: `street` es el último recurso porque en algunas
/// plataformas trae la línea entera (con ciudad o provincia), y ciudad y sector
/// ya tienen su propio campo en el alta.
String composeStreetLine({
  String? thoroughfare,
  String? subThoroughfare,
  String? street,
}) {
  final composed = [thoroughfare, subThoroughfare]
      .map((v) => v?.trim() ?? '')
      .where((v) => v.isNotEmpty)
      .join(' ');
  if (composed.isNotEmpty) return composed;
  return street?.trim() ?? '';
}

/// Une los componentes de una dirección (de un Placemark) en una línea legible,
/// omitiendo vacíos y duplicados. Puro y testeable.
///
/// SIN USO desde que el alta de consumidor desglosó la dirección en país /
/// ciudad / sector (cada pieza va a su campo y se contrasta con el catálogo de
/// `domain/locations.dart`). Se conserva a la espera de decidir si se borra.
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
