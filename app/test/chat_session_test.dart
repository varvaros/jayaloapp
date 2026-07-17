import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';
import 'package:jayalo_app/domain/chat_session.dart';

Map<String, dynamic> row(String id, String? sender, String body, String at, [String kind = 'text']) =>
    {'id': id, 'sender_id': sender, 'kind': kind, 'body': body, 'created_at': at};

void main() {
  test('seedFirstPage invierte a cronológico y fija hasMore', () {
    final s = ChatSession();
    s.seedFirstPage([row('3', 'a', 'c', '2026-07-17T10:02:00Z'), row('2', 'a', 'b', '2026-07-17T10:01:00Z')], 2);
    expect(s.messages.map((m) => m.id).toList(), ['2', '3']);
    expect(s.hasMore, isTrue); // página llena → puede haber más
    expect(s.oldestCursor(), ('2026-07-17T10:01:00Z', '2'));
  });
  test('página corta → hasMore false', () {
    final s = ChatSession();
    s.seedFirstPage([row('1', 'a', 'a', '2026-07-17T10:00:00Z')], 50);
    expect(s.hasMore, isFalse);
  });
  test('prependOlder mete al inicio', () {
    final s = ChatSession();
    s.seedFirstPage([row('3', 'a', 'c', '2026-07-17T10:02:00Z')], 1);
    s.prependOlder([row('2', 'a', 'b', '2026-07-17T10:01:00Z'), row('1', 'a', 'a', '2026-07-17T10:00:00Z')], 50);
    expect(s.messages.map((m) => m.id).toList(), ['1', '2', '3']);
    expect(s.hasMore, isFalse);
  });
  test('optimista: add + confirm reemplaza el temp', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: 'u', kind: 'text', body: 'hola', now: DateTime.utc(2026, 7, 17));
    expect(s.messages.single.sendStatus, SendStatus.sending);
    s.confirmOptimistic('temp-1', row('real-1', 'u', 'hola', '2026-07-17T10:00:00Z'));
    expect(s.messages.single.id, 'real-1');
    expect(s.messages.single.sendStatus, SendStatus.sent);
  });
  test('optimista: fallo lo retira', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: 'u', kind: 'text', body: 'hola', now: DateTime.utc(2026, 7, 17));
    s.removeOptimistic('temp-1');
    expect(s.messages, isEmpty);
  });
  test('mergeServer reconcilia con temp pendiente (mismo sender/kind/body)', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: 'u', kind: 'text', body: 'hola', now: DateTime.utc(2026, 7, 17));
    final changed = s.mergeServer(row('real-1', 'u', 'hola', '2026-07-17T10:00:00Z'));
    expect(changed, isTrue);
    expect(s.messages.single.id, 'real-1');
  });
  test('mergeServer dedupe por id', () {
    final s = ChatSession();
    s.seedFirstPage([row('1', 'a', 'x', '2026-07-17T10:00:00Z')], 50);
    expect(s.mergeServer(row('1', 'a', 'x', '2026-07-17T10:00:00Z')), isFalse);
    expect(s.messages.length, 1);
  });
  test('mergeServer del peer inserta ordenado', () {
    final s = ChatSession();
    s.seedFirstPage([row('1', 'a', 'x', '2026-07-17T10:00:00Z')], 50);
    s.mergeServer(row('0', 'b', 'w', '2026-07-17T09:00:00Z'));
    expect(s.messages.first.id, '0');
  });
  test('applyUpdate cambia el body (quick respondido)', () {
    final s = ChatSession();
    s.seedFirstPage([row('1', 'a', '{"q":1}', '2026-07-17T10:00:00Z', 'quick')], 50);
    s.applyUpdate(row('1', 'a', '{"q":2}', '2026-07-17T10:00:00Z', 'quick'));
    expect(s.messages.single.body, '{"q":2}');
  });
  test('gap: newestServerCreatedAtRaw ignora temps y mergeGap dedupea', () {
    final s = ChatSession();
    s.seedFirstPage([row('1', 'a', 'x', '2026-07-17T10:00:00Z')], 50);
    s.addOptimistic(tempId: 'temp-9', senderId: 'u', kind: 'text', body: 'y', now: DateTime.utc(2026, 7, 18));
    expect(s.newestServerCreatedAtRaw(), '2026-07-17T10:00:00Z');
    s.mergeGap([row('1', 'a', 'x', '2026-07-17T10:00:00Z'), row('2', 'b', 'z', '2026-07-17T10:05:00Z')]);
    expect(s.messages.where((m) => m.id == '2').length, 1);
    expect(s.messages.where((m) => m.id == '1').length, 1);
  });

  // FIX 1: seedFirstPage no debe destruir mensajes optimistas en vuelo.
  test('seedFirstPage preserva optimistas "sending" al final y siguen reconciliables', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: 'u', kind: 'text', body: 'hola', now: DateTime.utc(2026, 7, 17, 10, 5));
    s.seedFirstPage([row('1', 'a', 'x', '2026-07-17T10:00:00Z')], 50);
    expect(s.messages.map((m) => m.id).toList(), ['1', 'temp-1']);
    expect(s.messages.last.sendStatus, SendStatus.sending);
    s.confirmOptimistic('temp-1', row('real-1', 'u', 'hola', '2026-07-17T10:06:00Z'));
    expect(s.messages.map((m) => m.id).toList(), ['1', 'real-1']);
    expect(s.messages.last.sendStatus, SendStatus.sent);
  });

  // FIX 2: el orden de mergeServer debe comparar por DateTime, no por string
  // crudo — el mismo instante formateado como '+00:00' (fila existente) vs
  // 'Z' (fila nueva) NO son iguales como string ('Z' > '+00:00' siempre,
  // sin importar el instante real), así que el string-compare rompe tanto
  // la igualdad como el desempate por id. Con DateTime real hay empate de
  // tiempo y debe desempatar por id ('1' < '2' → la nueva va primero).
  test('mergeServer ordena por createdAt real (empate) y desempata por id, no por string crudo mixto', () {
    final s = ChatSession();
    s.seedFirstPage([row('2', 'a', 'x', '2026-07-17T10:00:00+00:00')], 50);
    s.mergeServer(row('1', 'b', 'y', '2026-07-17T10:00:00Z'));
    expect(s.messages.map((m) => m.id).toList(), ['1', '2']);
  });

  // FIX 3: confirmOptimistic no debe duplicar si mergeServer ya reconcilió
  // la fila real primero (realtime ganó la carrera). AJUSTE (Task 9 fix 3):
  // antes se usaba senderId: null para forzar el no-match, aprovechando que
  // addOptimistic con senderId null NO se agregaba a `_pending`. Con el fix
  // de FIX 3, addOptimistic SIEMPRE agrega a `_pending` (senderId null
  // incluido), así que ahora se fuerza el no-match con un body distinto
  // entre el optimista y la fila real — la heurística de mergeServer
  // matchea por (senderId, kind, body), así que un body distinto no matchea
  // igual que antes lo lograba el senderId null.
  test('confirmOptimistic es no-op si la fila real ya fue reconciliada por mergeServer', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: 'u', kind: 'text', body: 'hola', now: DateTime.utc(2026, 7, 17));
    final realRow = row('real-1', 'u', 'distinto', '2026-07-17T10:00:00Z');
    final changed = s.mergeServer(realRow);
    expect(changed, isTrue);
    expect(s.messages.map((m) => m.id).toSet(), {'temp-1', 'real-1'});
    s.confirmOptimistic('temp-1', realRow);
    expect(s.messages.where((m) => m.id == 'real-1').length, 1);
    expect(s.messages.length, 1);
  });

  // FIX 3 (Task 9 review, Important): addOptimistic solo agregaba a
  // `_pending` cuando senderId != null, así que un mensaje con sender NULL
  // (ej. 'audit', insertado con systemSender) que llega por realtime ANTES
  // de que confirme su propio insert no tenía con qué reconciliar por
  // heurística en mergeServer → quedaba como mensaje nuevo separado del
  // optimista, produciendo burbuja duplicada transitoria. Con el fix,
  // `_pending` trackea también senderId null (null == null matchea en Dart).
  test('addOptimistic con senderId null se reconcilia por mergeServer (no duplica)', () {
    final s = ChatSession();
    s.addOptimistic(tempId: 'temp-1', senderId: null, kind: 'audit', body: '¿Ya recibiste tu producto?', now: DateTime.utc(2026, 7, 17));
    final changed = s.mergeServer(row('real-1', null, '¿Ya recibiste tu producto?', '2026-07-17T10:00:00Z', 'audit'));
    expect(changed, isTrue);
    expect(s.messages.length, 1);
    expect(s.messages.single.id, 'real-1');
  });
}
