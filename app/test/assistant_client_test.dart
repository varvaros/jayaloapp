import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:jayalo_app/core/assistant_client.dart';

void main() {
  test('state manda Origin + Bearer y la acción', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({
            'active': true,
            'paused': false,
            'handoverRequested': false,
            'enabled': true,
            'perChatCost': 2,
          }),
          200);
    });
    final s = await AssistantClient(inner: mock)
        .state(conversationId: 'conv-1', accessToken: 'tok');
    expect(captured.headers['Authorization'], 'Bearer tok');
    expect(captured.headers['Origin'], 'https://jayalo.com');
    expect(jsonDecode(captured.body)['action'], 'state');
    expect(jsonDecode(captured.body)['conversation_id'], 'conv-1');
    expect(s.active, true);
    expect(s.perChatCost, 2);
  });

  test('el coste sale del servidor, no de un literal', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'active': false,
          'paused': false,
          'handoverRequested': false,
          'enabled': true,
          'perChatCost': 7,
        }),
        200));
    final s = await AssistantClient(inner: mock)
        .state(conversationId: 'c', accessToken: 't');
    expect(s.perChatCost, 7);
  });

  test('activate devuelve lo cobrado y el modo', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'ok': true,
          'charged': 0,
          'billing_mode': 'monthly',
          'balance': 40,
        }),
        200));
    final r = await AssistantClient(inner: mock)
        .activate(conversationId: 'c', accessToken: 't');
    expect(r.charged, 0);
    expect(r.billingMode, 'monthly');
    expect(r.balance, 40);
  });

  test('pause manda el booleano', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    await AssistantClient(inner: mock)
        .pause(conversationId: 'c', paused: false, accessToken: 't');
    expect(jsonDecode(captured.body)['action'], 'pause');
    expect(jsonDecode(captured.body)['paused'], false);
  });

  test('un 402 lleva coste y saldo a la excepción', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({'error': 'saldo insuficiente', 'cost': 2, 'balance': 1}), 402));
    try {
      await AssistantClient(inner: mock)
          .activate(conversationId: 'c', accessToken: 't');
      fail('debía lanzar');
    } on AssistantException catch (e) {
      expect(e.status, 402);
      expect(e.cost, 2);
      expect(e.balance, 1);
      expect(e.sinSaldo, true);
    }
  });

  test('un 403 es excepción sin coste', () async {
    final mock = MockClient(
        (req) async => http.Response(jsonEncode({'error': 'Forbidden'}), 403));
    try {
      await AssistantClient(inner: mock)
          .state(conversationId: 'c', accessToken: 't');
      fail('debía lanzar');
    } on AssistantException catch (e) {
      expect(e.status, 403);
      expect(e.sinSaldo, false);
      expect(e.cost, isNull);
    }
  });

  test('un cuerpo que no es JSON no revienta con FormatException', () async {
    final mock = MockClient((req) async => http.Response('<html>502</html>', 502));
    try {
      await AssistantClient(inner: mock)
          .state(conversationId: 'c', accessToken: 't');
      fail('debía lanzar');
    } on AssistantException catch (e) {
      expect(e.status, 502);
    }
  });

  test('subscription devuelve fecha y coste', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'monthly_active_until': '2026-10-15T00:00:00.000Z',
          'monthlyCost': 20,
        }),
        200));
    final r = await AssistantClient(inner: mock)
        .subscription(businessId: 'b', accessToken: 't');
    expect(r.activeUntil, DateTime.parse('2026-10-15T00:00:00.000Z'));
    expect(r.monthlyCost, 20);
  });

  test('subscription sin suscripción devuelve null en la fecha', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({'monthly_active_until': null, 'monthlyCost': 20}), 200));
    final r = await AssistantClient(inner: mock)
        .subscription(businessId: 'b', accessToken: 't');
    expect(r.activeUntil, isNull);
    expect(r.monthlyCost, 20);
  });

  test('subscribe devuelve lo cobrado', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'ok': true,
          'expires_at': '2026-10-15T00:00:00.000Z',
          'charged': 20,
          'monthlyCost': 20,
        }),
        200));
    final r = await AssistantClient(inner: mock)
        .subscribe(businessId: 'b', accessToken: 't');
    expect(r.charged, 20);
    expect(r.expiresAt, DateTime.parse('2026-10-15T00:00:00.000Z'));
  });

  test('enable manda la acción y no interpreta el cuerpo', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    await AssistantClient(inner: mock)
        .enable(conversationId: 'c', accessToken: 't');
    expect(jsonDecode(captured.body)['action'], 'enable');
    expect(jsonDecode(captured.body)['conversation_id'], 'c');
  });

  test('reply devuelve el motivo cuando no manda nada', () async {
    final mock = MockClient((req) async =>
        http.Response(jsonEncode({'sent': false, 'reason': 'disabled'}), 200));
    final r = await AssistantClient(inner: mock)
        .reply(conversationId: 'c', accessToken: 't');
    expect(r.sent, false);
    expect(r.reason, 'disabled');
  });
}
