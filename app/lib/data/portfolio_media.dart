/// Los archivos de un trabajo del portafolio (spec 2026-08-20).
///
/// REGLA QUE SOSTIENE TODO: `image_urls` es el ESPEJO SOLO-IMAGENES de `media`.
/// `request_detail_screen.dart` ("cargar trabajos anteriores") copia
/// `image_urls` ENTERO dentro de la oferta; mientras lea el espejo, un video no
/// puede llegar a `provider_offers` jamas. Si mueves ese lector a `media`,
/// reabres la fuga. Ver §8 de la spec.
class PortfolioMedia {
  const PortfolioMedia({
    required this.url,
    required this.kind,
    this.poster,
    this.duration,
  });

  final String url;

  /// `'image'` o `'video'`.
  final String kind;

  /// Miniatura del video. `null` en imagenes y en videos subidos antes de que
  /// existiera el paso de poster — esos degradan al placeholder, NUNCA al mp4.
  final String? poster;

  /// Segundos. Solo video.
  final int? duration;

  bool get esVideo => kind == 'video';
}

/// Normaliza la columna `media`; si viene vacia, reconstruye desde `image_urls`
/// para que las filas escritas antes de la migracion se sigan viendo.
List<PortfolioMedia> parseMedia(dynamic media, dynamic imageUrls) {
  final crudo = media is List ? media : const [];
  final limpio = <PortfolioMedia>[];
  for (final el in crudo) {
    if (el is! Map) continue;
    final url = el['url'];
    final kind = el['kind'];
    if (url is! String || url.isEmpty) continue;
    if (kind != 'image' && kind != 'video') continue;
    final poster = el['poster'];
    final duration = el['duration'];
    limpio.add(PortfolioMedia(
      url: url,
      kind: kind as String,
      poster: poster is String && poster.isNotEmpty ? poster : null,
      duration: duration is int ? duration : null,
    ));
  }
  if (limpio.isNotEmpty) return limpio;

  final urls = imageUrls is List ? imageUrls : const [];
  return [
    for (final u in urls)
      if (u is String && u.isNotEmpty) PortfolioMedia(url: u, kind: 'image'),
  ];
}

/// El espejo: las URLs de las IMAGENES, en orden. Nunca un video.
List<String> imagesOf(List<PortfolioMedia> media) =>
    [for (final m in media) if (!m.esVideo) m.url];

/// Que pintar como miniatura. Un video jamas devuelve su .mp4: si no tiene
/// poster devuelve `null` y quien pinte usa `tilePlaceholder`.
({String? src, bool esVideo}) coverOf(PortfolioMedia m) =>
    m.esVideo ? (src: m.poster, esVideo: true) : (src: m.url, esVideo: false);
