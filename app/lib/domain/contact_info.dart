/// Deteccion de datos de contacto en texto publico (anti-elusion, PO
/// 2026-07-29).
///
/// Espejo en Dart de `public.contains_contact_info(text)` (migracion
/// `20260729100000_contact_info_guard.sql`) y de `src/lib/contactInfo.ts`
/// (web, Task 3 del mismo plan). La que MANDA es la de la BASE DE DATOS: esta
/// copia existe solo para avisar en el formulario ANTES de enviar y no hacer
/// perder lo escrito. Si las tres discrepan, la BD gana y el usuario ve un
/// error tardio (traducido por [isContactInfoError]) -- por eso las tres se
/// prueban con la MISMA bateria de 14 casos (ver `test/contact_info_test.dart`
/// y el plan en jayalo-main).
library;

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// SQLSTATE con el que el trigger `enforce_no_contact_info` rechaza la fila.
/// Espeja el patron de `chatRateLimitCode` (JY429, anti-flood) de
/// `domain/chat.dart:70`.
const String contactInfoCode = 'JY422';

const String contactInfoMessage =
    'No incluyas teléfonos ni correos aquí. El contacto se comparte cuando se concreta el trato.';

/// Espacio duro (NBSP, U+00A0) -- uno de los 7 separadores. Se construye con
/// `String.fromCharCode` (no como caracter literal en el codigo fuente)
/// porque un NBSP pegado entre letras normales es indistinguible a simple
/// vista de un espacio comun y facil de corromper al copiar/pegar.
final String _nbsp = String.fromCharCode(0xA0);

/// Familia de guiones Unicode U+2010..U+2015 (como rango para la clase) y el
/// signo menos U+2212. Se construyen con `String.fromCharCode` por la misma
/// razon que [_nbsp]: un guion largo entre digitos es indistinguible del `-`
/// ASCII a simple vista, y el copiar/pegar y el autocorrector lo meten solos
/// -- `809<U+2013>555<U+2013>1234` pasaba las tres implementaciones.
final String _guionesUnicode =
    '${String.fromCharCode(0x2010)}-${String.fromCharCode(0x2015)}'
    '${String.fromCharCode(0x2212)}';

// Los separadores que se eliminan (espeja `SEPARADORES` del TS): punto, guion
// ASCII, parentesis, espacio duro, coma y la familia de guiones Unicode.
// NUNCA letras -- ver el comentario en [containsContactInfo].
//
// ⚠️ v2 (2026-08-14): el ESPACIO ya NO se elimina. Es el nucleo del arreglo, y
// es un cambio de UN caracter facil de pasar por alto en una revision: si
// alguien devuelve el espacio a esta clase, la app deja de bloquear
// "8 0 9 5 5 5 1 2 3 4" mientras la BD si lo bloquea, y el usuario pierde lo
// escrito. Hay un test que lo afirma explicitamente.
/// Los 6 INVISIBLES que hay que borrar por PARIDAD, no por estetica: son
/// exactamente los codepoints en los que `\s` de Dart/ECMAScript y
/// `[[:space:]]` de glibc NO coinciden (glibc incluye 1C..1F y 0085 pero NO
/// FEFF; Dart al reves). Sin borrarlos, `809 + U+FEFF + 8675309` lo BLOQUEABA el
/// SQL y lo dejaban pasar TS y Dart -- la divergencia en la PEOR direccion: el
/// formulario acepta, la BD rechaza y el usuario pierde lo escrito despues de
/// subir fotos. Y un BOM se cuela solo al pegar desde Word.
final String _invisibles = '${String.fromCharCode(0xFEFF)}'
    '${String.fromCharCode(0x85)}'
    '${String.fromCharCode(0x1C)}-${String.fromCharCode(0x1F)}';

final RegExp _separadores =
    RegExp('[.\\-()$_nbsp,$_guionesUnicode$_invisibles]');

/// HUECO admitido entre dos digitos del telefono (espeja `HUECO` del TS y el
/// `replace(..., 'H', ...)` de la migracion). Existe porque "809 x 1234567"
/// (medida legitima) y "809x8675309" (evasion) son la MISMA forma. Al dejar de
/// borrar el espacio, la diferencia aparece sola: el caracter de una evasion va
/// PEGADO, el de una medida va ESPACIADO.
///   1) `[ \t]+` espacios/tabs, NUNCA salto de linea (frontera dura: sin eso,
///      las viñetas y listas numeradas que compone la MAQUINA se fusionaban).
///      Sin esta rama se cae "8 0 9 5 5 5 1 2 3 4".
///   2) `[^0-9\s]+` basura PEGADA. Es el ticket. Con `+` porque un emoji con
///      tono de piel son DOS code points.
///   3) simbolo de teclado telefonico entre espacios (lista BLANCA: admitir
///      cualquiera devolveria el falso positivo de las viñetas).
const String _hueco = r'(?:[ \t]+|[^0-9\s]+|[ \t]*[*/#:;_+][ \t]*)?';

/// El hueco cubre CADA par de digitos, incluido el prefijo: si solo cubriera los
/// 7 finales, "8 0 9 5 5 5 1 2 3 4" se escaparia -- una regresion.
/// `unicode: true` es OBLIGATORIO: sin el, un emoji fuera del BMP se parte en
/// dos unidades UTF-16 y el veredicto diverge del servidor.
final RegExp _telRd = RegExp(
  '(?:\\+?1$_hueco)?8$_hueco(?:0|2|4)$_hueco'
  '9(?:$_hueco[0-9]){7}',
  unicode: true,
);
final RegExp _whatsapp = RegExp(
  r'(wa\.me/|api\.whatsapp\.com|chat\.whatsapp\.com)',
  caseSensitive: false,
);
// `[\p{L}\p{N}]` (con `unicode: true`) en vez de `[a-z0-9]`, para espejar el
// `[[:alnum:]]` del SQL: con el lc_ctype UTF-8 de Supabase esa clase POSIX SI
// casa letras acentuadas, asi que la regla ASCII dejaba pasar un correo con
// tilde (jose@..., ...ferreteria.do con tilde) en el formulario para que la BD
// lo rechazara despues -- el usuario perdia lo escrito. Con nombres
// dominicanos (Jose, Maria, Ramon, Andres) no es un caso de laboratorio.
final RegExp _correo = RegExp(
  r'[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.\p{L}{2,}',
  caseSensitive: false,
  unicode: true,
);

/// Digitos de ancho completo (fullwidth 0-9) -> ASCII.
String _aAscii(String v) => v.replaceAllMapped(
      RegExp('[０-９]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFF10 + 0x30),
    );

/// Este texto contiene un telefono dominicano, un enlace de WhatsApp o un
/// correo? Se eliminan SOLO separadores (espacio, punto, guion, parentesis,
/// espacio duro, coma), NUNCA letras: quitar todo lo no-digito convertiria
/// "modelo 809, pieza 5551234" en un falso positivo.
bool containsContactInfo(String? value) {
  if (value == null || value.isEmpty) return false;
  final normalizado = _aAscii(value).replaceAll(_separadores, '');
  return _telRd.hasMatch(normalizado) ||
      _whatsapp.hasMatch(value) ||
      _correo.hasMatch(value);
}

/// Un valor que ES una URL no es texto redactado por el usuario: es una ruta de
/// Storage o un data URI de una foto sin subir. NINGUNA columna vigilada por el
/// trigger es una URL, asi que saltarlas no pierde cobertura -- y NO saltarlas
/// da falsos positivos duros: la ruta lleva un `Date.now()` de 13 digitos y,
/// como `-` y `.` son separadores que se eliminan, el timestamp queda como un
/// bloque de digitos contiguo. Entre 2027-04-30 y 2027-05-10 (y otra vez del
/// 2027-12-17 al 2027-12-28) empieza por 1829.../1849..., asi que TODO envio con
/// foto casaria `(809|829|849)[0-9]{7}`.
///
/// La regla de WhatsApp SI se aplica sobre URLs: es la unica de las tres que
/// apunta a enlaces a proposito. Espeja `valorTieneContacto` de la web.
final RegExp _esUrl = RegExp(r'^(https?:|data:)', caseSensitive: false);

bool _valorTieneContacto(String v) {
  if (_esUrl.hasMatch(v.trimLeft())) return _whatsapp.hasMatch(v);
  return containsContactInfo(v);
}

/// Barre TODO el payload que va a la BD (strings y listas de strings) buscando
/// datos de contacto. Espejo de `payloadHasContactInfo` de la web.
///
/// Por que existe: la app venia manteniendo A MANO cuatro listas de campos a
/// revisar, mientras la web recorria el payload entero "asi no se desincroniza".
/// La logica de deteccion estaba en paridad exacta; lo que divergia era la
/// COBERTURA. Al sumar una columna vigilada nueva, el usuario de la app escribia,
/// subia fotos, enviaba, y recien ahi recibia un JY422 -- perdiendo trabajo real.
/// Con esto ningun campo del payload puede quedarse fuera por olvido.
bool payloadHasContactInfo(Map<String, dynamic> payload) {
  for (final v in payload.values) {
    if (v is String) {
      if (_valorTieneContacto(v)) return true;
    } else if (v is List) {
      for (final el in v) {
        if (el is String && _valorTieneContacto(el)) return true;
      }
    }
  }
  return false;
}

/// Este error de Supabase es el rechazo del trigger anti-elusion? Espeja la
/// forma exacta en que `chat_screen.dart` lee el codigo de un
/// PostgrestException para el JY429 del anti-flood (`e is PostgrestException
/// ? e.code : null`). Un JY500 (error de PROGRAMACION nuestro -- ver la
/// migracion: una columna renombrada que esta regla ya no encuentra) tiene un
/// codigo distinto y por eso da `false` aqui: no debe traducirse al mensaje
/// humano de [contactInfoMessage], que hablaria de "telefonos y correos"
/// sobre un bug que no tiene nada que ver con eso.
bool isContactInfoError(Object error) =>
    error is PostgrestException && error.code == contactInfoCode;
