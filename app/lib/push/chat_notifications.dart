import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';

/// Notificaciones locales de chat con acción "Responder" inline (solo Android).
///
/// El push de chat llega como **data-message** (send-push manda `kind:'chat'`
/// sin bloque `notification` para los de chat), así que el SO NO lo pinta solo:
/// esta capa lo dibuja con `flutter_local_notifications` y le añade el botón de
/// respuesta directa. El envío del texto ocurre en [notificationBackgroundHandler],
/// un entry-point de nivel superior que corre en un isolate propio incluso con
/// la app cerrada.
const kChatChannelId = 'chat_replies';
const kReplyActionId = 'REPLY';

final flnp = FlutterLocalNotificationsPlugin();

/// Inicializa el plugin y registra los callbacks de respuesta (foreground y
/// background). Idempotente: llamarlo tanto en `initPush` como al arrancar el
/// isolate de background.
Future<void> initChatNotifications(
  void Function(NotificationResponse) onResponse,
) async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flnp.initialize(
    settings: const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
  );
}

/// Id de notificación estable por conversación (mismo chat → misma notificación,
/// se reemplaza en vez de apilar).
int _notifId(String conversationId) => conversationId.hashCode & 0x7fffffff;

/// Pinta (o reemplaza) la notificación de un mensaje de chat con el botón
/// "Responder". El `payload` lleva el `conversation_id` para el handler.
Future<void> showChatReplyNotification({
  required String conversationId,
  required String title,
  required String body,
  int? badge,
}) async {
  final details = AndroidNotificationDetails(
    kChatChannelId,
    'Mensajes de chat',
    channelDescription: 'Mensajes nuevos de tus conversaciones en Jayalo',
    importance: Importance.high,
    priority: Priority.high,
    // Badge numérico del ícono (launchers que lo soportan): total sin leer.
    // Reemplaza al `notification_count` que el SO ponía en los notification-
    // message, ahora que el chat va como data-message.
    number: badge,
    actions: <AndroidNotificationAction>[
      const AndroidNotificationAction(
        kReplyActionId,
        'Responder',
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(label: 'Escribe tu respuesta'),
        ],
        allowGeneratedReplies: true,
        showsUserInterface: false,
      ),
    ],
  );
  await flnp.show(
    id: _notifId(conversationId),
    title: title,
    body: body,
    notificationDetails: NotificationDetails(android: details),
    payload: jsonEncode({'conversation_id': conversationId}),
  );
}

/// Notificación simple sin acción (confirmación de "Enviado"/"No se pudo").
Future<void> _showStatus(String conversationId, String title, String body) =>
    flnp.show(
      id: _notifId(conversationId),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kChatChannelId,
          'Mensajes de chat',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );

/// Handler de la respuesta directa. Corre en un **isolate de background** cuando
/// la app está cerrada, así que arranca en frío: hay que reinicializar Supabase
/// (restaura la sesión persistida) antes de insertar el mensaje.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  if (r.actionId != kReplyActionId) return;
  final text = (r.input ?? '').trim();
  if (text.isEmpty) return;

  final payload = r.payload == null
      ? const <String, dynamic>{}
      : jsonDecode(r.payload!) as Map<String, dynamic>;
  final conversationId = payload['conversation_id'] as String?;
  if (conversationId == null || conversationId.isEmpty) return;

  // supabase_flutter restaura la sesión persistida (SharedPreferences) al init.
  // initialize es idempotente si otro isolate ya lo hizo.
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  } catch (_) {
    // Ya inicializado en este isolate: seguimos con la instancia existente.
  }
  final client = Supabase.instance.client;
  final session = client.auth.currentSession;
  final userId = client.auth.currentUser?.id;
  if (session == null || session.isExpired || userId == null) {
    await _showStatus(
        conversationId, 'No se pudo enviar', 'Abre la app para responder');
    return;
  }

  try {
    // MISMO camino que el chat (repos.insertChatMessage): kind 'text' +
    // sender_id = auth.uid(). No usar RPC: el chat inserta directo.
    await client.from('conversation_messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      'kind': 'text',
      'body': text,
    });
    await _showStatus(conversationId, 'Respondiste', text);
  } catch (e) {
    debugPrint('Respuesta desde push falló: $e');
    await _showStatus(
        conversationId, 'No se pudo enviar', 'Abre la app para reintentar');
  }
}
