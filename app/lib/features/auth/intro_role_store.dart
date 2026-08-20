import 'package:shared_preferences/shared_preferences.dart';

/// De qué lado dijo el usuario que está, en la lámina 1 del intro.
enum IntroRole { consumer, provider }

/// Guarda la elección de rol hecha ANTES de autenticarse.
///
/// La clave no lleva sufijo de usuario (a diferencia de
/// `onboarding_guides_<uid>` del OnboardingStore) porque en ese momento no hay
/// sesión ni uid. Consecuencia directa: hay que BORRARLA en cuanto se consume,
/// o el siguiente que se registre en el mismo teléfono hereda la elección del
/// anterior.
class IntroRoleStore {
  static const String kKey = 'intro_role_choice';

  Future<void> save(IntroRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kKey, role.name);
  }

  Future<IntroRole?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kKey);
    if (raw == null) return null;
    // Un valor que no reconocemos se trata como "sin elección": mejor caer en
    // ChooseRoleScreen que abrir un alta equivocada.
    for (final r in IntroRole.values) {
      if (r.name == raw) return r;
    }
    return null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kKey);
  }
}
