import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'config.dart';
import 'motion.dart';

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
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTsLoad" async defer></script>
</head><body style="margin:0;display:flex;justify-content:center;align-items:center">
<div id="ts"></div><script>
console.log('turnstile html cargado');
function onTsLoad(){
  console.log('api.js listo, render...');
  turnstile.render('#ts',{
    sitekey:'${AppConfig.turnstileSiteKey}',
    callback:function(t){TokenChannel.postMessage(t);},
    'error-callback':function(c){TokenChannel.postMessage('ERROR:'+c);}
  });
}
</script></body></html>''';

/// Obtiene un token Turnstile mostrando el widget en un bottom sheet pequeño
/// (~1s si Cloudflare no exige interacción; si la exige, el usuario puede
/// tocarlo). El HTML se carga con baseUrl jayalo.com para que el hostname pase
/// la validación del widget (gotcha 110200). Nota: la variante 100% invisible
/// (Offstage 1x1) se probó en device y se CUELGA — Turnstile managed necesita
/// un viewport real. Única pieza WebView permitida en la app.
Future<String> getTurnstileToken(BuildContext context) async {
  final completer = Completer<String>();

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
    ..setNavigationDelegate(NavigationDelegate(
      onWebResourceError: (e) =>
          debugPrint('turnstile: web error ${e.errorCode} ${e.description}'),
    ))
    ..loadHtmlString(_html(), baseUrl: AppConfig.siteUrl);
  unawaited(
      controller.setOnConsoleMessage((m) => debugPrint('turnstile js: ${m.message}')));

  if (!context.mounted) throw TurnstileException('contexto desmontado');
  final nav = Navigator.of(context, rootNavigator: true);
  var sheetOpen = true;
  unawaited(showModalBottomSheet(
    sheetAnimationStyle: JayaloMotion.sheetMenu,
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Verificación de seguridad…'),
          const SizedBox(height: 12),
          SizedBox(height: 100, child: WebViewWidget(controller: controller)),
        ]),
      ),
    ),
  ).whenComplete(() => sheetOpen = false));

  try {
    return await completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () => throw TurnstileException('timeout'));
  } finally {
    if (sheetOpen) nav.pop();
  }
}
