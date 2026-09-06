/// URLs de imagen servidas por el TRANSFORMADOR de Supabase Storage.
///
/// Gemelo en Dart de `src/lib/imageUrl.ts` de la web, con los mismos casos de
/// prueba uno a uno (`test/image_url_test.dart`), igual que se hizo con
/// `contact_info`. Las dos superficies piden las fotos al mismo servidor: si
/// una reescribe la URL distinto que la otra, tenemos dos comportamientos
/// bajo un solo nombre.
///
/// Problema que resuelve (auditoria 2026-09-02): la app ya acotaba la
/// DECODIFICACION al tamano real en pantalla (`ResizeImage` en
/// `network_image.dart`), pero seguia DESCARGANDO el fichero entero para luego
/// encogerlo en el telefono. Lo que se ahorraba era RAM, no datos moviles.
/// Medido contra produccion sobre un objeto real:
///
///   object/public              image/jpeg   526.720 B
///   render/image ?width=40     image/webp    11.332 B    46x menos
///
/// FORMATO: no se pide ninguno. El transformador mira la cabecera `Accept` y
/// devuelve WebP, que Android decodifica de forma nativa. AVIF todavia no esta
/// disponible en Supabase.
library;

import 'dart:math' as math;

/// Ruta del objeto crudo, tal como la devuelve `getPublicUrl`.
const _rutaPublica = '/storage/v1/object/public/';

/// Ruta del transformador. Solo sirve buckets PUBLICOS.
const _rutaRender = '/storage/v1/render/image/public/';

/// Techo y suelo DOCUMENTADOS de Supabase (1-2500). Fuera de ese rango la
/// peticion falla, y aqui un fallo es una foto que no aparece en pantalla.
const _anchoMin = 1;
const _anchoMax = 2500;

const _calidadPorDefecto = 80;

int _anchoValido(int width) => math.min(_anchoMax, math.max(_anchoMin, width));

/// Devuelve la URL de esta imagen servida al ancho pedido, o **la misma cadena**
/// si no es una imagen publica de Storage.
///
/// Que las URL ajenas salgan intactas es lo que permite meter esto dentro de
/// `JayaloNetworkImage` sin comprobar de donde sale cada foto: un avatar de
/// Google o una URL firmada de bucket privado siguen funcionando igual que
/// antes. Las firmadas se quedan fuera a proposito: ahi las opciones de
/// transformacion viajan EMBEBIDAS en el token, asi que reescribir la ruta a
/// mano rompe la firma.
String transformedImageUrl(
  String src, {
  required int width,
  int quality = _calidadPorDefecto,
}) {
  if (src.isEmpty) return src;

  final url = Uri.tryParse(src);
  if (url == null || !url.hasScheme) return src;

  final esPublica = url.path.startsWith(_rutaPublica);
  final yaRender = url.path.startsWith(_rutaRender);
  if (!esPublica && !yaRender) return src;

  final path = esPublica
      ? _rutaRender + url.path.substring(_rutaPublica.length)
      : url.path;

  // Se REEMPLAZAN, no se anaden: reescribir una URL ya transformada debe
  // cambiar el ancho, no dejar dos `width` que el servidor resolveria a ciegas.
  //
  // `resize=contain` es OBLIGATORIO: sin el, el transformador aplica su
  // `cover` por defecto y, al no llevar `height`, conserva el alto ORIGINAL y
  // recorta el ancho — devuelve una TIRA vertical, no una miniatura. Medido
  // contra prod el 2026-09-06 (logo 1600x1600 y foto 1200x1600):
  //
  //   ?width=184                 184x1600  (recortada, se veia el logo cortado)
  //   ?width=184&resize=contain  184x184
  //   ?width=470                 470x1600   95.623 B
  //   ?width=470&resize=contain  470x627    23.964 B
  final params = Map<String, String>.from(url.queryParameters)
    ..['width'] = _anchoValido(width).toString()
    ..['quality'] = quality.toString()
    ..['resize'] = 'contain';

  return url.replace(path: path, queryParameters: params).toString();
}
