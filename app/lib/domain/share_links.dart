/// Qué se puede compartir desde la app, y con qué texto.
///
/// Lógica PURA (sin widgets ni Supabase) para poder probar las URLs y el copy
/// sin montar pantalla.
///
/// **Solo se comparte lo que tiene página PÚBLICA en jayalo.com.** Compartir
/// un enlace que el receptor no puede abrir es peor que no ofrecer el botón:
///
/// | Contenido | Página pública | Se comparte |
/// |---|---|---|
/// | Solicitud | `/requests/{id}` | Sí |
/// | Producto o servicio del catálogo | `/products/{id}` | Sí |
/// | **Tienda de un negocio** | `/provider/business/{id}` | **No**: ver abajo |
/// | **Oferta** | ninguna — solo la ve el dueño de la solicitud | **No** |
/// | **Interés de producto** | ninguna — es privado entre las dos partes | **No** |
/// | **Paquete** | vive dentro de la landing del negocio | **No**: se comparte la tienda |
/// | **Perfil / reputación del cliente** | no existe | **No** |
///
/// 🔴 **La TIENDA no se comparte, y no es un olvido.** Su página pública vive
/// en `/provider/business/{id}`, y `test/no_link_out_test.dart` prohíbe que la
/// app construya CUALQUIER URL bajo `/provider`: ese panel de la web lleva dos
/// botones de «Recargar créditos» que abren PayPal, y Play prohíbe el link-out
/// a un método de pago ajeno —también insinuarlo—. Un solo call site
/// reintroducido hace el binario no publicable. Compartir la tienda necesita
/// primero una ruta pública FUERA de `/provider` (p. ej. `/negocio/{id}`), que
/// hoy no existe en la web.
///
/// ⚠️ Estos enlaces abren en el NAVEGADOR, no en la app, aunque el receptor la
/// tenga instalada: el único `intent-filter` de la app es `jayalo://wallet`.
/// Para que un `https://jayalo.com/...` abriera la app harían falta App Links
/// verificados, y eso exige publicar `/.well-known/assetlinks.json` con el
/// SHA-256 de Play App Signing (que todavía no existe: no hay cuenta de Play
/// Console). Mientras tanto, compartir lleva tráfico a la web, que es donde el
/// enlace sí funciona.
library;

import '../core/config.dart';

/// Un enlace listo para la hoja de compartir del sistema.
class ShareContent {
  const ShareContent({required this.url, required this.text});

  /// La URL canónica en jayalo.com.
  final String url;

  /// Lo que viaja a la hoja de compartir. Incluye la URL al final: Android
  /// manda UN solo texto, y los mensajeros enlazan la que encuentran dentro.
  final String text;
}

/// Corta el título para que el mensaje no sea un muro. Colapsa los saltos de
/// línea y los espacios repetidos que traen los títulos escritos por la IA.
String _oneLine(String raw, {int max = 80}) {
  final clean = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max - 1).trimRight()}…';
}

/// `null` cuando falta el id: sin id no hay URL, y el botón se esconde en vez
/// de compartir un enlace roto.
ShareContent? shareForRequest({required String? id, required String title}) {
  if (id == null || id.isEmpty) return null;
  final url = '${AppConfig.siteUrl}/requests/$id';
  final head = _oneLine(title);
  final intro = head.isEmpty ? 'Mira esta solicitud' : head;
  return ShareContent(
    url: url,
    text: '$intro\n\nMira esta solicitud en Jayalo y haz tu oferta:\n$url',
  );
}

ShareContent? shareForProduct({required String? id, required String name}) {
  if (id == null || id.isEmpty) return null;
  final url = '${AppConfig.siteUrl}/products/$id';
  final head = _oneLine(name);
  final intro = head.isEmpty ? 'Mira esto' : head;
  return ShareContent(url: url, text: '$intro\n\nMíralo en Jayalo:\n$url');
}
