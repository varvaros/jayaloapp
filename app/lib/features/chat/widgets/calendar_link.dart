import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el enlace «añadir a Google Calendar» de una fecha pautada.
///
/// Vive en su propio fichero a propósito: `no_link_out_test.dart` mantiene una
/// lista blanca de los ficheros que pueden sacar al usuario al navegador, y
/// meter `launchUrl` dentro de `chat_screen.dart` habría metido en esa lista la
/// pantalla más grande del chat — cualquier salida futura escondida ahí pasaría
/// desapercibida. El destino es `calendar.google.com/calendar/render` (plantilla
/// de evento, sin token de sesión y sin ninguna vía de pago), así que va con
/// `externalApplication`: es lo que deja que se lo quede la app de Google
/// Calendar si está instalada.
///
/// `launchUrl` puede lanzar si nada sabe manejar el enlace; se captura para no
/// dejar una excepción suelta en un `onTap` y se avisa con el mismo SnackBar
/// que usa el resto del chat.
Future<void> openCalendarLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('No se pudo abrir el calendario')),
  );
}
