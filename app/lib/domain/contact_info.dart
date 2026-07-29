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

// Los separadores que se eliminan (espeja `SEPARADORES` del TS): espacio,
// punto, guion ASCII, parentesis, espacio duro, coma y la familia de guiones
// Unicode. NUNCA letras -- ver el comentario en [containsContactInfo]. `/` y
// `_` NO entran a proposito (fusionarian numeros legitimos: "pieza
// 809/5551234") -- decision aparte.
final RegExp _separadores = RegExp('[ .\\-()$_nbsp,$_guionesUnicode]');
final RegExp _telRd = RegExp(r'(\+?1)?(809|829|849)[0-9]{7}');
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
