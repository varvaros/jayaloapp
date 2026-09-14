import 'dart:async';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error_reporter.dart';
import '../../domain/request_share_message.dart';

/// Ofrecer una solicitud por WhatsApp.
///
/// `wa.me` SIN numero abre el selector de contactos de WhatsApp, que es lo que
/// se quiere: el proveedor todavia no esta en Jayalo y su numero lo tiene el
/// admin en su agenda. Mismo camino que `features/provider/unlock_flow.dart`.
///
/// Los tres huecos se inyectan para poder probarlo sin abrir nada.
Future<void> compartirSolicitud(
  ShareableRequest r, {
  Future<bool> Function(Uri)? abrir,
  Future<void> Function(String)? hoja,
  void Function(String)? aviso,
}) async {
  final abrirFn = abrir ??
      (u) => launchUrl(u, mode: LaunchMode.externalApplication);
  final hojaFn = hoja ??
      (t) => SharePlus.instance.share(ShareParams(text: t)).then((_) {});

  final texto = buildRequestShareText(r);

  try {
    if (await abrirFn(whatsappShareUri(r))) return;
  } catch (_) {
    // Sin WhatsApp instalado, o el sistema rechaza el intent: se intenta la
    // hoja antes de rendirse.
  }

  try {
    await hojaFn(texto);
  } catch (e, st) {
    // A diferencia del catch de arriba, este SÍ se reporta: no tener
    // WhatsApp es esperable, pero que falle también la hoja del sistema no
    // lo es, y un `catch (_) {}` aquí dejaba ese fallo sin rastro en
    // `error_events` aunque nadie enganche `aviso`.
    unawaited(reportError(e, st));
    aviso?.call('No se pudo abrir WhatsApp');
  }
}
