import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Fallo al eliminar la cuenta. `reauthRequired` es el caso que la UI trata
/// distinto: no es un error, es "vuelve a iniciar sesión y repite".
class DeleteAccountException implements Exception {
  DeleteAccountException(this.status, this.message);
  final int status;
  final String message;

  /// El servidor exige identidad probada hace <5 min (la RPC
  /// `anonymize_my_account` espeja REAUTH_WINDOW_MS de la web). Una sesión
  /// abierta y olvidada NO basta para borrar la cuenta.
  bool get reauthRequired => message == 'reauth_required';

  @override
  String toString() => 'DeleteAccountException($status): $message';
}

class DeleteAccountResult {
  const DeleteAccountResult({
    required this.alreadyDeleted,
    required this.creditsForfeited,
  });
  final bool alreadyDeleted;
  final int creditsForfeited;
}

/// Elimina la cuenta del usuario (requisito de Google Play).
///
/// Mismo patrón de llamada que `EditorLinkClient`: Origin + Bearer del JWT de
/// sesión. El borrado real lo hace la RPC `anonymize_my_account()` en la BD;
/// el endpoint además purga los ficheros de Storage del usuario.
class AccountDeletionClient {
  AccountDeletionClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<DeleteAccountResult> deleteAccount({
    required String accessToken,
  }) async {
    final res = await _http.post(
      Uri.parse(AppConfig.deleteAccountEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Origin': AppConfig.siteUrl,
        'Authorization': 'Bearer $accessToken',
      },
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw DeleteAccountException(res.statusCode, 'Respuesta inválida');
    }

    if (res.statusCode != 200) {
      throw DeleteAccountException(
          res.statusCode, body['error']?.toString() ?? 'Error');
    }

    return DeleteAccountResult(
      alreadyDeleted: body['alreadyDeleted'] == true,
      creditsForfeited: (body['creditsForfeited'] as num?)?.toInt() ?? 0,
    );
  }
}
