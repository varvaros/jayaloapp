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

    // Pedido PO 2026-08-22: «debe ser "lo que no has abierto"; si tiene una
    // actualizacion que no has abierto, cuenta». El badge del PROVEEDOR contaba
    // el INVENTARIO de "Para ti", no la novedad, y no habia forma de apagarlo.
    // Se guarda la VERSION vista (`updated_at` de la fila al abrirla), no la
    // hora del telefono: la comparacion es servidor contra servidor.
    final t1 = DateTime.utc(2026, 8, 22, 10);
    final t2 = DateTime.utc(2026, 8, 22, 11);

    test('el badge NO cuenta las solicitudes que ya viste', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b'), req('c')],
        fetchOfferedOpen: null,
        seen: {'a': t1, 'b': t1},
        fetchUpdatedAt: (_) async => {'a': t1, 'b': t1, 'c': t1},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 1, reason: 'solo "c" queda sin ver');
      expect(data.items.length, 3,
          reason: 'verlas NO las saca de la bandeja, solo del badge');
    });

    test('una solicitud ACTUALIZADA despues de verla VUELVE a contar',
        () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b')],
        fetchOfferedOpen: null,
        seen: {'a': t1, 'b': t1},
        // "a" cambio despues de que la vieras; "b" sigue igual.
        fetchUpdatedAt: (_) async => {'a': t2, 'b': t1},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 1, reason: '"a" trae algo que no has abierto');
    });

    test('vistas todas y sin cambios, el badge se APAGA', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b')],
        fetchOfferedOpen: null,
        seen: {'a': t2, 'b': t2},
        fetchUpdatedAt: (_) async => {'a': t1, 'b': t1},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 0);
    });

    // Queja del PO 2026-08-25: «sigo sin saber que es ese 4 en la barra, no me
    // senala nada pendiente». Una solicitud DESCARTADA con el swipe sale de la
    // bandeja pero seguia contando en el badge: el numero apuntaba a tarjetas
    // que NO estan en pantalla, asi que no habia forma de bajarlo.
    test('el badge NO cuenta las solicitudes DESCARTADAS', () async {
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b')],
        fetchOfferedOpen: null,
        hidden: {'b'},
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 1, reason: 'descartar la saca tambien del badge');
      expect(
        data.items.length,
        2,
        reason: 'el filtro visual vive en la pantalla; aqui solo se deja de contar',
      );
      expect(
        data.badgeIds,
        containsAll(['a', 'b']),
        reason: 'sigue siendo candidata: «Deshacer» la devuelve al contador '
            'sin volver a la red',
      );
    });

    test('si updated_at no llega, lo ya visto SIGUE visto', () async {
      // La consulta es best-effort: al fallar no se puede saber si cambio. Se
      // cree lo que se sabe — el badge se queda corto, nunca grita de mas.
      final data = await loadInboxData(
        fetchItems: () async => [req('a'), req('b')],
        fetchOfferedOpen: null,
        seen: {'a': t1},
        fetchUpdatedAt: (_) async => throw Exception('sin red'),
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (_) async => {},
      );
      expect(data.badgeCount, 1, reason: 'solo "b", que nunca se abrio');
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
