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
  // Orden del PO (2026-09-04, 2a vuelta):
  // aceptadas · sin ofertar · actualizadas · ofertadas · rechazadas.
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

    test('sin oferta (null) → 2: por delante de todo lo ya ofertado', () {
      expect(inboxPriority(status: null, unlocked: false), 2);
    });

    test('ya ofertaste y te la CAMBIARON → 3', () {
      expect(
        inboxPriority(status: 'pending', unlocked: false, updated: true),
        3,
      );
    });

    test('ya ofertaste y nadie la tocó → 4', () {
      expect(inboxPriority(status: 'pending', unlocked: false), 4);
    });

    test('rechazada → 5 (la última)', () {
      expect(inboxPriority(status: 'rejected', unlocked: false), 5);
    });

    test('cancelada → 5 (la última, igual que rechazada)', () {
      expect(inboxPriority(status: 'cancelled', unlocked: false), 5);
    });

    test('unlocked=true gana siempre, sea cual sea el status', () {
      expect(inboxPriority(status: 'pending', unlocked: true), 1);
      expect(inboxPriority(status: null, unlocked: true), 1);
    });

    test('`updated` NO mueve nada fuera del grupo de las ya ofertadas', () {
      // Por delante no hay nada que partir y por detrás no interesa: una
      // rechazada editada sigue siendo una rechazada.
      expect(
        inboxPriority(status: 'accepted', unlocked: false, updated: true),
        0,
      );
      expect(
        inboxPriority(status: 'completed', unlocked: false, updated: true),
        1,
      );
      expect(inboxPriority(status: null, unlocked: false, updated: true), 2);
      expect(
        inboxPriority(status: 'rejected', unlocked: false, updated: true),
        5,
      );
    });
  });

  group('sortInboxItems', () {
    test('pendiente de desbloqueo va PRIMERO sin importar la fecha', () {
      final items = [
        req('vieja-sin-oferta', createdAt: '2020-01-01T00:00:00Z'),
        req('nueva-pendiente-desbloqueo', createdAt: '2026-09-04T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {'nueva-pendiente-desbloqueo': 'accepted'},
        unlockedIds: const {},
        unseenIds: const {},
        updatedIds: const {},
      );
      expect(sorted.first['id'], 'nueva-pendiente-desbloqueo');
      expect(sorted.last['id'], 'vieja-sin-oferta');
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
          updatedIds: const {},
        );
        expect(sorted.first['id'], 'pendiente-desbloqueo');
      },
    );

    test('la que NO has ofertado va por delante de la que ya ofertaste, '
        'aunque sea más vieja', () {
      final items = [
        req('ya-ofertaste', createdAt: '2026-09-04T00:00:00Z'), // más nueva
        req('sin-ofertar', createdAt: '2020-01-01T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {'ya-ofertaste': 'pending'},
        unlockedIds: const {},
        unseenIds: const {},
        updatedIds: const {},
      );
      expect(sorted.first['id'], 'sin-ofertar');
      expect(sorted.last['id'], 'ya-ofertaste');
    });

    test('entre dos que ya ofertaste, la que te CAMBIARON sube', () {
      final items = [
        req('ofertada-quieta', createdAt: '2026-09-04T00:00:00Z'), // más nueva
        req('ofertada-cambiada', createdAt: '2020-01-01T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {
          'ofertada-quieta': 'pending',
          'ofertada-cambiada': 'pending',
        },
        unlockedIds: const {},
        unseenIds: const {},
        updatedIds: const {'ofertada-cambiada'},
      );
      expect(sorted.first['id'], 'ofertada-cambiada');
    });

    test('una ofertada CAMBIADA no le gana a una que no has ofertado', () {
      final items = [
        req('ofertada-cambiada', createdAt: '2026-09-04T00:00:00Z'),
        req('sin-ofertar', createdAt: '2020-01-01T00:00:00Z'), // más vieja
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {'ofertada-cambiada': 'pending'},
        unlockedIds: const {},
        unseenIds: const {},
        updatedIds: const {'ofertada-cambiada'},
      );
      expect(sorted.first['id'], 'sin-ofertar');
    });

    test('el orden completo de los cinco grupos, entrando al revés', () {
      final entrada = [
        req('5-rechazada'),
        req('4-ofertada'),
        req('3-ofertada-cambiada'),
        req('2-sin-ofertar'),
        req('1-desbloqueada'),
        req('0-pendiente-desbloqueo'),
      ];
      final sorted = sortInboxItems(
        entrada,
        statuses: const {
          '5-rechazada': 'rejected',
          '4-ofertada': 'pending',
          '3-ofertada-cambiada': 'pending',
          '1-desbloqueada': 'unlocked',
          '0-pendiente-desbloqueo': 'accepted',
        },
        unlockedIds: const {'1-desbloqueada'},
        unseenIds: const {},
        updatedIds: const {'3-ofertada-cambiada'},
      );
      expect(sorted.map((r) => r['id']).toList(), [
        '0-pendiente-desbloqueo',
        '1-desbloqueada',
        '2-sin-ofertar',
        '3-ofertada-cambiada',
        '4-ofertada',
        '5-rechazada',
      ]);
    });

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
        updatedIds: const {},
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
        updatedIds: const {},
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
        updatedIds: const {},
      );
      expect(sorted.map((r) => r['id']).toList(), ['a', 'b', 'c']);
    });

    test('las filas de tienda (source=store, sin oferta) no revientan y '
        'caen en el grupo sin-oferta, DELANTE de las ya ofertadas', () {
      final items = [
        req('pendiente-desbloqueo', createdAt: '2020-01-01T00:00:00Z'),
        req('interes-tienda',
            createdAt: '2026-09-04T00:00:00Z', source: 'store'),
        req('ya-ofertaste', createdAt: '2026-09-04T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {
          'pendiente-desbloqueo': 'accepted',
          'ya-ofertaste': 'pending',
        },
        unlockedIds: const {},
        unseenIds: const {},
        updatedIds: const {},
      );
      expect(sorted.map((r) => r['id']).toList(), [
        'pendiente-desbloqueo',
        'interes-tienda',
        'ya-ofertaste',
      ]);
    });

    test('lista vacía no revienta', () {
      expect(
        sortInboxItems(
          const [],
          statuses: const {},
          unlockedIds: const {},
          unseenIds: const {},
          updatedIds: const {},
        ),
        isEmpty,
      );
    });
  });
}
