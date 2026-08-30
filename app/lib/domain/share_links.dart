import '../core/config.dart';

/// Los enlaces públicos que la app puede compartir, y el texto que los
/// acompaña (pedido PO 2026-08-30: "debe haber un botón de compartir" en las
/// ofertas, las solicitudes, las de otros usuarios, los productos del catálogo
/// y la tienda).
///
/// Se comparte SIEMPRE la página de la WEB, no un deep link de la app: quien
/// recibe el enlace casi nunca tiene Jayalo instalado, y esas tres páginas ya
/// son públicas y traen su propia tarjeta OG. Espeja `src/lib/share.ts` de la
/// web — si una ruta cambia, cambian las dos.
///
/// Vive en `domain/` y no en el widget para poder probar los textos sin montar
/// pantalla.
abstract final class ShareLinks {
  static String request(String id) => '${AppConfig.siteUrl}/requests/$id';
  static String product(String id) => '${AppConfig.siteUrl}/products/$id';

  // 🔴 NO hay `business(id)` A PROPOSITO. La tienda vive en la web bajo
  // `/provider/business/<id>`, y `test/no_link_out_test.dart` prohibe que la
  // app construya NINGUNA ruta `/provider` de jayalo.com: esa zona pinta la
  // barra con «Mis créditos» → PayPal, que es link-out prohibido por Play. Por
  // eso el editor de negocio se abre con `?embed=app`.
  //
  // Compartir la tienda desde la app queda BLOQUEADO hasta que entre el PR
  // `claude/tienda-compartible-sin-pago` («la landing pública del negocio va
  // sin vías de pago»), que existe justo para esto. El guardia NO se toca.

  /// 🔴 `ShareParams` NO admite `text` y `uri` a la vez — la documentación del
  /// paquete es explícita ("Cannot be used in combination with [text]") y el
  /// plugin usa uno U otro. Así que el enlace viaja DENTRO del texto, en su
  /// propia línea: es lo que WhatsApp y el resto convierten en tarjeta.
  static String mensaje(String texto, String url) => '$texto\n$url';

  static String requestText(String? title) =>
      'Esta solicitud en Jayalo podría interesarte: "${_limpio(title)}"';

  static String productText(String? name) =>
      'Mira esto en Jayalo: "${_limpio(name)}"';

  /// Un título vacío o de solo espacios dejaría comillas huérfanas («…: ""»).
  /// Se recorta y se acepta el vacío: el enlace vale igual.
  static String _limpio(String? s) => (s ?? '').trim();
}
