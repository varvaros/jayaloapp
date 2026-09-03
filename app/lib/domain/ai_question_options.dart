// Paridad con la web: `jayalo-main/src/lib/aiQuestionOptions.ts`.
//
// El prompt le pide a la IA ofrecer un catch-all ("Otra marca", "Otros")
// junto a las opciones concretas. Ese botón NO es una respuesta útil: si se
// envía tal cual, el proveedor recibe "Otros" como la marca pedida. Aquí se
// detecta para que la pantalla lo convierta en un disparador del campo de
// texto libre en vez de una respuesta.
//
// Si se toca esta lógica, tocar también la de la web (y sus tests): las dos
// consumen el MISMO endpoint `/api/ai/chat-stream`, así que la IA genera las
// mismas etiquetas para ambos clientes.

/// Normaliza para comparar sin acentos ni mayúsculas.
String _norm(String s) {
  final lower = s.trim().toLowerCase();
  // Dart no trae normalize(NFD): se mapean a mano las vocales acentuadas y la
  // ñ, que es todo lo que aparece en las etiquetas en español de la IA.
  const map = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString();
}

/// La misma normalización, pública: la transcripción (`buildTranscript`)
/// compara respuestas con opciones con esta regla y nadie más debe
/// reinventarla. Trim + minúsculas + vocales sin acento + ñ→n.
String normalizeLabel(String s) => _norm(s);

final _catchAll = RegExp(
    r'^otr[oa]s?(\s+(marcas?|modelos?|opcion(?:es)?|tipos?|colores|color|medidas?|materiales|material|tamanos?))?$');

final _helperParen = RegExp(r'\((?:[^()]*)\)\s*$');
final _trailingDots = RegExp(r'[…\.:]+$');

/// ¿La opción es un catch-all tipo "Otra marca" / "Otro" / "Otros"?
///
/// Se ancla al inicio y exige que "otra/otro/otras/otros" sea palabra completa
/// seguida a lo sumo de un sustantivo genérico, para no confundir respuestas
/// reales ("Motorola", "Otro Mundo Cerveza").
bool isCatchAllOption(String option) {
  final v = _norm(option)
      .replaceAll(_helperParen, '') // "otro (especifica)"
      .replaceAll(_trailingDots, '') // "otra opción…", "otro:"
      .trim();
  if (v.isEmpty) return false;
  return _catchAll.hasMatch(v);
}
