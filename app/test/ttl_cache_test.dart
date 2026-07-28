import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/ttl_cache.dart';

/// Espejo de `jayalo-main/src/lib/ttlCache.test.ts`: la app y la web amortizan
/// las mismas lecturas, así que la semántica del caché debe coincidir. Lo que
/// la app añade sobre la web: coalescing de peticiones en vuelo y un registro
/// global para vaciar todo en el signOut.
void main() {
  setUp(TtlCache.clearAll);

  group('TtlCache', () {
    test('vacío = miss', () {
      final c = TtlCache<int>(const Duration(seconds: 1));
      expect(c.has, isFalse);
      expect(c.value, isNull);
    });

    test('sirve el valor dentro del TTL', () {
      var now = DateTime(2026, 7, 28, 12);
      final c = TtlCache<int>(const Duration(seconds: 60), clock: () => now);
      c.set(42);
      now = now.add(const Duration(seconds: 59));
      expect(c.has, isTrue);
      expect(c.value, 42);
    });

    test('expira justo al cumplirse el TTL', () {
      var now = DateTime(2026, 7, 28, 12);
      final c = TtlCache<int>(const Duration(seconds: 60), clock: () => now);
      c.set(42);
      now = now.add(const Duration(seconds: 60));
      expect(c.has, isFalse);
      expect(c.value, isNull);
    });

    test('distingue "no hay valor" de un null/false cacheado', () {
      final c = TtlCache<int?>(const Duration(seconds: 60));
      expect(c.has, isFalse);
      c.set(null);
      expect(c.has, isTrue, reason: 'null cacheado ES un valor vigente');
      expect(c.value, isNull);
    });

    test('clear() vacía', () {
      final c = TtlCache<int>(const Duration(seconds: 60))..set(1);
      c.clear();
      expect(c.has, isFalse);
    });

    test('clearAll() vacía TODAS las registradas (signOut)', () {
      final a = TtlCache<int>(const Duration(seconds: 60))..set(1);
      final b = TtlCache<String>(const Duration(seconds: 60))..set('x');
      TtlCache.clearAll();
      expect(a.has, isFalse);
      expect(b.has, isFalse);
    });
  });

  group('read', () {
    test('llama al fetcher una vez y luego sirve de caché', () async {
      var calls = 0;
      final c = TtlCache<int>(const Duration(seconds: 60));
      Future<int> fetch() async {
        calls++;
        return 7;
      }

      expect(await c.read(fetch), 7);
      expect(await c.read(fetch), 7);
      expect(calls, 1);
    });

    test('vuelve a pedir cuando expira', () async {
      var now = DateTime(2026, 7, 28, 12);
      var calls = 0;
      final c = TtlCache<int>(const Duration(seconds: 60), clock: () => now);
      Future<int> fetch() async => ++calls;

      expect(await c.read(fetch), 1);
      now = now.add(const Duration(seconds: 61));
      expect(await c.read(fetch), 2);
      expect(calls, 2);
    });

    test('NO cachea errores: el siguiente intento reintenta', () async {
      var calls = 0;
      final c = TtlCache<int>(const Duration(seconds: 60));
      Future<int> fetch() async {
        calls++;
        if (calls == 1) throw StateError('red caída');
        return 9;
      }

      await expectLater(c.read(fetch), throwsStateError);
      expect(c.has, isFalse, reason: 'un fallo no debe dejar entrada');
      expect(await c.read(fetch), 9);
      expect(calls, 2);
    });

    test(
      'coalescing: dos lecturas simultáneas comparten UNA petición',
      () async {
        var calls = 0;
        final gate = Completer<int>();
        final c = TtlCache<int>(const Duration(seconds: 60));
        Future<int> fetch() {
          calls++;
          return gate.future;
        }

        final a = c.read(fetch);
        final b = c.read(fetch);
        gate.complete(5);
        expect(await a, 5);
        expect(await b, 5);
        expect(calls, 1, reason: 'la segunda se cuelga del future en vuelo');
      },
    );

    test(
      'tras un error en vuelo, ambos esperadores fallan y no queda entrada',
      () async {
        final gate = Completer<int>();
        final c = TtlCache<int>(const Duration(seconds: 60));
        final a = c.read(() => gate.future);
        final b = c.read(() => gate.future);
        gate.completeError(StateError('boom'));
        await expectLater(a, throwsStateError);
        await expectLater(b, throwsStateError);
        expect(c.has, isFalse);
      },
    );

    test(
      'clear() durante una petición en vuelo no deja valor rancio',
      () async {
        final gate = Completer<int>();
        final c = TtlCache<int>(const Duration(seconds: 60));
        final f = c.read(() => gate.future);
        c.clear(); // p.ej. un unlock invalidó el saldo mientras se pedía
        gate.complete(3);
        expect(await f, 3, reason: 'quien pidió igual recibe su respuesta');
        expect(
          c.has,
          isFalse,
          reason: 'pero el valor invalidado NO se guarda como vigente',
        );
      },
    );
  });
}
