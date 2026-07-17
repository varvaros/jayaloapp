/// Validación pura de una imagen elegida antes de subirla — espejo de
/// `validateImageFile` de la web (`src/lib/uploadGuards.ts`). El tope de
/// CANTIDAD lo pasa el llamador (2 en solicitud, 5 en oferta), porque es lo
/// único que cambia entre superficies.
///
/// `image_picker` ya recomprime (`maxWidth: 1200, imageQuality: 85`), así que
/// el chequeo de 5 MB rara vez disparará — se mantiene por paridad y defensa.
library;

/// Máximo por foto, en MB (idéntico a `MAX_IMAGE_MB` de la web).
const int maxImageMb = 5;

/// Extensiones permitidas (idénticas a `ALLOWED_IMAGE_EXT` de la web).
const Set<String> allowedImageExt = {'jpg', 'jpeg', 'png', 'webp'};

sealed class ImagePickResult {
  const ImagePickResult();
}

class ImagePickOk extends ImagePickResult {
  const ImagePickOk();
}

class ImagePickError extends ImagePickResult {
  const ImagePickError(this.message);
  final String message;
}

ImagePickResult validatePickedImage({
  required int sizeBytes,
  required String path,
  required int currentCount,
  required int maxCount,
}) {
  // Cantidad primero: si ya no cabe otra, no importa el archivo.
  if (currentCount >= maxCount) {
    return ImagePickError(
        'Puedes subir hasta $maxCount foto${maxCount == 1 ? '' : 's'}.');
  }
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
  if (!allowedImageExt.contains(ext)) {
    return const ImagePickError('Formato no permitido. Usa JPG, PNG o WEBP.');
  }
  if (sizeBytes > maxImageMb * 1024 * 1024) {
    return const ImagePickError('La imagen supera 5 MB. Usa una más liviana.');
  }
  return const ImagePickOk();
}
