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
/// turno de IA fallido: toast + reintento) pero distinguible: al primer
/// fallo de parseo la pantalla deja de pedir plantillas en esa conversación
/// (§8.1).
class TemplateFormatException extends FormatException {
  const TemplateFormatException() : super('Turno template malformado');
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
      'template' =>
        parseTemplateTurn(json) ?? (throw const TemplateFormatException()),
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
          'attribute': ?q.attribute,
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
          'condition': ?r.condition,
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
