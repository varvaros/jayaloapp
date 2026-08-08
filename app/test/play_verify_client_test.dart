import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo_app/core/config.dart';
import 'package:jayalo_app/core/play_verify_client.dart';

/// Los casos de abajo espejan la TABLA DE CONTRATO de
/// `src/routes/api/app/play-verify.ts`. Si esa tabla cambia, estos tests son el
/// sitio donde tiene que notarse.
void main() {
  /// `Response.bytes` + `utf8.encode` a propósito: el constructor de `Response`
  /// que toma un String codifica en latin-1 si no hay charset en la cabecera,
  /// y entonces el fixture no se parecería a lo que manda el servidor de
  /// verdad (JSON en UTF-8). Los mensajes llevan tildes, así que la diferencia
  /// no es teórica.
  PlayVerifyClient clientReturning(String body, int status) => PlayVerifyClient(
      inner: MockClient((_) async => http.Response.bytes(utf8.encode(body), status)));

  test('manda Origin y Bearer, y devuelve el balance', () async {
    late http.Request seen;
    final client = PlayVerifyClient(inner: MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode(
            {'balance': 65, 'points': 55, 'credited': true, 'retryable': false}),
        200,
      );
    }));

    final res = await client.verify(
        accessToken: 'JWT', purchaseToken: 'TOK', productId: 'creditos_50usd');

    expect(res.balance, 65);
    expect(res.points, 55);
    expect(res.credited, isTrue);
    expect(seen.headers['Authorization'], 'Bearer JWT');
    expect(seen.headers['Origin'], AppConfig.siteUrl);
    expect(jsonDecode(seen.body),
        {'purchaseToken': 'TOK', 'productId': 'creditos_50usd'});
  });

  test('credited=false (reintento del mismo token) NO es un error', () async {
    final client = clientReturning(
        jsonEncode(
            {'balance': 65, 'points': 0, 'credited': false, 'retryable': false}),
        200);

    final res = await client.verify(
        accessToken: 'JWT', purchaseToken: 'TOK', productId: 'creditos_50usd');

    expect(res.credited, isFalse);
    expect(res.balance, 65);
  });

  test('un 502 con retryable:true (Google caído) es reintentable', () async {
    final client = clientReturning(
        jsonEncode({
          'error': 'No se pudo confirmar el pago todavía',
          'retryable': true,
          'balance': 0,
          'points': 0,
          'credited': false,
        }),
        502);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  // El caso que la derivación por status HTTP se come: mismo 502, decisión
  // opuesta. Google dice que el token no existe -> no hay nada que reintentar.
  test('un 502 con retryable:false (token inexistente) NO es reintentable',
      () async {
    final client = clientReturning(
        jsonEncode({
          'error': 'No se pudo confirmar el pago todavía',
          'retryable': false,
          'balance': 0,
          'points': 0,
          'credited': false,
        }),
        502);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isFalse)),
    );
  });

  test('un 409 (compra no completada) NO es reintentable', () async {
    final client = clientReturning(
        jsonEncode({'error': 'purchase_not_completed', 'retryable': false}), 409);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isFalse)),
    );
  });

  // El fallo caro: sesión vencida sobre una compra YA PAGADA. Por status, 401
  // parece terminal; el servidor dice que no lo es.
  test('un 401 (sesión vencida) SÍ es reintentable — el token sigue vivo',
      () async {
    final client = clientReturning(
        jsonEncode({'error': 'No autenticado', 'retryable': true}), 401);

    await expectLater(
      client.verify(
          accessToken: 'VIEJO', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  test('un 202 (pago diferido pendiente en Google) es reintentable', () async {
    final client = clientReturning(
        jsonEncode({'error': 'purchase_pending', 'retryable': true}), 202);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  test('sin campo retryable se asume reintentable (nunca descartar un pago)',
      () async {
    final client = clientReturning(jsonEncode({'error': 'lo que sea'}), 500);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  // Un byte mal codificado en el texto NO puede cambiar la decisión sobre el
  // dinero: `retryable` es ASCII y tiene que leerse igual.
  test('un cuerpo con bytes mal codificados conserva el veredicto del servidor',
      () async {
    final json = jsonEncode({
      'error': 'No se pudo confirmar el pago todavía',
      'retryable': false,
    });
    final client = PlayVerifyClient(
        inner: MockClient((_) async =>
            // latin-1: la 'í' queda como 0xED, que no es UTF-8 válido.
            http.Response.bytes(latin1.encode(json), 502)));

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isFalse)),
    );
  });

  test('una respuesta que no es JSON no revienta con FormatException', () async {
    final client = clientReturning('<html>502 Bad Gateway</html>', 502);

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  test('un fallo de red es reintentable y no trae status', () async {
    final client = PlayVerifyClient(
        inner: MockClient((_) async => throw http.ClientException('sin red')));

    await expectLater(
      client.verify(
          accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
          .having((e) => e.status, 'status', 0)
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });
}
