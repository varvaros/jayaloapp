# App: «Atrás» + transcripción + modo plantilla — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el creador de solicitudes de la app Android tenga «Atrás» en cada turno (botón + gesto de Android, sin llamadas al servidor), guarde las respuestas en el formato de la web (`Pregunta: …\nRespuesta: …`), registre la conversación en `request_ai_transcripts` (fase 0) y ejecute el modo plantilla calcado de la web, dormido detrás del interruptor del servidor.

**Architecture:** Toda la lógica nueva es pura y vive en `app/lib/domain/` (`ai_turns.dart`, `request_transcript.dart`, `template_run.dart`) con tests portados 1:1 de `aiTurns.test.ts`, `requestTranscript.test.ts` y `templateRun.test.ts` de la web. La pantalla (`create_request_screen.dart`, 2578 líneas, NO montable en tests porque necesita Supabase vivo) solo cablea: estado ← `stepBack`/`answeredCount`, botón «Atrás», `_goBack`, modo plantilla local. El gesto ATRÁS pasa por un segundo gancho en `unsaved_guard.dart` que `BackGuard` consulta antes que el aviso de cambios sin guardar. Escrituras a `request_ai_transcripts` y `request_template_runs` son best-effort (`reportError`, nunca UI). Dos carriles sobre la misma rama `feat/atras-y-plantillas-app` (base `feat/fecha-pautada-app`): carril 1 = Tasks 1-5, carril 2 = Tasks 6-9.

**Tech Stack:** Flutter/Dart 3 (sdk ^3.12.2), supabase_flutter, http (+ `package:http/testing.dart` MockClient), flutter_test, go_router.

**Spec:** docs/superpowers/specs/2026-09-03-app-atras-y-plantillas-design.md (ya commiteada junto a este plan).

## Global Constraints

- Repo: `C:\Users\ac\Downloads\jayalo-app`. Antes de empezar: `git status` limpio, `git checkout feat/fecha-pautada-app && git checkout -b feat/atras-y-plantillas-app`. Todos los comandos `flutter` se lanzan desde `C:\Users\ac\Downloads\jayalo-app\app`.
- TDD estricto: test que falla → código → test que pasa. Tests con `flutter test test/<fichero>.dart` (uno) o `flutter test` (todos). `flutter analyze` sin avisos nuevos.
- Un commit por task, mensaje en español como el repo (`feat(app): …`, `fix(app): …`). NUNCA `git push`. NUNCA tocar la BD (ni MCP ni SQL): los grants ya están vivos y son la frontera.
- Formato de respuesta a `question`: `'Pregunta: ${q.question}\nRespuesta: $texto'`. «No» a `kind_switch`: `'Pregunta: ${k.message}\nRespuesta: No, sigo como $kind.'`.
- Literal de la segunda foto: `const secondPhotoMsg = 'Aquí tienes otra foto para más contexto.';` (hoy la app manda `'Aquí tienes una foto para más contexto.'`; el servidor adjunta `imageDataUrl2` al ÚLTIMO mensaje `user` sea cual sea su texto — `chat-stream.ts` L516-533 — así que el literal solo importa para `keepsSecondPhoto`).
- `request_template_runs` — INSERT EXACTAMENTE `id, user_id, template_id, template_version`; UPDATE solo con `outcome, fallback_key, answered_count, other_count, title_edited, request_id, ended_at` (+`user_id` en el grant, no se manda) filtrando `.eq('id', runId)`; `outcome` ∈ `published|fallback|abandoned`. Un campo de más = 42501 en la petición ENTERA.
- `request_ai_transcripts` — INSERT EXACTAMENTE `request_id, messages, attributes, question_count, other_count, model, prompt_version, source, template_id, template_version`. CHECK: `source ∈ ai|template|fallback` y `(source = 'ai') = (template_id IS NULL)`. `messages::text` ≤ 65 536 bytes (el cliente corta en 60 000).
- `useTemplates: true` viaja SOLO cuando `messages.length == 1` (primer turno y reinicio por `kind_switch`), y solo si el llamador lo pide; el servidor solo lo mira con `messages.length === 1` (`chat-stream.ts` L331).
- Best-effort: runs y transcripción nunca bloquean ni enseñan error; el fallo va a `reportError(Object error, StackTrace? stack)` de `app/lib/core/error_reporter.dart`.
- La pantalla no se monta en tests (Supabase singleton: ver `app/test/create_center_state_test.dart`, que prueba solo funciones de nivel de fichero). Lo de pantalla se certifica con el smoke del PO (lista en Task 5 y Task 9).
- APK: `flutter build apk --release` desde `app/`, instalar con `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Commitear ANTES de compilar (mina: worktree sucio = diseño que desaparece del APK; el sello de Ajustes → «Esta versión» avisa «sin commitear»).

## Contraste con el código (leído el 2026-09-03; manda el código donde la spec supone otra cosa)

1. `AiMessage` vive HOY en `app/lib/core/ai_client.dart`, no en el dominio. `stepBack`/`answeredCount` lo necesitan en `domain/ai_turns.dart` ⇒ se MUEVE al dominio y `ai_client.dart` lo re-exporta (`export '../domain/ai_turns.dart' show AiMessage;`) para no tocar los importadores.
2. `AiTurn` es `sealed`: Dart exige que sus subclases vivan en la MISMA biblioteca ⇒ `AiTemplate` (y `parseTemplateTurn`, `TemplateQuestion`) se declaran en `ai_turns.dart`, no en `template_run.dart` como dice la spec §8.2; `template_run.dart` los re-exporta para que el código y los tests importen `template_run.dart` como la spec pide.
3. La app NO usa un paquete `uuid`: `newRequestClientId()` en `app/lib/data/repos.dart` L501 genera un UUID v4 con `Random.secure()`. Se reutiliza para `runId`.
4. `reportError` existe: `Future<void> reportError(Object error, StackTrace? stack)` (`app/lib/core/error_reporter.dart` L35), con `debugOnReport` para tests. La pantalla no lo importa hoy; `repos.dart` sí.
5. Segunda foto hoy: `_pickForRequest` manda `'Cambié la foto, mira esta.'` (cupo lleno, reemplaza la última) o `'Aquí tienes una foto para más contexto.'`. La app permite DOS fotos en el compositor antes de empezar (la web solo una): «Atrás» solo suelta la 2ª foto si la puso el usuario DENTRO de la conversación (flag `_secondPhotoFromChat`), nunca una del compositor.
6. `kind_switch` «Sí, cambiar» HOY en la app NO reinicia el historial: cambia `_kind` y manda la opción como un mensaje más (`create_request_screen.dart` L1383-1394). La spec §6 dice «reinicia el historial con el primer mensaje, como hoy» (cierto en la web, no en la app) y §8.3 exige el reinicio para volver a mandar `useTemplates`. Se implementa el reinicio (paridad web) en la Task 3.
7. «No es esto» no existe en la app: la ficha tiene «Corregir algo» (`_correcting = true`, L2203-2210) y el texto que el usuario escribe es la corrección. En modo plantilla, esa corrección ES el handoff (§8.3); además se añade «No es esto» en la ficha, solo en modo plantilla, con el literal de la web.
8. `_hasUnsavedWork` descuenta la siembra (`_seedTitle`, `_seedPhotos`, pedido PO): se conserva y solo se quita `_answers.isNotEmpty` (la spec §5.2 da la fórmula simplificada; quitar la regla de la siembra sería quitar comportamiento no acordado).
9. El botón de la cabecera (`HeaderCircleButton` `arrow_back_ios_new`, L927-940) SALE de la pantalla con `confirmDiscard`: no cambia. Solo el gesto de Android deshace un paso (§5.3).
10. `submitRequest` trata el 23505 (reintento con el mismo `client_request_id`) como éxito silencioso: en ese camino no hay `id` ⇒ devuelve `null` y la transcripción se salta (no se hace un `select` por `client_request_id`: no está verificado su grant de columna y la memoria del proyecto manda mirar `column_privileges` antes de escribir un `.select()`).
11. Los tests existentes fijan el gesto ATRÁS con `await tester.binding.handlePopRoute()` (`app/test/product_detail_back_nav_test.dart` L69) y `roleStore.value = RoleState.consumer` de `core/session_state.dart`.
12. El auto-«ok» del routing en la app es el literal `'ok'` (web: `'Perfecto, ahora dame la ficha final.'`). El flujo de IA sigue con `'ok'`; el cierre LOCAL del modo plantilla copia el literal de la web, como `finishTemplate`.

---

## Task 1: `ai_turns.dart` — dominio rehidratable («Atrás» puro)

**Files**
- Modify: `app/lib/domain/ai_turns.dart` (reescritura completa, hoy 118 líneas)
- Modify: `app/lib/core/ai_client.dart` L1-11 (quitar `AiMessage`, re-exportar)
- Create: `app/test/ai_turns_back_test.dart`
- Copy: spec → `docs/superpowers/specs/2026-09-03-app-atras-y-plantillas-design.md`

**Interfaces**
- Consumes: nada nuevo (`dart:convert`).
- Produces (todo en `package:jayalo_app/domain/ai_turns.dart`):
  - `class AiMessage { const AiMessage(String role, String content); Map<String,String> toJson(); }` con `==`/`hashCode`.
  - `class AiQuestion extends AiTurn { …, final String? attribute; }`
  - `class AiReady extends AiTurn { …, final Map<String,String> attributes; final ({String model, String promptVersion})? meta; }`
  - `String? sanitizeAttributeKey(Object? raw)` · `Map<String,String> sanitizeAttributes(Object? raw)`
  - `AiTurn parseAiTurn(Map<String,dynamic> json)` (lanza `FormatException` si desconocido, como hoy)
  - `Map<String,dynamic> turnToJson(AiTurn t)`
  - `AiTurn? parseAssistantTurn(String content)` (nunca lanza)
  - `const String secondPhotoMsg` · `bool keepsSecondPhoto(List<AiMessage> messages)`
  - `typedef StepBack = ({List<AiMessage> messages, AiTurn? turn});` · `StepBack stepBack(List<AiMessage> messages)`
  - `String answerTextOf(String content)` · `List<String> answerTexts(List<AiMessage>)` · `int answeredCount(List<AiMessage>)`
  - `String answerContent(AiTurn? current, String text)` · `String kindSwitchNoContent(AiKindSwitch k, String kind)`

### Steps

- [ ] **1.1 Rama y spec.** YA HECHO por el controlador (worktree creado, spec y plan commiteados). Solo comprobar `git status` limpio y `git branch --show-current` = `feat/atras-y-plantillas-app`.

- [ ] **1.2 Test que falla.** Crear `app/test/ai_turns_back_test.dart`:

```dart
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
```

- [ ] **1.3 Correr:** `flutter test test/ai_turns_back_test.dart` → falla al compilar (`AiMessage` no está en `ai_turns.dart`, `stepBack` etc. no existen).

- [ ] **1.4 Implementar.** Reemplazar TODO `app/lib/domain/ai_turns.dart` por:

```dart
import 'dart:convert';

/// Turnos del endpoint IA `/api/ai/chat-stream` (que NO es streaming: cada
/// turno es un POST que devuelve UN objeto JSON). Contrato verificado en
/// jayalo-main: src/lib/ai/prompts.ts L30-82 + chat-stream.ts L438-500.
/// «Atrás», transcripción y plantillas: paridad con src/lib/aiTurns.ts.

/// Un mensaje del historial que viaja en `messages` (`role`: 'user' |
/// 'assistant'). Vive en el dominio (antes en core/ai_client.dart) porque
/// `stepBack`/`answeredCount` lo leen; `ai_client.dart` lo re-exporta para
/// que nadie tenga que cambiar sus imports. Compara por valor: «Atrás»
/// reconstruye listas y los tests las cotejan enteras.
class AiMessage {
  const AiMessage(this.role, this.content);
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};

  @override
  bool operator ==(Object other) =>
      other is AiMessage && other.role == role && other.content == content;
  @override
  int get hashCode => Object.hash(role, content);
  @override
  String toString() => 'AiMessage($role, $content)';
}

sealed class AiTurn {
  const AiTurn();
}

class AiQuestion extends AiTurn {
  const AiQuestion(
      {required this.question,
      required this.options,
      required this.allowOther,
      this.attribute});
  final String question;
  final List<String> options;
  final bool allowOther;

  /// Clave snake_case del atributo que produce la pregunta (prompt
  /// 2026-09-03.1; las preguntas de plantilla lo llevan siempre). null si el
  /// modelo no lo mandó o no era una clave válida.
  final String? attribute;
}

class AiImageRequest extends AiTurn {
  const AiImageRequest({required this.message, required this.hint});
  final String message;
  final String hint;
}

class AiRouting extends AiTurn {
  const AiRouting(
      {required this.message,
      required this.categories,
      required this.rubros,
      this.readyNext});
  final String message;
  final List<String> categories;
  final List<String> rubros; // UUIDs — los añade el servidor al post-procesar

  /// F3: el `ready` que el servidor adjunta al routing cuando se le pide
  /// (`wantReadyNext`), para ahorrarse el POST del auto-«ok» — que re-subía
  /// la(s) foto(s) en base64 enteras. null = servidor viejo o `readyNext`
  /// omitido (timeout/formato/oferta pura): se cae al auto-«ok» de siempre.
  final AiReady? readyNext;
}

class AiReady extends AiTurn {
  const AiReady(
      {required this.title,
      required this.bullets,
      required this.wholesale,
      this.condition,
      this.attributes = const {},
      this.meta});
  final String title;
  final List<String> bullets;
  final bool wholesale;

  /// 'nuevo' | 'usado' | 'ambos' si el usuario lo dijo espontáneamente en la
  /// conversación (paridad con `parseReadyCondition` de la web): permite
  /// saltar el paso Estado del formulario final. null = hay que preguntar.
  final String? condition;

  /// `{"marca": "Samsung", "tipo_unidad": "split"}` ya saneado (claves
  /// snake_case, valores recortados). `{}` si el servidor no lo mandó. Va a
  /// `request_ai_transcripts.attributes`.
  final Map<String, String> attributes;

  /// Modelo y versión del prompt que produjeron la ficha; null si el
  /// servidor no los mandó. Va a `model`/`prompt_version` de la transcripción.
  final ({String model, String promptVersion})? meta;
}

class AiKindSwitch extends AiTurn {
  const AiKindSwitch(
      {required this.message, required this.suggestedKind, required this.options});
  final String message;
  final String suggestedKind;
  final List<String> options;
}

List<String> _strs(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const [];

// ── Atributos (paridad con src/lib/ai/aiAttributes.ts) ─────────────────────

final _attrKeyRe = RegExp(r'^[a-z0-9_]{1,40}$');
const attributesMaxKeys = 20;
const attributeValueMaxChars = 120;

/// La regla de clave, en un solo sitio: `ready.attributes` y
/// `question.attribute` la comparten. null si no es una clave válida.
String? sanitizeAttributeKey(Object? raw) {
  if (raw is! String) return null;
  final key = raw.trim();
  return _attrKeyRe.hasMatch(key) ? key : null;
}

/// Claves inválidas, valores no-string o vacíos: fuera. Valores recortados a
/// 120 chars, como mucho 20 claves. NUNCA lanza: un atributo raro no puede
/// tumbar un turno.
Map<String, String> sanitizeAttributes(Object? raw) {
  final out = <String, String>{};
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    if (out.length >= attributesMaxKeys) break;
    final key = sanitizeAttributeKey(e.key);
    final v = e.value;
    if (key == null || v is! String) continue;
    var clean = v.trim();
    if (clean.length > attributeValueMaxChars) {
      clean = clean.substring(0, attributeValueMaxChars);
    }
    if (clean.isEmpty) continue;
    out[key] = clean;
  }
  return out;
}

({String model, String promptVersion})? _metaOf(dynamic v) {
  if (v is! Map) return null;
  final m = v['model'];
  final p = v['promptVersion'];
  return (m is String && p is String) ? (model: m, promptVersion: p) : null;
}

// ── Parseo ─────────────────────────────────────────────────────────────────

/// Parsea el `readyNext` adjunto a un routing. Cualquier malformación degrada
/// a null (= fallback al auto-«ok»), nunca rompe el turno que lo trae.
AiReady? _readyNextOf(dynamic v) {
  if (v is! Map<String, dynamic> || v['type'] != 'ready') return null;
  try {
    final turn = parseAiTurn(v);
    return turn is AiReady ? turn : null;
  } catch (_) {
    return null;
  }
}

AiTurn parseAiTurn(Map<String, dynamic> json) => switch (json['type']) {
      'question' => AiQuestion(
          question: json['question'] as String? ?? '',
          options: _strs(json['options']),
          allowOther: json['allowOther'] as bool? ?? true,
          attribute: sanitizeAttributeKey(json['attribute'])),
      'image_request' => AiImageRequest(
          message: json['message'] as String? ?? '',
          hint: json['hint'] as String? ?? ''),
      'routing' => AiRouting(
          message: json['message'] as String? ?? '',
          categories: _strs(json['categories']),
          rubros: _strs(json['rubros']),
          readyNext: _readyNextOf(json['readyNext'])),
      'ready' => AiReady(
          title: json['title'] as String? ?? '',
          bullets: _strs(json['bullets']),
          wholesale: json['wholesale'] == true,
          condition: switch (json['condition']) {
            'nuevo' || 'usado' || 'ambos' => json['condition'] as String,
            _ => null,
          },
          attributes: sanitizeAttributes(json['attributes']),
          meta: _metaOf(json['meta'])),
      'kind_switch' => AiKindSwitch(
          message: json['message'] as String? ?? '',
          suggestedKind: json['suggested_kind'] as String? ?? 'servicio',
          options: _strs(json['options'])),
      _ => throw FormatException('Turno IA desconocido: ${json['type']}'),
    };

/// El JSON que va al historial (`messages`) por cada turno de la IA. Antes era
/// `_turnToJson` privado de la pantalla; «Atrás» rehidrata desde aquí, así
/// que parse ↔ serialize tienen que ser inversos. `attributes`/`meta`/
/// `condition` solo si vienen; `readyNext` NO se guarda (como siempre: el
/// ready se añade como su propio turno).
Map<String, dynamic> turnToJson(AiTurn t) => switch (t) {
      AiQuestion q => {
          'type': 'question',
          'question': q.question,
          'options': q.options,
          'allowOther': q.allowOther,
          if (q.attribute case final a?) 'attribute': a,
        },
      AiImageRequest i => {
          'type': 'image_request',
          'message': i.message,
          'hint': i.hint,
        },
      AiRouting r => {
          'type': 'routing',
          'message': r.message,
          'categories': r.categories,
          'rubros': r.rubros,
        },
      AiReady r => {
          'type': 'ready',
          'title': r.title,
          'bullets': r.bullets,
          if (r.wholesale) 'wholesale': true,
          if (r.condition case final c?) 'condition': c,
          if (r.attributes.isNotEmpty) 'attributes': r.attributes,
          if (r.meta case final m?)
            'meta': {'model': m.model, 'promptVersion': m.promptVersion},
        },
      AiKindSwitch k => {
          'type': 'kind_switch',
          'message': k.message,
          'suggested_kind': k.suggestedKind,
          'options': k.options,
        },
    };

/// Un turno de la IA desde el `content` de un mensaje `assistant` del
/// historial. `null` si no es JSON, no es un objeto o no es un turno
/// conocido. NUNCA lanza (`parseAiTurn` sigue lanzando para el turno recién
/// recibido del servidor, que sí debe fallar ruidosamente).
AiTurn? parseAssistantTurn(String content) {
  try {
    final parsed = jsonDecode(content);
    if (parsed is! Map<String, dynamic>) return null;
    return parseAiTurn(parsed);
  } catch (_) {
    return null;
  }
}

// ── «Atrás» (paridad con stepBack de aiTurns.ts) ───────────────────────────

/// Mensaje con el que viaja la segunda foto (literal de la web,
/// `SECOND_PHOTO_MSG`). Mientras siga en el historial, la foto sigue.
const secondPhotoMsg = 'Aquí tienes otra foto para más contexto.';

/// «Atrás» puede deshacer el envío de la segunda foto: si el mensaje ya no
/// está, la foto tampoco debe estar.
bool keepsSecondPhoto(List<AiMessage> messages) =>
    messages.any((m) => m.role == 'user' && m.content == secondPhotoMsg);

typedef StepBack = ({List<AiMessage> messages, AiTurn? turn});

/// «Atrás»: quita el turno actual de la IA y la respuesta que lo provocó, y
/// rehidrata el turno anterior desde el historial. Cero llamadas: todo está
/// en `messages`. Si no queda ningún turno válido detrás, vuelve al inicio
/// (`messages: []`, `turn: null`), que en la pantalla es el compositor con
/// texto y foto intactos. No muta la lista que recibe.
StepBack stepBack(List<AiMessage> messages) {
  final msgs = List<AiMessage>.of(messages);
  // 1) el turno actual de la IA (puede haber más de uno seguido: routing +
  //    ready; se quitan todos)
  while (msgs.isNotEmpty && msgs.last.role == 'assistant') {
    msgs.removeLast();
  }
  // 2) la respuesta del usuario que lo provocó
  while (msgs.isNotEmpty && msgs.last.role == 'user') {
    msgs.removeLast();
  }
  // 3) el turno anterior; si no parsea, seguir hacia atrás
  while (msgs.isNotEmpty) {
    final last = msgs.last;
    if (last.role == 'assistant') {
      final turn = parseAssistantTurn(last.content);
      if (turn != null) return (messages: msgs, turn: turn);
      msgs.removeLast();
      while (msgs.isNotEmpty && msgs.last.role == 'user') {
        msgs.removeLast();
      }
    } else {
      msgs.removeLast();
    }
  }
  return (messages: <AiMessage>[], turn: null);
}

// ── Respuestas del usuario (§5.1 answeredCount, §6 formato) ────────────────

const _answerMarker = '\nRespuesta:';

/// Lo que el usuario contestó, sin el envoltorio `Pregunta: …\nRespuesta: `.
/// Un mensaje sin envoltorio (el 'ok' del routing, la foto) vuelve tal cual.
String answerTextOf(String content) {
  final i = content.indexOf(_answerMarker);
  if (!content.startsWith('Pregunta:') || i == -1) return content;
  return content.substring(i + _answerMarker.length).trim();
}

/// Los mensajes `user` que responden a un `question` o `kind_switch` (los
/// que van JUSTO después de uno de esos turnos), en orden. Es la fuente de
/// la tarjeta «Tu solicitud» y del contador «Pregunta N»: con «Atrás» un
/// contador incremental se desincroniza; esto se recalcula del historial.
List<String> answerTexts(List<AiMessage> messages) {
  final out = <String>[];
  var pending = false;
  for (final m in messages) {
    if (m.role == 'assistant') {
      final t = parseAssistantTurn(m.content);
      pending = t is AiQuestion || t is AiKindSwitch;
      continue;
    }
    if (pending) {
      out.add(answerTextOf(m.content));
      pending = false;
    }
  }
  return out;
}

int answeredCount(List<AiMessage> messages) => answerTexts(messages).length;

/// Lo que se guarda en el historial al contestar. A un `question` se le
/// responde con el formato de la web (`new.tsx` L781) — el constructor de
/// plantillas lo exige (`request_template_qa_pairs` lee `\nRespuesta:`). A
/// todo lo demás (primer mensaje, foto, 'ok', corrección) va el texto suelto.
String answerContent(AiTurn? current, String text) => switch (current) {
      AiQuestion q => 'Pregunta: ${q.question}\nRespuesta: $text',
      _ => text,
    };

/// «No» a un `kind_switch` (web `new.tsx` L1950).
String kindSwitchNoContent(AiKindSwitch k, String kind) =>
    'Pregunta: ${k.message}\nRespuesta: No, sigo como $kind.';
```

- [ ] **1.5 `ai_client.dart`:** quitar la clase `AiMessage` y re-exportarla. Old (L1-11):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_turns.dart';
import 'config.dart';

class AiMessage {
  const AiMessage(this.role, this.content); // role: 'user' | 'assistant'
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}
```

New:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_turns.dart';
import 'config.dart';

// `AiMessage` se mudó al dominio (stepBack/answeredCount lo leen). Se
// re-exporta para que quien importaba `core/ai_client.dart` por él siga
// compilando sin tocar un import.
export '../domain/ai_turns.dart' show AiMessage;
```

- [ ] **1.6 Correr:** `flutter test test/ai_turns_back_test.dart test/ai_turns_test.dart test/ai_client_test.dart` → verde. `flutter analyze` → 0 issues nuevos (el screen aún usa `_turnToJson` privado: compila, se cambia en Task 3).

- [ ] **1.7 Commit:** `git add -A && git commit -m "feat(app): ai_turns rehidratable — turnToJson al dominio, attributes/meta, parseAssistantTurn, stepBack, answeredCount"`.

---

## Task 2: gesto ATRÁS de Android — `takeBackStep` + `BackGuard`

**Files**
- Modify: `app/lib/core/unsaved_guard.dart` (añadir al final)
- Modify: `app/lib/features/shell/back_guard.dart` L22-30
- Create: `app/test/back_step_test.dart`

**Interfaces**
- Produces (`package:jayalo_app/core/unsaved_guard.dart`):
  - `void takeBackStep({required Object owner, required bool Function() step})`
  - `void releaseBackStep(Object owner)`
  - `bool tryBackStep()` — llama al `step` del TOPE; `true` = consumió el gesto; `false` si no hay nada registrado.
- `BackGuard._handleBack` llama `tryBackStep()` ANTES de `hasUnsavedChanges()`.
- La navbar (`home_shell.dart` L356) NO se toca: cambiar de pestaña no es «un paso atrás».

### Steps

- [ ] **2.1 Test que falla.** Crear `app/test/back_step_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';
import 'package:jayalo_app/features/shell/back_guard.dart';

/// Spec §5.3: el gesto ATRÁS de Android deshace UN paso dentro del creador de
/// solicitudes. `unsaved_guard.dart` gana un segundo gancho (pila por dueño,
/// como el de cambios sin guardar) y `BackGuard` lo consulta ANTES del aviso
/// de descarte. Los guards son singletons de módulo: cada test suelta lo suyo.
void main() {
  final owner = Object();
  tearDown(() {
    releaseBackStep(owner);
    releaseUnsavedGuard(owner);
  });

  group('tryBackStep', () {
    test('sin nada registrado no consume', () {
      expect(tryBackStep(), isFalse);
    });

    test('llama al paso registrado y devuelve lo que este diga', () {
      var llamadas = 0;
      takeBackStep(owner: owner, step: () {
        llamadas++;
        return true;
      });
      expect(tryBackStep(), isTrue);
      expect(llamadas, 1);
      takeBackStep(owner: owner, step: () => false);
      expect(tryBackStep(), isFalse);
    });

    test('soltar deja de consumir', () {
      takeBackStep(owner: owner, step: () => true);
      releaseBackStep(owner);
      expect(tryBackStep(), isFalse);
    });

    test('manda el TOPE; al morir la de arriba, la de abajo recupera el gesto', () {
      final abajo = Object();
      addTearDown(() => releaseBackStep(abajo));
      takeBackStep(owner: abajo, step: () => true);
      takeBackStep(owner: owner, step: () => false);
      expect(tryBackStep(), isFalse, reason: 'manda la de arriba');
      releaseBackStep(owner);
      expect(tryBackStep(), isTrue, reason: 'vuelve a mandar la de abajo');
    });

    test('re-registrar el mismo dueño lo actualiza EN SU SITIO', () {
      final abajo = Object();
      addTearDown(() => releaseBackStep(abajo));
      takeBackStep(owner: abajo, step: () => false);
      takeBackStep(owner: owner, step: () => true);
      takeBackStep(owner: abajo, step: () => false);
      expect(tryBackStep(), isTrue, reason: 'sigue mandando la de arriba');
    });

    test('soltar con OTRO dueño no toca el registro vigente', () {
      takeBackStep(owner: owner, step: () => true);
      releaseBackStep(Object());
      expect(tryBackStep(), isTrue);
    });
  });

  group('BackGuard', () {
    setUp(() => roleStore.value = RoleState.consumer);

    GoRouter router() => GoRouter(
          initialLocation: '/client',
          routes: [
            GoRoute(
                path: '/client',
                builder: (_, _) => const BackGuard(child: Text('home'))),
          ],
        );

    testWidgets('el paso registrado consume el gesto: ni diálogo ni salida',
        (tester) async {
      var pasos = 0;
      takeBackStep(owner: owner, step: () {
        pasos++;
        return true;
      });
      takeUnsavedGuard(owner: owner, check: () => true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pasos, 1);
      expect(find.text('¿Salir y descartar los cambios?'), findsNothing,
          reason: 'el paso va ANTES del aviso de cambios sin guardar');
      expect(find.text('¿Salir de Jayalo?'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('si el paso NO consume, sigue el flujo de hoy', (tester) async {
      takeBackStep(owner: owner, step: () => false);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // En el home, arriba del todo y sin cambios: confirmar salida de la app.
      expect(find.text('¿Salir de Jayalo?'), findsOneWidget);
    });

    testWidgets('sin consumir y con cambios sin guardar, pregunta si descartar',
        (tester) async {
      takeBackStep(owner: owner, step: () => false);
      takeUnsavedGuard(owner: owner, check: () => true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('¿Salir y descartar los cambios?'), findsOneWidget);
    });
  });
}
```

- [ ] **2.2 Correr:** `flutter test test/back_step_test.dart` → falla al compilar (`takeBackStep` no existe).

- [ ] **2.3 Implementar.** Añadir al FINAL de `app/lib/core/unsaved_guard.dart`:

```dart
// ── Segundo gancho: «un paso atrás» DENTRO de la pantalla (spec §5.3) ──────

class _BackStepEntry {
  _BackStepEntry(this.owner, this.step);
  final Object owner;
  final bool Function() step;
}

/// Misma disciplina que `_stack`: pila por dueño, manda el tope, quien
/// registra suelta en `dispose`. Vive aparte del guard de cambios sin
/// guardar porque responde a OTRA pregunta: no «¿se pierde algo?», sino
/// «¿hay algo que deshacer antes de salir?». El creador de solicitudes
/// registra aquí su «Atrás» de la conversación; BackGuard lo consulta
/// PRIMERO. La navbar (home_shell) no: cambiar de pestaña no es un paso.
final List<_BackStepEntry> _backSteps = [];

/// Registra el «paso atrás» de ESTA pantalla. `step` devuelve `true` si
/// consumió el gesto (deshizo algo) y `false` si no había nada que deshacer
/// — entonces BackGuard sigue con el flujo de siempre. Re-registrar el mismo
/// `owner` lo actualiza en su sitio (no le roba el turno a la de arriba).
void takeBackStep({required Object owner, required bool Function() step}) {
  final entry = _BackStepEntry(owner, step);
  final i = _backSteps.indexWhere((e) => identical(e.owner, owner));
  if (i == -1) {
    _backSteps.add(entry);
  } else {
    _backSteps[i] = entry;
  }
}

/// Quita el registro de `owner`. Inofensivo si no está. Quien registra DEBE
/// soltar en `dispose`, o una pantalla muerta se comería el atrás de la
/// siguiente para siempre.
void releaseBackStep(Object owner) {
  _backSteps.removeWhere((e) => identical(e.owner, owner));
}

/// `true` si la pantalla del tope consumió el gesto. `false` si no hay nada
/// registrado o el tope dijo que no tenía nada que deshacer.
bool tryBackStep() =>
    _backSteps.isEmpty ? false : _backSteps.last.step();
```

- [ ] **2.4 `BackGuard`.** En `app/lib/features/shell/back_guard.dart`, old (L22-29):

```dart
  Future<void> _handleBack(BuildContext context) async {
    // Antes de cualquier navegacion: si la pantalla actual tiene trabajo sin
    // guardar, se pregunta. Vale para las cinco BackAction — la de irse a otra
    // pantalla y la de salir de la app.
    if (hasUnsavedChanges()) {
```

New:

```dart
  Future<void> _handleBack(BuildContext context) async {
    // Primero: ¿la pantalla tiene un paso que deshacer? El creador de
    // solicitudes registra su «Atrás» de la conversación (spec §5.3): si lo
    // consume, el gesto termina aquí — ni diálogo ni navegación.
    if (tryBackStep()) return;
    // Antes de cualquier navegacion: si la pantalla actual tiene trabajo sin
    // guardar, se pregunta. Vale para las cinco BackAction — la de irse a otra
    // pantalla y la de salir de la app.
    if (hasUnsavedChanges()) {
```

- [ ] **2.5 Correr:** `flutter test test/back_step_test.dart test/unsaved_guard_test.dart test/product_detail_back_nav_test.dart test/root_nav_push_repro_test.dart` → verde.

- [ ] **2.6 Commit:** `git add -A && git commit -m "feat(app): gesto ATRÁS con paso deshacible — takeBackStep/tryBackStep y BackGuard lo consulta primero"`.


---

## Task 3: pantalla — «Atrás», formato de respuestas, contadores del historial

**Files**
- Modify: `app/lib/features/client/create_request_screen.dart` — estado L188-232, `_hasUnsavedWork` L259-266, `initState`/`dispose` L301-329, `_send` L366-449, `_pickForRequest` L516-523, `_handleTurn` L629-630, `_turnToJson` L708-739 (se borra), `_startSend` L1239-1260, `_questionArea` L1352-1417, `_buildingCard` L1490-1492/1522/1584, `_finalForm` acciones L2193-2211.

**Interfaces**
- Consumes: `turnToJson`, `parseAssistantTurn`, `stepBack`, `keepsSecondPhoto`, `secondPhotoMsg`, `answeredCount`, `answerTexts`, `answerContent`, `kindSwitchNoContent` (Task 1); `takeBackStep`/`releaseBackStep` (Task 2).
- Produces (privados del State): `Future<void> _send(String text, {bool force = false, bool raw = false})`, `Future<bool> _ask()`, `Future<void> _restartWithKind(String kind)`, `void _goBack()`, `AiRouting? _lastRouting(List<AiMessage> msgs)`, `Widget _backButton()`.
- Sin test de widget: la pantalla exige Supabase vivo (`supa` = `Supabase.instance.client` en `repos.dart` L19, `_ai` HTTP real). Se certifica con `flutter analyze` + el smoke de la Task 5. Toda la lógica que sí se puede probar ya quedó probada en Task 1/2.

### Steps

- [ ] **3.1 Estado.** Old (L191-193):

```dart
  final List<_PendingPhoto> _photos = [];
  final List<String> _answers = [];
  AiTurn? _current;
```

New:

```dart
  final List<_PendingPhoto> _photos = [];
  AiTurn? _current;
```

Old (L231-232):

```dart
  String? _catalogError;
  int _aiAnswered = 0;
```

New:

```dart
  String? _catalogError;

  /// La 2ª foto la puso el usuario DENTRO de la conversación (respondiendo a
  /// un `image_request`), no en el compositor. Solo esa se va con «Atrás»
  /// cuando su mensaje (`secondPhotoMsg`) deja de estar en el historial; las
  /// del compositor nunca pasaron por el historial y se quedan (§5.2: la 1ª
  /// foto NUNCA se suelta; la app admite dos en el compositor, la web una).
  bool _secondPhotoFromChat = false;

  /// Lo que el usuario escribió en el compositor al arrancar. `_send` vacía
  /// `_input`; «Atrás» hasta el inicio lo devuelve al campo (§5.2).
  String _composerText = '';
```

- [ ] **3.2 `_hasUnsavedWork`.** Old (L259-266):

```dart
  bool _hasUnsavedWork() {
    if (_submitted) return false;
    return _kind.isNotEmpty ||
        _messages.isNotEmpty ||
        _answers.isNotEmpty ||
        _photos.length > _seedPhotos ||
        _input.text.trim() != _seedTitle.trim();
  }
```

New:

```dart
  bool _hasUnsavedWork() {
    if (_submitted) return false;
    // Las respuestas viven en `_messages` (ver `answerTexts`): no hay lista
    // aparte que pueda desincronizarse con «Atrás».
    return _kind.isNotEmpty ||
        _messages.isNotEmpty ||
        _photos.length > _seedPhotos ||
        _input.text.trim() != _seedTitle.trim();
  }
```

- [ ] **3.3 `initState` / `dispose`.** Old (L306-313):

```dart
    takeUnsavedGuard(
      owner: this,
      check: _hasUnsavedWork,
      message: 'Perderás lo que escribiste en esta solicitud.',
    );
    if (widget.seedFrom != null) {
```

New:

```dart
    takeUnsavedGuard(
      owner: this,
      check: _hasUnsavedWork,
      message: 'Perderás lo que escribiste en esta solicitud.',
    );
    // El gesto ATRÁS de Android deshace UN paso de la conversación (spec
    // §5.3) y BackGuard lo consulta antes que el aviso de descarte. En el
    // compositor (sin historial) o mientras la IA piensa no consume: se sale
    // como siempre. La flecha del header NO pasa por aquí: esa sale.
    takeBackStep(
      owner: this,
      step: () {
        if (_messages.isEmpty || _busy) return false;
        _goBack();
        return true;
      },
    );
    if (widget.seedFrom != null) {
```

Old (L319-320):

```dart
    releaseCenterAction(_centerCamera);
    releaseUnsavedGuard(this);
```

New:

```dart
    releaseCenterAction(_centerCamera);
    releaseUnsavedGuard(this);
    releaseBackStep(this);
```

- [ ] **3.4 `_send` → `_send` + `_ask` + `_restartWithKind` + `_goBack`.** Old (L366-449, el bloque entero desde el doc-comment de `force` hasta el cierre de `_send`):

```dart
  /// `force` es SOLO para las continuaciones internas (el auto-"ok" del
  /// routing): se disparan dentro del `try` del envío anterior, cuando `_busy`
  /// aún es true — sin force, el guard se las tragaba en silencio y el flujo
  /// quedaba muerto esperando al usuario (bug pre-existente que el chat viejo
  /// disimulaba y la vista guiada destapó).
  Future<void> _send(String text, {bool force = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Solo cuentan como "respuesta" de la solicitud las contestaciones a una
    // pregunta real de la IA (no el auto-"ok" del routing, ni la foto, ni las
    // correcciones tras el ready).
    final record =
        !_correcting && (_current is AiQuestion || _current is AiKindSwitch);
    // Mismo pulso que el chat entre personas: acá el usuario también le está
    // MANDANDO algo a alguien (la IA que arma la solicitud).
    JayaloHaptics.sent();
    // El estado del botón central lo decide `_syncCenter` desde `build` (la
    // cámara deja de mandar en cuanto arranca la conversación, PO 2026-08-20).
    // No se pierde nada: el único punto del flujo donde hace falta otra foto es
    // el turno `image_request`, y ese trae sus propios botones dentro del
    // contenido («Tomar otra foto» / «Seguir sin foto»).
    setState(() {
      _busy = true;
      _showOther = false;
      _messages.add(AiMessage('user', text));
      if (record) {
        _answers.add(text);
        _aiAnswered++;
      }
      _input.clear();
    });
    try {
      // El JWT de la sesión exime el Turnstile del primer turno (ADR-0032);
      // el WebView del CAPTCHA se quitó: se pintaba negro en MIUI y colgaba
      // el flujo completo de crear solicitud.
      final turn = await _ai.sendTurn(
        messages: _messages,
        kind: _kind,
        wholesale: _wholesale,
        accessToken: supa.auth.currentSession?.accessToken,
        imageDataUrl: _photos.isNotEmpty ? _photos[0].dataUrl : null,
        imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null,
      );
      _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(turn))));
      // `sendTurn` tarda 2-8 s en datos móviles y el usuario puede cerrar el
      // compositor mientras tanto. Sin este guard, `_handleTurn` y los dos
      // `catch` de abajo llamaban `setState` sobre un State ya desmontado
      // ("setState() called after dispose()"): el turno se perdía y el error
      // ensuciaba el tracking. El `finally` ya lo hacía bien; estas ramas no.
      if (!mounted) return;
      // La correccion se da por consumida SOLO cuando el turno llego. Si la
      // IA falla, `_correcting` sigue en true y el usuario vuelve a ver el
      // campo de corregir con su formulario intacto detras, en vez de
      // quedarse en una pantalla sin nada que tocar.
      setState(() => _correcting = false);
      await _handleTurn(turn);
    } on AiHttpException catch (e) {
      if (!mounted) return;
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      setState(() {
        _messages.removeLast();
        if (record) {
          _answers.removeLast();
          _aiAnswered--;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        if (record) {
          _answers.removeLast();
          _aiAnswered--;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

New:

```dart
  /// `force` es SOLO para las continuaciones internas (el auto-"ok" del
  /// routing): se disparan dentro del `try` del envío anterior, cuando `_busy`
  /// aún es true — sin force, el guard se las tragaba en silencio y el flujo
  /// quedaba muerto esperando al usuario (bug pre-existente que el chat viejo
  /// disimulaba y la vista guiada destapó).
  ///
  /// `raw` manda `text` tal cual. Sin `raw`, la respuesta a un `question` se
  /// guarda como `Pregunta: …\nRespuesta: …` (spec §6, paridad web): el
  /// constructor de plantillas lee ese formato. La corrección tras la ficha
  /// (`_correcting`) y todo lo que no responde a un `question` van sueltos.
  Future<void> _send(String text, {bool force = false, bool raw = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Mismo pulso que el chat entre personas: acá el usuario también le está
    // MANDANDO algo a alguien (la IA que arma la solicitud).
    JayaloHaptics.sent();
    final content =
        raw ? text : answerContent(_correcting ? null : _current, text);
    // El estado del botón central lo decide `_syncCenter` desde `build` (la
    // cámara deja de mandar en cuanto arranca la conversación, PO 2026-08-20).
    // No se pierde nada: el único punto del flujo donde hace falta otra foto es
    // el turno `image_request`, y ese trae sus propios botones dentro del
    // contenido («Tomar otra foto» / «Seguir sin foto»).
    setState(() {
      _busy = true;
      _showOther = false;
      _messages.add(AiMessage('user', content));
      _input.clear();
    });
    final ok = await _ask();
    // El mensaje que provocó el fallo se quita: el usuario reintenta desde el
    // mismo punto. Las respuestas ya no se cuentan aparte (`answerTexts` lee
    // el historial), así que no hay contador que revertir.
    if (!ok && mounted) {
      setState(() {
        _messages.removeLast();
      });
    }
  }

  /// Manda el historial TAL CUAL está y trata el turno que vuelve. `true` si
  /// llegó un turno (o la pantalla murió mientras tanto); `false` si falló,
  /// ya con su toast. Quien añadió un mensaje antes de llamar decide qué
  /// hacer con él (`_send` lo quita; `_restartWithKind` restaura el anterior).
  Future<bool> _ask() async {
    setState(() => _busy = true);
    try {
      // El JWT de la sesión exime el Turnstile del primer turno (ADR-0032);
      // el WebView del CAPTCHA se quitó: se pintaba negro en MIUI y colgaba
      // el flujo completo de crear solicitud.
      final turn = await _ai.sendTurn(
        messages: _messages,
        kind: _kind,
        wholesale: _wholesale,
        accessToken: supa.auth.currentSession?.accessToken,
        imageDataUrl: _photos.isNotEmpty ? _photos[0].dataUrl : null,
        imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null,
      );
      _messages.add(AiMessage('assistant', jsonEncode(turnToJson(turn))));
      // `sendTurn` tarda 2-8 s en datos móviles y el usuario puede cerrar el
      // compositor mientras tanto. Sin este guard, `_handleTurn` y los dos
      // `catch` de abajo llamaban `setState` sobre un State ya desmontado
      // ("setState() called after dispose()"): el turno se perdía y el error
      // ensuciaba el tracking. El `finally` ya lo hacía bien; estas ramas no.
      if (!mounted) return true;
      // La correccion se da por consumida SOLO cuando el turno llego. Si la
      // IA falla, `_correcting` sigue en true y el usuario vuelve a ver el
      // campo de corregir con su formulario intacto detras, en vez de
      // quedarse en una pantalla sin nada que tocar.
      setState(() => _correcting = false);
      await _handleTurn(turn);
      return true;
    } on AiHttpException catch (e) {
      if (!mounted) return false;
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      _toast('Algo falló. Intenta de nuevo.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «Sí, cambiar» de un `kind_switch`: como la web (`new.tsx` L1860-1900),
  /// se cambia el tipo y la conversación ARRANCA DE NUEVO con solo el primer
  /// mensaje. Antes la app mandaba la opción como un mensaje más sobre el
  /// historial viejo; con el tipo cambiado, ese historial ya no vale — y el
  /// reinicio es lo que permite volver a pedir plantillas (Task 8).
  Future<void> _restartWithKind(String kind) async {
    if (_busy || _messages.isEmpty) return;
    final previous = List<AiMessage>.of(_messages);
    final previousCurrent = _current;
    final first = _messages.first;
    JayaloHaptics.sent();
    setState(() {
      _kind = kind;
      _messages
        ..clear()
        ..add(first);
      _current = null;
      _ready = null;
      _categories = [];
      _rubros = [];
      _showOther = false;
      _pop++;
    });
    final ok = await _ask();
    if (!ok && mounted) {
      // Si el reinicio falla, se vuelve a donde estaba (con el kind ya
      // cambiado: eso lo pidió el usuario y no depende del servidor).
      setState(() {
        _messages
          ..clear()
          ..addAll(previous);
        _current = previousCurrent;
      });
    }
  }

  /// «Atrás» de la conversación (spec §5.2): deshace el último paso desde el
  /// historial, SIN llamar al servidor. Lo disparan el botón y el gesto ATRÁS
  /// de Android (`takeBackStep` en `initState`). Si no queda turno detrás se
  /// vuelve al compositor con el texto y las fotos del compositor intactos.
  void _goBack() {
    if (_busy || _messages.isEmpty) return;
    final r = stepBack(_messages);
    final routing = _lastRouting(r.messages);
    final categories = List<String>.of(routing?.categories ?? const []);
    // El catálogo de rubros es de las categorías CARGADAS; si «Atrás» cambia
    // las categorías, el catálogo y la selección ya no corresponden.
    final catalogStale = categories.join(',') != _categories.join(',');
    setState(() {
      _showOther = false;
      _correcting = false;
      if (r.turn == null) _input.text = _composerText;
      _messages
        ..clear()
        ..addAll(r.messages);
      _current = r.turn;
      _ready = switch (r.turn) {
        AiReady rd => rd,
        _ => null,
      };
      _categories = categories;
      _rubros = List<String>.of(routing?.rubros ?? const []);
      if (catalogStale) {
        _catalogRubros = [];
        _selectedRubros = {};
      }
      // Si «Atrás» deshizo el envío de la segunda foto, la foto misma se va:
      // si no, «Seguir sin foto» en el siguiente `image_request` la mandaría
      // igual (repro del PO en la web). Solo la que entró por el chat.
      if (_secondPhotoFromChat &&
          !keepsSecondPhoto(_messages) &&
          _photos.length > 1) {
        _photos.removeLast();
        _secondPhotoFromChat = false;
      }
      _pop++;
    });
    if (catalogStale && _categories.isNotEmpty) unawaited(_loadRubroCatalog());
  }

  /// El último `routing` que queda en el historial (o null): de ahí salen las
  /// categorías/rubros tras un «Atrás».
  AiRouting? _lastRouting(List<AiMessage> msgs) {
    for (final m in msgs.reversed) {
      if (m.role != 'assistant') continue;
      if (parseAssistantTurn(m.content) case AiRouting r) return r;
    }
    return null;
  }

  /// Botón «Atrás» de la conversación: texto + `arrow_back`, mismo estilo que
  /// «Otra respuesta…» (TextButton centrado). Apagado mientras la IA piensa.
  Widget _backButton() => Center(
        child: TextButton.icon(
          onPressed: _busy ? null : _goBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Atrás'),
        ),
      );
```

- [ ] **3.5 `_pickForRequest`.** Old (L516-523):

```dart
  Future<void> _pickForRequest(ImageSource source) async {
    final replacing = _photos.length >= _maxRequestPhotos;
    if (await _pickPhoto(source, replaceLast: replacing)) {
      await _send(replacing
          ? 'Cambié la foto, mira esta.'
          : 'Aquí tienes una foto para más contexto.');
    }
  }
```

New:

```dart
  Future<void> _pickForRequest(ImageSource source) async {
    final replacing = _photos.length >= _maxRequestPhotos;
    if (await _pickPhoto(source, replaceLast: replacing)) {
      // La 2ª foto viaja con el literal de la web (`secondPhotoMsg`): «Atrás»
      // sabe que sigue en juego mientras ese mensaje siga en el historial
      // (`keepsSecondPhoto`). El servidor adjunta `imageDataUrl2` al ÚLTIMO
      // mensaje `user` sea cual sea su texto (chat-stream.ts L516-533), así
      // que el reemplazo de la 2ª también va con este literal.
      final isSecond = _photos.length == _maxRequestPhotos;
      if (isSecond) _secondPhotoFromChat = true;
      await _send(
        isSecond ? secondPhotoMsg : 'Aquí tienes una foto para más contexto.',
        raw: true,
      );
    }
  }
```

- [ ] **3.6 `_handleTurn` (F3).** Old (L629-630):

```dart
          _messages.add(const AiMessage('user', 'ok'));
          _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(rn))));
```

New:

```dart
          _messages.add(const AiMessage('user', 'ok'));
          _messages.add(AiMessage('assistant', jsonEncode(turnToJson(rn))));
```

Y en el comentario justo encima (L627) cambiar «mismo `_turnToJson`» por «mismo `turnToJson`».

- [ ] **3.7 Borrar `_turnToJson`.** Old (L708-739), se ELIMINA entero:

```dart
  Map<String, dynamic> _turnToJson(AiTurn t) => switch (t) {
    AiQuestion q => {
      'type': 'question',
      'question': q.question,
      'options': q.options,
      'allowOther': q.allowOther,
    },
    AiImageRequest i => {
      'type': 'image_request',
      'message': i.message,
      'hint': i.hint,
    },
    AiRouting r => {
      'type': 'routing',
      'message': r.message,
      'categories': r.categories,
      'rubros': r.rubros,
    },
    AiReady r => {
      'type': 'ready',
      'title': r.title,
      'bullets': r.bullets,
      if (r.wholesale) 'wholesale': true,
    },
    AiKindSwitch k => {
      'type': 'kind_switch',
      'message': k.message,
      'suggested_kind': k.suggestedKind,
      'options': k.options,
    },
  };
```

- [ ] **3.8 `_startSend` guarda el texto del compositor.** Old (L1239-1260):

```dart
  void _startSend(String text) {
    if (_kind.isEmpty) {
      _toast('Elige Producto, Servicio o Al por mayor para continuar.');
      return;
    }
```

New:

```dart
  void _startSend(String text) {
    if (_kind.isEmpty) {
      _toast('Elige Producto, Servicio o Al por mayor para continuar.');
      return;
    }
    // «Atrás» hasta el inicio devuelve esto al campo (spec §5.2).
    _composerText = text.trim();
```

- [ ] **3.9 `_questionArea`: contador, «Atrás», kind_switch.** Old (L1352-1417, el `switch (_current)` completo dentro del `else`):

```dart
      switch (_current) {
        case AiQuestion q:
          question = q.question;
          counter = 'Pregunta ${_aiAnswered + 1}';
          // Si la IA ya ofreció un catch-all ("Otros", "Otra marca"), ese botón
          // ES el disparador del campo de texto: enviarlo tal cual mandaba
          // "Otros" al proveedor como si fuera la respuesta (bug PO
          // 2026-07-28). Paridad con la web (requests/new.tsx + isCatchAllOption).
          final hasCatchAll = q.options.any(isCatchAllOption);
          actions = [
            for (final op in q.options)
              if (isCatchAllOption(op))
                _optionButton(op, () => setState(() => _showOther = true),
                    icon: Icons.edit_outlined)
              else
                _optionButton(op, () => _send(op)),
            // El campo de texto vive escondido: esto lo revela solo cuando
            // ninguna opción sirve (feedback PO: "se ve todo el tiempo
            // enviar mensaje cuando solo se está dando clic"). Con un
            // catch-all a la vista el enlace sobraría (igual que en la web).
            if (q.allowOther &&
                q.options.isNotEmpty &&
                !hasCatchAll &&
                !_showOther)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showOther = true),
                  child: const Text('Otra respuesta…'),
                ),
              ),
          ];
        case AiKindSwitch k:
          question = k.message;
          actions = [
            for (final op in k.options)
              _optionButton(op, () {
                final low = op.toLowerCase();
                if (low.startsWith('sí') || low.startsWith('si')) {
                  setState(() => _kind = k.suggestedKind);
                }
                _send(op);
              }),
          ];
        case AiImageRequest ir:
          question = ir.hint.isEmpty ? ir.message : '${ir.message}\n${ir.hint}';
          // El cargador se ofrece SIEMPRE: con el cupo lleno la nueva foto
          // reemplaza a la última (ver `_pickForRequest`). Antes desaparecía
          // y la foto equivocada quedaba clavada.
          actions = [
            _optionButton(
              _photos.length >= _maxRequestPhotos
                  ? 'Tomar otra foto'
                  : 'Tomar foto',
              icon: Icons.photo_camera_outlined,
              () => _pickForRequest(ImageSource.camera),
            ),
            _optionButton(
              'Elegir de la galería',
              icon: Icons.photo_library_outlined,
              () => _pickForRequest(ImageSource.gallery),
            ),
            _optionButton('Seguir sin foto', () => _send('Sigamos sin foto.')),
          ];
        default:
          return const SizedBox.shrink();
      }
```

New:

```dart
      switch (_current) {
        case AiQuestion q:
          question = q.question;
          // Del historial, no de un contador: «Atrás» lo baja solo.
          counter = 'Pregunta ${answeredCount(_messages) + 1}';
          // Si la IA ya ofreció un catch-all ("Otros", "Otra marca"), ese botón
          // ES el disparador del campo de texto: enviarlo tal cual mandaba
          // "Otros" al proveedor como si fuera la respuesta (bug PO
          // 2026-07-28). Paridad con la web (requests/new.tsx + isCatchAllOption).
          final hasCatchAll = q.options.any(isCatchAllOption);
          actions = [
            for (final op in q.options)
              if (isCatchAllOption(op))
                _optionButton(op, () => setState(() => _showOther = true),
                    icon: Icons.edit_outlined)
              else
                _optionButton(op, () => _send(op)),
            // El campo de texto vive escondido: esto lo revela solo cuando
            // ninguna opción sirve (feedback PO: "se ve todo el tiempo
            // enviar mensaje cuando solo se está dando clic"). Con un
            // catch-all a la vista el enlace sobraría (igual que en la web).
            if (q.allowOther &&
                q.options.isNotEmpty &&
                !hasCatchAll &&
                !_showOther)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showOther = true),
                  child: const Text('Otra respuesta…'),
                ),
              ),
            _backButton(),
          ];
        case AiKindSwitch k:
          question = k.message;
          actions = [
            for (final op in k.options)
              _optionButton(op, () {
                final low = op.toLowerCase();
                if (low.startsWith('sí') || low.startsWith('si')) {
                  // Reinicio con el tipo nuevo (paridad web).
                  _restartWithKind(k.suggestedKind);
                } else {
                  // «No»: formato de la web (new.tsx L1950), sigue el hilo.
                  _send(kindSwitchNoContent(k, _kind), raw: true);
                }
              }),
            _backButton(),
          ];
        case AiImageRequest ir:
          question = ir.hint.isEmpty ? ir.message : '${ir.message}\n${ir.hint}';
          // El cargador se ofrece SIEMPRE: con el cupo lleno la nueva foto
          // reemplaza a la última (ver `_pickForRequest`). Antes desaparecía
          // y la foto equivocada quedaba clavada.
          actions = [
            _optionButton(
              _photos.length >= _maxRequestPhotos
                  ? 'Tomar otra foto'
                  : 'Tomar foto',
              icon: Icons.photo_camera_outlined,
              () => _pickForRequest(ImageSource.camera),
            ),
            _optionButton(
              'Elegir de la galería',
              icon: Icons.photo_library_outlined,
              () => _pickForRequest(ImageSource.gallery),
            ),
            _optionButton('Seguir sin foto', () => _send('Sigamos sin foto.')),
            _backButton(),
          ];
        case AiRouting r:
          // Solo se ve si el auto-«ok» falló (si no, el routing dura lo que
          // tarda el POST siguiente). Antes aquí no había NADA que tocar;
          // «Atrás» es la salida de ese callejón: se vuelve a la pregunta
          // anterior y se reintenta desde ahí.
          question = r.message;
          actions = [_backButton()];
        default:
          return const SizedBox.shrink();
      }
```

- [ ] **3.10 `_buildingCard`.** Old (L1490-1492):

```dart
  Widget _buildingCard(ColorScheme cs) {
    final total = estimatedTotal(answered: _aiAnswered, wholesale: _wholesale);
    final frac = (_aiAnswered / total).clamp(0.0, .96);
```

New:

```dart
  Widget _buildingCard(ColorScheme cs) {
    final answers = answerTexts(_messages);
    final answered = answers.length;
    final total = estimatedTotal(answered: answered, wholesale: _wholesale);
    final frac = (answered / total).clamp(0.0, .96);
```

Old (L1522):

```dart
                '$_aiAnswered de ~$total',
```

New:

```dart
                '$answered de ~$total',
```

Old (L1584):

```dart
          for (final a in _answers)
```

New:

```dart
          for (final a in answers)
```

- [ ] **3.11 «Atrás» en la ficha.** Old (L2193-2211, la fila de acciones de `_finalForm`):

```dart
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const JayaloSpinner(size: 16, color: Colors.white)
                  : const Text('Enviar solicitud'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _correcting = true;
                    }),
              child: const Text('Corregir algo'),
            ),
          ],
        ),
```

New (`Wrap` en vez de `Row`: tres botones no caben en 360 dp; nada se quita):

```dart
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const JayaloSpinner(size: 16, color: Colors.white)
                  : const Text('Enviar solicitud'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _correcting = true;
                    }),
              child: const Text('Corregir algo'),
            ),
            // «Atrás» desde la ficha (spec §5.2): vuelve al routing/última
            // pregunta sin llamar al servidor. Oculto mientras `_correcting`
            // porque entonces no se pinta la ficha, sino `_questionArea`.
            TextButton.icon(
              onPressed: _busy ? null : _goBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Atrás'),
            ),
          ],
        ),
```

- [ ] **3.12 Verificar:** `flutter analyze` (0 issues: ya no debe quedar ninguna referencia a `_answers`, `_aiAnswered`, `_turnToJson` — comprobar con `grep -n "_answers\|_aiAnswered\|_turnToJson" app/lib/features/client/create_request_screen.dart` → vacío) y `flutter test` (todo verde).

- [ ] **3.13 Commit:** `git add -A && git commit -m "feat(app): «Atrás» en el creador de solicitudes — botón + gesto Android, respuestas en formato Pregunta/Respuesta, contadores desde el historial"`.

**Smoke manual (se ejecuta en Task 5 con el APK):** pregunta 2 → «Atrás» → vuelve la pregunta 1 con su contador «Pregunta 1» y la tarjeta sin la respuesta 1; gesto Android ×N → compositor con el texto y las fotos del compositor; ficha → «Atrás» → routing/última pregunta; `image_request` → 2ª foto → siguiente pregunta → «Atrás» → la 2ª foto desaparece de la tarjeta; `kind_switch` «Sí» → reinicia con el tipo nuevo; «No» → sigue; «Corregir algo» → no hay «Atrás» hasta «Volver al formulario»; mientras «Pensando…» el gesto Android NO deshace (sale con el aviso de siempre si se insiste).

---

## Task 4: transcripción (fase 0) — `buildTranscript` + `submitRequest` devuelve el id + insert best-effort

**Files**
- Create: `app/lib/domain/request_transcript.dart`
- Modify: `app/lib/domain/ai_question_options.dart` (exponer el normalizador, L14-40)
- Modify: `app/lib/data/repos.dart` `submitRequest` L518 (firma) y L588-641 (insert + return)
- Modify: `app/lib/features/client/create_request_screen.dart` imports L11-37, `_submit` L838-886, nuevo `_saveTranscript`
- Create: `app/test/request_transcript_test.dart`

**Interfaces**
- Produces:
  - `String normalizeLabel(String s)` en `ai_question_options.dart` (trim + lower + sin acentos; el mismo `_norm` de `isCatchAllOption`).
  - `const int transcriptMaxBytes = 60000;`
  - `Map<String, dynamic>? buildTranscript(String requestId, List<AiMessage> messages, {Map<String, String> attributes = const {}, String? model, String? promptVersion, String source = 'ai', String? templateId, int? templateVersion})` — claves EXACTAS del grant: `request_id, messages, attributes, question_count, other_count, model, prompt_version, source, template_id, template_version`.
  - `Future<String?> submitRequest({...misma firma...})` — el `id` de la fila; `null` en el reintento 23505.
  - `Future<void> _saveTranscript(String requestId)` (privado del State).

### Steps

- [ ] **4.1 Test que falla.** Crear `app/test/request_transcript_test.dart` (port de `requestTranscript.test.ts`, 10 casos):

```dart
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
```

- [ ] **4.2 Correr:** `flutter test test/request_transcript_test.dart` → falla al compilar.

- [ ] **4.3 `ai_question_options.dart`:** añadir justo después de la función `_norm` (tras su `}` de cierre, antes de `final _catchAll = …`):

```dart
/// La misma normalización, pública: la transcripción (`buildTranscript`)
/// compara respuestas con opciones con esta regla y nadie más debe
/// reinventarla. Trim + minúsculas + vocales sin acento + ñ→n.
String normalizeLabel(String s) => _norm(s);
```

- [ ] **4.4 Crear `app/lib/domain/request_transcript.dart`:**

```dart
import 'dart:convert';
import 'ai_question_options.dart';
import 'ai_turns.dart';

/// Fase 0 del «registro de patrones» (paridad con la web,
/// src/lib/requestTranscript.ts): la conversación con la IA que produjo una
/// solicitud se guarda TAL CUAL en `request_ai_transcripts` (migración
/// `20260902185204` + `20260902222240`). Hoy nadie la lee; es la materia
/// prima del constructor nocturno de plantillas. Sin este registro, las
/// solicitudes de la app no alimentaban la biblioteca de patrones.
///
/// Los contadores se precalculan aquí para que el informe no parsee jsonb:
/// `question_count` = turnos `question` de la IA; `other_count` = respuestas
/// del usuario que NO eran una de las opciones ofrecidas («Otra»).

/// Por debajo del CHECK de la BD (65 536 sobre `messages::text`, que Postgres
/// renderiza con espacios y por tanto más largo que `jsonEncode`). El
/// servidor ya acota la conversación a 40 mensajes × 8 000 chars; una real
/// pesa 2-8 KB. Si aun así se pasa, mejor sin registro que sin solicitud.
const transcriptMaxBytes = 60000;

const _answerMarker = '\nRespuesta:';

/// La fila para `supa.from('request_ai_transcripts').insert(row)`, con
/// EXACTAMENTE las 10 columnas del grant de INSERT — una de más tumba la
/// petición entera con 42501. `null` si no hay conversación o si pesa de más.
/// `source` distinto de `'ai'` sin `templateId` se degrada a `'ai'`: el CHECK
/// `(source = 'ai') = (template_id IS NULL)` lo exige.
Map<String, dynamic>? buildTranscript(
  String requestId,
  List<AiMessage> messages, {
  Map<String, String> attributes = const {},
  String? model,
  String? promptVersion,
  String source = 'ai',
  String? templateId,
  int? templateVersion,
}) {
  if (messages.isEmpty) return null;

  var questionCount = 0;
  var otherCount = 0;
  // Opciones de la última pregunta de la IA, a la espera de la respuesta.
  List<String>? pendingOptions;

  for (final m in messages) {
    if (m.role == 'assistant') {
      final turn = parseAssistantTurn(m.content);
      if (turn is AiQuestion) {
        questionCount++;
        pendingOptions = turn.options;
      } else {
        pendingOptions = null;
      }
      continue;
    }
    if (pendingOptions != null) {
      final i = m.content.indexOf(_answerMarker);
      if (i != -1 && pendingOptions.isNotEmpty) {
        final answer =
            normalizeLabel(m.content.substring(i + _answerMarker.length));
        if (!pendingOptions.any((o) => normalizeLabel(o) == answer)) {
          otherCount++;
        }
      }
      pendingOptions = null;
    }
  }

  final encoded = messages.map((m) => m.toJson()).toList();
  if (utf8.encode(jsonEncode(encoded)).length > transcriptMaxBytes) return null;

  final withTemplate = source != 'ai' && templateId != null;
  return {
    'request_id': requestId,
    'messages': encoded,
    'attributes': attributes,
    'question_count': questionCount,
    'other_count': otherCount,
    'model': model,
    'prompt_version': promptVersion,
    'source': withTemplate ? source : 'ai',
    'template_id': withTemplate ? templateId : null,
    'template_version': withTemplate ? templateVersion : null,
  };
}
```

- [ ] **4.5 Correr:** `flutter test test/request_transcript_test.dart test/ai_question_options_test.dart` → verde.

- [ ] **4.6 `submitRequest` devuelve el id.** En `app/lib/data/repos.dart`, old (L518):

```dart
Future<void> submitRequest({
```

New:

```dart
/// Devuelve el `id` de la fila creada (la política «Requests: select» del
/// dueño permite el `.select('id')` del insert), o `null` en el reintento
/// 23505 — ahí la solicitud ya existe pero no se vuelve a leer. El id lo usa
/// la transcripción (fase 0, best-effort); sin id no hay transcripción.
Future<String?> submitRequest({
```

Old (L588-589):

```dart
  try {
    await supa.from('customer_requests').insert({
```

New:

```dart
  String? id;
  try {
    final row = await supa.from('customer_requests').insert({
```

Old (L634-641):

```dart
      'target_business_id': null,
    });
  } on PostgrestException catch (e) {
    // 23505 = choque con `uq_customer_requests_client_idempotency`: el primer
    // intento SÍ creó la solicitud y su ack de red se perdió; este es el
    // reintento con el MISMO token. Idempotente: no es error — la solicitud ya
    // existe, así que se trata como éxito (no se re-inserta, no se re-dispara el
    // fan-out de notificaciones a proveedores).
    if (e.code != '23505') rethrow;
  }
  AppCaches.invalidateRequestLists();
  requestsChanged.value++;
}
```

New:

```dart
      'target_business_id': null,
    }).select('id').single();
    id = row['id'] as String?;
  } on PostgrestException catch (e) {
    // 23505 = choque con `uq_customer_requests_client_idempotency`: el primer
    // intento SÍ creó la solicitud y su ack de red se perdió; este es el
    // reintento con el MISMO token. Idempotente: no es error — la solicitud ya
    // existe, así que se trata como éxito (no se re-inserta, no se re-dispara el
    // fan-out de notificaciones a proveedores). Sin id: no se hace un select
    // por `client_request_id` (grant de columna no verificado; la memoria del
    // proyecto manda mirar `column_privileges` antes de un `.select()`).
    if (e.code != '23505') rethrow;
  }
  AppCaches.invalidateRequestLists();
  requestsChanged.value++;
  return id;
}
```

- [ ] **4.7 Pantalla: imports.** Old (L15-16):

```dart
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
```

New:

```dart
import '../../core/error_reporter.dart';
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
```

Old (L27-28):

```dart
import '../../domain/request_progress.dart';
import '../../domain/request_seed.dart';
```

New:

```dart
import '../../domain/request_progress.dart';
import '../../domain/request_seed.dart';
import '../../domain/request_transcript.dart';
```

- [ ] **4.8 Pantalla: `_submit` guarda la transcripción tras publicar.** Old (L838):

```dart
      await submitRequest(
```

New:

```dart
      final requestId = await submitRequest(
```

Old (L878-886):

```dart
      if (!mounted) return;
      // El botón central pasa a «Publicada» apagado en el `build` siguiente
      // (`_syncCenter`): soltarlo aquí devolvía el ＋ encendido del shell, que
      // en esta ruta no navega a ningún sitio.
      //
      // Publicada: nada que perder — que ninguna salida pregunte.
      releaseUnsavedGuard(this);
      setState(() => _submitted = true);
    } catch (e) {
```

New:

```dart
      if (!mounted) return;
      // El botón central pasa a «Publicada» apagado en el `build` siguiente
      // (`_syncCenter`): soltarlo aquí devolvía el ＋ encendido del shell, que
      // en esta ruta no navega a ningún sitio.
      //
      // Publicada: nada que perder — que ninguna salida pregunte.
      releaseUnsavedGuard(this);
      setState(() => _submitted = true);
      // Fase 0 del registro de patrones (spec §7): DESPUÉS del «Publicada»,
      // fire-and-forget. Nunca bloquea ni enseña error.
      if (requestId != null) unawaited(_saveTranscript(requestId));
    } catch (e) {
```

Añadir el método justo antes de `void _toast(String m) {` (L903):

```dart
  /// Guarda la conversación en `request_ai_transcripts` (fase 0, spec §7).
  /// Best-effort: un fallo va a `reportError`, jamás a la UI — la solicitud
  /// ya está publicada. `model`/`prompt_version` salen de `AiReady.meta`
  /// (null si el servidor no los mandó); `attributes` de `AiReady.attributes`.
  Future<void> _saveTranscript(String requestId) async {
    final rd = _ready;
    final row = buildTranscript(
      requestId,
      List<AiMessage>.of(_messages),
      attributes: rd?.attributes ?? const {},
      model: rd?.meta?.model,
      promptVersion: rd?.meta?.promptVersion,
    );
    if (row == null) return;
    try {
      await supa.from('request_ai_transcripts').insert(row);
    } catch (e, s) {
      unawaited(reportError(e, s));
    }
  }
```

- [ ] **4.9 Verificar:** `flutter analyze` (0 issues) y `flutter test` (verde). `grep -rn "submitRequest(" app/lib` → solo la pantalla la llama (si hubiera otro llamador, el `Future<String?>` sigue siendo compatible con un `await` que ignora el valor).

- [ ] **4.10 Commit:** `git add -A && git commit -m "feat(app): transcripción de la conversación (fase 0) — buildTranscript, submitRequest devuelve el id, insert best-effort tras publicar"`.

---

## Task 5: carril 1 — versión `1.0.4+101`, checkpoint y APK

**Files**
- Modify: `app/pubspec.yaml` L24 (`version: 1.0.4+100` → `version: 1.0.4+101`)

### Steps

- [ ] **5.1 Versión.** Old (`app/pubspec.yaml` L24):

```yaml
version: 1.0.4+100
```

New:

```yaml
version: 1.0.4+101
```

- [ ] **5.2 Checkpoint de calidad** (desde `app/`): `flutter analyze` → «No issues found!»; `flutter test` → todo verde (incluidos `ai_turns_test`, `ai_turns_back_test`, `ai_client_test`, `back_step_test`, `unsaved_guard_test`, `request_transcript_test`, `create_center_state_test`, `sello_build_test`, `version_publica_test`).

- [ ] **5.3 Commit ANTES de compilar:** `git add -A && git commit -m "chore(app): version 1.0.4+101 — «Atrás», formato de respuestas y transcripción (carril 1)"`. `git status` limpio (el sello de build lo calcula Gradle desde el árbol: sucio = «sin commitear» en Ajustes → «Esta versión»).

- [ ] **5.4 APK** (desde `app/`): `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`. Instalar: `adb install -r build/app/outputs/flutter-apk/app-release.apk` (conserva la sesión). Comprobar en Ajustes → «Esta versión» (5 toques): `Jayalo v1.0.4 (101)` y el sello `feat/atras-y-plantillas-app · <sha>` sin «sin commitear». (Si se quiere el build ofuscado de Play: `./scripts/build-release-apk.ps1` — no hace falta para el smoke.)

- [ ] **5.5 Smoke del carril 1 (PO, teléfono real):**
  - Producto + texto → pregunta 1 → contestar → pregunta 2 → **«Atrás»** → vuelve pregunta 1, contador «Pregunta 1», tarjeta «Tu solicitud» sin la respuesta.
  - Gesto ATRÁS de Android ×N → compositor con el texto y la foto del compositor; una vez en el compositor, el gesto vuelve a preguntar «¿Salir y descartar…?».
  - Con la IA pensando, el gesto NO deshace.
  - `image_request` → tomar 2ª foto → siguiente turno → «Atrás» → la 2ª foto desaparece de la tarjeta; la 1ª sigue.
  - Ficha → «Atrás» → routing o última pregunta; «Corregir algo» → sin «Atrás» hasta «Volver al formulario».
  - `kind_switch` (escribir un servicio con Producto elegido): «Sí, cambiar» reinicia con el tipo nuevo; «No» sigue.
  - Publicar → en Supabase (lo mira el PO/agente con acceso, NO este plan) fila en `request_ai_transcripts` con `messages` que contienen `Pregunta:/Respuesta:` y `attributes` no vacío si el prompt los mandó; `source='ai'`.

---

## Task 6: `template_run.dart` — lógica pura del modo plantilla (+ `AiTemplate` en `ai_turns.dart`)

**Files**
- Modify: `app/lib/domain/ai_turns.dart` — añadir `TemplateQuestion`, `AiTemplate`, `TemplateFormatException`, `parseTemplateTurn`; caso `'template'` en `parseAiTurn`; caso `AiTemplate` en `turnToJson`.
- Create: `app/lib/domain/template_run.dart`
- Modify: `app/lib/features/client/create_request_screen.dart` `_handleTurn` (caso `AiTemplate` para que el `switch` sobre el sealed siga siendo exhaustivo; el comportamiento llega en Task 8).
- Create: `app/test/template_run_test.dart`

**Interfaces**
- Produces en `ai_turns.dart` (re-exportado por `template_run.dart`):
  - `typedef TemplateQuestion = ({String key, String label, String question, List<String> options});`
  - `class AiTemplate extends AiTurn { final String id; final int version; final String scope; final List<TemplateQuestion> questions; final List<String> categories; final List<String> rubros; final Map<String,String> knownAttributes; }`
  - `class TemplateFormatException extends FormatException` (la lanza `parseAiTurn` cuando `type == 'template'` y `parseTemplateTurn` devuelve null).
  - `AiTemplate? parseTemplateTurn(Object? json)` — nunca lanza.
- Produces en `template_run.dart`:
  - `const otherOption = 'Otra opción';`
  - `List<TemplateQuestion> pendingQuestions(AiTemplate t, Map<String,String> answers)`
  - `AiQuestion templateQuestionTurn(TemplateQuestion q)`
  - `bool isOther(TemplateQuestion q, String answer)`
  - `List<AiMessage> answerMsgs(TemplateQuestion q, String answer)`
  - `List<AiMessage> appendTemplateAnswer(List<AiMessage> msgs, TemplateQuestion q, String answer)`
  - `Map<String,String> templateAnswersIn(List<AiMessage> messages, AiTemplate t)` — respuestas que quedan en el historial tras un «Atrás» (§8.3).
  - `({AiReady ready, AiRouting routing}) buildTemplateReady(AiTemplate t, Map<String,String> answers, String scopeLabel)`

### Steps

- [ ] **6.1 Test que falla.** Crear `app/test/template_run_test.dart` (port de `templateRun.test.ts` + los casos propios: `parseAiTurn` con `template`, `appendTemplateAnswer`, `templateAnswersIn`):

```dart
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
      'template': {
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
      expect(templateAnswersIn(stepBack(msgs).messages, t), {'marca': 'LG'});
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
```

- [ ] **6.2 Correr:** `flutter test test/template_run_test.dart` → falla al compilar (`template_run.dart` no existe).

- [ ] **6.3 `ai_turns.dart`: `AiTemplate` (sealed ⇒ misma biblioteca).** Insertar después de la clase `AiKindSwitch` (antes de `List<String> _strs(...)`):

```dart
/// Una pregunta de plantilla (`request_templates.questions[i]`), validada
/// como `TemplateQuestionSchema` de la web: key `^[a-z0-9_]{1,40}$`, label
/// 1-60, question 1-200, options ≤ 8 de 1-80 chars (todo recortado).
typedef TemplateQuestion = ({
  String key,
  String label,
  String question,
  List<String> options,
});

/// Turno `template` (spec §8.1): la respuesta del servidor al PRIMER mensaje
/// cuando hay una plantilla activa para el ámbito y `useTemplates: true`.
/// A partir de ahí todo corre LOCAL (`domain/template_run.dart`). Vive aquí
/// y no en template_run.dart porque `AiTurn` es sealed: Dart exige que sus
/// subclases estén en la misma biblioteca. Nunca se guarda en `messages`.
class AiTemplate extends AiTurn {
  const AiTemplate({
    required this.id,
    required this.version,
    required this.scope,
    required this.questions,
    required this.categories,
    required this.rubros,
    required this.knownAttributes,
  });
  final String id;
  final int version;
  final String scope;
  final List<TemplateQuestion> questions;
  final List<String> categories;
  final List<String> rubros;
  final Map<String, String> knownAttributes;
}

/// `parseAiTurn` la lanza cuando el servidor manda `type: 'template'` con una
/// forma inesperada. Es un `FormatException` (la pantalla lo trata como un
/// turno de IA fallido: toast + reintento) pero distinguible: a la segunda
/// vez la pantalla deja de pedir plantillas en esa conversación (§8.1).
class TemplateFormatException extends FormatException {
  const TemplateFormatException() : super('Turno template malformado');
}
```

Insertar después de `_metaOf` (antes de la sección `// ── Parseo`):

```dart
// ── Turno template (paridad con parseTemplateTurn de templateRun.ts) ───────

final _templateKeyRe = RegExp(r'^[a-z0-9_]{1,40}$');

List<String> _strsOnly(dynamic v) =>
    v is List ? v.whereType<String>().toList() : const [];

TemplateQuestion? _templateQuestionOf(dynamic v) {
  if (v is! Map) return null;
  final key = v['key'];
  final label = v['label'];
  final question = v['question'];
  final options = v['options'];
  if (key is! String || !_templateKeyRe.hasMatch(key)) return null;
  if (label is! String) return null;
  final l = label.trim();
  if (l.isEmpty || l.length > 60) return null;
  if (question is! String) return null;
  final q = question.trim();
  if (q.isEmpty || q.length > 200) return null;
  if (options is! List || options.length > 8) return null;
  final opts = <String>[];
  for (final o in options) {
    if (o is! String) return null;
    final t = o.trim();
    if (t.isEmpty || t.length > 80) return null;
    opts.add(t);
  }
  return (key: key, label: l, question: q, options: opts);
}

/// `null` ante cualquier forma inesperada — nunca lanza (mismo trato que
/// `parseAssistantTurn`). `version` admite el double entero que deja
/// `jsonDecode` (3.0), como `Number.isInteger` en la web.
AiTemplate? parseTemplateTurn(Object? json) {
  if (json is! Map || json['type'] != 'template') return null;
  final t = json['template'];
  if (t is! Map) return null;
  final id = t['id'];
  final rawVersion = t['version'];
  final scope = t['scope'];
  final qs = t['questions'];
  if (id is! String || id.isEmpty) return null;
  final version = switch (rawVersion) {
    int v => v,
    double v when v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
  if (version == null || version <= 0) return null;
  if (scope is! String || scope.isEmpty) return null;
  if (qs is! List || qs.isEmpty || qs.length > 12) return null;
  final questions = <TemplateQuestion>[];
  for (final q in qs) {
    final parsed = _templateQuestionOf(q);
    if (parsed == null) return null;
    questions.add(parsed);
  }
  final routing = json['routing'];
  final r = routing is Map ? routing : const <String, dynamic>{};
  return AiTemplate(
    id: id,
    version: version,
    scope: scope,
    questions: questions,
    categories: _strsOnly(r['categories']),
    rubros: _strsOnly(r['rubros']),
    knownAttributes: sanitizeAttributes(json['known_attributes']),
  );
}
```

En `parseAiTurn`, old:

```dart
      _ => throw FormatException('Turno IA desconocido: ${json['type']}'),
    };
```

New:

```dart
      'template' =>
        parseTemplateTurn(json) ?? (throw const TemplateFormatException()),
      _ => throw FormatException('Turno IA desconocido: ${json['type']}'),
    };
```

En `turnToJson`, old (el último caso):

```dart
      AiKindSwitch k => {
          'type': 'kind_switch',
          'message': k.message,
          'suggested_kind': k.suggestedKind,
          'options': k.options,
        },
    };
```

New:

```dart
      AiKindSwitch k => {
          'type': 'kind_switch',
          'message': k.message,
          'suggested_kind': k.suggestedKind,
          'options': k.options,
        },
      // Nunca va al historial (la pantalla no lo añade a `messages`); se
      // serializa entero solo para que el switch sea exhaustivo y reversible.
      AiTemplate t => {
          'type': 'template',
          'template': {
            'id': t.id,
            'version': t.version,
            'scope': t.scope,
            'questions': [
              for (final q in t.questions)
                {
                  'key': q.key,
                  'label': q.label,
                  'question': q.question,
                  'options': q.options,
                },
            ],
          },
          'routing': {'categories': t.categories, 'rubros': t.rubros},
          'known_attributes': t.knownAttributes,
        },
    };
```

- [ ] **6.4 Crear `app/lib/domain/template_run.dart`:**

```dart
import 'dart:convert';
import 'ai_turns.dart';

export 'ai_turns.dart'
    show AiTemplate, TemplateQuestion, TemplateFormatException, parseTemplateTurn;

/// El modo plantilla, sin Flutter (paridad con src/lib/templateRun.ts). El
/// endpoint responde el PRIMER mensaje con un turno `template` (spec §8.1) y
/// la pantalla lo ejecuta LOCAL: salta las preguntas ya contestadas por
/// `known_attributes`, enseña cada pregunta restante con la UI de `question`
/// que ya existe, y al final arma `routing`/`ready` ella misma, sin volver a
/// llamar al servidor. Esta es la lógica pura de ese recorrido.

/// Las preguntas que faltan por hacer, en el orden de la plantilla.
List<TemplateQuestion> pendingQuestions(
        AiTemplate t, Map<String, String> answers) =>
    t.questions
        .where((q) =>
            !answers.containsKey(q.key) && !t.knownAttributes.containsKey(q.key))
        .toList();

/// La añade el CLIENTE (§6.2 de la spec web) — la plantilla guardada en BD
/// nunca la incluye. `isCatchAllOption` la reconoce: abre el campo de texto.
const otherOption = 'Otra opción';

AiQuestion templateQuestionTurn(TemplateQuestion q) => AiQuestion(
      question: q.question,
      options: [...q.options, otherOption],
      allowOther: true,
      attribute: q.key,
    );

/// `true` si la respuesta no calza (sin distinguir mayúsculas ni espacios)
/// con ninguna opción declarada.
bool isOther(TemplateQuestion q, String answer) {
  final normalized = answer.trim().toLowerCase();
  return !q.options.any((o) => o.trim().toLowerCase() == normalized);
}

/// Mismo formato EXACTO que produce el flujo de la IA al responder una
/// pregunta — así la transcripción y el fallback al clarificador son
/// indistinguibles de un turno `question` real.
List<AiMessage> answerMsgs(TemplateQuestion q, String answer) => [
      AiMessage('assistant', jsonEncode(turnToJson(templateQuestionTurn(q)))),
      AiMessage('user', 'Pregunta: ${q.question}\nRespuesta: $answer'),
    ];

/// `answerMsgs` siempre antepone assistant(pregunta)+user(respuesta). Tras un
/// «Atrás» que dejó la MISMA pregunta de cola en el historial (`stepBack` se
/// detiene en ella), anteponerla de nuevo duplicaría la línea en la
/// transcripción — aquí solo se añade el user si el assistant ya está.
List<AiMessage> appendTemplateAnswer(
    List<AiMessage> msgs, TemplateQuestion q, String answer) {
  final pair = answerMsgs(q, answer);
  final last = msgs.isEmpty ? null : msgs.last;
  final alreadyThere =
      last != null && last.role == 'assistant' && last.content == pair[0].content;
  return [...msgs, if (!alreadyThere) pair[0], pair[1]];
}

/// Las respuestas de plantilla que QUEDAN en el historial: cada `assistant`
/// `question` con `attribute` de la plantilla seguido de su `user`. Es como
/// «Atrás» recalcula `answers` (spec §8.3) en vez de restar a un contador.
Map<String, String> templateAnswersIn(List<AiMessage> messages, AiTemplate t) {
  final keys = {for (final q in t.questions) q.key};
  final out = <String, String>{};
  String? pending;
  for (final m in messages) {
    if (m.role == 'assistant') {
      final turn = parseAssistantTurn(m.content);
      pending = (turn is AiQuestion && keys.contains(turn.attribute))
          ? turn.attribute
          : null;
      continue;
    }
    if (pending != null) {
      out[pending] = answerTextOf(m.content);
      pending = null;
    }
  }
  return out;
}

/// `tipo_unidad` -> `Tipo Unidad`. Solo para los atributos conocidos sin
/// pregunta propia.
String _initcap(String key) => key
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

const _titleMax = 120;

/// Arma `ready`+`routing` LOCAL, sin volver a llamar al servidor. Los
/// `knownAttributes` ya pasaron por `sanitizeAttributes` al parsear; las
/// respuestas del usuario NO — vienen tal cual las tecleó, así que se
/// recortan aquí (y las vacías se quedan fuera) antes de mezclarlas.
({AiReady ready, AiRouting routing}) buildTemplateReady(
  AiTemplate t,
  Map<String, String> answers,
  String scopeLabel,
) {
  final clean = <String, String>{
    for (final e in answers.entries)
      if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
  };
  final attributes = <String, String>{...t.knownAttributes, ...clean};

  final parts = <String>[attributes['tipo'] ?? scopeLabel];
  if (attributes['marca'] case final m?) parts.add(m);
  if (attributes['modelo'] case final m?) parts.add(m);
  var title = parts.join(' ').trim();
  if (title.length > _titleMax) title = title.substring(0, _titleMax);
  if (title.isEmpty) title = 'Solicitud';

  final bullets = <String>[];
  final covered = <String>{};
  for (final q in t.questions) {
    covered.add(q.key);
    final value = clean[q.key] ?? t.knownAttributes[q.key];
    if (value != null && value.isNotEmpty) bullets.add('${q.label}: $value');
  }
  for (final e in t.knownAttributes.entries) {
    if (covered.contains(e.key)) continue;
    bullets.add('${_initcap(e.key)}: ${e.value}');
  }

  return (
    ready: AiReady(
      title: title,
      bullets: bullets,
      wholesale: false,
      attributes: attributes,
      meta: (model: 'template', promptVersion: '${t.scope}@v${t.version}'),
    ),
    routing: AiRouting(
      message: 'Voy a enviar tu solicitud a:',
      categories: t.categories,
      rubros: t.rubros,
    ),
  );
}
```

- [ ] **6.5 Pantalla: exhaustividad.** En `_handleTurn` de `create_request_screen.dart`, old (el final del `switch`, tras el caso `AiReady rd:`):

```dart
        if (_catalogRubros.isEmpty && !_loadingCatalog) {
          unawaited(_loadRubroCatalog());
        }
    }
  }
```

New:

```dart
        if (_catalogRubros.isEmpty && !_loadingCatalog) {
          unawaited(_loadRubroCatalog());
        }
      case AiTemplate():
        // El modo plantilla se cablea en la Task 8 (`_startTemplate`). Hasta
        // entonces la app no manda `useTemplates`, así que este turno no
        // puede llegar; el caso existe para que el switch sobre el sealed
        // siga siendo exhaustivo.
        break;
    }
  }
```

- [ ] **6.6 Correr:** `flutter test test/template_run_test.dart test/ai_turns_back_test.dart test/ai_turns_test.dart` → verde; `flutter analyze` → 0 issues.

- [ ] **6.7 Commit:** `git add -A && git commit -m "feat(app): template_run — turno template, preguntas pendientes, Otra opción, ready/routing locales (lógica pura + tests de la web)"`.

---

## Task 7: `ai_client.dart` — `useTemplates` solo en el primer turno

**Files**
- Modify: `app/lib/core/ai_client.dart` `sendTurn` (firma L46-53, body L63-73)
- Modify: `app/test/ai_client_test.dart` (añadir 2 tests al final del `main`)

**Interfaces**
- `Future<AiTurn> sendTurn({required List<AiMessage> messages, String? kind, bool wholesale = false, String? accessToken, String? imageDataUrl, String? imageDataUrl2, bool useTemplates = false})` — el body lleva `'useTemplates': true` SOLO si `useTemplates && messages.length == 1`.

### Steps

- [ ] **7.1 Tests que fallan.** Añadir dentro de `main()` de `app/test/ai_client_test.dart`, antes del `}` final:

```dart
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
```

- [ ] **7.2 Correr:** `flutter test test/ai_client_test.dart` → los cuatro nuevos fallan (`useTemplates` no es un parámetro).

- [ ] **7.3 Implementar.** Old (`ai_client.dart`, firma de `sendTurn`):

```dart
  Future<AiTurn> sendTurn({
    required List<AiMessage> messages,
    String? kind, // 'producto' | 'servicio'
    bool wholesale = false,
    String? accessToken,
    String? imageDataUrl,
    String? imageDataUrl2,
  }) async {
```

New:

```dart
  /// `useTemplates`: pide al servidor que mire plantillas por rubro (spec
  /// §8.1). Solo tiene sentido en el PRIMER turno (`messages.length == 1`):
  /// el servidor solo lo consulta ahí (chat-stream.ts L331) y el fallback a
  /// IA manda el historial completo SIN plantillas. Aquí se filtra por
  /// longitud para que ningún caller pueda mandarlo en un turno 2+.
  Future<AiTurn> sendTurn({
    required List<AiMessage> messages,
    String? kind, // 'producto' | 'servicio'
    bool wholesale = false,
    String? accessToken,
    String? imageDataUrl,
    String? imageDataUrl2,
    bool useTemplates = false,
  }) async {
```

Old (body):

```dart
            'aiTicket': ?_ticket,
            // F3: pide el `ready` adjunto al routing (ahorra el POST del
            // auto-«ok»). Va en TODOS los turnos porque el cliente no puede
            // predecir cuál será routing; el servidor solo actúa ahí, y un
            // servidor viejo descarta la clave sin enterarse (fijado por test
            // en la web: chatStreamBody.test.ts).
            'wantReadyNext': true,
          }),
```

New:

```dart
            'aiTicket': ?_ticket,
            // F3: pide el `ready` adjunto al routing (ahorra el POST del
            // auto-«ok»). Va en TODOS los turnos porque el cliente no puede
            // predecir cuál será routing; el servidor solo actúa ahí, y un
            // servidor viejo descarta la clave sin enterarse (fijado por test
            // en la web: chatStreamBody.test.ts).
            'wantReadyNext': true,
            // Modo plantilla (spec §8.1): solo en el primer mensaje. Un
            // servidor viejo o con el interruptor apagado lo ignora.
            if (useTemplates && messages.length == 1) 'useTemplates': true,
          }),
```

- [ ] **7.4 Correr:** `flutter test test/ai_client_test.dart` → verde. `flutter analyze` → 0 issues.

- [ ] **7.5 Commit:** `git add -A && git commit -m "feat(app): AiClient manda useTemplates solo en el primer turno"`.

---

## Task 8: pantalla — modo plantilla (§8.3)

**Files**
- Modify: `app/lib/features/client/create_request_screen.dart`: imports; estado del run; `_send` (gancho de plantilla); `_ask` (`useTemplates`, `AiTemplate`, `TemplateFormatException`); `_restartWithKind` (abandona el run); `_goBack` (rama plantilla); `_handleTurn` (caso `AiTemplate` → `_startTemplate`); `_saveTranscript` (source/template); `_submit` (run `published`); `_finalForm` («No es esto»); nuevos `_startTemplate`, `_showNextTemplateQuestion`, `_finishTemplate`, `_fallBackToAi`, `_scopeLabelFor`, `_goBackTemplate`, `_answerTemplate`, `_insertTemplateRun`, `_updateTemplateRun`; clase `_TemplateRun` a nivel de fichero.

**Interfaces**
- Consumes: `template_run.dart` (Task 6), `sendTurn(useTemplates:)` (Task 7), `newRequestClientId()` de `repos.dart` (UUID v4), `categoryNameById` de `domain/catalog.dart`, `reportError`.
- Produces (privados):
  - `class _TemplateRun { final AiTemplate turn; final String runId; final Map<String,String> answers; int otherCount; bool fellBack; String? fallbackKey; bool get live; }`
  - `Future<bool> _ask({bool useTemplates = false})`
  - `Future<void> _startTemplate(AiTemplate t)` · `void _showNextTemplateQuestion()` · `Future<void> _finishTemplate()` · `void _answerTemplate(_TemplateRun run, String text)` · `Future<void> _fallBackToAi(String handoff, String? fallbackKey)` · `void _goBackTemplate(_TemplateRun run)` · `String _scopeLabelFor(AiTemplate t)`
  - `Future<void> _insertTemplateRun(_TemplateRun run, String uid)` · `Future<void> _updateTemplateRun(String runId, Map<String, dynamic> patch)`
- Sin test de widget (Supabase). La lógica está probada en Task 6/7; lo demás lo cubre el checkpoint de la Task 9 (y no hay smoke visible hasta que exista una plantilla activa).

### Steps

- [ ] **8.1 Imports.** Old:

```dart
import '../../domain/request_transcript.dart';
```

New:

```dart
import '../../domain/request_transcript.dart';
import '../../domain/template_run.dart';
```

- [ ] **8.2 Clase del run.** Insertar a nivel de fichero justo antes de `class CreateRequestScreen extends StatefulWidget {`:

```dart
/// Modo plantilla (spec §8.3): el turno `template` reemplaza al clarificador
/// para el PRIMER mensaje cuando hay una plantilla activa para el ámbito. A
/// partir de ahí TODO corre local — cero llamadas a la IA — hasta que el
/// usuario publica, pulsa «No es esto» o corrige (`fellBack`). `runId` es un
/// UUID v4 LOCAL (`newRequestClientId`, sin paquete uuid): es la PK de
/// `request_template_runs` y se manda en el INSERT.
class _TemplateRun {
  _TemplateRun({required this.turn, required this.runId});
  final AiTemplate turn;
  final String runId;
  final Map<String, String> answers = {};
  int otherCount = 0;
  bool fellBack = false;
  String? fallbackKey;

  /// Sigue en modo plantilla (no cayó a IA).
  bool get live => !fellBack;

  String get id => turn.id;
  int get version => turn.version;
  String get scope => turn.scope;
}
```

- [ ] **8.3 Estado.** Old:

```dart
  /// Lo que el usuario escribió en el compositor al arrancar. `_send` vacía
  /// `_input`; «Atrás» hasta el inicio lo devuelve al campo (§5.2).
  String _composerText = '';
```

New:

```dart
  /// Lo que el usuario escribió en el compositor al arrancar. `_send` vacía
  /// `_input`; «Atrás» hasta el inicio lo devuelve al campo (§5.2).
  String _composerText = '';

  /// Run de plantilla en curso (null = flujo de IA de siempre).
  _TemplateRun? _templateRun;

  /// El servidor mandó un turno `template` que no parseó (ya con toast). A la
  /// siguiente se deja de pedir plantillas en ESTA conversación (§8.1): el
  /// reintento cae al clarificador de siempre en vez de repetir el fallo.
  bool _templateBroken = false;
```

- [ ] **8.4 `_send`: gancho de plantilla.** Old (principio de `_send`):

```dart
  Future<void> _send(String text, {bool force = false, bool raw = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Mismo pulso que el chat entre personas: acá el usuario también le está
    // MANDANDO algo a alguien (la IA que arma la solicitud).
    JayaloHaptics.sent();
```

New:

```dart
  Future<void> _send(String text, {bool force = false, bool raw = false}) async {
    if (text.trim().isEmpty || (_busy && !force)) return;
    // Modo plantilla (§8.3): las respuestas a una pregunta de plantilla se
    // resuelven LOCAL, y una corrección tras la ficha es el handoff al
    // clarificador. `force`/`raw` son caminos internos (auto-«ok», foto,
    // «No» del kind_switch, el propio handoff) y pasan de largo.
    if (_templateRun case final run? when run.live && !force && !raw) {
      if (_correcting) {
        await _fallBackToAi(text, null);
        return;
      }
      if (_current is AiQuestion) {
        _answerTemplate(run, text);
        return;
      }
    }
    // Mismo pulso que el chat entre personas: acá el usuario también le está
    // MANDANDO algo a alguien (la IA que arma la solicitud).
    JayaloHaptics.sent();
```

Old (final de `_send`):

```dart
    final ok = await _ask();
    // El mensaje que provocó el fallo se quita: el usuario reintenta desde el
```

New:

```dart
    // `useTemplates` solo cuando el historial es el primer mensaje (§8.3);
    // `sendTurn` lo filtra otra vez por longitud.
    final ok = await _ask(useTemplates: _messages.length == 1);
    // El mensaje que provocó el fallo se quita: el usuario reintenta desde el
```

- [ ] **8.5 `_ask`: `useTemplates`, `AiTemplate`, `TemplateFormatException`.** Old:

```dart
  Future<bool> _ask() async {
    setState(() => _busy = true);
    try {
      // El JWT de la sesión exime el Turnstile del primer turno (ADR-0032);
      // el WebView del CAPTCHA se quitó: se pintaba negro en MIUI y colgaba
      // el flujo completo de crear solicitud.
      final turn = await _ai.sendTurn(
        messages: _messages,
        kind: _kind,
        wholesale: _wholesale,
        accessToken: supa.auth.currentSession?.accessToken,
        imageDataUrl: _photos.isNotEmpty ? _photos[0].dataUrl : null,
        imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null,
      );
      _messages.add(AiMessage('assistant', jsonEncode(turnToJson(turn))));
```

New:

```dart
  Future<bool> _ask({bool useTemplates = false}) async {
    setState(() => _busy = true);
    try {
      // El JWT de la sesión exime el Turnstile del primer turno (ADR-0032);
      // el WebView del CAPTCHA se quitó: se pintaba negro en MIUI y colgaba
      // el flujo completo de crear solicitud.
      final turn = await _ai.sendTurn(
        messages: _messages,
        kind: _kind,
        wholesale: _wholesale,
        accessToken: supa.auth.currentSession?.accessToken,
        imageDataUrl: _photos.isNotEmpty ? _photos[0].dataUrl : null,
        imageDataUrl2: _photos.length > 1 ? _photos[1].dataUrl : null,
        useTemplates: useTemplates && !_templateBroken,
      );
      if (!mounted) return true;
      if (turn is AiTemplate) {
        // El turno `template` NUNCA va al historial (paridad web): la
        // conversación sigue siendo [primer mensaje] + los pares locales.
        setState(() => _correcting = false);
        await _startTemplate(turn);
        return true;
      }
      _messages.add(AiMessage('assistant', jsonEncode(turnToJson(turn))));
```

Old (los catch de `_ask`):

```dart
    } on AiHttpException catch (e) {
      if (!mounted) return false;
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      return false;
    } catch (e) {
```

New:

```dart
    } on AiHttpException catch (e) {
      if (!mounted) return false;
      _toast(
        e.status == 429
            ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
            : e.message,
      );
      return false;
    } on TemplateFormatException {
      // Turno `template` malformado (§8.1): se trata como un turno de IA
      // fallido — toast + reintento — pero a la siguiente ya no se piden
      // plantillas en esta conversación.
      if (!mounted) return false;
      _templateBroken = true;
      _toast('Algo falló. Intenta de nuevo.');
      return false;
    } catch (e) {
```

- [ ] **8.6 `_restartWithKind`: abandona el run y reinicia con plantillas.** Old:

```dart
    final previous = List<AiMessage>.of(_messages);
    final previousCurrent = _current;
    final first = _messages.first;
    JayaloHaptics.sent();
    setState(() {
      _kind = kind;
```

New:

```dart
    final previous = List<AiMessage>.of(_messages);
    final previousCurrent = _current;
    final first = _messages.first;
    JayaloHaptics.sent();
    // El cambio de kind invalida el run de plantilla en curso, si lo hay: el
    // ámbito de la plantilla ya no corresponde al kind nuevo (§8.3). Estado
    // primero; la escritura es best-effort y no demora el reinicio.
    final closing = _templateRun;
    _templateRun = null;
    if (closing != null && closing.live) {
      unawaited(_updateTemplateRun(closing.runId, {
        'outcome': 'abandoned',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }));
    }
    setState(() {
      _kind = kind;
```

Old:

```dart
      _showOther = false;
      _pop++;
    });
    final ok = await _ask();
    if (!ok && mounted) {
      // Si el reinicio falla, se vuelve a donde estaba (con el kind ya
```

New:

```dart
      _showOther = false;
      _pop++;
    });
    // Es un primer mensaje, igual que el arranque: puede devolver plantilla.
    final ok = await _ask(useTemplates: true);
    if (!ok && mounted) {
      // Si el reinicio falla, se vuelve a donde estaba (con el kind ya
```

- [ ] **8.7 `_goBack`: rama plantilla.** Old:

```dart
  void _goBack() {
    if (_busy || _messages.isEmpty) return;
    final r = stepBack(_messages);
```

New:

```dart
  void _goBack() {
    if (_busy || _messages.isEmpty) return;
    if (_templateRun case final run? when run.live) {
      _goBackTemplate(run);
      return;
    }
    final r = stepBack(_messages);
```

- [ ] **8.8 `_handleTurn`: caso `AiTemplate`.** Old:

```dart
      case AiTemplate():
        // El modo plantilla se cablea en la Task 8 (`_startTemplate`). Hasta
        // entonces la app no manda `useTemplates`, así que este turno no
        // puede llegar; el caso existe para que el switch sobre el sealed
        // siga siendo exhaustivo.
        break;
```

New:

```dart
      case AiTemplate t:
        // Normalmente `_ask` lo intercepta antes (no va al historial); si
        // llega por aquí, el trato es el mismo.
        await _startTemplate(t);
```

- [ ] **8.9 Métodos del modo plantilla.** Insertar justo después de `_backButton()` (y antes de `_pickPhoto`):

```dart
  // ── Modo plantilla (spec §8.3, paridad con new.tsx) ────────────────────

  /// Arranca el modo plantilla: pinta la primera pregunta pendiente (o la
  /// ficha si no falta ninguna) y DESPUÉS registra el run — fire-and-forget,
  /// `reportError` si falla. INSERT con EXACTAMENTE `id, user_id,
  /// template_id, template_version` (grant por columna: uno de más = 42501).
  Future<void> _startTemplate(AiTemplate t) async {
    final run = _TemplateRun(turn: t, runId: newRequestClientId());
    setState(() {
      _templateRun = run;
      _ready = null;
      _categories = List<String>.of(t.categories);
      _rubros = List<String>.of(t.rubros);
      _catalogRubros = [];
      _selectedRubros = {};
    });
    unawaited(_loadRubroCatalog());
    _showNextTemplateQuestion();
    final uid = supa.auth.currentUser?.id;
    if (uid != null) unawaited(_insertTemplateRun(run, uid));
  }

  Future<void> _insertTemplateRun(_TemplateRun run, String uid) async {
    try {
      await supa.from('request_template_runs').insert({
        'id': run.runId,
        'user_id': uid,
        'template_id': run.id,
        'template_version': run.version,
      });
    } catch (e, s) {
      unawaited(reportError(e, s));
    }
  }

  /// UPDATE del desenlace del run, best-effort. `patch` solo puede llevar
  /// columnas del grant de UPDATE (`outcome, fallback_key, answered_count,
  /// other_count, title_edited, request_id, ended_at`).
  Future<void> _updateTemplateRun(
      String runId, Map<String, dynamic> patch) async {
    try {
      await supa.from('request_template_runs').update(patch).eq('id', runId);
    } catch (e, s) {
      unawaited(reportError(e, s));
    }
  }

  /// Siguiente pregunta pendiente con la UI de `question` de siempre; si no
  /// queda ninguna, la ficha local.
  void _showNextTemplateQuestion() {
    final run = _templateRun;
    if (run == null) return;
    final pending = pendingQuestions(run.turn, run.answers);
    if (pending.isEmpty) {
      unawaited(_finishTemplate());
      return;
    }
    setState(() {
      _ready = null;
      _current = templateQuestionTurn(pending.first);
      _showOther = false;
      _pop++;
    });
  }

  /// `routing` + `ready` LOCALES al historial (mismos JSON que `turnToJson`,
  /// mismo 'user' intermedio que la web) y `_handleTurn(ready)` sin POST.
  Future<void> _finishTemplate() async {
    final run = _templateRun;
    if (run == null) return;
    final built =
        buildTemplateReady(run.turn, run.answers, _scopeLabelFor(run.turn));
    _messages.add(AiMessage('assistant', jsonEncode(turnToJson(built.routing))));
    _messages.add(const AiMessage('user', 'Perfecto, ahora dame la ficha final.'));
    _messages.add(AiMessage('assistant', jsonEncode(turnToJson(built.ready))));
    setState(() {
      _categories = List<String>.of(built.routing.categories);
      _rubros = List<String>.of(built.routing.rubros);
    });
    await _handleTurn(built.ready);
  }

  /// Título de la ficha cuando la plantilla no conoce el `tipo`: el nombre
  /// de la primera categoría del routing si la app lo tiene (catálogo local
  /// `kCategories`), si no el `scope` tal cual.
  String _scopeLabelFor(AiTemplate t) {
    final first = t.categories.isEmpty ? null : t.categories.first;
    return categoryNameById(first) ?? t.scope;
  }

  /// Respuesta a una pregunta de plantilla: par assistant+user al historial,
  /// `answers[key]`, `otherCount` si no calza con las opciones; siguiente
  /// pendiente o ficha. Cero llamadas.
  void _answerTemplate(_TemplateRun run, String text) {
    final pending = pendingQuestions(run.turn, run.answers);
    if (pending.isEmpty) {
      // No debería pasar (clic tardío tras cerrar el run) — nunca un no-op
      // silencioso: cae al clarificador con la respuesta tal cual.
      unawaited(_fallBackToAi(answerContent(_current, text), null));
      return;
    }
    final q = pending.first;
    JayaloHaptics.sent();
    final next = appendTemplateAnswer(_messages, q, text);
    run.answers[q.key] = text;
    if (isOther(q, text)) run.otherCount++;
    setState(() {
      _messages
        ..clear()
        ..addAll(next);
      _showOther = false;
      _input.clear();
      _current = null;
    });
    _showNextTemplateQuestion();
  }

  /// Cierra el run como `fallback` (best-effort, sin bloquear) y le pasa la
  /// posta al clarificador con el historial COMPLETO (primer mensaje + pares
  /// de plantilla + `handoff`) SIN `useTemplates`. La usan «No es esto»
  /// (`fallbackKey: null` desde la ficha), la corrección (`_correcting`) y el
  /// defensivo de `_answerTemplate`. Desde aquí la conversación es de IA.
  Future<void> _fallBackToAi(String handoff, String? fallbackKey) async {
    final run = _templateRun;
    if (_busy || run == null || run.fellBack) return;
    run.fellBack = true;
    run.fallbackKey = fallbackKey;
    unawaited(_updateTemplateRun(run.runId, {
      'outcome': 'fallback',
      'fallback_key': fallbackKey,
      'answered_count': run.answers.length,
      'other_count': run.otherCount,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }));
    // `raw`: el handoff va tal cual y se salta el gancho de plantilla de
    // `_send` (el run ya no está `live`). El historial tiene 2+ mensajes,
    // así que `useTemplates` no viaja.
    await _send(handoff, raw: true);
  }

  /// «Atrás» en modo plantilla (§8.3): `stepBack` sobre el historial y
  /// `answers` se recalcula desde los pares que quedan. Desde la ficha se
  /// deshace primero el cierre local (los 3 mensajes de `_finishTemplate`),
  /// como en la web: si no, `stepBack` se pararía en el `routing`. Si no
  /// queda nada, se abandona el run y se vuelve al compositor.
  void _goBackTemplate(_TemplateRun run) {
    var base = List<AiMessage>.of(_messages);
    if (_current is AiReady && base.length >= 3) {
      base = base.sublist(0, base.length - 3);
    }
    final r = stepBack(base);
    if (r.turn == null) {
      final abandoning = run.runId;
      setState(() {
        _templateRun = null;
        _input.text = _composerText;
        _messages.clear();
        _current = null;
        _ready = null;
        _categories = [];
        _rubros = [];
        _showOther = false;
        _correcting = false;
        _pop++;
      });
      unawaited(_updateTemplateRun(abandoning, {
        'outcome': 'abandoned',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }));
      return;
    }
    final answers = templateAnswersIn(r.messages, run.turn);
    run.answers
      ..clear()
      ..addAll(answers);
    run.otherCount = answers.entries.where((e) {
      final q = run.turn.questions.firstWhere((q) => q.key == e.key);
      return isOther(q, e.value);
    }).length;
    setState(() {
      _messages
        ..clear()
        ..addAll(r.messages);
      _ready = null;
      _current = null;
      _showOther = false;
      _correcting = false;
    });
    _showNextTemplateQuestion();
  }
```

- [ ] **8.10 Publicar: transcripción con source y run `published`.** Old (`_saveTranscript`):

```dart
    final rd = _ready;
    final row = buildTranscript(
      requestId,
      List<AiMessage>.of(_messages),
      attributes: rd?.attributes ?? const {},
      model: rd?.meta?.model,
      promptVersion: rd?.meta?.promptVersion,
    );
    if (row == null) return;
```

New:

```dart
    final rd = _ready;
    final run = _templateRun;
    final row = buildTranscript(
      requestId,
      List<AiMessage>.of(_messages),
      attributes: rd?.attributes ?? const {},
      model: rd?.meta?.model,
      promptVersion: rd?.meta?.promptVersion,
      // Fase 1: de dónde salió la conversación. `buildTranscript` degrada a
      // 'ai' si faltara la plantilla (el CHECK de la BD lo exige).
      source: run == null ? 'ai' : (run.fellBack ? 'fallback' : 'template'),
      templateId: run?.id,
      templateVersion: run?.version,
    );
    if (row == null) return;
```

Old (`_submit`, tras `setState(() => _submitted = true);`):

```dart
      if (requestId != null) unawaited(_saveTranscript(requestId));
    } catch (e) {
```

New:

```dart
      if (requestId != null) unawaited(_saveTranscript(requestId));
      // Cierra el run de plantilla como `published` — best-effort. Si «No es
      // esto»/corregir ya lo cerró como `fallback`, no se toca (pisaría la
      // señal real). La app no edita el título en la ficha: `title_edited`
      // queda false.
      if (requestId != null && _templateRun case final run? when run.live) {
        unawaited(_updateTemplateRun(run.runId, {
          'outcome': 'published',
          'answered_count': run.answers.length,
          'other_count': run.otherCount,
          'title_edited': false,
          'request_id': requestId,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        }));
      }
    } catch (e) {
```

- [ ] **8.11 «No es esto» en la ficha (solo modo plantilla).** Old (el `Wrap` de acciones de `_finalForm`, tras el `TextButton.icon` de «Atrás»):

```dart
            TextButton.icon(
              onPressed: _busy ? null : _goBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Atrás'),
            ),
          ],
        ),
```

New:

```dart
            TextButton.icon(
              onPressed: _busy ? null : _goBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Atrás'),
            ),
            // Modo plantilla (§8.3): la ficha la armó la plantilla, no la
            // IA. «No es esto» cierra el run como fallback (sin
            // `fallback_key`: ya no queda pregunta pendiente) y sigue con el
            // clarificador de verdad. Literal de la web (`templateFallback`).
            if (_templateRun case final run? when run.live)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _fallBackToAi(
                          'Lo anterior no encaja del todo; sigue preguntando tú lo que falte.',
                          null,
                        ),
                child: const Text('No es esto'),
              ),
          ],
        ),
```

- [ ] **8.12 Verificar:** `flutter analyze` (0 issues) y `flutter test` (verde). Comprobar a mano: `grep -n "request_template_runs" app/lib/features/client/create_request_screen.dart` → exactamente 2 sitios (`_insertTemplateRun`, `_updateTemplateRun`); los payloads de `_updateTemplateRun` en el fichero solo usan `outcome, fallback_key, answered_count, other_count, title_edited, request_id, ended_at`.

- [ ] **8.13 Commit:** `git add -A && git commit -m "feat(app): modo plantilla calcado de la web — run local, No es esto, fallback a IA, Atrás y publish con source/template (dormido tras request_templates_enabled)"`.

---

## Task 9: carril 2 — checkpoint, sonda del body y APK `+101`

**Files**
- Ninguno nuevo. (La versión sigue en `1.0.4+101`: es la misma release; el APK se recompila con el carril 2 encima.)

### Steps

- [ ] **9.1 Checkpoint** (desde `app/`): `flutter analyze` → «No issues found!»; `flutter test` → verde. Repasar que en `create_request_screen.dart` no queda `_turnToJson`, `_answers`, `_aiAnswered` (`grep`), y que `useTemplates` solo aparece en `_send` (`_messages.length == 1`) y `_restartWithKind` (`useTemplates: true`).

- [ ] **9.2 Sonda del body:** `flutter test test/ai_client_test.dart` — los tests «useTemplates viaja SOLO en el primer turno» y «sonda del body del primer turno» son la certificación del contrato con el servidor (`chat-stream.ts` L331 solo mira `useTemplates` con `messages.length === 1`). No hay smoke visible del carril 2 hasta que exista una plantilla activa (`request_templates_enabled` está en `false`): la app se comporta EXACTAMENTE como el carril 1.

- [ ] **9.3 Commit ANTES de compilar** (si `git status` no está limpio): `git add -A && git commit -m "chore(app): carril 2 listo — modo plantilla dormido, misma version 1.0.4+101"`.

- [ ] **9.4 APK:** `flutter build apk --release` → `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Ajustes → «Esta versión»: `Jayalo v1.0.4 (101)` + sello `feat/atras-y-plantillas-app · <sha del 9.3>` sin «sin commitear».

- [ ] **9.5 Smoke de regresión (PO):** repetir la lista de la Task 5.5 con este APK (el carril 2 no cambia nada visible mientras el interruptor esté apagado). Si el PO enciende `request_templates_enabled` y aprueba una plantilla en `/admin/plantillas` para un ámbito: primer mensaje en ese ámbito → preguntas de la plantilla (con «Otra opción» abriendo el campo), «Atrás» entre ellas, ficha con «No es esto» → cae a IA; publicar → `request_ai_transcripts.source='template'` + `request_template_runs.outcome='published'` (lo verifica quien tenga acceso a la BD; este plan no la toca).

- [ ] **9.6 Entrega:** rama `feat/atras-y-plantillas-app` con 9 commits, SIN push (lo decide el PO). Actualizar la memoria del proyecto con: la mina del sealed (`AiTemplate` en `ai_turns.dart`), que `kind_switch` «Sí» ahora reinicia (antes no), y que `submitRequest` devuelve `String?`.

---

## Self-review

**Cobertura spec → task**

| Spec | Task |
|---|---|
| §5.1 `turnToJson` al dominio, `AiReady.attributes/meta`, `AiQuestion.attribute` | 1 |
| §5.1 `parseAssistantTurn` (nunca lanza) | 1 |
| §5.1 `secondPhotoMsg` / `keepsSecondPhoto` | 1 (dominio), 3 (`_pickForRequest`) |
| §5.1 `stepBack` (3 reglas) | 1 |
| §5.1 `answeredCount` sustituye `_answers`/`_aiAnswered` | 1 (dominio), 3 (pantalla) |
| §5.2 botón «Atrás» en question/kind_switch/image_request/routing/ready; oculto con `_busy`/`_correcting`; no en el compositor | 3 (3.9, 3.11; `_backButton` apagado con `_busy`; `_correcting` pinta otra rama) |
| §5.2 `_goBack` (turn null → compositor con `_input`/`_photos`; turn → `_current`, `_ready`, categorías del último routing; 2ª foto) | 3 (3.4) |
| §5.2 «Pregunta N» y barra desde `answeredCount`; `_hasUnsavedWork` sin `_answers` | 3 (3.2, 3.9, 3.10) |
| §5.2 correcciones (`_correcting`) no cambian y «Atrás» las deshace | 3 (`_goBack` genérico sobre el historial) |
| §5.3 `takeBackStep/releaseBackStep/tryBackStep`; `BackGuard` primero; registro en `initState`/`dispose`; navbar no | 2 (+3.3) |
| §6 formato `Pregunta/Respuesta` en question; «No» del kind_switch; «Sí» reinicia; auto-ok/foto/corrección sin cambio | 1 (`answerContent`, `kindSwitchNoContent`), 3 (3.4, 3.9) |
| §7 `submitRequest` devuelve id | 4 (4.6) |
| §7 `buildTranscript` (question_count, other_count, null por vacío/60 000, source degradado) | 4 (4.4) |
| §7 insert best-effort tras publicar, columnas exactas, `reportError` | 4 (4.8) |
| §7 model/prompt_version de `AiReady.meta`, attributes de `AiReady.attributes` | 4 (4.8) |
| §8.1 `useTemplates` solo con `messages.length == 1`; turno `template` malformado ⇒ toast + reintento; deja de pedir a la 2ª | 7 (cliente), 8 (8.4, 8.5 `_templateBroken`) |
| §8.2 `AiTemplate`, `parseTemplateTurn`, `pendingQuestions`, `otherOption`, `templateQuestionTurn`, `isOther`, `answerMsgs`, `buildTemplateReady` | 6 |
| §8.3 `_templateRun` {id, version, scope, answers, otherCount, fellBack, fallbackKey, runId} | 8 (8.2: `_TemplateRun` con getters `id/version/scope`) |
| §8.3 al recibir `AiTemplate`: run local, primera pregunta, INSERT exacto después | 8 (8.9 `_startTemplate`) |
| §8.3 cada respuesta: `answerMsgs`, `answers[key]`, `otherCount`, siguiente o `buildTemplateReady` ⇒ routing+ready locales + `_handleTurn` sin POST; `scopeLabel` | 8 (`_answerTemplate`, `_finishTemplate`, `_scopeLabelFor`) |
| §8.3 «No es esto» y corrección ⇒ `_fallBackToAi` (UPDATE fallback exacto, historial completo sin `useTemplates`) | 8 (8.4, 8.11, `_fallBackToAi`) |
| §8.3 «Atrás» en modo plantilla: `stepBack` + `answers` recalculadas; sin nada ⇒ compositor | 8 (`_goBackTemplate`, `templateAnswersIn` de 6) |
| §8.3 `kind_switch` «Sí» limpia el run (`abandoned` si vivo) y reinicia con `useTemplates: true` | 8 (8.6) |
| §8.3 publicar: transcripción `source/templateId/templateVersion`; run `published` con `title_edited: false` | 8 (8.10) |
| §9 errores best-effort; `stepBack` puro | 1, 4, 8 |
| §10 tests: `stepBack` (5 casos + roto), `answeredCount`, round-trip `turnToJson`, `buildTranscript` ×10, `template_run`, `unsaved_guard`, `ai_client` body; widget test del botón: NO viable (documentado) | 1, 2, 4, 6, 7; smoke en 5/9 |
| §11 APK `1.0.4+101`, sello, adb, smoke carril 1 / sonda carril 2 | 5, 9 |
| §12 minas (commitear antes de compilar; grants por columna) | Global Constraints, 5.3, 9.3, 8.12 |

**Sin mapear a task:** ninguna sección. Desviaciones conscientes (documentadas en «Contraste con el código»): §5.2 la fórmula de `_hasUnsavedWork` conserva la regla de la siembra (#8); §8.2 `AiTemplate`/`parseTemplateTurn` viven en `ai_turns.dart` por el sealed (#2) y se re-exportan desde `template_run.dart`; §6 «Sí, cambiar» pasa a reiniciar (la app no lo hacía, #6); §5.2 la 2ª foto solo se suelta si entró por el chat (#5); §7 el reintento 23505 no produce transcripción (#10).

**Escaneo de placeholders:** el plan no contiene «TODO», «similar a la Task», «…igual que…» como sustituto de código, ni puntos suspensivos dentro de bloques Dart salvo en literales de texto de UI ya existentes (`'Pensando…'`, `'Otra respuesta…'`, `'Un momento… demasiadas solicitudes…'`) y en el resumen de firmas de las secciones **Interfaces** (`{...misma firma...}` de `submitRequest`, cuyo cuerpo completo se da en 4.6 como edits old/new).

**Consistencia de firmas entre tasks:**
- `AiMessage(role, content)` + `toJson()` + `==` — definida en 1, usada en 1/4/6/7/8 con `const AiMessage('user', …)`.
- `turnToJson(AiTurn)` — 1; usada en 3 (`_ask`, F3), 6 (`answerMsgs`, caso `AiTemplate`), 8 (`_finishTemplate`).
- `stepBack(List<AiMessage>) → ({messages, turn})` — 1; usada en 3 (`_goBack`), 6 (test `templateAnswersIn`), 8 (`_goBackTemplate`).
- `answerContent(AiTurn?, String)` / `kindSwitchNoContent(AiKindSwitch, String)` — 1; usadas en 3 (`_send`, kind_switch) y 8 (`_answerTemplate` defensivo).
- `answerTexts` / `answeredCount` — 1; usadas en 3 (`_buildingCard`, `_questionArea`).
- `takeBackStep({owner, step})` / `releaseBackStep(owner)` / `tryBackStep()` — 2; usadas en 2 (`BackGuard`) y 3 (`initState`/`dispose`).
- `_send(String, {force, raw})` — 3; `raw: true` en 3 (`_pickForRequest`, kind_switch «No») y 8 (`_fallBackToAi`).
- `_ask()` en 3 → `_ask({bool useTemplates = false})` en 8 (edit 8.5); los llamadores de 3 (`_send`, `_restartWithKind`) se actualizan en 8.4/8.6.
- `buildTranscript(requestId, messages, {attributes, model, promptVersion, source, templateId, templateVersion})` — 4; llamada en 4.8 con 3 named y en 8.10 con los 6.
- `submitRequest(...) → Future<String?>` — 4; `final requestId = await submitRequest(` en 4.8; `requestId` usado en 8.10.
- `AiTemplate{id, version, scope, questions, categories, rubros, knownAttributes}` y `TemplateQuestion` record — 6 (en `ai_turns.dart`, re-export); usados en 6 (`template_run.dart`, tests), 7 (test), 8 (`_TemplateRun`, `_scopeLabelFor`).
- `TemplateFormatException` — 6; capturada en 8.5; testeada en 6/7.
- `pendingQuestions(t, answers)`, `templateQuestionTurn(q)`, `isOther(q, answer)`, `appendTemplateAnswer(msgs, q, answer)`, `templateAnswersIn(messages, t)`, `buildTemplateReady(t, answers, scopeLabel) → ({ready, routing})` — 6; usadas en 8 con esos nombres y órdenes de argumentos.
- `sendTurn(..., useTemplates:)` — 7; pasada en 8.5.
- `newRequestClientId()` (`repos.dart`, ya importado por la pantalla vía `data/repos.dart`) y `categoryNameById` (`domain/catalog.dart`, ya importado en la pantalla L20) — usados en 8 sin imports nuevos.
