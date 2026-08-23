import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/notifications.dart';

void main() {
  group('familyFor', () {
    test('message_new es familia mensajes', () {
      expect(familyFor('message_new'), NotifFamily.messages);
    });
    // Pasa en un chat y se resuelve en un chat: NO puede caer en "sistema",
    // que es donde lo mandaria el fallback por no empezar por ningun prefijo.
    test('assistant_handover_requested es familia mensajes', () {
      expect(familyFor('assistant_handover_requested'), NotifFamily.messages);
      expect(iconFor('assistant_handover_requested'), Icons.support_agent);
      expect(mapLinkToRoute('/messages?c=39098468-6d7d-41ee-978a-1dd32669e60f',
              provider: true),
          '/messages/39098468-6d7d-41ee-978a-1dd32669e60f');
    });
    test('ofertas/ventas: offer_*, job_response_new, sale y cancelaciones', () {
      for (final k in [
        'offer_new', 'offer_accepted', 'offer_rejected', 'offer_sent_confirmation',
        'offer_cancelled_customer', 'job_response_new', 'sale_completed_provider',
        'request_cancelled_provider',
      ]) {
        expect(familyFor(k), NotifFamily.offers, reason: k);
      }
    });
    test('wallet_* es familia wallet', () {
      for (final k in ['wallet_low_balance', 'wallet_empty', 'wallet_recharged']) {
        expect(familyFor(k), NotifFamily.wallet, reason: k);
      }
    });
    test('review_* es familia reseñas', () {
      expect(familyFor('review_new'), NotifFamily.reviews);
      expect(familyFor('review_pending_reminder'), NotifFamily.reviews);
    });
    test('welcome, referidos y kinds desconocidos caen en sistema', () {
      for (final k in [
        'welcome_customer', 'welcome_provider', 'referral_invite',
        'referral_reward', 'kind_inventado_futuro',
      ]) {
        expect(familyFor(k), NotifFamily.system, reason: k);
      }
    });
    // Son avisos de una cita pautada en un chat y su link abre ese chat: van
    // con los mensajes, no en "sistema" (que es donde caerían por defecto al
    // no matchear ningún prefijo de arriba).
    test('appointment_* es familia mensajes', () {
      for (final k in [
        'appointment_proposed', 'appointment_confirmed',
        'appointment_cancelled', 'appointment_reminder',
        'appointment_followup',
      ]) {
        expect(familyFor(k), NotifFamily.messages, reason: k);
      }
    });
  });

  group('iconFor', () {
    test('mapea los kinds conocidos como la web', () {
      expect(iconFor('offer_new'), Icons.inventory_2_outlined);
      expect(iconFor('job_response_new'), Icons.work_outline);
      expect(iconFor('review_new'), Icons.star_outline);
      expect(iconFor('referral_reward'), Icons.card_giftcard);
      expect(iconFor('wallet_empty'), Icons.account_balance_wallet_outlined);
      expect(iconFor('sale_completed_provider'), Icons.check_circle_outline);
      expect(iconFor('request_cancelled_provider'), Icons.cancel_outlined);
      expect(iconFor('welcome_provider'), Icons.auto_awesome);
      expect(iconFor('message_new'), Icons.chat_bubble_outline);
    });
    test('kind desconocido usa el fallback de su familia', () {
      expect(iconFor('wallet_algo_nuevo'), Icons.account_balance_wallet_outlined);
      expect(iconFor('cualquier_cosa'), Icons.notifications_none);
    });
    // Icono propio de calendario, distinto del fallback de "mensajes"
    // (Icons.chat_bubble_outline) al que caerían si no tuvieran caso explícito.
    test('appointment_* usa el icono de calendario', () {
      for (final k in [
        'appointment_proposed', 'appointment_confirmed',
        'appointment_cancelled', 'appointment_reminder',
        'appointment_followup',
      ]) {
        expect(iconFor(k), Icons.event_outlined, reason: k);
      }
    });
  });

  group('cleanBody', () {
    test('quita el tag __VALUE__ con salto de línea (regex de la web)', () {
      expect(cleanBody('Recargaste créditos.\n__VALUE__:25'), 'Recargaste créditos.');
    });
    test('quita el tag sin salto de línea y con decimales', () {
      expect(cleanBody('Saldo bajo __VALUE__:2.5'), 'Saldo bajo');
    });
    test('cuerpo sin tag queda igual (trim aplicado)', () {
      expect(cleanBody('  Hola  '), 'Hola');
    });
  });

  group('badgeLabel', () {
    test('hasta 9 muestra el número, 10+ muestra 9+', () {
      expect(badgeLabel(1), '1');
      expect(badgeLabel(9), '9');
      expect(badgeLabel(10), '9+');
      expect(badgeLabel(99), '9+');
    });
  });

  group('relativeTimeEs', () {
    final now = DateTime(2026, 7, 18, 15, 0);
    test('menos de 1 min es "ahora"', () {
      expect(relativeTimeEs(now.subtract(const Duration(seconds: 30)), now: now), 'ahora');
    });
    test('minutos y horas del mismo día', () {
      expect(relativeTimeEs(now.subtract(const Duration(minutes: 5)), now: now), 'hace 5 min');
      expect(relativeTimeEs(DateTime(2026, 7, 18, 11, 0), now: now), 'hace 4 h');
    });
    test('ayer es "ayer" aunque hayan pasado pocas horas', () {
      expect(relativeTimeEs(DateTime(2026, 7, 17, 23, 30), now: now), 'ayer');
    });
    test('más viejo usa fecha corta', () {
      expect(relativeTimeEs(DateTime(2026, 7, 15, 10, 0), now: now), '15 jul');
    });
  });

  group('AppNotification.fromMap', () {
    test('parsea la fila y convierte created_at a hora local', () {
      final n = AppNotification.fromMap({
        'id': 'abc',
        'kind': 'offer_new',
        'title': 'Nueva oferta',
        'body': 'Te ofertaron\n__VALUE__:500',
        'link': '/requests/123',
        'read_at': null,
        'created_at': '2026-07-18T12:00:00+00:00',
      });
      expect(n.id, 'abc');
      expect(n.unread, isTrue);
      expect(n.createdAt.isUtc, isFalse);
    });
    test('read_at presente marca como leída; campos null no explotan', () {
      final n = AppNotification.fromMap({
        'id': 'x',
        'kind': null,
        'title': null,
        'body': null,
        'link': null,
        'read_at': '2026-07-18T13:00:00+00:00',
        'created_at': '2026-07-18T12:00:00+00:00',
      });
      expect(n.unread, isFalse);
      expect(n.title, '');
      expect(n.link, '');
    });
  });

  group('groupByDay', () {
    AppNotification mk(String id, DateTime d) => AppNotification.fromMap({
          'id': id, 'kind': 'message_new', 'title': 't', 'body': '', 'link': '',
          'read_at': null, 'created_at': d.toUtc().toIso8601String(),
        });
    test('agrupa preservando orden con etiquetas Hoy/Ayer/fecha', () {
      final now = DateTime(2026, 7, 18, 15, 0);
      final groups = groupByDay([
        mk('a', DateTime(2026, 7, 18, 14, 0)),
        mk('b', DateTime(2026, 7, 18, 9, 0)),
        mk('c', DateTime(2026, 7, 17, 20, 0)),
        mk('d', DateTime(2026, 7, 15, 8, 0)),
      ], now: now);
      expect(groups.map((g) => g.label).toList(), ['Hoy', 'Ayer', '15 jul']);
      expect(groups.first.items.map((n) => n.id).toList(), ['a', 'b']);
      expect(groups.last.items.single.id, 'd');
    });
    test('lista vacía produce cero grupos', () {
      expect(groupByDay([], now: DateTime(2026, 7, 18)), isEmpty);
    });
  });

  group('mapLinkToRoute', () {
    test('mensajes: query ?c=, path directo y lista', () {
      expect(mapLinkToRoute('/messages?c=abc-123', provider: false), '/messages/abc-123');
      expect(mapLinkToRoute('/messages/abc-123', provider: true), '/messages/abc-123');
      expect(mapLinkToRoute('/messages', provider: false), '/messages');
    });
    test('solicitud del cliente', () {
      expect(mapLinkToRoute('/requests/deadbeef-1', provider: false), '/client/request/deadbeef-1');
    });
    test('UUID en mayúsculas también matchea (hex case-insensitive)', () {
      expect(mapLinkToRoute('/requests/DEADBEEF-1', provider: false), '/client/request/DEADBEEF-1');
    });
    test('BUG (a): detalle de solicitud del proveedor va al detalle nativo', () {
      expect(mapLinkToRoute('/provider/requests/deadbeef-2', provider: true),
          '/provider/request/deadbeef-2');
    });
    test('ofertas del proveedor en sus dos formatos', () {
      expect(mapLinkToRoute('/provider/offers', provider: true), '/provider/offers');
      expect(mapLinkToRoute('/provider?view=offers', provider: true), '/provider/offers');
    });
    test('los avisos de saldo llevan a la tienda de créditos, no al dashboard', () {
      // Su copy dice "recarga ahora": el tap tiene que dejarte donde se recarga.
      expect(mapLinkToRoute('/provider?panel=wallet', provider: true), '/tienda-creditos');
    });
    test('el resto de /provider cae en /provider', () {
      expect(mapLinkToRoute('/provider', provider: true), '/provider');
      expect(mapLinkToRoute('/provider/history', provider: true), '/provider');
      // La otra forma del link de wallet (la que usan wallet_recharged,
      // wallet_gift y payment_failed) NO se mapea a propósito: esa cadena está
      // prohibida en `lib/` por `no_link_out_test` (es la ruta del wallet web,
      // con botones de PayPal). Aquí se puede escribir porque el guard solo
      // escanea `lib/`. Si se le da push a alguno de esos kinds, hay que cambiar
      // el link EN EL TRIGGER, no mapearlo aquí.
      expect(mapLinkToRoute('/provider/wallet', provider: true), '/provider');
    });
    test('BUG (b): desconocido/vacío cae por ROL activo, no fijo /client', () {
      expect(mapLinkToRoute('/empleos/xyz', provider: true), '/provider');
      expect(mapLinkToRoute('/empleos/xyz', provider: false), '/client');
      expect(mapLinkToRoute('', provider: true), '/provider');
      expect(mapLinkToRoute('', provider: false), '/client');
    });
  });
}
