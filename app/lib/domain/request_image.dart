/// Primera foto de una solicitud (paridad con la web: `image_url` primaria,
/// `image_urls` como respaldo). `null` si no tiene foto.
///
/// Vivía privada en `my_requests_screen.dart` (`_firstImage`). Se extrajo el
/// 2026-09-22 cuando Reclutar necesitó la MISMA regla para pintar la
/// miniatura de cada fila: dos copias de "cuál es la foto" se separan solas.
String? firstRequestImage(Map<String, dynamic> r) {
  final primary = r['image_url'] as String?;
  if (primary != null && primary.isNotEmpty) return primary;
  final list = (r['image_urls'] as List?)?.cast<String>() ?? const [];
  final first = list.where((u) => u.isNotEmpty);
  return first.isEmpty ? null : first.first;
}
