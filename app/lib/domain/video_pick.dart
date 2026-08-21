/// Validacion pura de un video elegido para el portafolio, antes de subirlo
/// — mismo espiritu que `image_pick.dart` (`validatePickedImage`), pero los
/// topes son otros: duracion y tamaño DESPUES de comprimir, no cantidad (esa
/// la maneja el llamador ANTES de abrir el selector, ver `_pickVideo` en
/// `add_store_item_screen.dart` — evita gastar bateria/datos comprimiendo un
/// video que de entrada no cabe).
///
/// Correccion del PO sobre el brief original de la Task 13 (los topes del
/// brief estaban desactualizados): 45 segundos de duracion maxima, 10 MB por
/// video, 2 videos por trabajo (`kMaxPortfolioVideos`, declarado junto a
/// `kMaxPortfolioPhotos` en `add_store_item_screen.dart`). El techo de 10
/// videos por NEGOCIO existe pero es del trigger de la base de datos, no de
/// esta pantalla.
library;

/// Duracion maxima de un video de trabajo, en segundos.
const int maxVideoSeconds = 45;

/// Tamaño maximo de un video YA COMPRIMIDO, en MB. Rechazo duro: comprimir
/// no exime de validar (un video muy largo o muy movido puede seguir
/// pasandose incluso despues de comprimir).
const int maxVideoMb = 10;

/// Objetivo de bitrate al comprimir — NO es el tope de rechazo (ese es
/// [maxVideoMb], aplicado al archivo YA comprimido). Es la media que
/// buscamos quedarnos POR DEBAJO del tope: un clip de 45 s a este bitrate
/// pesa ~6.75 MB, con margen bajo los 10 MB en vez de pegado al borde.
///
/// El motivo NO es ahorrar disco: es que el video NO SE CORTE al
/// reproducirse. 10 MB / 45 s = ~1.8 Mbps de media — en una conexion movil
/// peor que eso (normal fuera de la capital dominicana) el video se
/// entrecorta mientras el cliente lo ve, y el proveedor queda mal sin saber
/// por que. A ~1.2 Mbps hay margen real.
///
/// ⚠️ GOTCHA verificado en el codigo nativo de `video_compress: 3.1.4`
/// (Task 13, 2026-08-21): este valor es SOLO documentacion de intencion,
/// **no se aplica** — el plugin no expone ningun parametro de bitrate en su
/// API Dart (`compressVideo(path, {quality, frameRate, ...})`), y para el
/// preset `Res1280x720Quality` que usamos (`VideoCompressPlugin.kt`, rama
/// `quality==6`) tampoco respeta el `frameRate` que le pasemos — ese
/// parametro solo se usa en la rama `HighestQuality` (sin tope de
/// resolucion, no nos sirve). El bitrate real que sale de esa rama lo
/// calcula el motor nativo (`com.otaliastudios:transcoder`,
/// `BitRates.estimateVideoBitRate = 0.14 * ancho * alto * fps`, formula
/// verificada en su codigo fuente): a 1280x720 y ~30 fps de origen eso da
/// ~3.87 Mbps, muy por encima de esta meta — un clip de 45 s a esa tasa
/// pesa ~21.8 MB y caeria en el rechazo duro de [maxVideoMb] con frecuencia.
/// No se pudo MEDIR en un device real dentro de esta tarea (bloqueante de
/// entorno ajeno al codigo: falta `android/app/google-services.json`, un
/// secreto que no vive en el repo — ver el informe de la Task 13). Decision
/// pendiente del PO: aceptar el rechazo frecuente cerca de los 45 s hasta
/// una tarea de seguimiento, o bajar el preset (540p/480p) como parche.
const int targetVideoBitrateBps = 1200000;

sealed class VideoPickResult {
  const VideoPickResult();
}

class VideoPickOk extends VideoPickResult {
  const VideoPickOk();
}

class VideoPickError extends VideoPickResult {
  const VideoPickError(this.message);
  final String message;
}

/// Valida un video YA comprimido — duracion (se mide antes de comprimir,
/// pero no cambia al comprimir) y tamaño (se mide DESPUES, es el archivo
/// real que se sube).
VideoPickResult validatePickedVideo({
  required int durationSeconds,
  required int sizeBytes,
}) {
  if (durationSeconds > maxVideoSeconds) {
    return const VideoPickError(
        'El video no puede durar más de $maxVideoSeconds segundos.');
  }
  if (sizeBytes > maxVideoMb * 1024 * 1024) {
    return const VideoPickError(
        'El video supera $maxVideoMb MB. Usa uno más corto o liviano.');
  }
  return const VideoPickOk();
}
