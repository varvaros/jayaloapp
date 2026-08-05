import '../domain/geo.dart';

/// Compone el cuerpo del mensaje de direccion del chat.
///
/// El enlace va SIEMPRE en la ULTIMA linea: `splitMapLink` lo busca por prefijo
/// y la burbuja lo saca del texto para pintarlo como boton.
String? buildLocationBody({
  required String address,
  required String cityLine,
  required String reference,
  required double? lat,
  required double? lng,
}) {
  final parts = <String>[
    if (address.trim().isNotEmpty) address.trim(),
    if (cityLine.trim().isNotEmpty) cityLine.trim(),
    if (reference.trim().isNotEmpty) 'Referencia: ${reference.trim()}',
  ];
  if (parts.isEmpty) return null;
  if (lat != null && lng != null) parts.add(mapsLinkFor(lat, lng));
  return parts.join('\n');
}
