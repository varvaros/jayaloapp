import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/inbox_load.dart';

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
  });

  group('loadInboxData — semántica', () {
    test('el badge cuenta los items de marketplace ANTES del merge', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('tienda', source: 'store')],
        fetchOfferedOpen: () async => [req('b')],
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
      );
      expect(
        data.badgeCount,
        1,
        reason: 'la tienda no cuenta, y "b" es seguimiento, no pendiente',
      );
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
          ),
          throwsStateError,
        );
      },
    );
  });
}
