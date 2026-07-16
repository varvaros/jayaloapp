import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'config.dart';

class TurnstileException implements Exception {
  TurnstileException(this.message);
  final String message;
  @override
  String toString() => 'TurnstileException: $message';
}

// Sin SRI a propósito: api.js de Turnstile es un script rotativo que Cloudflare
// actualiza sin aviso; un hash integrity pineado rompería el widget. Mismo modo
// de carga que usa la web de Jayalo (TurnstileWidget.tsx).
String _html() => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTsLoad" async defer></script>
</head><body><div id="ts"></div><script>
function onTsLoad(){
  turnstile.render('#ts',{
    sitekey:'${AppConfig.turnstileSiteKey}',
    callback:function(t){TokenChannel.postMessage(t);},
    'error-callback':function(c){TokenChannel.postMessage('ERROR:'+c);}
  });
}
</script></body></html>''';

/// Obtiene un token Turnstile sin mostrar nada al usuario (~1s). El HTML se
/// carga con baseUrl jayalo.com para que el hostname pase la validación del
/// widget (gotcha 110200). Única pieza WebView permitida en la app (plomería,
/// spec §7 opción a).
Future<String> getTurnstileToken(BuildContext context) {
  final completer = Completer<String>();
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;

  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('TokenChannel', onMessageReceived: (msg) {
      if (completer.isCompleted) return;
      final v = msg.message;
      if (v.startsWith('ERROR:')) {
        completer.completeError(TurnstileException('widget ${v.substring(6)}'));
      } else {
        completer.complete(v);
      }
    })
    ..loadHtmlString(_html(), baseUrl: AppConfig.siteUrl);

  entry = OverlayEntry(
    builder: (_) => Offstage(
      offstage: true,
      child: SizedBox(width: 1, height: 1, child: WebViewWidget(controller: controller)),
    ),
  );
  overlay.insert(entry);

  return completer.future
      .timeout(const Duration(seconds: 25),
          onTimeout: () => throw TurnstileException('timeout'))
      .whenComplete(entry.remove);
}
