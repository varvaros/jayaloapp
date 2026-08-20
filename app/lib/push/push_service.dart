import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session_state.dart';
import '../core/sfx.dart';
import '../data/repos.dart' show messagesBadge;
import '../domain/chat.dart';
import '../domain/notifications.dart';
import '../features/chat/opened_conversations.dart';
import '../features/notifications/notification_bell.dart' show notifCountStore;
import 'chat_notifications.dart';
import 'push_permission.dart';

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
  // Sin Firebase no hay nada que registrar: `FirebaseMessaging.instance`
  // reventaría en la línea siguiente. Único await que corta en seco.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase.initializeApp falló: $e');
    return;
  }
  final fcm = FirebaseMessaging.instance;

  // Los taps en caliente (onMessageOpenedApp) rutean bien por rol porque
  // roleStore ya está resuelto cuando el usuario toca la notificación.
  //
  // Los taps en FRÍO (getInitialMessage) perdían el destino: `initPush` corre
  // ANTES de que se resuelva el rol (RoleState.unknown → `provider:false`, ruta
  // equivocada) y encima `redirectTarget` manda todo a `/gate` mientras el rol
  // esté sin resolver, así que el destino se descartaba. Eso rompía el bucle de
  // re-enganche que justifica todo el trabajo de push.
  //
  // Fix: si el rol no está resuelto, el link se GUARDA y se navega en cuanto
  // `roleStore` notifique. `needsOnboarding` no navega a propósito — el gate
  // debe llevarlo a completar el alta, no a un chat que todavía no puede usar.
  void goToLink(String link) {
    if (link.isEmpty) return;

    void navigate() {
      router.go(mapLinkToRoute(link,
          provider: roleStore.value == RoleState.provider));
    }

    if (roleStore.value != RoleState.unknown) {
      if (roleStore.value != RoleState.needsOnboarding) navigate();
      return;
    }

    late final VoidCallback onRoleResolved;
    onRoleResolved = () {
      if (roleStore.value == RoleState.unknown) return;
      roleStore.removeListener(onRoleResolved);
      if (roleStore.value == RoleState.needsOnboarding) return;
      // Microtask: deja que el redirect del propio router reaccione primero al
      // cambio de rol (gate → /provider|/client) y navegamos encima. Al revés,
      // ese redirect pisaría el destino que acabamos de fijar.
      Future.microtask(navigate);
    };
    roleStore.addListener(onRoleResolved);
  }

  void goFrom(RemoteMessage m) => goToLink(m.data['link'] as String? ?? '');

  // Respuesta o tap sobre una notificación LOCAL: la del chat con "Responder" y
  // las de aviso que pintamos en foreground. Ambas rutean por `goToLink` para
  // reusar la espera de rol de arriba.
  void onNotifResponse(NotificationResponse r) {
    if (r.actionId == kReplyActionId) {
      notificationBackgroundHandler(r);
      return;
    }
    final payload = r.payload == null
        ? const <String, dynamic>{}
        : jsonDecode(r.payload!) as Map<String, dynamic>;
    // Aviso: el destino viaja como el `link` crudo del backend.
    final link = payload['link'] as String?;
    if (link != null && link.isNotEmpty) {
      goToLink(link);
      return;
    }
    final cid = payload['conversation_id'] as String?;
    if (cid != null && cid.isNotEmpty) goToLink('/messages?c=$cid');
  }

  // Un push con la app en FOREGROUND. Android no pinta NADA por su cuenta en
  // este estado (ni data-message ni notification-message), así que todo lo que
  // el usuario ve u oye aquí lo ponemos nosotros.
  //
  // Hasta el 2026-08-13 solo actuaba el chat: los otros NUEVE kinds de la
  // allowlist (offer_new, offer_accepted, offer_unlocked, offer_improved,
  // request_new_in_category, product_interest_new, conversation_completed /
  // _closed_inactivity / _inactivity_warning) entraban en silencio absoluto, sin
  // banner, sin sonido y sin badge: un proveedor con la app abierta no se
  // enteraba de una solicitud nueva.
  Future<void> onForegroundMessage(RemoteMessage m) async {
    try {
      final kind = m.data['kind'] as String? ?? '';

      // Rama del chat data-only: hoy INERTE (send-push manda los mensajes como
      // notification-message, `kind:'message_new'`). Se conserva por si se
      // retoma el botón "Responder" desde la notificación.
      if (kind == 'chat') {
        await showChatReplyNotification(
          conversationId: m.data['conversation_id'] ?? '',
          title: m.data['title'] ?? 'Nuevo mensaje',
          body: m.data['body'] ?? '',
          badge: int.tryParse(m.data['badge'] ?? ''),
        );
        return;
      }

      // La campana cuenta TODAS las no leídas, incluidas las de chat, así que se
      // refresca para cualquier kind. `refresh()` (conteo del SERVIDOR) y nunca
      // `add(1)`: la pantalla de notificaciones también reacciona a la MISMA
      // fila por realtime, y sumar en los dos lados dejaba el contador una
      // unidad por encima. Dos `refresh()` concurrentes convergen.
      notifCountStore.refresh();

      if (kind == 'message_new') {
        // Va ANTES del return de abajo: dentro del chat es justo cuando más
        // falta hace que el badge de la pestaña quede al día.
        messagesBadge.refresh();
        // Si estás DENTRO de esa conversación, el sonido ya lo puso ChatScreen
        // al recibir el mensaje por realtime; sonar aquí sería un eco.
        final cid = convIdFromMessageLink(m.data['link'] as String?);
        if (cid != null && cid == activeConversationId) return;
        // Sin banner a propósito (pedido PO 2026-07-28): la lista y los badges
        // ya se actualizan solos, solo avisamos al oído.
        await playSfx(Sfx.messageElsewhere);
        return;
      }

      // El título y el cuerpo viajan en el bloque `notification`, NO en `data`
      // (send-push solo mete link/kind/conversation_id en data). Leerlos de
      // `data` dejaría el aviso en blanco.
      final n = m.notification;
      if (n == null) return;
      // Se pinta la MISMA notificación que vería con la app cerrada, en el canal
      // de alertas. Nada de playSfx: el timbre es propiedad del CANAL, así que
      // sonaría dos veces y además dejaría de poder silenciarse por separado
      // desde los Ajustes del sistema.
      await showAlertNotification(
        link: m.data['link'] as String? ?? '',
        title: n.title ?? 'Jayalo',
        body: n.body ?? '',
      );
    } catch (e) {
      // Un push nunca debe tumbar la app que el usuario está usando.
      debugPrint('push en foreground falló: $e');
    }
  }

  // ── PRIMERO todo lo que se REGISTRA ───────────────────────────────────────
  // Enganchar listeners es síncrono y no puede fallar; `requestPermission()` y
  // `getToken()` sí pueden lanzar o COLGARSE (el diálogo de permiso se queda
  // pillado en MIUI, ver main.dart). Cuando iban delante se saltaban todos los
  // registros posteriores y la sesión entera se quedaba sin ruteo de taps y sin
  // escuchar el login — y no hay segunda oportunidad: main.dart traga la
  // excepción con un debugPrint e `initPush` solo se llama una vez.
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
  FirebaseMessaging.onMessage.listen(onForegroundMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(goFrom);
  fcm.onTokenRefresh.listen(_saveToken);
  // Tiene que quedar enganchado antes del primer await lento: si el usuario
  // inicia sesión mientras el diálogo de permiso está en pantalla (arranque en
  // frío en login/OTP), el `signedIn` se perdía y el dispositivo se quedaba SIN
  // token hasta el siguiente arranque, en silencio.
  Supabase.instance.client.auth.onAuthStateChange.listen((e) async {
    if (e.event != AuthChangeEvent.signedIn) return;
    try {
      final t = await fcm.getToken();
      if (t != null) await _saveToken(t);
    } catch (err) {
      debugPrint('getToken tras signedIn falló: $err');
    }
  });

  // ── DESPUÉS lo que puede fallar, cada uno con su propia red ───────────────
  // Orden por fragilidad creciente: primero el plugin local, luego lo que
  // CADUCA (los mensajes que abrieron la app), y al final el diálogo de permiso,
  // que es el que se cuelga.
  try {
    await initChatNotifications(onNotifResponse);
  } catch (e) {
    debugPrint('initChatNotifications falló: $e');
  }
  try {
    // Tap sobre una notificación LOCAL con la app cerrada: el plugin no invoca
    // el callback en ese caso, hay que preguntarle con qué la abrieron.
    final launch = await flnp.getNotificationAppLaunchDetails();
    final resp = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && resp != null) {
      onNotifResponse(resp);
    }
  } catch (e) {
    debugPrint('getNotificationAppLaunchDetails falló: $e');
  }
  try {
    final initial = await fcm.getInitialMessage();
    if (initial != null) goFrom(initial);
  } catch (e) {
    debugPrint('getInitialMessage falló: $e');
  }
  try {
    final token = await fcm.getToken();
    if (token != null) await _saveToken(token);
  } catch (e) {
    debugPrint('getToken falló: $e');
  }
  // El diálogo de permiso de Android 13+ YA NO se pide en el arranque.
  //
  // Iba aquí, el último de la lista, porque es el que se cuelga — pero se
  // pedía igual con la app recién abierta y SIN sesión, y entonces aterrizaba
  // encima de la primera pantalla que hubiera: el intro. Tapaba los recuadros
  // «Busco algo / Vendo algo» justo en la única apertura en que se ven
  // (PO 2026-08-20), y con el gotcha de MIUI —los toques atraviesan los
  // overlays— un toque en «No permitir» podía además elegir lado por debajo.
  //
  // Ahora espera al primer instante en que el rol queda resuelto, o sea a que
  // el usuario esté DENTRO de la app y tenga algo que le puedan notificar. No
  // hay await: el arranque no depende de esto, y `requestPermission` sigue
  // pudiendo colgarse sin arrastrar a nadie.
  wirePushPermissionPrompt(
    source: roleStore,
    role: () => roleStore.value,
    ask: fcm.requestPermission,
  );
}
