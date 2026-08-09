import 'dart:io';

/// Extensiones aceptadas para subir una imagen elegida localmente (portada,
/// logo — y las tareas 6-8 que reusan este mismo guard).
const _allowedImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

/// Tope de tamaño para una imagen subida desde el picker: 5 MB.
const _maxImageBytes = 5 * 1024 * 1024;

/// Valida un fichero de imagen ya elegido del picker ANTES de subirlo:
/// extensión soportada y tamaño dentro del tope. Devuelve el mensaje de error
/// a mostrar en un toast, o `null` si el fichero pasa.
///
/// Puro + `File` (sin red, sin `BuildContext`): se testea con ficheros de
/// verdad en un directorio temporal, sin necesidad de montar ningún widget.
String? validateLocalImage(File file) {
  final ext = file.path.split('.').last.toLowerCase();
  if (!_allowedImageExtensions.contains(ext)) {
    return 'Formato no soportado. Usa JPG, PNG o WEBP.';
  }
  if (file.lengthSync() > _maxImageBytes) {
    return 'La imagen no puede pesar más de 5 MB.';
  }
  return null;
}
