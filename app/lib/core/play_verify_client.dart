import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Fallo al verificar una compra de Play.
///
/// [retryable] separa "vuelve a intentarlo luego" (red, Google caído, sesión
/// vencida) de "esta compra no va a acreditar nunca" (no está pagada). Importa
/// para dos cosas: el copy (al usuario que ya pagó JAMÁS se le dice que el pago
/// falló) y, sobre todo, si se CONSUME la compra en Play. Consumir una compra
/// que sí estaba pagada pierde el crédito para siempre.
///
/// ⚠️ El valor lo decide el SERVIDOR y viaja en el cuerpo — no se deriva del
/// status HTTP. La tabla de contrato de `src/routes/api/app/play-verify.ts`
/// asigna a propósito el mismo status a casos con distinta reintentabilidad
/// (502 = Google caído → reintentar; 502 = Google dice que el token no existe →
/// terminal) y, al revés, marca reintentables varios 4xx (401 de sesión
/// vencida, 403 de Origin, 429). Derivarlo del status descartaría el token de
/// una compra ya cobrada en cuanto al usuario se le venza la sesión.
class PlayVerifyException implements Exception {
  PlayVerifyException(this.status, this.message, {required this.retryable});

  final int status;
  final String message;
  final bool retryable;

  @override
  String toString() =>
      'PlayVerifyException($status, retryable: $retryable): $message';
}

class PlayVerifyResult {
  const PlayVerifyResult({
    required this.balance,
    required this.points,
    required this.credited,
  });

  final int balance;
  final int points;

  /// false = el servidor ya había acreditado este token (reintento). No es un
  /// error: el saldo devuelto sigue siendo el bueno.
  final bool credited;
}

/// Manda el `purchaseToken` al servidor, que es quien decide si acredita.
/// Mismo patrón que `AccountDeletionClient`: Origin + Bearer del JWT.
class PlayVerifyClient {
  PlayVerifyClient({http.Client? inner, Duration? timeout})
      : _http = inner ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 20);
  final http.Client _http;

  /// Sin esto, una conexión colgada dejaba la verificación en vuelo para
  /// siempre: el token quedaba retenido en el dedup del servicio sin emitir
  /// evento, y la compra no se reintentaba hasta reiniciar la app.
  final Duration _timeout;

  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse(AppConfig.playVerifyEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Origin': AppConfig.siteUrl,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(
                {'purchaseToken': purchaseToken, 'productId': productId}),
          )
          .timeout(_timeout);
    } catch (e) {
      // Sin red o expirado: reintentable por definición. La respuesta nunca
      // llegó, así que el purchaseToken sigue tan vivo como antes.
      throw PlayVerifyException(0, e.toString(), retryable: true);
    }

    Map<String, dynamic>? body;
    try {
      // `allowMalformed` a propósito: un byte mal codificado en el TEXTO del
      // mensaje (todos llevan tildes) no puede costarnos el veredicto
      // `retryable`, que es puro ASCII y decide si se conserva el token de una
      // compra pagada. Los bytes rotos se vuelven U+FFFD y el JSON se parsea.
      body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))
          as Map<String, dynamic>;
    } catch (_) {
      // Cuerpo ilegible (un 502 en HTML del proxy, un 500 sin JSON del
      // framework…): no sabemos nada del estado de la compra, así que se
      // CONSERVA el token. Nunca descartar por no poder leer la respuesta.
      throw PlayVerifyException(res.statusCode, 'Respuesta inválida',
          retryable: true);
    }

    if (res.statusCode != 200) {
      throw PlayVerifyException(
        res.statusCode,
        body['error']?.toString() ?? 'Error',
        // Ausente sólo puede significar que la respuesta no la generó nuestro
        // handler (que siempre lo emite). Se asume reintentable: conservar un
        // token muerto cuesta un reintento inútil; descartar uno pagado cuesta
        // el dinero del usuario.
        retryable: body['retryable'] is bool ? body['retryable'] as bool : true,
      );
    }

    try {
      return PlayVerifyResult(
        balance: (body['balance'] as num?)?.toInt() ?? 0,
        points: (body['points'] as num?)?.toInt() ?? 0,
        credited: body['credited'] == true,
      );
    } catch (_) {
      // Un 200 que no cumple el contrato (balance como string…) es tan
      // ilegible como un cuerpo roto: el contrato de esta clase es lanzar
      // SOLO PlayVerifyException, y ante lo ilegible se CONSERVA el token.
      throw PlayVerifyException(200, 'Respuesta inválida', retryable: true);
    }
  }
}
