/// Datos del centro de notificaciones (spec 2026-07-18 §1).
/// Sin cambios de backend: tabla `notifications` + RLS + realtime ya en prod.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'repos.dart' show supa;

const notifCols = 'id,kind,title,body,link,read_at,created_at';
const notifPageSize = 30;

/// Página N (0-based) de 30, más recientes primero. La última página se
/// detecta porque vuelve con menos de [notifPageSize] filas.
Future<List<Map<String, dynamic>>> notificationsPage(int page) async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('notifications')
      .select(notifCols)
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      // Desempate estable: dos filas con el mismo created_at no deben
      // reordenarse entre páginas (offset pagination).
      .order('id', ascending: false)
      .range(page * notifPageSize, page * notifPageSize + notifPageSize - 1));
}

/// Ventana de la CAMPANA de la app. Es un empujón ("tienes cosas recientes por
/// ver"), no un histórico: sin ventana, las informativas que nadie abre
/// (confirmaciones, billetera, bienvenidas) se acumulaban hasta números
/// absurdos.
///
/// YA NO ES ESPEJO DE NADIE. El servidor tenía su propio `BADGE_WINDOW_DAYS`
/// para escribir el globo del ícono, y se retiró el 2026-08-28: mandar el total
/// de no-leídas en cada push envenenaba ese globo, porque Android lo calcula
/// SUMANDO el `number` de todo lo vivo en la bandeja (marcaba 43 con TRES
/// no-leídas reales). Hoy el globo del ícono cuenta avisos en bandeja y este
/// número solo alimenta la campana in-app — son dos cosas distintas a
/// propósito, y no tienen por qué coincidir.
const notifBadgeWindowDays = 30;

/// Conteo de no-leídas para el badge. `count` respeta los filtros e IGNORA
/// limit/range, así que el `limit(1)` deja el payload en ~1 fila — el
/// equivalente práctico del `head: true` que usa la web.
Future<int> unreadNotificationsCount() async {
  final uid = supa.auth.currentUser!.id;
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(days: notifBadgeWindowDays))
      .toIso8601String();
  final res = await supa
      .from('notifications')
      .select('id')
      .eq('user_id', uid)
      .isFilter('read_at', null)
      .gte('created_at', since)
      .limit(1)
      .count(CountOption.exact);
  return res.count;
}

/// Marcar leída = update de read_at. NUNCA DELETE (convención del proyecto).
Future<void> markNotificationRead(String id) async => supa
    .from('notifications')
    .update({'read_at': DateTime.now().toUtc().toIso8601String()})
    .eq('id', id)
    .isFilter('read_at', null);

Future<void> markAllNotificationsRead() async {
  final uid = supa.auth.currentUser!.id;
  await supa
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', uid)
      .isFilter('read_at', null);
}

/// Canal realtime de INSERTs del usuario. Suscribir SOLO con la pantalla de
/// notificaciones visible y la app en foreground (patrón del chat) — el
/// llamador es dueño del ciclo de vida.
RealtimeChannel subscribeNotifications(
    void Function(Map<String, dynamic> row) onInsert) {
  final uid = supa.auth.currentUser!.id;
  return supa
      .channel('notifs-$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();
}

void unsubscribeNotifications(RealtimeChannel ch) => supa.removeChannel(ch);
