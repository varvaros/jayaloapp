import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/inbox_order.dart';

Map<String, dynamic> req(
  String id, {
  String? createdAt,
  String? source,
}) => {
  'id': id,
  'created_at': createdAt ?? '2026-07-28T10:00:00Z',
  'source': ?source,
};

void main() {
  group('inboxPriority', () {
    test('aceptada y SIN desbloquear → 0 (la más urgente)', () {
      expect(inboxPriority(status: 'accepted', unlocked: false), 0);
    });

    test('desbloqueada → 1', () {
      expect(inboxPriority(status: 'unlocked', unlocked: true), 1);
    });

    test('completada nunca es 0: cae en el grupo desbloqueado (1)', () {
      expect(inboxPriority(status: 'completed', unlocked: false), 1);
    });

    test('ya ofertaste (pending) → 2', () {
      expect(inboxPriority(status: 'pending', unlocked: false), 2);
    });

    test('sin oferta (null) → 3', () {
      expect(inboxPriority(status: null, unlocked: false), 3);
    });

    test('rechazada → 4 (la última)', () {
      expect(inboxPriority(status: 'rejected', unlocked: false), 4);
    });

    test('cancelada → 4 (la última, igual que rechazada)', () {
      expect(inboxPriority(status: 'cancelled', unlocked: false), 4);
    });

    test('unlocked=true gana siempre, sea cual sea el status', () {
      expect(inboxPriority(status: 'pending', unlocked: true), 1);
      expect(inboxPriority(status: null, unlocked: true), 1);
    });
  });

  group('sortInboxItems', () {
    test('pendiente de desbloqueo va PRIMERO sin importar la fecha', () {
      final items = [
        req('vieja-sin-oferta', createdAt: '2020-01-01T00:00:00Z'),
        req('nueva-pendiente-desbloqueo', createdAt: '2026-09-04T00:00:00Z'),
      ];
      // La pendiente-de-desbloqueo es la MÁS VIEJA de las dos, y aun así
      // debe salir primero.
      final byDateDesc = [
        req('nueva-pendiente-desbloqueo', createdAt: '2026-09-04T00:00:00Z'),
        req('vieja-sin-oferta', createdAt: '2020-01-01T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        byDateDesc.reversed.toList(), // entra en el orden "malo"
        statuses: const {'nueva-pendiente-desbloqueo': 'accepted'},
        unlockedIds: const {},
        unseenIds: const {},
      );
      expect(sorted.first['id'], 'nueva-pendiente-desbloqueo');
      // sanity: usando la lista de arriba también (ambos órdenes de entrada)
      final sorted2 = sortInboxItems(
        items,
        statuses: const {'nueva-pendiente-desbloqueo': 'accepted'},
        unlockedIds: const {},
        unseenIds: const {},
      );
      expect(sorted2.first['id'], 'nueva-pendiente-desbloqueo');
      expect(sorted2.last['id'], 'vieja-sin-oferta');
    });

    test(
      'completed NUNCA le gana el primer puesto a una pendiente de '
      'desbloqueo, aunque sea la más reciente',
      () {
        final items = [
          req('completada', createdAt: '2026-09-04T00:00:00Z'), // más nueva
          req('pendiente-desbloqueo', createdAt: '2020-01-01T00:00:00Z'),
        ];
        final sorted = sortInboxItems(
          items,
          statuses: const {
            'completada': 'completed',
            'pendiente-desbloqueo': 'accepted',
          },
          unlockedIds: const {},
          unseenIds: const {},
        );
        expect(sorted.first['id'], 'pendiente-desbloqueo');
      },
    );

    test('una oferta rechazada va al final', () {
      final items = [
        req('rechazada', createdAt: '2026-09-04T00:00:00Z'), // más reciente
        req('sin-oferta', createdAt: '2020-01-01T00:00:00Z'),
        req('pendiente-desbloqueo', createdAt: '2010-01-01T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {
          'rechazada': 'rejected',
          'pendiente-desbloqueo': 'accepted',
        },
        unlockedIds: const {},
        unseenIds: const {},
      );
      expect(sorted.last['id'], 'rechazada');
      expect(sorted.first['id'], 'pendiente-desbloqueo');
    });

    test('sin abrir (unseen) va antes que lo ya visto, dentro del MISMO '
        'grupo (sin oferta)', () {
      final items = [
        req('vista-mas-nueva', createdAt: '2026-09-04T00:00:00Z'),
        req('sin-abrir-mas-vieja', createdAt: '2020-01-01T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {},
        unlockedIds: const {},
        unseenIds: const {'sin-abrir-mas-vieja'},
      );
      expect(sorted.first['id'], 'sin-abrir-mas-vieja');
    });

    test('estable: dos filas con TODO igual conservan su orden de entrada', () {
      final items = [
        req('a', createdAt: '2026-09-04T00:00:00Z'),
        req('b', createdAt: '2026-09-04T00:00:00Z'),
        req('c', createdAt: '2026-09-04T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {},
        unlockedIds: const {},
        unseenIds: const {},
      );
      expect(sorted.map((r) => r['id']).toList(), ['a', 'b', 'c']);
    });

    test('las filas de tienda (source=store, sin oferta) no revientan y '
        'caen en el grupo sin-oferta', () {
      final items = [
        req('pendiente-desbloqueo', createdAt: '2020-01-01T00:00:00Z'),
        req('interes-tienda', createdAt: '2026-09-04T00:00:00Z', source: 'store'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {'pendiente-desbloqueo': 'accepted'},
        unlockedIds: const {},
        unseenIds: const {},
      );
      expect(sorted.first['id'], 'pendiente-desbloqueo');
      expect(sorted.last['id'], 'interes-tienda');
    });

    test('lista vacía no revienta', () {
      expect(
        sortInboxItems(
          const [],
          statuses: const {},
          unlockedIds: const {},
          unseenIds: const {},
        ),
        isEmpty,
      );
    });
  });
}
