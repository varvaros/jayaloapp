import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config.dart';
import 'core/error_reporter.dart';
import 'core/router.dart';
import 'core/theme_store.dart';
import 'push/push_service.dart';

Future<void> main() async {
  initErrorReporting(() async {
    await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey);
    final router = buildRouter();
    // Preferencia de tema ANTES de runApp: la app pinta directo en claro/oscuro
    // sin parpadeo. Supabase.initialize ya llamó ensureInitialized, así que
    // SharedPreferences está disponible aquí.
    await themeStore.load();
    // El push es ACCESORIO y arranca DESPUÉS de la primera pantalla. El try/catch
    // de antes solo cubría que initPush LANZARA; si en vez de lanzar se QUEDA
    // COLGADO (el diálogo de permiso de Android 13+ que MIUI a veces no muestra,
    // o getToken sin responder), nunca se llegaba a runApp y la app se quedaba en
    // BLANCO para siempre — reproducido en el Redmi con instalación limpia
    // 2026-07-18. Pintar primero es la única forma de que un cuelgue del push no
    // pueda secuestrar el arranque.
    runApp(JayaloApp(router: router));
    unawaited(initPush(router).catchError((Object e, StackTrace s) {
      debugPrint('initPush falló (no bloqueante): $e\n$s');
    }));
  });
}
