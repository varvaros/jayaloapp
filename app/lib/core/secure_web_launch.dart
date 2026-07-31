import 'package:url_launcher/url_launcher.dart';

/// Abre en el navegador un URL que LLEVA UN TOKEN de sesión (magic link de
/// billetera, magic link del editor de negocio).
///
/// ⚠️ NUNCA con `LaunchMode.externalApplication` para estos URLs. Ese modo es un
/// `Intent.ACTION_VIEW` PÚBLICO: cualquier app instalada que declare un
/// intent-filter para el dominio entra en el selector y puede quedarse con el
/// link. Y como por decisión documentada del proyecto NO se usa PKCE (rompe los
/// magic links — ver el gotcha "PKCE rompe magic links"), quien posea ese link
/// lo canjea por una SESIÓN COMPLETA del usuario.
///
/// `inAppBrowserView` es Custom Tabs en Android: mismo motor y las MISMAS
/// cookies que el navegador del usuario (el magic link necesita esa sesión para
/// no pedir un segundo login), pero el URL viaja al navegador por binder y no
/// por un intent que cualquiera pueda interceptar. Tampoco es el WebView que se
/// quemó con MIUI (ADR-0032): sigue siendo el navegador de verdad.
///
/// Fallback consciente: si no hay navegador con soporte de Custom Tabs se
/// reintenta al modo anterior. Es un caso raro y la alternativa es dejar al
/// proveedor sin poder recargar; el residual queda anotado aquí a propósito.
Future<bool> launchAuthenticatedUrl(Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.inAppBrowserView)) return true;
  } catch (_) {
    // Sigue al fallback.
  }
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
