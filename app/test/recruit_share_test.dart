import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/error_reporter.dart';
import 'package:jayalo_app/domain/request_share_message.dart';
import 'package:jayalo_app/features/admin/recruit_share.dart';

const _r = ShareableRequest(
  id: 'r1',
  title: 'Silla de caoba',
  zone: 'Piantini',
  description: null,
  budgetMin: null,
  budgetMax: null,
  urgency: null,
  kind: 'product',
);

void main() {
  test('abre WhatsApp con el mensaje y NO usa la hoja del sistema', () async {
    Uri? abierta;
    var hojas = 0;
    await compartirSolicitud(_r,
        abrir: (u) async {
          abierta = u;
          return true;
        },
        hoja: (_) async => hojas++);
    expect(abierta!.origin, 'https://wa.me');
    expect(abierta!.queryParameters['text'], buildRequestShareText(_r));
    expect(hojas, 0);
  });

  test('si WhatsApp no abre, cae a la hoja del sistema con el MISMO texto',
      () async {
    String? texto;
    await compartirSolicitud(_r,
        abrir: (_) async => false, hoja: (t) async => texto = t);
    expect(texto, buildRequestShareText(_r));
  });

  test('si launchUrl LANZA, tambien cae a la hoja (no se pierde el toque)',
      () async {
    String? texto;
    await compartirSolicitud(_r,
        abrir: (_) async => throw Exception('sin WhatsApp'),
        hoja: (t) async => texto = t);
    expect(texto, buildRequestShareText(_r));
  });

  test('si los dos fallan, avisa, reporta y no lanza', () async {
    String? aviso;
    Object? reportado;
    debugOnReport = (e) => reportado = e;
    addTearDown(() => debugOnReport = null);

    await compartirSolicitud(_r,
        abrir: (_) async => false,
        hoja: (_) async => throw Exception('nada'),
        aviso: (m) => aviso = m);

    expect(aviso, 'No se pudo abrir WhatsApp');
    expect(reportado, isA<Exception>(),
        reason: 'un `catch (_) {}` mudo dejaba este fallo total sin rastro '
            'en error_events aunque nadie enganche `aviso`');
  });
}
