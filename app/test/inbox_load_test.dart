import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/inbox_load.dart';
import 'package:jayalo_app/domain/request_requirements.dart';

Map<String, dynamic> req(String id, {String? createdAt, String? source}) => {
  'id': id,
  'created_at': createdAt ?? '2026-07-28T10:00:00Z',
  'source': ?source,
};

void main() {
  group('loadInboxData — paralelismo', () {
    test(
      'oleada A: los items y las ofertas de otro rubro se piden A LA VEZ',
      () async {
        final itemsGate = Completer<List<Map<String, dynamic>>>();
        final offeredGate = Completer<List<Map<String, dynamic>>>();
        var offeredStarted = false;

        final future = loadInboxData(
          fetchItems: () => itemsGate.future,
          fetchOfferedOpen: () {
            offeredStarted = true;
            return offeredGate.future;
          },
          fetchStatuses: (_) async => {},
          fetchCounts: (_) async => {},
          fetchRequirements: (_) async => {},
        );

        await Future<void>.delayed(Duration.zero);
        expect(
          offeredStarted,
          isTrue,
          reason: 'no debe esperar a que lleguen los items para arrancar',
        );

        itemsGate.complete([req('a')]);
        offeredGate.complete([req('b')]);
        final data = await future;
        expect(data.items.map((r) => r['id']), containsAll(['a', 'b']));
      },
    );

    test('oleada B: estados y conteos se piden A LA VEZ', () async {
      final statusGate = Completer<Map<String, String>>();
      final countGate = Completer<Map<String, int>>();
      var countStarted = false;

      final future = loadInboxData(
        fetchItems: () async => [req('a')],
        fetchOfferedOpen: null,
        fetchStatuses: (_) => statusGate.future,
        fetchCounts: (_) {
          countStarted = true;
          return countGate.future;
        },
        fetchRequirements: (_) async => {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        countStarted,
        isTrue,
        reason: 'no debe esperar a los estados para pedir los conteos',
      );

      statusGate.complete({'a': 'pending'});
      countGate.complete({'a': 3});
      final data = await future;
      expect(data.statuses, {'a': 'pending'});
      expect(data.counts, {'a': 3});
    });

    test(
      'oleada B: los requisitos se piden A LA VEZ que los estados',
      () async {
        final statusGate = Completer<Map<String, String>>();
        final reqGate = Completer<Map<String, RequestRequirements>>();
        var reqStarted = false;

        final future = loadInboxData(
          fetchItems: () async => [req('a')],
          fetchOfferedOpen: null,
          fetchStatuses: (_) => statusGate.future,
          fetchCounts: (_) async => {},
          fetchRequirements: (_) {
            reqStarted = true;
            return reqGate.future;
          },
        );

        await Future<void>.delayed(Duration.zero);
        expect(
          reqStarted,
          isTrue,
          reason: 'no debe esperar a los estados para pedir los requisitos',
        );

        statusGate.complete({'a': 'pending'});
        reqGate.complete({'a': const RequestRequirements(withShipping: true)});
        final data = await future;
        expect(data.requirements['a']!.withShipping, isTrue);
      },
    );
  });

  group('loadInboxData — semántica', () {
    test('el badge cuenta los items de marketplace ANTES del merge', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('tienda', source: 'store')],
        fetchOfferedOpen: () async => [req('b')],
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(
        data.badgeCount,
        1,
        reason: 'la tienda no cuenta, y "b" es seguimiento, no pendiente',
      );
    });

    test('el badge NO cuenta las solicitudes que YA ABRISTE', () async {
      // Pedido PO 2026-08-22: "solicitudes tiene una notificacion de 3, ya abri
      // todas las ventanas y sigue ahi". El badge del PROVEEDOR contaba el
      // INVENTARIO de "Para ti" (`items.length`), no la novedad, asi que no
      // habia forma de apagarlo: nada marcaba nada como visto. Ahora cuenta
      // solo lo que este dispositivo todavia no ha abierto.
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b'), req('c')],
        fetchOfferedOpen: null,
        openedIds: const {'a', 'b'},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 1, reason: 'solo "c" queda sin abrir');
      expect(data.items.length, 3,
          reason: 'abrirlas NO las saca de la bandeja, solo del badge');
    });

    test('abiertas todas, el badge se APAGA', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b')],
        fetchOfferedOpen: null,
        openedIds: const {'a', 'b'},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 0);
    });

    test(
      'el merge no duplica lo que ya venía y ordena por fecha desc',
      () async {
        final data = await loadInboxData(
          fetchItems: () async => [
            req('a', createdAt: '2026-07-20T00:00:00Z'),
            req('dup', createdAt: '2026-07-22T00:00:00Z'),
          ],
          fetchOfferedOpen: () async => [
            req('dup', createdAt: '2026-07-22T00:00:00Z'),
            req('z', createdAt: '2026-07-27T00:00:00Z'),
          ],
          fetchStatuses: (_) async => {},
          fetchCounts: (_) async => {},
          fetchRequirements: (_) async => {},
        );
        expect(data.items.map((r) => r['id']).toList(), ['z', 'dup', 'a']);
      },
    );

    test('sin fetchOfferedOpen (pestaña "Todas") no hay merge', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a')],
        fetchOfferedOpen: null,
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.items.map((r) => r['id']).toList(), ['a']);
    });

    test('los ids de marketplace excluyen la tienda', () async {
      List<String>? vistos;
      await loadInboxData(
        fetchItems: () async => [req('a'), req('s', source: 'store')],
        fetchOfferedOpen: null,
        fetchStatuses: (ids) async {
          vistos = ids;
          return {};
        },
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(vistos, ['a']);
    });
  });

  group('loadInboxData — best-effort', () {
    test(
      'si fallan las ofertas de otro rubro, la lista principal sobrevive',
      () async {
        final data = await loadInboxData(
          fetchItems: () async => [req('a')],
          fetchOfferedOpen: () async => throw StateError('red caída'),
          fetchStatuses: (_) async => {},
          fetchCounts: (_) async => {},
          fetchRequirements: (_) async => {},
        );
        expect(data.items.map((r) => r['id']).toList(), ['a']);
      },
    );

    test(
      'si fallan estados y conteos, quedan vacíos y la lista sobrevive',
      () async {
        final data = await loadInboxData(
          fetchItems: () async => [req('a')],
          fetchOfferedOpen: null,
          fetchStatuses: (_) async => throw StateError('boom'),
          fetchCounts: (_) async => throw StateError('boom'),
          fetchRequirements: (_) async => {},
        );
        expect(data.items.map((r) => r['id']).toList(), ['a']);
        expect(data.statuses, isEmpty);
        expect(data.counts, isEmpty);
      },
    );

    test(
      'si falla la lista principal, el error SÍ propaga (no es best-effort)',
      () async {
        await expectLater(
          loadInboxData(
            fetchItems: () async => throw StateError('sin red'),
            fetchOfferedOpen: () async => [req('b')],
            fetchStatuses: (_) async => {},
            fetchCounts: (_) async => {},
            fetchRequirements: (_) async => {},
          ),
          throwsStateError,
        );
      },
    );

    test(
      'si fallan los requisitos, quedan vacíos y la bandeja sobrevive',
      () async {
        final data = await loadInboxData(
          fetchItems: () async => [req('a')],
          fetchOfferedOpen: null,
          fetchStatuses: (_) async => {},
          fetchCounts: (_) async => {},
          fetchRequirements: (_) async => throw StateError('boom'),
        );
        expect(data.items.map((r) => r['id']).toList(), ['a']);
        expect(data.requirements, isEmpty);
      },
    );

    test('los requisitos NO se piden para las filas de la tienda', () async {
      List<String>? vistos;
      await loadInboxData(
        fetchItems: () async => [req('a'), req('s', source: 'store')],
        fetchOfferedOpen: null,
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (ids) async {
          vistos = ids;
          return {};
        },
      );
      expect(
        vistos,
        ['a'],
        reason:
            'un interés de producto no es una solicitud: no tiene requisitos',
      );
    });
  });
}
