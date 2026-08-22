/// Duración de una oferta de servicio: número + unidad.
///
/// Espejo Dart de `src/lib/offerDuration.ts` del repo web. Si tocas una, toca
/// la otra: las dos plataformas escriben en la MISMA columna y tienen que
/// componer y leer exactamente lo mismo.
///
/// POR QUÉ EXISTE. La duración se guarda en `provider_offers.estimated_duration`,
/// que es UNA columna `text NOT NULL DEFAULT ''`. Se sigue guardando la etiqueta
/// compuesta (`"3 días"`) y NO se parte en dos columnas a propósito: añadir
/// claves nuevas al payload obligaría a migrar antes de desplegar, porque
/// PostgREST **rechaza la petición entera** si una clave no tiene GRANT — es la
/// lección de `includes_materials`, donde ordenar mal deja a todos los
/// proveedores sin poder ofertar. Con una sola columna, web y app se despliegan
/// en cualquier orden y conviven.
///
/// DOS REGLAS QUE NO SE PUEDEN ROMPER:
///
/// 1. **Ninguna etiqueta de unidad puede contener `" · "`** (espacio, punto
///    medio, espacio). El mensaje de la oferta se compone uniendo partes con ese
///    separador y `freeTextFromOfferMessage` lo usa para partirlo. Medido: un
///    valor con `" · "` dentro parte la línea en dos y el cliente ve texto
///    duplicado. Un `:` dentro del valor, en cambio, es INOFENSIVO (el lector
///    corta en el PRIMER `": "`, así que la etiqueta sigue siendo `Duración`).
///
/// 2. **Tope de 3 dígitos.** No es cosmético. El campo era texto libre y admitía
///    letras; con números sin tope volvería a ser una caja de dígitos
///    arbitraria. El anti-elusión detecta el teléfono dominicano completo
///    (809/829/849 + 7), pero **NO puede ver un número local de 7 dígitos** como
///    `5551234` — siete dígitos sueltos son indistinguibles de un precio, y
///    nunca serán detectables. Con 3 dígitos el campo es incapaz de transportar
///    un contacto. `999 semanas` son 19 años: sobra para cualquier trabajo real.
///
///    ⚠️ El tope vive en DOS sitios y hacen falta los dos: aquí (que rechaza) y
///    los `inputFormatters` del campo (que impiden teclearlo). Sin los
///    formatters se puede escribir `8095551234`, [formatOfferDuration] devuelve
///    `''` y la duración se pierde EN SILENCIO.
///
///    ALCANCE HONESTO, medido: el tope vive SOLO en el cliente. La columna no
///    tiene `CHECK` ni trigger de forma, y `authenticated` tiene INSERT/UPDATE
///    sobre ella, así que quien llame a PostgREST a mano sigue pudiendo escribir
///    7 dígitos. Es una consecuencia asumida del «sin migración»: esto cierra el
///    camino que usan las personas, no el de un atacante decidido.
///
/// Puro, sin Flutter: se puede probar sin montar una pantalla.
library;

/// Unidades en el orden en que se ofrecen. `minutos` existe porque la lista
/// vieja tenía «30 minutos» y quitarla habría perdido granularidad real
/// (decisión del PO). El orden de declaración ES el orden del desplegable:
/// `OfferDurationUnit.values` se pinta tal cual.
enum OfferDurationUnit { minutos, horas, dias, semanas }

/// Tope de dígitos del input. Ver la regla 2 de la cabecera: es de seguridad.
const int kOfferDurationMaxDigits = 3;

/// Unidad por defecto de un formulario nuevo. Paridad con la web
/// (`RequestRespondSection.tsx`, `useState<OfferDurationUnit>("dias")`): sin
/// fijarla, la misma entrada daría etiquetas distintas en cada plataforma.
const OfferDurationUnit kOfferDurationDefaultUnit = OfferDurationUnit.dias;

extension OfferDurationUnitLabels on OfferDurationUnit {
  /// Lo que se lee en el desplegable. Es SIEMPRE el plural.
  String get label => plural;

  String get singular => switch (this) {
        OfferDurationUnit.minutos => 'minuto',
        OfferDurationUnit.horas => 'hora',
        OfferDurationUnit.dias => 'día',
        OfferDurationUnit.semanas => 'semana',
      };

  String get plural => switch (this) {
        OfferDurationUnit.minutos => 'minutos',
        OfferDurationUnit.horas => 'horas',
        OfferDurationUnit.dias => 'días',
        OfferDurationUnit.semanas => 'semanas',
      };
}

/// Compone la etiqueta que se guarda y que ve el cliente: `"1 día"`, `"3 días"`.
/// Devuelve `''` si el número no es un entero válido dentro del tope — nunca
/// inventa un valor ni lanza. [value] admite `num` o `String` porque en la app
/// viene de un `TextEditingController`.
String formatOfferDuration(Object? value, OfferDurationUnit unit) {
  final n = value is num ? value : num.tryParse(value?.toString().trim() ?? '');
  // `isFinite` primero: `num.tryParse('Infinity')` devuelve infinito, para el
  // que `n == n.roundToDouble()` es CIERTO y `toInt()` LANZA. Sin esta guarda,
  // esta función incumpliría su propia promesa de no lanzar nunca (medido
  // contra el TS, que devuelve "" — allí `Number.isInteger(Infinity)` es false).
  if (n == null || !n.isFinite || n != n.roundToDouble() || n < 1) return '';
  final entero = n.toInt();
  if ('$entero'.length > kOfferDurationMaxDigits) return '';
  return '$entero ${entero == 1 ? unit.singular : unit.plural}';
}

/// Quita tildes para poder reconocer `dias` y `días` con la misma rama.
///
/// La web usa `normalize("NFD")`, que el SDK de Dart NO tiene. Se replica a mano
/// sobre las vocales acentuadas del español, que es todo lo que este parser
/// necesita. La paridad entre los dos no se razona, se MIDE: la tabla de casos
/// del test es la misma en `offerDuration.test.ts` y en `offer_duration_test.dart`
/// (lección de `contact_info_guard_v2`, donde `[[:space:]]` de glibc y `\s` de JS
/// resultaron no ser lo mismo).
///
/// Hay que quitar las DOS formas, no solo la precompuesta: «día» puede llegar
/// como `í` (U+00ED) o como `i` + acento combinante (U+0301), que es lo que
/// escriben algunos teclados de macOS y lo que sobrevive a un copiar-pegar. El
/// `normalize("NFD")` de la web las acepta las dos; medido, un mapa que solo
/// conociera la precompuesta las trataba distinto — la web leía «3 días» y la
/// app no.
String _sinTildes(String s) {
  const acentos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  };
  // Bloque «Combining Diacritical Marks» (U+0300-U+036F) — EXACTAMENTE el
  // mismo rango que borra la web tras su normalize("NFD"). Escrito con
  // escapes y no con los caracteres literales: son invisibles en un editor
  // y un copiar-pegar los perdería sin que el diff lo enseñara.
  final combinantes = RegExp('[\u0300-\u036f]');
  var out = s.replaceAll(combinantes, '');
  acentos.forEach((con, sin) => out = out.replaceAll(con, sin));
  return out;
}

/// Lee una etiqueta guardada y devuelve sus partes, o `null` si no la reconoce.
///
/// TOLERANTE A PROPÓSITO: la columna lleva años aceptando texto libre desde la
/// app (en producción hay una oferta cuya duración es literalmente `"d"`) y la
/// lista vieja de la web tenía cosas como `"8 horas (1 día laboral)"` o
/// `"A definir según evaluación"`. Ante cualquiera de esas, devuelve `null`.
///
/// ⚠️ `null` significa «no lo sé leer», NUNCA «está vacío»: quien llame debe
/// CONSERVAR el valor original en vez de sobrescribirlo con `''`. Si no, editar
/// una oferta vieja le borra al proveedor un dato que sí tenía. Ver
/// [durationForSave], que es esa regla escrita una sola vez.
({int value, OfferDurationUnit unit})? parseOfferDuration(String? raw) {
  final s = _sinTildes((raw ?? '').trim().toLowerCase());
  final m = RegExp(r'^(\d{1,3})\s+(minuto|minutos|hora|horas|dia|dias|semana|semanas)$')
      .firstMatch(s);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  if (n == null || n < 1) return null;
  final raiz = m.group(2)!;
  final unit = raiz.startsWith('minuto')
      ? OfferDurationUnit.minutos
      : raiz.startsWith('hora')
          ? OfferDurationUnit.horas
          : raiz.startsWith('dia')
              ? OfferDurationUnit.dias
              : OfferDurationUnit.semanas;
  return (value: n, unit: unit);
}

/// Los tres controles de la duración a partir de lo que trae la fila.
///
/// Es la mitad de entrada de la regla «`null` = no lo sé leer»: lo que
/// [parseOfferDuration] no reconoce sale por [legacy] en vez de perderse. Una
/// duración de verdad vacía cae por la misma rama con `legacy: ''`, que es
/// exactamente lo que debe pasar — «vacío» e «ilegible» se distinguen por el
/// CONTENIDO del legado, no por el `null`.
///
/// Vive aquí y no en la pantalla a propósito: `ProviderRequestDetailScreen` no
/// se puede montar en un widget test (exige sesión real de Supabase desde
/// `initState`), así que sin extraerlo el camino más caro de este cambio —
/// editar una oferta vieja sin borrarle la duración al proveedor— se quedaría
/// sin un solo test. Mismo patrón que `offer_form_gate.dart` y `offer_edit.dart`.
({String typed, OfferDurationUnit unit, String legacy}) durationFieldsFromRaw(
    String? raw) {
  final s = (raw ?? '').trim();
  final p = parseOfferDuration(s);
  return p == null
      ? (typed: '', unit: kOfferDurationDefaultUnit, legacy: s)
      : (typed: '${p.value}', unit: p.unit, legacy: '');
}

/// Lo que se manda a `estimated_duration` desde el formulario de la oferta.
///
/// [typed] es lo que hay en el campo numérico y [legacy] el valor histórico que
/// [parseOfferDuration] no supo leer al prellenar. La regla, que es la razón de
/// ser de esta función: **con el campo vacío gana el legado**. Así, editar una
/// oferta vieja para cambiar el precio no le borra al proveedor una duración que
/// sí tenía. El legado se vacía cuando el proveedor teclea un número (lo
/// reemplaza) o cuando pulsa «Quitar» (lo borra a propósito) — las dos cosas
/// pasan en la pantalla, no aquí.
String durationForSave({
  required String typed,
  required OfferDurationUnit unit,
  required String legacy,
}) {
  final n = typed.trim();
  if (n.isEmpty) return legacy.trim();
  return formatOfferDuration(n, unit);
}
