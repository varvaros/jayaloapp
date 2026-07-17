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
}
