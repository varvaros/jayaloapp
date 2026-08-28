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
/// Canal de las notificaciones locales de chat. Es el MISMO que crea
/// `MainActivity` (`CHAT_CHANNEL_ID`), a propósito.
///
/// Antes valía `'chat_replies'`, un id que MainActivity no creaba nunca: Android
/// lo auto-creaba al primer uso con **sonido por defecto**, así que el pop de
/// burbuja (`msg_bubble`) no sonaba aquí. Es exactamente la desalineación
/// canal↔sonido que este módulo documenta como el bug que dejó el sonido mudo
/// desde el 2026-07-22 — el sonido es propiedad del CANAL, no del push. Hoy está
/// latente (send-push v17+ manda `message_new` como notification-message y lo
/// pinta el SO), pero se dispara en cuanto el chat vuelva a ir por data-message.
///
/// De paso: un solo canal "Mensajes" en los Ajustes del sistema, así el usuario
/// silencia los chats de una vez sin perder los avisos de dinero.
const kChatChannelId = 'jayalo_chat_v1';

/// Canal de los AVISOS que no son chat (ofertas, desbloqueos, billetera). Es el
/// MISMO que crea `MainActivity` (`ALERTS_CHANNEL_ID`, con el timbre
/// `notif_bell`) y el mismo que `send-push` pide en `channel_id` para todo lo
/// que no es `message_new`; además es el `default_notification_channel_id` del
/// manifest. Los tres tienen que decir lo mismo: inventar aquí otro id haría que
/// Android auto-creara un canal con el sonido por defecto — exactamente la
/// desalineación que dejó mudo el pop de burbuja en julio.
///
/// Como el canal ya existe cuando Dart arranca, `flutter_local_notifications` NO
/// lo recrea (su acción por defecto es "crear si no existe"), así que el sonido
/// del canal manda. Por eso [showAlertNotification] no pasa `sound:` ni
/// `channelAction:`: hacerlo devolvería el aviso al tono genérico del sistema.
const kAlertsChannelId = 'jayalo_alerts_v2';

const kReplyActionId = 'REPLY';

final flnp = FlutterLocalNotificationsPlugin();

/// Inicializa el plugin y registra los callbacks de respuesta (foreground y
/// background). Idempotente: llamarlo tanto en `initPush` como al arrancar el
/// isolate de background.
Future<void> initChatNotifications(
  void Function(NotificationResponse) onResponse,
) async {
  // Silueta monocroma, NO el ícono del launcher: Android >= 21 usa solo el
  // canal alfa del ícono pequeño, y uno a todo color se ve como un cuadrado
  // negro (el bug que reportó el PO en las notificaciones de FCM).
  const android = AndroidInitializationSettings('@drawable/ic_stat_jayalo');
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

/// Pinta un aviso que NO es de chat (oferta nueva, contacto desbloqueado,
/// interés en un producto…) con la app en FOREGROUND, que es justo donde Android
/// no dibuja nada por su cuenta ni siquiera con los notification-message. Es la
/// MISMA notificación que el usuario vería con la app cerrada: mismo canal y por
/// tanto mismo timbre.
///
/// Sin `number:` a propósito — el badge del launcher lo lleva `NotifCountStore`
/// con el conteo real del servidor, y escribirlo también aquí lo haría parpadear
/// entre dos fuentes. Y sin acción "Responder": eso es solo del chat.
Future<void> showAlertNotification({
  required String link,
  required String title,
  required String body,
}) async {
  try {
    await flnp.show(
      // Id único por aviso: dos ofertas seguidas deben APILARSE, no
      // reemplazarse (al revés que el chat, que colapsa por conversación).
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kAlertsChannelId,
          'Avisos de Jayalo',
          channelDescription: 'Ofertas, billetera y avisos de tu cuenta',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'link': link}),
    );
  } catch (e) {
    // Un aviso que no se puede pintar (plugin aún sin inicializar en la ventana
    // de arranque) jamás debe tumbar la app que el usuario está usando.
    debugPrint('No se pudo pintar el aviso: $e');
  }
}

/// Vacía de la BANDEJA DEL SISTEMA los avisos que no son chat, sin tocar la
/// tabla `notifications` (leer sigue siendo marcar `read_at`).
///
/// Hace falta porque el globo del ícono NO lo decide la app: Android —y MIUI /
/// HyperOS más aún— lo calcula SUMANDO el `Notification.number` de todo lo que
/// el paquete tenga vivo en la bandeja. Los avisos se quedaban ahí hasta
/// caducar a las 72 h y el número solo subía. `AppBadgePlus` no puede
/// arreglarlo desde aquí: en MIUI su `updateBadge` es un NO-OP MUDO
/// (`MiUIBadge.kt` sale de vacío porque nadie llama a `Badge.applyNotification`),
/// así que la ÚNICA palanca real sobre el globo es la bandeja.
///
/// Selectivo por canal a propósito: se lleva [kAlertsChannelId] y deja vivos los
/// mensajes de chat sin leer. `cancelAll()` sería una línea, pero borra TODO lo
/// que postea el paquete —incluido lo que pinta Play Services— y le quitaría de
/// la bandeja conversaciones que el usuario todavía no ha abierto.
///
/// Best-effort de arriba abajo: `getActiveNotifications` LANZA en API < 23, y
/// un fallo aquí nunca debe romper la pantalla que lo llama.
Future<void> clearAlertNotifications() async {
  try {
    final active = await flnp.getActiveNotifications();
    for (final n in active) {
      if (n.channelId != kAlertsChannelId) continue;
      final id = n.id;
      // Las que pinta Play Services desde FCM llegan con `id:0` y un `tag`
      // propio (`FCM-Notification:<n>`); las locales, con `tag:null`. Cancelar
      // exige la MISMA pareja (id, tag) con la que se posteó — y en Android el
      // plugin SIEMPRE rellena el id (`getId()` del StatusBarNotification), así
      // que el `null` que documenta el tipo es cosa de iOS.
      if (id == null) continue;
      await flnp.cancel(id: id, tag: n.tag);
    }
  } catch (e) {
    debugPrint('No se pudo limpiar la bandeja: $e');
  }
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
