/// Qué rubros se le ofrecen al usuario en el formulario final de una solicitud.
///
/// Existe por un bloqueo real (2026-08-07): la pantalla pintaba las fichas
/// SOLO con lo que la IA había sugerido (`for (final id in _rubros)`), mientras
/// el título de la sección (hoy "¿Dónde más buscamos? *") y el guard del envío se mostraban
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

/// Ids que se pintan como FICHAS, arriba: lo sugerido por la IA más lo que el
/// usuario ya añadió desde el desplegable.
///
/// Pedido del PO (2026-08-07): la parrilla con el catálogo entero en fichas es
/// tediosa. Arriba solo lo relevante; el resto se elige en un desplegable.
///
/// Un sugerido se queda como ficha aunque esté DESmarcado — si desapareciera al
/// desmarcarlo, el usuario no podría volver a marcarlo sin buscarlo. Y un
/// seleccionado que no esté en el catálogo tampoco se pierde, o quedaría
/// enviado sin forma de quitarlo.
List<String> rubroChipIds({
  required List<String> suggested,
  required Set<String> selected,
  required List<Map<String, dynamic>> catalog,
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
  // Los añadidos a mano van detrás, en el orden del catálogo (estable entre
  // rebuilds; el de un Set no lo es).
  for (final row in catalog) {
    final id = row['id'] as String?;
    if (id != null && selected.contains(id)) add(id);
  }
  // Y por último lo seleccionado que no aparece en el catálogo.
  for (final id in selected) {
    add(id);
  }
  return out;
}

/// Resto del catálogo, para el desplegable: lo que no está ya como ficha.
List<String> rubroDropdownIds({
  required List<Map<String, dynamic>> catalog,
  required List<String> shown,
}) {
  final ya = shown.toSet();
  final out = <String>[];
  for (final row in catalog) {
    final id = row['id'] as String?;
    if (id != null && id.isNotEmpty && !ya.contains(id) && !out.contains(id)) {
      out.add(id);
    }
  }
  return out;
}
