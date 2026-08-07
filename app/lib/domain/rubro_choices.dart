/// Qué rubros se le ofrecen al usuario en el formulario final de una solicitud.
///
/// Existe por un bloqueo real (2026-08-07): la pantalla pintaba las fichas
/// SOLO con lo que la IA había sugerido (`for (final id in _rubros)`), mientras
/// el título "Elige uno o más rubros *" y el guard del envío se mostraban
/// siempre. El servidor retiró su fallback "top-3 por sort_order" (commit
/// `35b7263` de jayalo-main) razonando que "el cliente elige en el picker, que
/// ya es obligatorio en web y app" — cierto en la web (`RubroPicker` consulta
/// la tabla `rubros`), FALSO en la app. En cuanto el clasificador devolvió
/// vacío, el usuario veía una sección obligatoria sin una sola opción y no
/// podía continuar.
///
/// La regla es por tanto: las sugerencias de la IA son una AYUDA (van primero y
/// se premarcan), nunca la única fuente de opciones. El catálogo de las
/// categorías objetivo es lo que garantiza que siempre haya algo que elegir.
library;

/// Ids de rubro a ofrecer, en orden de presentación.
///
/// [catalog] son las filas de `rubros` de las categorías objetivo, tal como las
/// devuelve `rubrosForCategories` (claves `id`, `name`, `category_id`).
/// [suggested] son los ids que sugirió la IA en el turno `routing`.
///
/// Los sugeridos van delante para que la ayuda de la IA siga siendo visible sin
/// tener que buscar. Un sugerido que no esté en el catálogo se conserva igual:
/// si la lectura del catálogo falló, perderlo dejaría al usuario tan bloqueado
/// como en el bug original.
List<String> rubroChoiceIds({
  required List<Map<String, dynamic>> catalog,
  required List<String> suggested,
}) {
  final out = <String>[];
  final seen = <String>{};

  void add(String? id) {
    if (id == null || id.isEmpty || !seen.add(id)) return;
    out.add(id);
  }

  for (final id in suggested) {
    add(id);
  }
  for (final row in catalog) {
    add(row['id'] as String?);
  }
  return out;
}
