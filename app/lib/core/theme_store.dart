import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de tema (persistida) — el toggle "Modo oscuro" de Ajustes.
///
/// Se carga con [load] ANTES de `runApp` (ver `main.dart`) para que la app
/// pinte directo en el tema elegido, sin un parpadeo claro→oscuro al arrancar.
/// Toggle binario claro/oscuro (decisión PO 2026-07-23): no seguir el modo del
/// sistema por ahora; el default preserva el comportamiento anterior (claro).
class ThemeStore extends ValueNotifier<ThemeMode> {
  ThemeStore() : super(ThemeMode.light);

  static const _key = 'theme_mode_dark';

  bool get isDark => value == ThemeMode.dark;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = (prefs.getBool(_key) ?? false) ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      // Best-effort: si SharedPreferences falla, la app queda en claro.
    }
  }

  /// Cambia el tema en el acto (la UI ya reacciona por el ValueNotifier) y
  /// persiste la preferencia (best-effort: el cambio visual no depende de que
  /// el guardado termine).
  Future<void> setDark(bool dark) async {
    value = dark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, dark);
    } catch (_) {
      // Se aplicó en memoria; el próximo arranque podría no recordarlo.
    }
  }
}

final themeStore = ThemeStore();
