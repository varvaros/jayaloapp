import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_question_options.dart';
import 'package:jayalo_app/domain/ai_turns.dart';
import 'package:jayalo_app/domain/request_transcript.dart';

const req = '11111111-1111-4111-8111-111111111111';

AiMessage q(String question, List<String> options) => AiMessage(
    'assistant',
    jsonEncode({
      'type': 'question',
      'question': question,
      'options': options,
      'allowOther': true,
    }));
AiMessage a(String question, String answer) =>
    AiMessage('user', 'Pregunta: $question\nRespuesta: $answer');
final routing = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'routing',
      'message': 'Voy a enviar tu solicitud a:',
      'categories': ['climatizacion'],
      'rubros': <String>[],
    }));
final ready = AiMessage(
    'assistant',
    jsonEncode({
      'type': 'ready',
      'title': 'Reparación de aire split',
      'bullets': ['Tipo: split', 'Síntoma: no enfría'],
    }));

void main() {
  test('normalizeLabel: trim, minúsculas, sin acentos', () {
    expect(normalizeLabel('  Sí '), 'si');
    expect(normalizeLabel('NGK'), 'ngk');
  });

  group('buildTranscript', () {
    test('cuenta las preguntas y las respuestas fuera de las opciones («Otra»)', () {
      final messages = [
        const AiMessage('user', 'Mi aire no enfría'),
        q('¿Es split o de ventana?', ['Split', 'Ventana']),
        a('¿Es split o de ventana?', 'Split'),
        q('¿Enciende normalmente?', ['Sí', 'No']),
        a('¿Enciende normalmente?', 'Enciende pero se apaga a los 5 minutos'),
        routing,
        const AiMessage('user', 'Perfecto, ahora dame la ficha final.'),
        ready,
      ];
      final row = buildTranscript(req, messages)!;
      expect(row['request_id'], req);
      expect(row['question_count'], 2);
      expect(row['other_count'], 1);
      // La conversación se guarda ENTERA y tal cual, incluido el turno ready.
      expect(row['messages'], messages.map((m) => m.toJson()).toList());
      expect(row['attributes'], <String, String>{});
      expect(row['model'], isNull);
      expect(row['prompt_version'], isNull);
      // Exactamente las 10 columnas del grant: una de más = 42501.
      expect(row.keys.toSet(), {
        'request_id', 'messages', 'attributes', 'question_count', 'other_count',
        'model', 'prompt_version', 'source', 'template_id', 'template_version',
      });
    });

    test('una conversación sin preguntas (foto clara → routing → ready) cuenta cero', () {
      final row = buildTranscript(req, [const AiMessage('user', 'Quiero cotización por esto.'), routing, ready])!;
      expect(row['question_count'], 0);
      expect(row['other_count'], 0);
    });

    test('la respuesta se compara con las opciones sin distinguir mayúsculas ni espacios', () {
      final row = buildTranscript(req, [
        const AiMessage('user', 'Busco bujías'),
        q('¿Qué marca?', ['NGK', 'Bosch', 'Otra marca', 'Cualquier marca / no tengo preferencia']),
        a('¿Qué marca?', '  ngk '),
        ready,
      ])!;
      expect(row['other_count'], 0);
    });

    test('tampoco distingue acentos: «si» cuenta como la opción «Sí», no como «Otra»', () {
      final row = buildTranscript(req, [
        const AiMessage('user', 'Mi aire no enfría'),
        q('¿Enciende normalmente?', ['Sí', 'No']),
        a('¿Enciende normalmente?', 'si'),
        ready,
      ])!;
      expect(row['other_count'], 0);
    });

    test('un turno assistant que no es JSON no rompe nada ni cuenta como pregunta', () {
      final row = buildTranscript(req, [
        const AiMessage('user', 'Hola'),
        const AiMessage('assistant', 'esto no es json {'),
        const AiMessage('user', 'Pregunta: ?\nRespuesta: lo que sea'),
        ready,
      ])!;
      expect(row['question_count'], 0);
      expect(row['other_count'], 0);
    });

    test('pasa atributos y meta cuando vienen', () {
      final row = buildTranscript(req, [const AiMessage('user', 'x'), ready],
          attributes: {'marca': 'Samsung'},
          model: 'gemini-3.1-flash-lite',
          promptVersion: '2026-09-02.1')!;
      expect(row['attributes'], {'marca': 'Samsung'});
      expect(row['model'], 'gemini-3.1-flash-lite');
      expect(row['prompt_version'], '2026-09-02.1');
    });

    test('devuelve null si no hay conversación que guardar', () {
      expect(buildTranscript(req, const []), isNull);
    });

    test('devuelve null si la conversación supera el tope de bytes (mejor sin fila que sin solicitud)', () {
      final big = 'x' * transcriptMaxBytes;
      expect(buildTranscript(req, [AiMessage('user', big), ready]), isNull);
    });

    test('por defecto la fila es source=ai sin plantilla', () {
      final row = buildTranscript(req, [const AiMessage('user', 'x'), ready])!;
      expect(row['source'], 'ai');
      expect(row['template_id'], isNull);
      expect(row['template_version'], isNull);
    });

    test('acepta source=template con id y versión, y source=fallback', () {
      final t = buildTranscript(req, [const AiMessage('user', 'x'), ready],
          source: 'template',
          templateId: '22222222-2222-4222-8222-222222222222',
          templateVersion: 3)!;
      expect(t['source'], 'template');
      expect(t['template_id'], '22222222-2222-4222-8222-222222222222');
      expect(t['template_version'], 3);
      final f = buildTranscript(req, [const AiMessage('user', 'x'), ready],
          source: 'fallback',
          templateId: '22222222-2222-4222-8222-222222222222',
          templateVersion: 3)!;
      expect(f['source'], 'fallback');
    });

    test('source=template SIN plantilla es un error de programación: se degrada a ai', () {
      final row = buildTranscript(req, [const AiMessage('user', 'x'), ready], source: 'template')!;
      expect(row['source'], 'ai');
      expect(row['template_id'], isNull);
      expect(row['template_version'], isNull);
    });
  });
}
