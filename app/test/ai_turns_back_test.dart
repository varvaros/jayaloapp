import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_turns.dart';

/// Port de jayalo-main src/lib/aiTurns.test.ts + los casos propios de la app
/// (turnToJson con attributes/meta, answeredCount, formato de respuesta).
final q1 = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'question',
      'question': '¿Marca?',
      'options': ['Samsung', 'LG'],
      'allowOther': true,
      'attribute': 'marca',
    }));
const a1 = AiMessage('user', 'Pregunta: ¿Marca?\nRespuesta: Samsung');
final q2 = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'question',
      'question': '¿Cantidad?',
      'options': ['1', '2'],
    }));
const a2 = AiMessage('user', 'Pregunta: ¿Cantidad?\nRespuesta: 1');
final routing = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'routing',
      'message': 'Voy a enviar tu solicitud a:',
      'categories': ['electronica'],
      'rubros': ['r1'],
    }));
const ok = AiMessage('user', 'ok');
final ready = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'ready',
      'title': 'Tele Samsung',
      'bullets': ['Marca: Samsung'],
      'attributes': {'marca': 'Samsung'},
      'meta': {'model': 'm', 'promptVersion': 'v'},
    }));

void main() {
  group('AiMessage', () {
    test('compara por valor (los tests de stepBack lo necesitan)', () {
      expect(const AiMessage('user', 'x'), const AiMessage('user', 'x'));
      expect(const AiMessage('user', 'x'), isNot(const AiMessage('assistant', 'x')));
      expect(const AiMessage('user', 'x').toJson(), {'role': 'user', 'content': 'x'});
    });
  });

  group('parseAssistantTurn', () {
    test('parsea los cinco tipos y devuelve null para lo demás', () {
      expect(parseAssistantTurn(q1.content), isA<AiQuestion>());
      final r = parseAssistantTurn(routing.content) as AiRouting;
      expect(r.message, 'Voy a enviar tu solicitud a:');
      expect(r.categories, ['electronica']);
      expect(r.rubros, ['r1']);
      final rd = parseAssistantTurn(ready.content) as AiReady;
      expect(rd.attributes, {'marca': 'Samsung'});
      expect(rd.meta, (model: 'm', promptVersion: 'v'));
      expect(rd.wholesale, isFalse);
      expect(
          parseAssistantTurn(jsonEncode({
            'type': 'kind_switch',
            'message': 'x',
            'suggested_kind': 'servicio',
            'options': ['Sí', 'No'],
          })),
          isA<AiKindSwitch>());
      expect(
          parseAssistantTurn(jsonEncode(
              {'type': 'image_request', 'message': 'otra foto', 'hint': 'de cerca'})),
          isA<AiImageRequest>());
      expect(parseAssistantTurn('no es json'), isNull);
      expect(parseAssistantTurn('{roto'), isNull);
      expect(parseAssistantTurn('[1,2]'), isNull);
      expect(parseAssistantTurn(jsonEncode({'type': 'otra_cosa'})), isNull);
    });

    test('una question sin options válidas devuelve options vacías, no revienta', () {
      final t = parseAssistantTurn(
          jsonEncode({'type': 'question', 'question': '¿?', 'options': 'mal'})) as AiQuestion;
      expect(t.question, '¿?');
      expect(t.options, isEmpty);
      expect(t.allowOther, isTrue);
      expect(t.attribute, isNull);
    });
  });

  group('attributes y meta', () {
    test('question.attribute solo si es una clave snake_case válida', () {
      expect((parseAiTurn({'type': 'question', 'question': 'q', 'attribute': 'tipo_unidad'}) as AiQuestion).attribute, 'tipo_unidad');
      expect((parseAiTurn({'type': 'question', 'question': 'q', 'attribute': 'Tipo Unidad'}) as AiQuestion).attribute, isNull);
      expect((parseAiTurn({'type': 'question', 'question': 'q', 'attribute': 7}) as AiQuestion).attribute, isNull);
    });

    test('ready.attributes se sanea como en la web (aiAttributes.ts)', () {
      final rd = parseAiTurn({
        'type': 'ready',
        'title': 'T',
        'bullets': <String>[],
        'attributes': {
          'marca': '  Samsung ',
          'Tipo': 'x',
          'con-guion': 'x',
          'numero': 5,
          'vacio': '   ',
          'largo': 'x' * 200,
        },
      }) as AiReady;
      expect(rd.attributes['marca'], 'Samsung');
      expect(rd.attributes.containsKey('Tipo'), isFalse);
      expect(rd.attributes.containsKey('con-guion'), isFalse);
      expect(rd.attributes.containsKey('numero'), isFalse);
      expect(rd.attributes.containsKey('vacio'), isFalse);
      expect(rd.attributes['largo']!.length, 120);
    });

    test('attributes: como mucho 20 claves; basura → {}', () {
      final many = {for (var i = 0; i < 30; i++) 'k$i': 'v'};
      final rd = parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[], 'attributes': many}) as AiReady;
      expect(rd.attributes.length, 20);
      expect((parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[], 'attributes': 'no'}) as AiReady).attributes, isEmpty);
      expect((parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[], 'attributes': [1]}) as AiReady).attributes, isEmpty);
    });

    test('meta solo si model y promptVersion son strings', () {
      expect((parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[], 'meta': {'model': 'm'}}) as AiReady).meta, isNull);
      expect((parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[], 'meta': 'x'}) as AiReady).meta, isNull);
      expect((parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': <String>[]}) as AiReady).meta, isNull);
    });
  });

  group('turnToJson', () {
    test('question con attribute: mismo orden de claves que la web', () {
      final q = AiQuestion(question: '¿Cuál es la marca?', options: const ['Samsung', 'LG', 'Otra opción'], allowOther: true, attribute: 'marca');
      expect(jsonEncode(turnToJson(q)),
          '{"type":"question","question":"¿Cuál es la marca?","options":["Samsung","LG","Otra opción"],"allowOther":true,"attribute":"marca"}');
      final sin = AiQuestion(question: 'q', options: const ['a'], allowOther: false);
      expect(turnToJson(sin).containsKey('attribute'), isFalse);
    });

    test('ready conserva attributes, meta y condition solo si vienen (round-trip)', () {
      final con = parseAiTurn({
        'type': 'ready',
        'title': 'T',
        'bullets': ['b'],
        'wholesale': true,
        'condition': 'usado',
        'attributes': {'marca': 'LG'},
        'meta': {'model': 'template', 'promptVersion': 'rubro:x@v2'},
      }) as AiReady;
      final json = turnToJson(con);
      expect(json['wholesale'], isTrue);
      expect(json['condition'], 'usado');
      expect(json['attributes'], {'marca': 'LG'});
      expect(json['meta'], {'model': 'template', 'promptVersion': 'rubro:x@v2'});
      final back = parseAiTurn(jsonDecode(jsonEncode(json)) as Map<String, dynamic>) as AiReady;
      expect(back.attributes, con.attributes);
      expect(back.meta, con.meta);
      expect(back.condition, 'usado');

      final sin = parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': ['b']}) as AiReady;
      expect(turnToJson(sin), {'type': 'ready', 'title': 'T', 'bullets': ['b']});
    });

    test('los otros turnos serializan como hoy (paridad con el _turnToJson viejo)', () {
      expect(turnToJson(const AiImageRequest(message: 'm', hint: 'h')), {'type': 'image_request', 'message': 'm', 'hint': 'h'});
      expect(turnToJson(const AiRouting(message: 'm', categories: ['c'], rubros: ['r'])), {'type': 'routing', 'message': 'm', 'categories': ['c'], 'rubros': ['r']});
      expect(turnToJson(const AiKindSwitch(message: 'm', suggestedKind: 'servicio', options: ['Sí', 'No'])), {'type': 'kind_switch', 'message': 'm', 'suggested_kind': 'servicio', 'options': ['Sí', 'No']});
    });
  });

  group('stepBack', () {
    test('desde la segunda pregunta vuelve a la primera y quita su respuesta', () {
      final out = stepBack([const AiMessage('user', 'busco tele'), q1, a1, q2]);
      expect(out.messages, [const AiMessage('user', 'busco tele'), q1]);
      expect((out.turn as AiQuestion).question, '¿Marca?');
    });
    test('desde routing vuelve a la última pregunta', () {
      final out = stepBack([const AiMessage('user', 'x'), q1, a1, q2, a2, routing]);
      expect(out.messages, [const AiMessage('user', 'x'), q1, a1, q2]);
      expect(out.turn, isA<AiQuestion>());
    });
    test('desde ready vuelve al routing (routing + ready seguidos se quitan juntos)', () {
      final out = stepBack([const AiMessage('user', 'x'), q1, a1, routing, ok, ready]);
      expect(out.messages, [const AiMessage('user', 'x'), q1, a1, routing]);
      expect(out.turn, isA<AiRouting>());
    });
    test('desde la primera pregunta vuelve al inicio: sin mensajes y sin turno', () {
      final out = stepBack([const AiMessage('user', 'busco tele'), q1]);
      expect(out.messages, isEmpty);
      expect(out.turn, isNull);
    });
    test('con historial vacío no hace nada', () {
      final out = stepBack(const []);
      expect(out.messages, isEmpty);
      expect(out.turn, isNull);
    });
    test('si el turno anterior no parsea, sigue retrocediendo hasta uno válido o el inicio', () {
      const bad = AiMessage('assistant', '{roto');
      final out = stepBack([const AiMessage('user', 'x'), bad, const AiMessage('user', 'Pregunta: ?\nRespuesta: y'), q2]);
      expect(out.messages, isEmpty);
      expect(out.turn, isNull);
    });
    test('no muta la lista que recibe', () {
      final orig = [const AiMessage('user', 'x'), q1, a1, q2];
      stepBack(orig);
      expect(orig.length, 4);
    });
  });

  group('keepsSecondPhoto', () {
    test('true solo mientras el mensaje de la segunda foto siga en el historial', () {
      final withPhoto = [const AiMessage('user', 'x'), q1, const AiMessage('user', secondPhotoMsg), q2];
      expect(keepsSecondPhoto(withPhoto), isTrue);
      expect(keepsSecondPhoto(stepBack(withPhoto).messages), isFalse);
      expect(keepsSecondPhoto(const []), isFalse);
      expect(secondPhotoMsg, 'Aquí tienes otra foto para más contexto.');
    });
  });

  group('answeredCount / answerTexts', () {
    final ks = AiMessage('assistant', jsonEncode({'type': 'kind_switch', 'message': '¿Es un servicio?', 'suggested_kind': 'servicio', 'options': ['Sí, cambiar', 'No']}));
    final img = AiMessage('assistant', jsonEncode({'type': 'image_request', 'message': 'Otra foto', 'hint': ''}));

    test('cuenta solo los user que responden a question o kind_switch', () {
      final msgs = [
        const AiMessage('user', 'busco tele'),
        q1, a1,
        ks, const AiMessage('user', 'Pregunta: ¿Es un servicio?\nRespuesta: No, sigo como producto.'),
        img, const AiMessage('user', 'Sigamos sin foto.'),
        q2, a2,
        routing, ok, ready,
      ];
      expect(answeredCount(msgs), 3);
      expect(answerTexts(msgs), ['Samsung', 'No, sigo como producto.', '1']);
    });
    test('un user suelto (sin turno delante) o tras un assistant roto no cuenta', () {
      expect(answeredCount([const AiMessage('user', 'x')]), 0);
      expect(answeredCount([const AiMessage('user', 'x'), const AiMessage('assistant', '{roto'), const AiMessage('user', 'y')]), 0);
    });
    test('answerTextOf quita el prefijo Pregunta/Respuesta y deja lo demás tal cual', () {
      expect(answerTextOf('Pregunta: ¿Marca?\nRespuesta:  Samsung '), 'Samsung');
      expect(answerTextOf('ok'), 'ok');
    });
    test('tras «Atrás» el contador baja solo', () {
      final msgs = [const AiMessage('user', 'x'), q1, a1, q2, a2, routing];
      expect(answeredCount(msgs), 2);
      expect(answeredCount(stepBack(msgs).messages), 1);
    });
  });

  group('formato de las respuestas (§6)', () {
    test('answerContent envuelve solo cuando el turno actual es question', () {
      final q = parseAssistantTurn(q1.content);
      expect(answerContent(q, 'Samsung'), 'Pregunta: ¿Marca?\nRespuesta: Samsung');
      expect(answerContent(null, 'busco tele'), 'busco tele');
      expect(answerContent(parseAssistantTurn(routing.content), 'ok'), 'ok');
      expect(answerContent(const AiImageRequest(message: 'm', hint: ''), 'Sigamos sin foto.'), 'Sigamos sin foto.');
    });
    test('kindSwitchNoContent usa el literal de la web (new.tsx L1950)', () {
      const k = AiKindSwitch(message: '¿Es un servicio?', suggestedKind: 'servicio', options: ['Sí', 'No']);
      expect(kindSwitchNoContent(k, 'producto'), 'Pregunta: ¿Es un servicio?\nRespuesta: No, sigo como producto.');
    });
  });
}
