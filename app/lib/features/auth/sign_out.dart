import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../push/push_service.dart';

/// Cierre de sesión de la app, en un solo sitio.
///
/// Vivía dentro de `SettingsScreen` cuando "Cerrar sesión" era una fila de
/// Ajustes. Al moverse al menú del avatar (pedido PO 2026-08-22) pasaron a
/// necesitarlo DOS sitios —el menú y el borrado de cuenta, que cierra sesión
/// al terminar—, y un copiar-pegar habría dejado dos versiones que se
/// desincronizan a la primera.
///
/// Cada paso es best-effort y NINGUNO puede impedir los siguientes: lo único
/// que no se puede quedar sin hacer es el `signOut` de Supabase.
Future<void> signOutJayalo() async {
  await deleteCurrentToken(); // best-effort (ya trae su try/catch)
  try {
    await GoogleSignIn(serverClientId: AppConfig.googleWebClientId).signOut();
  } catch (e) {
    // Si Google falla, la sesión de Supabase debe cerrarse igual.
    debugPrint('GoogleSignIn.signOut falló (no bloqueante): $e');
  }
  try {
    // `local` EXPLÍCITO (ya era el default de supabase_flutter, pero el de
    // supabase-js es `global` → los dos lados hacían cosas opuestas sin que
    // nadie lo decidiera). Cerrar sesión aquí no debe sacar al usuario de la
    // web ni de otro teléfono; para eso haría falta una acción propia
    // "cerrar sesión en todos mis dispositivos" (`SignOutScope.global`).
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  } catch (e) {
    // El signOut local ya limpió la sesión antes de la llamada de red; si esa
    // falla (p.ej. "connection reset" al perder señal) NO es un error real.
    debugPrint('auth.signOut red falló (no bloqueante): $e');
  }
}
