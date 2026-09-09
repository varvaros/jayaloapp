import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo_app/core/ai_client.dart';
import 'package:jayalo_app/domain/ai_turns.dart';

/// El servidor emite un `aiTicket` HMAC en cada respuesta y lo EXIGE en los
/// turnos 2+ (cierra el bypass del historial inventado, `aiTicket.server.ts`
/// de la web). Sin reenviarlo, cada turno de la app paga un `auth.getUser()`
/// contra Supabase Auth que la web se ahorra — el ticket se valida en local.
void main() {
  Map<String, dynamic> bodyOf(http.Request req) =>
      jsonDecode(req.body) as Map<String, dynamic>;

  /// Ids de conversación de ejemplo: 32 hex, la forma que emite el servidor.
  const conv1 = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
  const conv2 = '00112233445566778899aabbccddeeff';

  http.Response turnWithTicket({String? ticket, String? conversationId}) =>
      http.Response(
          jsonEncode({
            'type': 'question',
            // ASCII a propósito: http.Response(String) codifica latin-1 y el
            // cliente decodifica utf8 — un acento aquí rompería el fixture.
            'question': 'Marca?',
            'options': ['A', 'B'],
            'aiTicket': ?ticket,
            'aiConversationId': ?conversationId,
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

  test('todo POST pide el readyNext del routing (F3, opt-in wantReadyNext)',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket();
    }));
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    expect(sent[0]['wantReadyNext'], isTrue);
  });

  test('un routing con readyNext llega parseado hasta el caller (F3)',
      () async {
    final c = AiClient(inner: MockClient((req) async {
      return http.Response(
          jsonEncode({
            'type': 'routing',
            'message': 'Voy a enviar tu solicitud a:',
            'categories': ['hogar'],
            'rubros': ['u1'],
            'readyNext': {
              'type': 'ready',
              'title': 'Silla de oficina',
              'bullets': ['Con ruedas'],
            },
          }),
          200);
    }));
    final turn =
        await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    final r = turn as AiRouting;
    expect(r.readyNext, isNotNull);
    expect(r.readyNext!.title, 'Silla de oficina');
  });

  // Desde `aiTicket` v2 (2026-09-09) el ticket va ATADO a su conversación: el
  // servidor exige el par y un ticket suelto ya no vale. Sin reenviar el id, la
  // app cae en la exención por JWT y paga un `auth.getUser()` por turno.
  test('reenvía el PAR (ticket + aiConversationId) en el turno siguiente',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-1', conversationId: conv1);
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    // Primer turno: ninguno de los dos existe todavía.
    expect(sent[0].containsKey('aiTicket'), isFalse);
    expect(sent[0].containsKey('aiConversationId'), isFalse);
    expect(sent[1]['aiTicket'], 'tkt-1');
    expect(sent[1]['aiConversationId'], conv1);
  });

  test('sigue al servidor si cambia el id de conversación', () async {
    final sent = <Map<String, dynamic>>[];
    var calls = 0;
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      calls++;
      return turnWithTicket(
          ticket: 'tkt-$calls', conversationId: calls == 1 ? conv1 : conv2);
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[1]['aiConversationId'], conv1);
    expect(sent[2]['aiConversationId'], conv2);
  });

  test('un id con forma inválida se descarta: no se reenvía basura', () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-1', conversationId: 'NO-ES-HEX');
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[1]['aiTicket'], 'tkt-1');
    expect(sent[1].containsKey('aiConversationId'), isFalse);
  });

  test('un servidor viejo (ticket sin id) no deja el par a medias', () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-1');
    }));

    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[1]['aiTicket'], 'tkt-1');
    expect(sent[1].containsKey('aiConversationId'), isFalse);
  });

  test('cada AiClient es una conversación: no comparten el par', () async {
    final sentA = <Map<String, dynamic>>[];
    final sentB = <Map<String, dynamic>>[];
    final a = AiClient(inner: MockClient((req) async {
      sentA.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-a', conversationId: conv1);
    }));
    final b = AiClient(inner: MockClient((req) async {
      sentB.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-b', conversationId: conv2);
    }));

    await a.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await b.sendTurn(messages: [const AiMessage('user', 'hola')]);
    await a.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sentB[0].containsKey('aiConversationId'), isFalse);
    expect(sentA[1]['aiConversationId'], conv1);
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

  test('useTemplates viaja SOLO en el primer turno, y solo si el caller lo pide',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket(ticket: 'tkt-1');
    }));

    // Primer turno con el flag: va.
    await c.sendTurn(
        messages: [const AiMessage('user', 'hola')], useTemplates: true);
    // Turno 2+ aunque el caller insista: NO va (el servidor solo lo mira con
    // messages.length === 1, chat-stream.ts L331; y el fallback a IA manda
    // el historial completo sin plantillas, spec §8.3).
    await c.sendTurn(messages: [
      const AiMessage('user', 'hola'),
      const AiMessage('assistant', '{"type":"question","question":"q","options":[]}'),
      const AiMessage('user', 'Pregunta: q\nRespuesta: a'),
    ], useTemplates: true);
    // Primer turno sin pedirlo: NO va (comportamiento de siempre).
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);

    expect(sent[0]['useTemplates'], isTrue);
    expect(sent[1].containsKey('useTemplates'), isFalse);
    expect(sent[2].containsKey('useTemplates'), isFalse);
  });

  test('sonda del body del primer turno: las claves que el servidor espera',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket();
    }));
    await c.sendTurn(
        messages: [const AiMessage('user', 'busco un aire')],
        kind: 'producto',
        useTemplates: true);
    expect(sent[0].keys.toSet(),
        {'messages', 'kind', 'wantReadyNext', 'useTemplates'});
    expect(sent[0]['messages'], [
      {'role': 'user', 'content': 'busco un aire'}
    ]);
  });

  test('un turno template válido llega parseado como AiTemplate', () async {
    final c = AiClient(inner: MockClient((req) async {
      return http.Response(
          jsonEncode({
            'type': 'template',
            'template': {
              'id': 'tpl-1',
              'version': 1,
              'scope': 'rubro:x',
              'questions': [
                {'key': 'marca', 'label': 'Marca', 'question': 'Marca?', 'options': ['A']},
              ],
            },
            'routing': {'categories': ['hogar'], 'rubros': ['u1']},
            'known_attributes': {'tipo': 'aire'},
            'aiTicket': 'tkt-1',
          }),
          200);
    }));
    final turn = await c.sendTurn(
        messages: [const AiMessage('user', 'hola')], useTemplates: true);
    expect(turn, isA<AiTemplate>());
    expect((turn as AiTemplate).categories, ['hogar']);
  });

  test('un template malformado lanza TemplateFormatException (turno fallido, no cuelgue)',
      () async {
    final c = AiClient(inner: MockClient((req) async {
      return http.Response(
          jsonEncode({'type': 'template', 'template': 'x', 'aiTicket': 'tkt-1'}), 200);
    }));
    await expectLater(
        c.sendTurn(messages: [const AiMessage('user', 'hola')], useTemplates: true),
        throwsA(isA<TemplateFormatException>()));
  });

  test('manual viaja SOLO en el primer turno y solo si el caller lo pide', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = AiClient(inner: MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"type":"ready","title":"x","bullets":[]}', 200);
    }));
    await client.sendTurn(messages: const [AiMessage('user', 'silla')], manual: true);
    await client.sendTurn(
        messages: const [AiMessage('user', 'silla'), AiMessage('assistant', '{}')],
        manual: true);
    await client.sendTurn(messages: const [AiMessage('user', 'silla')]);
    expect(bodies[0]['manual'], isTrue);
    expect(bodies[1].containsKey('manual'), isFalse);
    expect(bodies[2].containsKey('manual'), isFalse);
  });

  test('manda imageId en vez del base64 cuando la ranura tiene id; el mixto va por ranura',
      () async {
    final sent = <Map<String, dynamic>>[];
    final c = AiClient(inner: MockClient((req) async {
      sent.add(bodyOf(req));
      return turnWithTicket();
    }));
    await c.sendTurn(
        messages: [const AiMessage('user', 'hola')],
        imageId: 'a' * 32,
        imageDataUrl2: 'data:image/jpeg;base64,BBBB');
    expect(sent.single['imageId'], 'a' * 32);
    expect(sent.single.containsKey('imageDataUrl'), isFalse);
    expect(sent.single['imageDataUrl2'], 'data:image/jpeg;base64,BBBB');
    expect(sent.single.containsKey('imageId2'), isFalse);
  });

  test('expone los ids que devuelve el servidor en lastImageIds (nulos si no vienen)', () async {
    var conIds = true;
    final c = AiClient(inner: MockClient((req) async => http.Response(
        jsonEncode({
          'type': 'question',
          'question': 'Marca?',
          'options': ['A'],
          if (conIds) 'imageId': 'a' * 32,
          if (conIds) 'imageId2': 'b' * 32,
        }),
        200)));
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    expect(c.lastImageIds.first, 'a' * 32);
    expect(c.lastImageIds.second, 'b' * 32);
    conIds = false;
    await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
    expect(c.lastImageIds.first, isNull);
    expect(c.lastImageIds.second, isNull);
  });

  test('un 409 image_expired lanza AiHttpException con code', () async {
    final c = AiClient(inner: MockClient((_) async => http.Response(
        jsonEncode({'error': 'caduco', 'code': 'image_expired'}), 409)));
    try {
      await c.sendTurn(messages: [const AiMessage('user', 'hola')]);
      fail('debia lanzar');
    } on AiHttpException catch (e) {
      expect(e.status, 409);
      expect(e.code, 'image_expired');
    }
  });
}
