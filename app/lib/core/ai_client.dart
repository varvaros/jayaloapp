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

class AiHttpException implements Exception {
  AiHttpException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'AiHttpException($status): $message';
}

class AiClient {
  AiClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  /// Un turno = un POST. `accessToken` (JWT de la sesión de Supabase) exime
  /// el Turnstile del primer turno (ADR-0032) — la app siempre está
  /// autenticada, así que no monta WebView de CAPTCHA. El header Origin es
  /// obligatorio (el endpoint falla cerrado; somos nuestro propio cliente de
  /// confianza).
  /// `imageDataUrl` / `imageDataUrl2` (data URL base64, máx 8 MB c/u) son el
  /// contrato multimodal de la web: el cliente los manda en CADA POST y el
  /// servidor decide a qué mensaje del historial adjuntarlos
  /// (`chat-stream.ts` L408). El modelo ve la foto.
  Future<AiTurn> sendTurn({
    required List<AiMessage> messages,
    String? kind, // 'producto' | 'servicio'
    bool wholesale = false,
    String? accessToken,
    String? imageDataUrl,
    String? imageDataUrl2,
  }) async {
    final res = await _http.post(
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
        'imageDataUrl': ?imageDataUrl,
        'imageDataUrl2': ?imageDataUrl2,
      }),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw AiHttpException(res.statusCode, body['error']?.toString() ?? 'Error');
    }
    return parseAiTurn(body);
  }
}
