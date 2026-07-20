import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class EditorLinkException implements Exception {
  EditorLinkException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'EditorLinkException($status): $message';
}

/// Pide a la web un magic link de un solo uso que deja la sesión iniciada y
/// redirige a la página de edición del negocio (spec 2026-07-20-mi-tienda).
/// Mismo patrón de llamada que `AiClient`: Origin + Bearer del JWT de sesión.
class EditorLinkClient {
  EditorLinkClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<String> fetchEditorUrl({
    required String businessId,
    required String accessToken,
  }) async {
    final res = await _http.post(
      Uri.parse(AppConfig.editorLinkEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Origin': AppConfig.siteUrl,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'businessId': businessId}),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw EditorLinkException(
          res.statusCode, body['error']?.toString() ?? 'Error');
    }
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw EditorLinkException(res.statusCode, 'Respuesta inválida');
    }
    return url;
  }
}
