import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_turns.dart';
import 'config.dart';

// `AiMessage` se mudó al dominio (stepBack/answeredCount lo leen). Se
// re-exporta para que quien importaba `core/ai_client.dart` por él siga
// compilando sin tocar un import.
export '../domain/ai_turns.dart' show AiMessage;

class AiHttpException implements Exception {
  AiHttpException(this.status, this.message, {this.code});
  final int status;
  final String message;

  /// `code` del JSON de error del servidor (p. ej. `image_expired`), si lo trae.
  final String? code;
  @override
  String toString() => 'AiHttpException($status): $message';
}

class AiClient {
  AiClient({http.Client? inner, Duration? timeout})
      : _http = inner ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 45);
  final http.Client _http;

  /// Red de seguridad del cliente: el servidor ya acota Gemini con sus propios
  /// timeouts; esto solo corta un socket colgado de verdad (sin él, "Pensando…"
  /// duraba hasta que el SO rindiera el socket — minutos). El catch genérico
  /// de la pantalla convierte el TimeoutException en "Algo falló. Intenta de
  /// nuevo." y restaura el estado, igual que cualquier otro fallo de red.
  final Duration _timeout;

  /// Ticket HMAC de la conversación: el servidor lo emite en cada respuesta y
  /// lo exige en los turnos 2+ (`aiTicket.server.ts` de la web). Reenviarlo
  /// hace que el gate se valide EN LOCAL en el servidor; sin él, cada turno
  /// paga un `auth.getUser()` contra Supabase Auth (~100-300 ms). Vive en el
  /// cliente porque hay un AiClient por conversación (pantalla de crear).
  String? _ticket;

  /// Ids de foto cacheada (spec 2026-09-05-foto-cacheada-kv) que devolvió la
  /// ÚLTIMA respuesta 200; la pantalla los copia a sus fotos.
  ({String? first, String? second}) lastImageIds = (first: null, second: null);

  /// Un turno = un POST. `accessToken` (JWT de la sesión de Supabase) exime
  /// el Turnstile del primer turno (ADR-0032) — la app siempre está
  /// autenticada, así que no monta WebView de CAPTCHA. El header Origin es
  /// obligatorio (el endpoint falla cerrado; somos nuestro propio cliente de
  /// confianza).
  /// `imageDataUrl` / `imageDataUrl2` (data URL base64, máx 8 MB c/u) son el
  /// contrato multimodal de la web: el cliente los manda en CADA POST y el
  /// servidor decide a qué mensaje del historial adjuntarlos
  /// (`chat-stream.ts` L408). El modelo ve la foto. Desde la spec
  /// 2026-09-05-foto-cacheada-kv el servidor guarda ese base64 en KV (30 min)
  /// y devuelve su id: si la ranura ya tiene id, el caller manda `imageId` /
  /// `imageId2` EN VEZ del base64 y el POST deja de arrastrar la foto entera.
  /// Base64 y id en la misma ranura ⇒ gana el base64 (es el reintento tras un
  /// `409 image_expired`).
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
    String? imageId,
    String? imageId2,
    bool useTemplates = false,
    bool manual = false,
  }) async {
    final res = await _http
        .post(
          Uri.parse(AppConfig.aiEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Origin': AppConfig.siteUrl,
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'messages': messages.map((m) => m.toJson()).toList(),
            'kind': ?kind,
            if (wholesale) 'wholesale': true,
            // Foto cacheada: id si la ranura ya tiene, base64 si no (la
            // pantalla decide; en el reintento tras un 409 manda base64).
            'imageDataUrl': ?imageDataUrl,
            'imageDataUrl2': ?imageDataUrl2,
            'imageId': ?imageId,
            'imageId2': ?imageId2,
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
            // Solicitud MANUAL (spec 2026-09-05): salta la entrevista. Solo
            // tiene sentido en el primer mensaje; el servidor lo ignora en 2+.
            if (manual && messages.length == 1) 'manual': true,
          }),
        )
        .timeout(_timeout);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    // Como `keepAiTicket` en la web: se captura antes del check de status, y
    // una respuesta SIN ticket (error, o secret no configurado) no borra el
    // que ya se tenía.
    final t = body['aiTicket'];
    if (t is String && t.isNotEmpty) _ticket = t;
    if (res.statusCode != 200) {
      throw AiHttpException(res.statusCode, body['error']?.toString() ?? 'Error',
          code: body['code'] is String ? body['code'] as String : null);
    }
    // Solo en 200: un error no trae ids y no debe pisar los que ya había.
    lastImageIds = (first: _hex32(body['imageId']), second: _hex32(body['imageId2']));
    return parseAiTurn(body);
  }

  /// Un id de foto de KV es exactamente 32 hex (un uuid v4 sin guiones).
  /// Cualquier otra cosa se descarta: no se reenvía basura al servidor.
  String? _hex32(Object? v) =>
      v is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(v) ? v : null;
}
