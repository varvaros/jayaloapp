import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config.dart';
import 'core/router.dart';
import 'push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey);
  final router = buildRouter();
  // El push es ACCESORIO: si falla (sesión expirada, permiso denegado, sin
  // Google Play, Firebase caído) la app debe arrancar igual. Sin este guard,
  // cualquier excepción de initPush impide llegar a runApp y el usuario ve una
  // PANTALLA EN BLANCO — no un error (verificado en el Redmi 2026-07-17).
  try {
    await initPush(router);
  } catch (e, s) {
    debugPrint('initPush falló (no bloqueante): $e\n$s');
  }
  runApp(JayaloApp(router: router));
}
