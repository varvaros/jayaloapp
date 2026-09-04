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
    test('te aceptaron y falta desbloquear → 0 (lo más urgente)', () {
      expect(inboxPriority(status: 'accepted', unlocked: false), 0);
    });

    test('nadie ha ofertado (el chip) → 1', () {
      expect(
        inboxPriority(status: null, unlocked: false, firstOffer: true),
        1,
      );
    });

    test('sin ofertar pero ya hay ofertas de otros → 2', () {
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

    test('desbloqueada → 5: trabajo TERMINADO, deja de encabezar', () {
      // 3ª vuelta del PO. Se midió su bandeja real: tres ventas de agosto ya
      // pagadas y ya en el chat tapaban lo único que nadie había ofertado.
      expect(inboxPriority(status: 'unlocked', unlocked: true), 5);
    });

    test('completada cae con las desbloqueadas (5), nunca en 0', () {
      expect(inboxPriority(status: 'completed', unlocked: false), 5);
    });

    test('rechazada → 6 (la última)', () {
      expect(inboxPriority(status: 'rejected', unlocked: false), 6);
    });

    test('cancelada → 6 (la última, igual que rechazada)', () {
      expect(inboxPriority(status: 'cancelled', unlocked: false), 6);
    });

    test('unlocked=true gana siempre, sea cual sea el status', () {
      expect(inboxPriority(status: 'pending', unlocked: true), 5);
      expect(inboxPriority(status: null, unlocked: true), 5);
    });

    test('el chip NO puede sacar una fila de su grupo si ya ofertaste', () {
      // `showFirstOfferChip` ya exige `hasMyOffer == false`, pero la escala no
      // se apoya en eso: si alguna vez llegara un true de más, no debe colarse
      // por delante una fila que en realidad ya tiene oferta tuya.
      expect(
        inboxPriority(status: 'pending', unlocked: false, firstOffer: true),
        4,
      );
      expect(
        inboxPriority(status: 'accepted', unlocked: false, firstOffer: true),
        0,
      );
      expect(
        inboxPriority(status: 'rejected', unlocked: false, firstOffer: true),
        6,
      );
    });

    test('`updated` solo parte el grupo de las ya ofertadas', () {
      expect(
        inboxPriority(status: 'completed', unlocked: false, updated: true),
        5,
      );
      expect(inboxPriority(status: null, unlocked: false, updated: true), 2);
      expect(
        inboxPriority(status: 'rejected', unlocked: false, updated: true),
        6,
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
        firstOfferIds: const {},
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
          firstOfferIds: const {},
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
        firstOfferIds: const {},
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
        firstOfferIds: const {},
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
        firstOfferIds: const {},
      );
      expect(sorted.first['id'], 'sin-ofertar');
    });

    test('la bandeja del PO: una que NADIE ha ofertado le gana a tres '
        'desbloqueadas, aunque sean más viejas', () {
      // Reproduce la queja del 2026-09-04 medida contra prod: tres ventas de
      // agosto ya pagadas encabezaban la lista y tapaban unos audífonos del
      // 09-02 que nadie había ofertado.
      final items = [
        req('camisas-desbloqueada', createdAt: '2026-08-22T00:00:00Z'),
        req('funda-desbloqueada', createdAt: '2026-08-20T00:00:00Z'),
        req('llaveros-desbloqueada', createdAt: '2026-08-18T00:00:00Z'),
        req('audifonos-sin-ofertas', createdAt: '2026-09-02T00:00:00Z'),
      ];
      final sorted = sortInboxItems(
        items,
        statuses: const {
          'camisas-desbloqueada': 'unlocked',
          'funda-desbloqueada': 'unlocked',
          'llaveros-desbloqueada': 'unlocked',
        },
        unlockedIds: const {
          'camisas-desbloqueada',
          'funda-desbloqueada',
          'llaveros-desbloqueada',
        },
        unseenIds: const {},
        updatedIds: const {},
        firstOfferIds: const {'audifonos-sin-ofertas'},
      );
      expect(sorted.first['id'], 'audifonos-sin-ofertas');
    });

    test('el orden completo de los siete grupos, entrando al revés', () {
      final entrada = [
        req('6-rechazada'),
        req('5-desbloqueada'),
        req('4-ofertada'),
        req('3-ofertada-cambiada'),
        req('2-sin-ofertar-con-ofertas-de-otros'),
        req('1-nadie-ha-ofertado'),
        req('0-falta-desbloquear'),
      ];
      final sorted = sortInboxItems(
        entrada,
        statuses: const {
          '6-rechazada': 'rejected',
          '5-desbloqueada': 'unlocked',
          '4-ofertada': 'pending',
          '3-ofertada-cambiada': 'pending',
          '0-falta-desbloquear': 'accepted',
        },
        unlockedIds: const {'5-desbloqueada'},
        unseenIds: const {},
        updatedIds: const {'3-ofertada-cambiada'},
        firstOfferIds: const {'1-nadie-ha-ofertado'},
      );
      expect(sorted.map((r) => r['id']).toList(), [
        '0-falta-desbloquear',
        '1-nadie-ha-ofertado',
        '2-sin-ofertar-con-ofertas-de-otros',
        '3-ofertada-cambiada',
        '4-ofertada',
        '5-desbloqueada',
        '6-rechazada',
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
        firstOfferIds: const {},
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
        firstOfferIds: const {},
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
        firstOfferIds: const {},
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
        firstOfferIds: const {},
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
          firstOfferIds: const {},
        ),
        isEmpty,
      );
    });
  });
}
