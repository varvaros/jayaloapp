import 'dart:convert';
import 'ai_turns.dart';

// El `show` original del brief (§Interfaces) solo cubría los símbolos nuevos
// del turno template. Se amplía aquí porque tanto el test de esta lógica
// pura como la pantalla (Task 8) necesitan, con un único import a
// `template_run.dart`, los tipos y funciones que sus firmas usan a diario:
// `AiMessage`/`AiQuestion`/`AiRouting` (parámetros y resultados de las
// funciones de este fichero) y `parseAiTurn`/`parseAssistantTurn`/
// `turnToJson`/`stepBack` (parseo/serialización/«Atrás» del propio turno
// template y de las respuestas que produce).
export 'ai_turns.dart'
    show
        AiTemplate,
        TemplateQuestion,
        TemplateFormatException,
        parseTemplateTurn,
        AiMessage,
        AiQuestion,
        AiRouting,
        parseAiTurn,
        parseAssistantTurn,
        turnToJson,
        stepBack;

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
