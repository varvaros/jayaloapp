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
