/// Semilla para "También busco esto": solo el título y la primera foto de una
/// solicitud ajena. NO se copia nada más — la IA recoge el resto fresco.
class RequestSeed {
  const RequestSeed({required this.title, this.imageUrl});
  final String title;
  final String? imageUrl;

  static RequestSeed fromRow(Map<String, dynamic> r) {
    final urls = (r['image_urls'] as List?)?.cast<String>() ?? const <String>[];
    final primary = r['image_url'] as String?;
    final img = (primary != null && primary.isNotEmpty)
        ? primary
        : (urls.isNotEmpty ? urls.first : null);
    return RequestSeed(title: (r['title'] as String?) ?? '', imageUrl: img);
  }
}
