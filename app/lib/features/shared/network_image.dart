/// Imagen de red con CACHÉ EN DISCO. Sustituye a `Image.network` en toda la app.
///
/// Problema que resuelve (reporte PO 2026-07-22): `Image.network` solo cachea en
/// MEMORIA, que se pierde al cerrar la app → cada arranque re-descarga todas las
/// fotos y tardan. `CachedNetworkImageProvider` (paquete `cached_network_image`)
/// persiste en disco vía `flutter_cache_manager`, así que una foto ya vista
/// carga al instante en el siguiente arranque.
///
/// Es un envoltorio deliberadamente delgado sobre el widget `Image` estándar:
/// solo cambia el `ImageProvider`. Por eso conserva EXACTAMENTE la API de
/// `Image.network` que la app ya usaba (`errorBuilder`, `loadingBuilder`,
/// `frameBuilder`, `fit`, `width`, `height`), y el reemplazo fue textual.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class JayaloNetworkImage extends StatelessWidget {
  const JayaloNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageFrameBuilder? frameBuilder;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: CachedNetworkImageProvider(url),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      frameBuilder: frameBuilder,
    );
  }
}
