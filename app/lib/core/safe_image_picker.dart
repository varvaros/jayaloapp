import 'package:image_picker/image_picker.dart';

/// `image_picker` solo admite UN selector activo en TODA la app: si se lanza un
/// segundo pick mientras el primero sigue abierto (doble toque, o dos pantallas
/// que abren galería a la vez) el plugin tira
/// `PlatformException(already_active, Image picker is already active)`.
///
/// Por eso la guarda es GLOBAL (una sola bandera para todo el proceso), no
/// por-widget: un flag por pantalla no evitaría que dos superficies distintas
/// abran el selector a la vez.
bool _picking = false;

/// Corre [pick] bajo la guarda global. Si ya hay un selector activo, devuelve
/// `null` (como si el usuario cancelara) en vez de dejar reventar la excepción.
///
/// Uso:
/// ```dart
/// final picked = await guardedPick(
///     (p) => p.pickImage(source: source, maxWidth: 1200, imageQuality: 85));
/// ```
Future<T?> guardedPick<T>(Future<T?> Function(ImagePicker picker) pick) async {
  if (_picking) return null;
  _picking = true;
  try {
    return await pick(ImagePicker());
  } finally {
    _picking = false;
  }
}
