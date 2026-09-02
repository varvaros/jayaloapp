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
///
/// DOWNSAMPLING (auditoría de rendimiento 2026-07-22): las fotos de subida se
/// recortan a 1200px, pero sin acotar la DECODIFICACIÓN cada una se convertía a
/// un bitmap de resolución completa en RAM (~5-6 MB) aunque se pinte a 90-150px.
/// En listas largas (catálogo/bandeja) eso causa jank y riesgo de OOM en Android
/// de gama media. Aquí se acota el bitmap decodificado al tamaño físico real en
/// pantalla con `ResizeImage`, manteniendo el aspecto (se pasa UNA sola
/// dimensión, nunca las dos → nunca distorsiona; `fit` sigue haciendo su trabajo
/// al pintar).
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/image_url.dart';

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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Techo de decodificación en píxeles FÍSICOS. Se acota por UNA dimensión
    // (la conocida) para preservar el aspecto: `ResizeImage` con solo ancho o
    // solo alto escala manteniendo proporción. Si no hay ninguna (imagen que
    // llena su caja), se usa el ancho de pantalla como tope natural.
    int? cacheW;
    int? cacheH;
    if (width != null && width!.isFinite && width! > 0) {
      cacheW = (width! * dpr).round();
    } else if (height != null && height!.isFinite && height! > 0) {
      cacheH = (height! * dpr).round();
    } else {
      cacheW = (MediaQuery.sizeOf(context).width * dpr).round();
    }
    // Y ademas se le PIDE AL SERVIDOR ese tamano (auditoria 2026-09-02). Lo de
    // arriba acotaba la RAM, pero el fichero seguia viajando ENTERO: un logo de
    // 515 kB se descargaba completo para pintarse en un avatar de 40 px. Con el
    // transformador esa misma foto baja 11 kB en WebP (medido contra prod).
    // `ResizeImage` se queda igual: son dos problemas distintos —datos moviles
    // contra bitmap en RAM— y el servidor puede devolver algo mas grande de lo
    // pedido al conservar el aspecto.
    //
    // Solo cuando se conoce el ANCHO. Si unicamente hay alto, la URL se deja
    // como estaba: el transformador pide `width`, y deducirlo del alto seria
    // inventarse un recorte.
    //
    // OJO: la URL es la CLAVE de la cache en disco, asi que al estrenar esto
    // cada foto ya cacheada se vuelve a descargar UNA vez. Coste de una sola vez.
    final urlServida =
        cacheW != null ? transformedImageUrl(url, width: cacheW) : url;
    return Image(
      image: ResizeImage.resizeIfNeeded(
          cacheW, cacheH, CachedNetworkImageProvider(urlServida)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      frameBuilder: frameBuilder,
    );
  }
}

/// `ImageProvider` de red con caché en disco Y decodificación acotada, para los
/// sitios que necesitan un provider en vez del widget (p. ej.
/// `CircleAvatar.backgroundImage`). Mismo motivo de RAM que [JayaloNetworkImage].
/// [diameter] en px LÓGICOS — para un `CircleAvatar` es `2 * radius`.
ImageProvider jayaloAvatarImage(
    String url, double diameter, BuildContext context) {
  final px = (diameter * MediaQuery.devicePixelRatioOf(context)).round();
  // Mismo criterio que [JayaloNetworkImage]: al servidor se le pide el tamano
  // real del avatar en vez de traer la foto entera para encogerla aqui.
  final urlServida = px > 0 ? transformedImageUrl(url, width: px) : url;
  return ResizeImage.resizeIfNeeded(
      px > 0 ? px : null, null, CachedNetworkImageProvider(urlServida));
}
