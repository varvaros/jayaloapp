import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session_state.dart';
import '../domain/notifications.dart';

Future<void> _saveToken(String token) async {
  final auth = Supabase.instance.client.auth;
  // OJO: currentUser puede seguir existiendo con la sesión ya MUERTA (el
  // refresh token caducó o fue revocado) — el upsert saldría como `anon` y
  // PostgREST responde 42501. Hay que exigir sesión viva, no solo usuario.
  final session = auth.currentSession;
  if (session == null || session.isExpired || auth.currentUser == null) return;
  try {
    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': auth.currentUser!.id,
      'token': token,
      'platform': 'android',
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,token');
  } catch (e) {
    // Registrar el token es best-effort: nunca debe tumbar el arranque.
    debugPrint('No se pudo registrar el device token: $e');
  }
}

Future<void> deleteCurrentToken() async {
  // Best-effort igual: si esto lanzara, el usuario no podría CERRAR SESIÓN
  // (settings_screen lo llama antes de signOut).
  try {
    final t = await FirebaseMessaging.instance.getToken();
    if (t == null) return;
    await Supabase.instance.client.from('device_tokens').delete().eq('token', t);
  } catch (e) {
    debugPrint('No se pudo borrar el device token: $e');
  }
}

Future<void> initPush(GoRouter router) async {
  await Firebase.initializeApp();
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(); // Android 13+: diálogo del sistema

  final token = await fcm.getToken();
  if (token != null) await _saveToken(token);
  fcm.onTokenRefresh.listen(_saveToken);
  Supabase.instance.client.auth.onAuthStateChange.listen((e) async {
    if (e.event == AuthChangeEvent.signedIn) {
      final t = await fcm.getToken();
      if (t != null) await _saveToken(t);
    }
  });

  // Los taps en caliente (onMessageOpenedApp) rutean bien por rol porque
  // roleStore ya está resuelto cuando el usuario toca la notificación. Los
  // taps en frío (getInitialMessage) siguen perdiendo el deep link: initPush
  // corre ANTES de resolver el rol (roleState.unknown → cae a provider:false)
  // y además el redirect de /gate descarta el destino al arrancar. Pendiente:
  // guardar el link y navegar recién cuando el rol se resuelva.
  void goFrom(RemoteMessage m) {
    final link = m.data['link'] as String? ?? '';
    router.go(mapLinkToRoute(link,
        provider: roleStore.value == RoleState.provider));
  }

  final initial = await fcm.getInitialMessage();
  if (initial != null) goFrom(initial);
  FirebaseMessaging.onMessageOpenedApp.listen(goFrom);
}
