/// Turnos del endpoint IA `/api/ai/chat-stream` (que NO es streaming: cada
/// turno es un POST que devuelve UN objeto JSON). Contrato verificado en
/// jayalo-main: src/lib/ai/prompts.ts L30-82 + chat-stream.ts L438-500.
sealed class AiTurn {
  const AiTurn();
}

class AiQuestion extends AiTurn {
  const AiQuestion(
      {required this.question, required this.options, required this.allowOther});
  final String question;
  final List<String> options;
  final bool allowOther;
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
      this.condition});
  final String title;
  final List<String> bullets;
  final bool wholesale;

  /// 'nuevo' | 'usado' | 'ambos' si el usuario lo dijo espontáneamente en la
  /// conversación (paridad con `parseReadyCondition` de la web): permite
  /// saltar el paso Estado del formulario final. null = hay que preguntar.
  final String? condition;
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
          allowOther: json['allowOther'] as bool? ?? true),
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
          }),
      'kind_switch' => AiKindSwitch(
          message: json['message'] as String? ?? '',
          suggestedKind: json['suggested_kind'] as String? ?? 'servicio',
          options: _strs(json['options'])),
      _ => throw FormatException('Turno IA desconocido: ${json['type']}'),
    };
