import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo_app/core/ai_client.dart';

/// El servidor emite un `aiTicket` HMAC en cada respuesta y lo EXIGE en los
/// turnos 2+ (cierra el bypass del historial inventado, `aiTicket.server.ts`
/// de la web). Sin reenviarlo, cada turno de la app paga un `auth.getUser()`
/// contra Supabase Auth que la web se ahorra — el ticket se valida en local.
void main() {
  Map<String, dynamic> bodyOf(http.Request req) =>
      jsonDecode(req.body) as Map<String, dynamic>;

  http.Response turnWithTicket({String? ticket}) => http.Response(
      jsonEncode({
        'type': 'question',
        // ASCII a propósito: http.Response(String) codifica latin-1 y el
        // cliente decodifica utf8 — un acento aquí rompería el fixture.
        'question': 'Marca?',
        'options': ['A', 'B'],
        'aiTicket': ?ticket,
      }),
      200);

  test('reenvía el aiTicket de la respuesta anterior en el turno siguiente',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-1');
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    // Primer turno: sin ticket (aún no existe). Segundo: el emitido.
    expect(sent[0].containsKey('aiTicket'), isFalse);
    expect(sent[1]['aiTicket'], 'tkt-1');
  });

  test('una respuesta sin ticket NO borra el que ya se tenía', () async {
    final sent = <Map<String, dynamic>>[];
    var calls = 0;
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      calls++;
      // Solo el primer turno emite ticket; el segundo viene sin él.
      return turnWithTicket(ticket: calls == 1 ? 'tkt-1' : null);
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[2]['aiTicket'], 'tkt-1');
  });

  test('un error HTTP lanza AiHttpException y conserva el ticket', () async {
    final sent = <Map<String, dynamic>>[];
    var calls = 0;
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      calls++;
      if (calls == 2) return http.Response(jsonEncode({'error': 'boom'}), 429);
      return turnWithTicket(ticket: 'tkt-1');
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await expectLater(
        c.sendTurn(messages: [const AiMessage('user', 'hola')]),
        throwsA(isA<AiHttpException>()));
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[2]['aiTicket'], 'tkt-1');
  });

  test('un POST colgado se corta con TimeoutException (no espera infinita)',
      () async {
    final c = AiClient(
      timeout: const Duration(milliseconds: 50),
      inner: MockClient((_) =>
          Future.delayed(const Duration(seconds: 5), () => turnWithTicket())),
    );
    await expectLater(
        c.sendTurn(messages: [const AiMessage('user', 'hola')]),
        throwsA(isA<TimeoutException>()));
  });
}
