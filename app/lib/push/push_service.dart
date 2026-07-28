import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session_state.dart';
import '../core/sfx.dart';
import '../domain/chat.dart';
import '../domain/notifications.dart';
import '../features/chat/opened_conversations.dart';
import 'chat_notifications.dart';

/// Handler de mensajes FCM con la app en background/terminada. DEBE ser una
/// función de nivel superior con `@pragma('vm:entry-point')` (corre en un
/// isolate propio). Solo los push de chat son data-message (`kind:'chat'`): el
/// SO no los pinta, así que los dibujamos nosotros con la acción "Responder".
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage m) async {
  if (m.data['kind'] != 'chat') return;
  await Firebase.initializeApp();
  // Registra el plugin (y su background response handler) en este isolate.
  await initChatNotifications((_) {});
  await showChatReplyNotification(
    conversationId: m.data['conversation_id'] ?? '',
    title: m.data['title'] ?? 'Nuevo mensaje',
    body: m.data['body'] ?? '',
    badge: int.tryParse(m.data['badge'] ?? ''),
  );
}

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

  // Respuesta a la notificación de chat con la app viva (foreground o
  // background-no-terminada). El reply reusa el mismo envío que el isolate de
  // background; un tap simple abre la conversación.
  void onNotifResponse(NotificationResponse r) {
    if (r.actionId == kReplyActionId) {
      notificationBackgroundHandler(r);
      return;
    }
    final cid = r.payload == null
        ? null
        : (jsonDecode(r.payload!) as Map<String, dynamic>)['conversation_id']
            as String?;
    if (cid != null && cid.isNotEmpty) {
      router.go(mapLinkToRoute('/messages?c=$cid',
          provider: roleStore.value == RoleState.provider));
    }
  }

  await initChatNotifications(onNotifResponse);
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
  // Con la app en foreground el SO no pinta NADA por su cuenta (ni los
  // data-message ni los notification-message).
  FirebaseMessaging.onMessage.listen((m) {
    // Rama del chat data-only: hoy INERTE (send-push v17 manda los mensajes
    // como notification-message, `kind:'message_new'`). Se conserva por si se
    // retoma el botón "Responder" desde la notificación.
    if (m.data['kind'] == 'chat') {
      showChatReplyNotification(
        conversationId: m.data['conversation_id'] ?? '',
        title: m.data['title'] ?? 'Nuevo mensaje',
        body: m.data['body'] ?? '',
        badge: int.tryParse(m.data['badge'] ?? ''),
      );
      return;
    }
    // Mensaje nuevo con la app ABIERTA. Antes de esto entraba en silencio
    // absoluto: el SO no pinta los notification-message en foreground y nadie
    // escuchaba este kind. No dibujamos banner —la lista y los badges ya se
    // actualizan solos—, solo avisamos al oído (pedido PO 2026-07-28).
    if (m.data['kind'] == 'message_new') {
      // Si estás DENTRO de esa conversación, el sonido ya lo puso ChatScreen al
      // recibir el mensaje por realtime; sonar aquí sería un eco.
      final cid = convIdFromMessageLink(m.data['link'] as String?);
      if (cid != null && cid == activeConversationId) return;
      playSfx(Sfx.messageElsewhere);
    }
  });

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
