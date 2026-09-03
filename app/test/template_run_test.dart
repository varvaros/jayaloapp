import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/template_run.dart';

const marca = (
  key: 'marca',
  label: 'Marca',
  question: '¿Cuál es la marca?',
  options: ['Samsung', 'LG'],
);
const modelo = (
  key: 'modelo',
  label: 'Modelo',
  question: '¿Cuál es el modelo?',
  options: ['Split', 'Ventana'],
);

Map<String, dynamic> questionJson(TemplateQuestion q) => {
      'key': q.key,
      'label': q.label,
      'question': q.question,
      'options': q.options,
    };

Map<String, dynamic> validTemplateJson() => {
      'type': 'template',
      // Anotado <String, dynamic>: sin esto Dart infiere el tipo de valor del
      // literal como Object (no-nullable) por sus miembros (String/int/List),
      // y el test de 'rechaza version ... null' revienta al asignar null.
      'template': <String, dynamic>{
        'id': 'tpl-1',
        'version': 3,
        'scope': 'category:electronica/producto',
        'questions': [questionJson(marca), questionJson(modelo)],
      },
      'routing': {
        'categories': ['electronica'],
        'rubros': ['aires-acondicionados'],
      },
      'known_attributes': {'tipo': 'aire acondicionado'},
    };

AiTemplate makeTurn({Map<String, String>? known}) {
  final t = parseTemplateTurn(validTemplateJson())!;
  return AiTemplate(
    id: t.id,
    version: t.version,
    scope: t.scope,
    questions: t.questions,
    categories: t.categories,
    rubros: t.rubros,
    knownAttributes: known ?? t.knownAttributes,
  );
}

void expectQuestion(TemplateQuestion got, TemplateQuestion want) {
  expect(got.key, want.key);
  expect(got.label, want.label);
  expect(got.question, want.question);
  expect(got.options, want.options);
}

void main() {
  group('parseTemplateTurn', () {
    test('parsea un turno válido completo', () {
      final t = parseTemplateTurn(validTemplateJson())!;
      expect(t.id, 'tpl-1');
      expect(t.version, 3);
      expect(t.scope, 'category:electronica/producto');
      expect(t.questions.length, 2);
      expectQuestion(t.questions[0], marca);
      expectQuestion(t.questions[1], modelo);
      expect(t.categories, ['electronica']);
      expect(t.rubros, ['aires-acondicionados']);
      expect(t.knownAttributes, {'tipo': 'aire acondicionado'});
    });

    test("rechaza type distinto de 'template'", () {
      expect(parseTemplateTurn({...validTemplateJson(), 'type': 'question'}), isNull);
    });

    test('rechaza questions que no validan (key en mayúscula, options vacías es válido)', () {
      final bad = validTemplateJson();
      (bad['template'] as Map)['questions'] = [
        {'key': 'MAYUSCULA', 'label': 'x', 'question': 'x', 'options': <String>[]},
      ];
      expect(parseTemplateTurn(bad), isNull);
      final okEmpty = validTemplateJson();
      (okEmpty['template'] as Map)['questions'] = [
        {'key': 'color', 'label': 'x', 'question': 'x', 'options': <String>[]},
      ];
      expect(parseTemplateTurn(okEmpty), isNotNull);
    });

    test('rechaza version no entera, cero, o negativa; acepta 3.0 (JSON decodifica double)', () {
      for (final v in [1.5, 0, -1, '3', null]) {
        final bad = validTemplateJson();
        (bad['template'] as Map)['version'] = v;
        expect(parseTemplateTurn(bad), isNull, reason: 'version=$v');
      }
      final asDouble = validTemplateJson();
      (asDouble['template'] as Map)['version'] = 3.0;
      expect(parseTemplateTurn(asDouble)?.version, 3);
    });

    test('rechaza id/scope vacíos, questions vacías o más de 12, y basura', () {
      for (final mutate in <void Function(Map)>[
        (t) => t['id'] = '',
        (t) => t['scope'] = '',
        (t) => t['questions'] = <Object>[],
        (t) => t['questions'] = List.generate(13, (i) => {'key': 'k$i', 'label': 'l', 'question': 'q', 'options': <String>[]}),
        (t) => t['questions'] = 'no',
        (t) => t.remove('id'),
      ]) {
        final bad = validTemplateJson();
        mutate(bad['template'] as Map);
        expect(parseTemplateTurn(bad), isNull);
      }
      expect(parseTemplateTurn(null), isNull);
      expect(parseTemplateTurn('x'), isNull);
      expect(parseTemplateTurn({'type': 'template', 'template': 'x'}), isNull);
      expect(parseTemplateTurn({'type': 'template'}), isNull);
    });

    test('recorta label/question/options y rechaza los que se pasan de largo', () {
      final t = validTemplateJson();
      (t['template'] as Map)['questions'] = [
        {'key': 'marca', 'label': '  Marca ', 'question': ' ¿Marca? ', 'options': [' LG ']},
      ];
      final parsed = parseTemplateTurn(t)!;
      expect(parsed.questions[0].label, 'Marca');
      expect(parsed.questions[0].question, '¿Marca?');
      expect(parsed.questions[0].options, ['LG']);
      final long = validTemplateJson();
      (long['template'] as Map)['questions'] = [
        {'key': 'marca', 'label': 'x' * 61, 'question': 'q', 'options': <String>[]},
      ];
      expect(parseTemplateTurn(long), isNull);
      final nineOptions = validTemplateJson();
      (nineOptions['template'] as Map)['questions'] = [
        {'key': 'marca', 'label': 'l', 'question': 'q', 'options': List.filled(9, 'o')},
      ];
      expect(parseTemplateTurn(nineOptions), isNull);
    });

    test('routing y known_attributes ausentes degradan a vacío en vez de lanzar', () {
      final bad = validTemplateJson()
        ..remove('routing')
        ..remove('known_attributes');
      final t = parseTemplateTurn(bad)!;
      expect(t.categories, isEmpty);
      expect(t.rubros, isEmpty);
      expect(t.knownAttributes, isEmpty);
    });
  });

  group('parseAiTurn con template', () {
    test('un template válido llega como AiTemplate', () {
      expect(parseAiTurn(validTemplateJson()), isA<AiTemplate>());
    });
    test('un template malformado lanza TemplateFormatException (es un FormatException)', () {
      expect(() => parseAiTurn({'type': 'template', 'template': 'x'}), throwsA(isA<TemplateFormatException>()));
      expect(() => parseAiTurn({'type': 'template', 'template': 'x'}), throwsFormatException);
    });
    test('parseAssistantTurn con template devuelve el turno, nunca lanza', () {
      expect(parseAssistantTurn(jsonEncode(validTemplateJson())), isA<AiTemplate>());
      expect(parseAssistantTurn(jsonEncode({'type': 'template', 'template': 'x'})), isNull);
    });
    test('turnToJson(AiTemplate) es reversible', () {
      final t = parseTemplateTurn(validTemplateJson())!;
      final back = parseTemplateTurn(jsonDecode(jsonEncode(turnToJson(t))))!;
      expect(back.id, t.id);
      expect(back.version, t.version);
      expect(back.scope, t.scope);
      expect(back.questions.map((q) => q.key), ['marca', 'modelo']);
      expect(back.categories, t.categories);
      expect(back.knownAttributes, t.knownAttributes);
    });
  });

  group('pendingQuestions', () {
    test('salta las claves ya conocidas y ya respondidas, y conserva el orden de la plantilla', () {
      final withKnown = makeTurn(known: {'marca': 'Samsung'});
      expect(pendingQuestions(withKnown, {'modelo': 'Split'}), isEmpty);
      final empty = makeTurn(known: {});
      final p = pendingQuestions(empty, {});
      expect(p.map((q) => q.key), ['marca', 'modelo']);
    });
  });

  group('templateQuestionTurn', () {
    test('añade «Otra opción» al final y fija attribute al key de la pregunta', () {
      final q = templateQuestionTurn(marca);
      expect(q.question, '¿Cuál es la marca?');
      expect(q.options, ['Samsung', 'LG', otherOption]);
      expect(q.allowOther, isTrue);
      expect(q.attribute, 'marca');
      expect(otherOption, 'Otra opción');
    });
  });

  group('answerMsgs', () {
    test('produce el par exacto assistant/user del formato de la IA', () {
      final pair = answerMsgs(marca, 'Samsung');
      expect(pair, [
        const AiMessage('assistant',
            '{"type":"question","question":"¿Cuál es la marca?","options":["Samsung","LG","Otra opción"],"allowOther":true,"attribute":"marca"}'),
        const AiMessage('user', 'Pregunta: ¿Cuál es la marca?\nRespuesta: Samsung'),
      ]);
    });
  });

  group('appendTemplateAnswer', () {
    test('añade el par; si la pregunta ya es la cola (tras «Atrás»), solo el user', () {
      const first = AiMessage('user', 'busco un aire');
      final one = appendTemplateAnswer([first], marca, 'LG');
      expect(one.length, 3);
      final again = appendTemplateAnswer([first, one[1]], marca, 'Samsung');
      expect(again, [first, one[1], const AiMessage('user', 'Pregunta: ¿Cuál es la marca?\nRespuesta: Samsung')]);
    });
  });

  group('templateAnswersIn', () {
    test('lee los pares assistant(attribute)+user que quedan; una pregunta sin respuesta no cuenta', () {
      final t = makeTurn(known: {});
      const first = AiMessage('user', 'busco un aire');
      final msgs = [
        first,
        ...answerMsgs(marca, 'LG'),
        answerMsgs(modelo, 'Split')[0], // la pregunta de cola, sin responder
      ];
      expect(templateAnswersIn(msgs, t), {'marca': 'LG'});
      // «Atrás» desde el modelo (de cola) no solo la quita a ELLA: por el
      // algoritmo genérico de stepBack (ai_turns_back_test.dart, «vuelve a
      // la primera y quita su respuesta»), también quita la respuesta LG de
      // marca y deja a marca de cola sin responder — igual que retroceder
      // desde una SEGUNDA pregunta cualquiera. templateAnswersIn refleja eso:
      // ya no queda ninguna respuesta.
      expect(templateAnswersIn(stepBack(msgs).messages, t), isEmpty);
      expect(templateAnswersIn([first], t), isEmpty);
    });
    test('ignora claves que no son de la plantilla y respuestas sin envoltorio', () {
      final t = makeTurn(known: {});
      final ajena = AiMessage('assistant', jsonEncode(turnToJson(const AiQuestion(question: 'q', options: [], allowOther: true, attribute: 'color'))));
      expect(templateAnswersIn([ajena, const AiMessage('user', 'Pregunta: q\nRespuesta: rojo')], t), isEmpty);
    });
  });

  group('isOther', () {
    test('es insensible a mayúsculas y a espacios sobrantes', () {
      expect(isOther(marca, '  samsung  '), isFalse);
      expect(isOther(marca, 'SAMSUNG'), isFalse);
      expect(isOther(marca, 'Panasonic'), isTrue);
    });
    test("«Otra opción» misma siempre es 'otra', nunca calza con las opciones declaradas", () {
      expect(isOther(marca, otherOption), isTrue);
    });
  });

  group('buildTemplateReady', () {
    test('con tipo conocido: título de tipo + marca + modelo, bullets en orden de plantilla y meta.promptVersion', () {
      final r = buildTemplateReady(makeTurn(), {'marca': 'Samsung', 'modelo': 'Split'}, 'Aire acondicionado');
      expect(r.ready.title, 'aire acondicionado Samsung Split');
      expect(r.ready.bullets, ['Marca: Samsung', 'Modelo: Split', 'Tipo: aire acondicionado']);
      expect(r.ready.attributes, {'tipo': 'aire acondicionado', 'marca': 'Samsung', 'modelo': 'Split'});
      expect(r.ready.wholesale, isFalse);
      expect(r.ready.meta, (model: 'template', promptVersion: 'category:electronica/producto@v3'));
      expect(r.routing.message, 'Voy a enviar tu solicitud a:');
      expect(r.routing.categories, ['electronica']);
      expect(r.routing.rubros, ['aires-acondicionados']);
    });

    test('sin tipo conocido: el título sale del scopeLabel', () {
      final r = buildTemplateReady(makeTurn(known: {}), {'marca': 'LG'}, 'Aire acondicionado');
      expect(r.ready.title, 'Aire acondicionado LG');
    });

    test('bullets: conocidos sin pregunta propia van después, con la clave en Initcap', () {
      final r = buildTemplateReady(
          makeTurn(known: {'tipo': 'aire acondicionado', 'tipo_unidad': 'split'}),
          {'marca': 'Samsung'},
          'Aire acondicionado');
      expect(r.ready.bullets, ['Marca: Samsung', 'Tipo: aire acondicionado', 'Tipo Unidad: split']);
    });

    test('el título se recorta a 120 caracteres', () {
      final r = buildTemplateReady(makeTurn(known: {'tipo': 'x' * 100}), {'marca': 'y' * 50}, 'Aire acondicionado');
      expect(r.ready.title.length, 120);
      expect(r.ready.title, '${'x' * 100} ${'y' * 19}');
    });

    test('recorta espacios sobrantes de las respuestas antes de usarlas en título y bullets', () {
      final r = buildTemplateReady(makeTurn(known: {}), {'marca': '  Samsung ', 'modelo': 'Split'}, 'Aire acondicionado');
      expect(r.ready.title, 'Aire acondicionado Samsung Split');
      expect(r.ready.title.contains('  '), isFalse);
      expect(r.ready.bullets, ['Marca: Samsung', 'Modelo: Split']);
      expect(r.ready.attributes['marca'], 'Samsung');
    });

    test('una pregunta de la plantilla sin valor conocido ni respondido no genera bullet', () {
      final r = buildTemplateReady(makeTurn(known: {}), {'marca': 'Samsung'}, 'Aire acondicionado');
      expect(r.ready.bullets, ['Marca: Samsung']);
      expect(r.ready.bullets.any((b) => b.contains('null')), isFalse);
      expect(r.ready.bullets.any((b) => b.startsWith('Modelo')), isFalse);
    });

    test("si el título quedaría vacío (sin tipo ni marca/modelo, scopeLabel vacío), cae a 'Solicitud'", () {
      final r = buildTemplateReady(makeTurn(known: {}), {}, '');
      expect(r.ready.title, 'Solicitud');
    });

    test('el ready y el routing serializan con turnToJson (mismo JSON que un turno real)', () {
      final r = buildTemplateReady(makeTurn(), {'marca': 'LG'}, 'Aire');
      final json = turnToJson(r.ready);
      expect(json['meta'], {'model': 'template', 'promptVersion': 'category:electronica/producto@v3'});
      expect(json['attributes'], {'tipo': 'aire acondicionado', 'marca': 'LG'});
      expect(parseAssistantTurn(jsonEncode(turnToJson(r.routing))), isA<AiRouting>());
    });
  });
}
