/// Etiquetas visibles de los detalles de mayoreo (espejo de web
/// src/lib/wholesale.ts). Se guardan SLUGS; se muestran estas.
const kWholesaleSplitOptions = <(String, String)>[
  ('todo_junto', 'Todo junto'),
  ('lotes_iguales', 'En lotes iguales'),
  ('cantidades_especificas', 'En cantidades específicas'),
  ('no_importa', 'No importa'),
];

const kWholesalePackagingOptions = <(String, String)>[
  ('individual', 'Empaque individual'),
  ('por_cantidad', 'Empaque por cantidad'),
  ('caja', 'Caja'),
  ('bolsa', 'Bolsa'),
  ('otro', 'Otro'),
];

String _label(List<(String, String)> opts, String? slug) {
  if (slug == null) return '';
  for (final o in opts) {
    if (o.$1 == slug) return o.$2;
  }
  return slug;
}

String wholesaleSplitLabel(String? slug) => _label(kWholesaleSplitOptions, slug);
String wholesalePackagingLabel(String? slug) =>
    _label(kWholesalePackagingOptions, slug);
