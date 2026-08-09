/// Normalización para BUSCAR y ORDENAR texto en español.
///
/// Las dos cosas necesitan plegar tildes y mayúsculas: el `sort()` por defecto
/// de Dart ordena por código Unicode y manda «Ébano» después de la zeta, y un
/// buscador que no encuentre «Pekín» tecleando "pekin" no sirve en un
/// teléfono. La eñe se pliega a ene a propósito: pierde su puesto tradicional
/// después de la ene, pero "nino" encuentra «Niño» — en un buscador móvil eso
/// vale más que la colación académica.
library;

const _folds = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Minúsculas y sin tildes: la forma canónica para comparar.
String searchFold(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_folds[ch] ?? ch);
  }
  return b.toString();
}

/// Comparador alfabético insensible a tildes y mayúsculas. A igualdad de
/// forma plegada desempata por la cadena original (orden estable y total).
int compareFolded(String a, String b) {
  final byFold = searchFold(a).compareTo(searchFold(b));
  return byFold != 0 ? byFold : a.compareTo(b);
}
