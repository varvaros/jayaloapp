/// Dominio del centro de notificaciones (spec 2026-07-18).
/// Puro y testeable: familias, iconos, limpieza de body, tiempos relativos y
/// agrupación por día. Los COLORES concretos por familia viven en la UI.
library;

import 'package:flutter/material.dart' show IconData, Icons;

import 'chat_time.dart';

enum NotifFamily { messages, offers, wallet, reviews, system }

/// Familia visual por kind (tabla del spec §3). Los prefijos cubren kinds
/// futuros de la misma familia sin tocar código.
NotifFamily familyFor(String kind) {
  // El handover pasa en un chat y se resuelve en un chat: va con los mensajes,
  // no en "sistema", para que aparezca en el filtro donde el proveedor lo busca.
  if (kind == 'message_new' || kind == 'assistant_handover_requested') {
    return NotifFamily.messages;
  }
  if (kind.startsWith('offer_') ||
      kind == 'job_response_new' ||
      kind == 'sale_completed_provider' ||
      kind == 'request_cancelled_provider') {
    return NotifFamily.offers;
  }
  if (kind.startsWith('wallet_')) return NotifFamily.wallet;
  if (kind.startsWith('review_')) return NotifFamily.reviews;
  // La fecha pautada se propone/confirma/cancela dentro de un chat y su link
  // abre ese chat: va con los mensajes, no en "sistema".
  if (kind.startsWith('appointment_')) return NotifFamily.messages;
  return NotifFamily.system;
}

/// Icono por kind — espejo del `iconFor` de la web (NotificationsBell.tsx),
/// con fallback por familia para kinds nuevos.
IconData iconFor(String kind) => switch (kind) {
      'offer_new' ||
      'offer_accepted' ||
      'offer_rejected' ||
      'offer_sent_confirmation' =>
        Icons.inventory_2_outlined,
      'job_response_new' => Icons.work_outline,
      'review_new' || 'review_pending_reminder' => Icons.star_outline,
      'referral_invite' || 'referral_reward' => Icons.card_giftcard,
      'wallet_low_balance' || 'wallet_empty' || 'wallet_recharged' =>
        Icons.account_balance_wallet_outlined,
      'sale_completed_provider' => Icons.check_circle_outline,
      'request_cancelled_provider' ||
      'offer_cancelled_customer' =>
        Icons.cancel_outlined,
      'welcome_customer' || 'welcome_provider' => Icons.auto_awesome,
      'message_new' => Icons.chat_bubble_outline,
      // Un cliente pidio hablar con una persona y el asistente se apago solo.
      'assistant_handover_requested' => Icons.support_agent,
      // Aviso de que un chat está por cerrarse por inactividad (cron 48h).
      'conversation_inactivity_warning' => Icons.hourglass_bottom,
      // El trato se dio por completado, y el chat se cerró solo por
      // inactividad. Kinds propios desde el 2026-08-03: antes ambos llegaban
      // como `message_new` con el título "Nuevo mensaje".
      'conversation_completed' => Icons.check_circle_outline,
      'conversation_closed_inactivity' => Icons.hourglass_disabled,
      'appointment_proposed' ||
      'appointment_confirmed' ||
      'appointment_cancelled' ||
      'appointment_reminder' ||
      'appointment_followup' =>
        Icons.event_outlined,
      _ => _fallbackIcon(familyFor(kind)),
    };

IconData _fallbackIcon(NotifFamily f) => switch (f) {
      NotifFamily.messages => Icons.chat_bubble_outline,
      NotifFamily.offers => Icons.inventory_2_outlined,
      NotifFamily.wallet => Icons.account_balance_wallet_outlined,
      NotifFamily.reviews => Icons.star_outline,
      NotifFamily.system => Icons.notifications_none,
    };

/// El backend mete `__VALUE__:N` en el body de algunos correos/notifs
/// (misma regex de limpieza que la web: `/\n?__VALUE__:[\d.]+/g`).
final _valueTag = RegExp(r'\n?__VALUE__:[\d.]+');
String cleanBody(String body) => body.replaceAll(_valueTag, '').trim();

/// Texto del badge de la campana, tope "9+".
String badgeLabel(int count) => count > 9 ? '9+' : '$count';

/// Hora relativa corta en español: "ahora", "hace 5 min", "hace 3 h",
/// "ayer", "15 jul".
String relativeTimeEs(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (dayKey(d) == dayKey(n)) return 'hace ${diff.inHours} h';
  if (dayKey(d) == dayKey(n.subtract(const Duration(days: 1)))) return 'ayer';
  return formatDayLabel(d, now: n);
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        kind: m['kind'] as String? ?? '',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        link: m['link'] as String? ?? '',
        // La BD guarda UTC; agrupar por día y los tiempos relativos necesitan
        // la hora local del dispositivo.
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
      );

  final String id;
  final String kind;
  final String title;
  final String body;
  final String link;
  final DateTime createdAt;

  /// Mutable a propósito: el marcar-leída optimista lo escribe in situ y la
  /// tarjeta se apaga con AnimatedContainer sin reconstruir la lista.
  DateTime? readAt;

  bool get unread => readAt == null;
}

/// Agrupa una lista YA ordenada desc por fecha en secciones de día
/// ("Hoy", "Ayer", "15 jul") preservando el orden.
List<({String label, List<AppNotification> items})> groupByDay(
    List<AppNotification> list,
    {DateTime? now}) {
  final n = now ?? DateTime.now();
  final out = <({String label, List<AppNotification> items})>[];
  for (final item in list) {
    final label = formatDayLabel(item.createdAt, now: n);
    if (out.isEmpty || out.last.label != label) {
      out.add((label: label, items: [item]));
    } else {
      out.last.items.add(item);
    }
  }
  return out;
}

/// Ruteo del tap de una notificación (push Y lista in-app) — links reales que
/// escribe el backend, verificados en migraciones de jayalo-main (spec §4).
/// `provider` = rol activo, para el fallback de links desconocidos.
String mapLinkToRoute(String link, {required bool provider}) {
  final msgQuery = RegExp(r'^/messages\?c=([0-9a-fA-F-]+)').firstMatch(link);
  if (msgQuery != null) return '/messages/${msgQuery.group(1)}';
  final msgPath = RegExp(r'^/messages/([0-9a-fA-F-]+)').firstMatch(link);
  if (msgPath != null) return '/messages/${msgPath.group(1)}';
  if (link == '/messages') return '/messages';
  final req = RegExp(r'^/requests/([0-9a-fA-F-]+)').firstMatch(link);
  if (req != null) return '/client/request/${req.group(1)}';
  final provReq = RegExp(r'^/provider/requests/([0-9a-fA-F-]+)').firstMatch(link);
  if (provReq != null) return '/provider/request/${provReq.group(1)}';
  if (link == '/provider/offers' || link == '/provider?view=offers') {
    return '/provider/offers';
  }
  // Avisos de saldo (`wallet_low_balance` / `wallet_empty`, en la whitelist de
  // push desde el 2026-08-14): su copy dice "recarga ahora", así que el tap tiene
  // que dejar al proveedor EN la tienda de créditos IN-APP. Sin esta rama caían
  // al dashboard genérico y había que buscar la recarga a mano.
  //
  // Solo se mapea la forma con query. La otra que usan algunos triggers lleva
  // la ruta del wallet WEB en el literal, y `no_link_out_test` prohíbe esa
  // cadena en todo `lib/`: esa página tiene botones de PayPal y un solo call
  // site la haría no publicable en Play. Si algún día se le da push a
  // `wallet_recharged`, hay que cambiar el link EN EL TRIGGER, no aquí.
  if (link == '/provider?panel=wallet') return '/tienda-creditos';
  if (link.startsWith('/provider')) return '/provider';
  return provider ? '/provider' : '/client';
}
