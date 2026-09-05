import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_turns.dart';

void main() {
  test('question', () {
    final t = parseAiTurn(jsonDecode(
        '{"type":"question","question":"¿Qué medida?","options":["1/2\\"","3/4\\""],"allowOther":true}'));
    final q = t as AiQuestion;
    expect(q.question, '¿Qué medida?');
    expect(q.options, ['1/2"', '3/4"']);
    expect(q.allowOther, isTrue);
  });

  test('routing con rubros del servidor', () {
    final t = parseAiTurn(jsonDecode(
        '{"type":"routing","message":"Voy a enviar tu solicitud a:","categories":["plomeria"],"rubros":["a1b2","c3d4"]}'));
    final r = t as AiRouting;
    expect(r.categories, ['plomeria']);
    expect(r.rubros, ['a1b2', 'c3d4']);
  });

  test('ready con y sin wholesale', () {
    final r1 = parseAiTurn(jsonDecode(
            '{"type":"ready","title":"Llave de paso 1/2\\"","bullets":["Marca: cualquiera"]}'))
        as AiReady;
    expect(r1.wholesale, isFalse);
    final r2 = parseAiTurn(jsonDecode(
            '{"type":"ready","title":"Compra al por mayor: 500 camisetas","bullets":["Cantidad: 500"],"wholesale":true}'))
        as AiReady;
    expect(r2.wholesale, isTrue);
  });

  test('kind_switch e image_request', () {
    expect(
        parseAiTurn(jsonDecode(
            '{"type":"kind_switch","message":"Parece servicio","suggested_kind":"servicio","options":["Sí, cambiar a servicio","No"]}')),
        isA<AiKindSwitch>());
    expect(
        parseAiTurn(jsonDecode(
            '{"type":"image_request","message":"Necesito ver mejor","hint":"Foto del sifón"}')),
        isA<AiImageRequest>());
  });

  test('type desconocido lanza', () {
    expect(() => parseAiTurn({'type': 'sorpresa'}), throwsFormatException);
  });
  test('routing con readyNext valido lo trae parseado (F3)', () {
    final r = parseAiTurn({
      'type': 'routing',
      'message': 'Voy a enviar tu solicitud a:',
      'categories': ['hogar'],
      'rubros': ['uuid-1'],
      'readyNext': {
        'type': 'ready',
        'title': 'Ramo de rosas',
        'bullets': ['Empaque conico'],
        'wholesale': false,
      },
    }) as AiRouting;
    expect(r.readyNext, isNotNull);
    expect(r.readyNext!.title, 'Ramo de rosas');
    expect(r.readyNext!.bullets, ['Empaque conico']);
  });
  test('routing sin readyNext o con uno malformado degrada a null (F3)', () {
    final sin = parseAiTurn({
      'type': 'routing',
      'message': 'm',
      'categories': <String>[],
      'rubros': <String>[],
    }) as AiRouting;
    expect(sin.readyNext, isNull);
    final tipoMalo = parseAiTurn({
      'type': 'routing',
      'message': 'm',
      'categories': <String>[],
      'rubros': <String>[],
      'readyNext': {'type': 'question', 'question': 'q'},
    }) as AiRouting;
    expect(tipoMalo.readyNext, isNull);
    final basura = parseAiTurn({
      'type': 'routing',
      'message': 'm',
      'categories': <String>[],
      'rubros': <String>[],
      'readyNext': 'no soy un mapa',
    }) as AiRouting;
    expect(basura.readyNext, isNull);
  });
  test('ready parsea condition solo con valores validos (ADR web parity)', () {
    final con = parseAiTurn({
      'type': 'ready',
      'title': 'T',
      'bullets': ['b'],
      'condition': 'usado',
    }) as AiReady;
    expect(con.condition, 'usado');
    final sin = parseAiTurn({'type': 'ready', 'title': 'T', 'bullets': []}) as AiReady;
    expect(sin.condition, isNull);
    final invalido = parseAiTurn({
      'type': 'ready',
      'title': 'T',
      'bullets': [],
      'condition': 'roto',
    }) as AiReady;
    expect(invalido.condition, isNull);
  });

  group('ready manual (spec 2026-09-05): categorías y rubros en el ready', () {
    test('parsea categories/rubros y meta manual; sin ellos quedan vacíos', () {
      final t = parseAiTurn({
        'type': 'ready',
        'title': 'nevera samsung',
        'bullets': <String>[],
        'categories': ['hogar'],
        'rubros': ['11111111-1111-1111-1111-111111111111'],
        'meta': {'model': 'manual', 'promptVersion': '2026-09-03.1'},
      }) as AiReady;
      expect(t.categories, ['hogar']);
      expect(t.rubros, ['11111111-1111-1111-1111-111111111111']);
      expect(t.meta?.model, 'manual');
      final normal = parseAiTurn({'type': 'ready', 'title': 'x', 'bullets': <String>[]}) as AiReady;
      expect(normal.categories, isEmpty);
      expect(normal.rubros, isEmpty);
    });
    test('turnToJson conserva categories/rubros solo cuando hay', () {
      const conRubros = AiReady(
          title: 'x', bullets: [], wholesale: false, categories: ['hogar'], rubros: ['r1']);
      expect(turnToJson(conRubros)['categories'], ['hogar']);
      expect(turnToJson(conRubros)['rubros'], ['r1']);
      const sin = AiReady(title: 'x', bullets: [], wholesale: false);
      expect(turnToJson(sin).containsKey('categories'), isFalse);
      expect(turnToJson(sin).containsKey('rubros'), isFalse);
    });
  });
}
