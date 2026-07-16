import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mapea `/requests/ID` o `/provider/requests/ID` (links de la web en
/// notifications.link) a la ruta nativa correspondiente.
String mapLinkToRoute(String link) {
  final reqMatch = RegExp(r'^/requests/([0-9a-f-]+)').firstMatch(link);
  if (reqMatch != null) return '/client/request/${reqMatch.group(1)}';
  final provMatch = RegExp(r'^/provider/requests/([0-9a-f-]+)').firstMatch(link);
  if (provMatch != null) return '/provider/offers';
  if (link.startsWith('/provider')) return '/provider';
  return '/client';
}

Future<void> _saveToken(String token) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  await Supabase.instance.client.from('device_tokens').upsert({
    'user_id': uid,
    'token': token,
    'platform': 'android',
    'updated_at': DateTime.now().toIso8601String(),
  }, onConflict: 'user_id,token');
}

Future<void> deleteCurrentToken() async {
  final t = await FirebaseMessaging.instance.getToken();
  if (t == null) return;
  await Supabase.instance.client.from('device_tokens').delete().eq('token', t);
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

  void goFrom(RemoteMessage m) {
    final link = m.data['link'] as String? ?? '';
    router.go(mapLinkToRoute(link));
  }

  final initial = await fcm.getInitialMessage();
  if (initial != null) goFrom(initial);
  FirebaseMessaging.onMessageOpenedApp.listen(goFrom);
}
