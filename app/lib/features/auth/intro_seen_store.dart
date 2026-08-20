import 'package:shared_preferences/shared_preferences.dart';

/// ¿Ya se enseñó el carrusel de primera apertura EN ESTE TELÉFONO?
///
/// Decisión del PO (2026-08-20): «el onboarding de la app debe salir 1 sola vez
/// por dispositivo». De ahí que la clave NO lleve sufijo de uid (a diferencia
/// del `onboarding_guides_<uid>` del OnboardingStore): la marca sobrevive a
/// cerrar sesión y vale también para el segundo usuario del mismo teléfono. Se
/// pierde únicamente al desinstalar.
///
/// Y al contrario que [IntroRoleStore], esta marca NO se consume: quien la
/// tiene ve el login clásico (Portada Jayi) para siempre. Quien quiera cambiar
/// de lado lo hace en `ChooseRoleScreen`, que sigue siendo la red de seguridad.
class IntroSeenStore {
  static const String kKey = 'intro_seen_v1';

  /// Fail-open a MOSTRAR el intro: si `SharedPreferences` no responde, repetir
  /// el carrusel es un mal menor frente a dejar a un usuario nuevo sin la
  /// elección de lado y sin la explicación de para qué sirve Jayalo.
  Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kKey, true);
    } catch (_) {
      // Que no se pueda escribir la marca nunca debe tumbar el login: la
      // consecuencia es ver el intro una vez más, no quedarse fuera.
    }
  }
}
