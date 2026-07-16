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

  /// Un turno = un POST. El primer turno (messages.length == 1) DEBE llevar
  /// turnstileToken. El header Origin es obligatorio (el endpoint falla
  /// cerrado; somos nuestro propio cliente de confianza).
  Future<AiTurn> sendTurn({
    required List<AiMessage> messages,
    String? kind, // 'producto' | 'servicio'
    bool wholesale = false,
    String? turnstileToken,
  }) async {
    final res = await _http.post(
      Uri.parse(AppConfig.aiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Origin': AppConfig.siteUrl,
      },
      body: jsonEncode({
        'messages': messages.map((m) => m.toJson()).toList(),
        'kind': ?kind,
        if (wholesale) 'wholesale': true,
        'turnstileToken': ?turnstileToken,
      }),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw AiHttpException(res.statusCode, body['error']?.toString() ?? 'Error');
    }
    return parseAiTurn(body);
  }
}
