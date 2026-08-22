/// ¿Esta oferta tiene que declarar si la cotización incluye los materiales?
///
/// Decisión PO 2026-08-17, acotada el 2026-08-22: en SERVICIO solo si el oficio
/// trabaja con materiales (ver [kCategoriasSinMateriales]), y en PRODUCTO solo
/// cuando el proveedor ofrece instalación. Un producto pelado no tiene la pregunta: lo que
/// se vende ES el material.
///
/// Espejo TS en `src/lib/offerMaterials.ts` del repo web. Si tocas una, toca la
/// otra: los dos formularios tienen que aceptar y rechazar exactamente lo mismo.
/// ⚠️ 2026-08-22: el gate por oficio se aplicó SOLO aquí; la web sigue
/// preguntando siempre en servicio. Está pendiente de portar.
library;

/// Categorías de oficio cuyo trabajo NO lleva materiales: lo que se entrega es
/// tiempo, criterio o un archivo. «¿Incluye los materiales?» ahí no significa
/// nada — un abogado o un diseñador gráfico no compra materiales para el
/// cliente (pedido PO 2026-08-22).
///
/// Se lista lo que NO lleva materiales, y no al revés, a propósito: la lista de
/// oficios que SÍ los llevan es mucho más larga y variada, y olvidarse de uno
/// escondería una pregunta que hoy sí sale. Así, una categoría nueva o
/// desconocida conserva el comportamiento de siempre (preguntar).
const kCategoriasSinMateriales = {
  'arquitectura', // planos y diseño; la obra la ejecuta otro
  'contabilidad',
  'contenido',
  'deportes', // entrenadores
  'educacion',
  'fotografia',
  'inmobiliaria',
  'investigacion',
  'legal',
  'locucion',
  'marketing',
  'medios',
  'musica',
  'redaccion',
  'relaciones_publicas',
  'rrhh',
  'salud',
  'seguros',
  'servicios', // niñeras, choferes, asistentes
  'tecnologia', // software y soporte
  'turismo',
};

/// ¿El oficio de esta solicitud trabaja con materiales?
///
/// Basta que UNA de las categorías objetivo los lleve: una solicitud etiquetada
/// a la vez como `legal` y `construccion` sí tiene materiales de los que hablar.
/// Sin categorías (solicitud vieja, o el ruteo no las trajo) se pregunta, que
/// es lo que la app hacía antes de este gate.
bool categoriesUseMaterials(Iterable<String> targetCategories) {
  final cats = targetCategories.where((c) => c.trim().isNotEmpty);
  if (cats.isEmpty) return true;
  return cats.any((c) => !kCategoriasSinMateriales.contains(c));
}

bool materialsChoiceRequired({
  required bool isService,
  required bool offersInstallation,
  /// Solo pesa en SERVICIO. En producto manda [offersInstallation]: lo que se
  /// instala son cosas, lleve el oficio materiales o no.
  required bool serviceUsesMaterials,
}) =>
    (isService && serviceUsesMaterials) || offersInstallation;

/// Valor que va a `provider_offers.includes_materials`.
///
/// `null` = "no aplica" o "sin contestar", distinto de `false` = "no los
/// incluye". Cuando la pregunta no aplica se manda `null` y NO lo que el
/// proveedor tuviera elegido de antes: afirmar algo sobre los materiales de una
/// instalación que ya no ofrece sería inventar un dato.
bool? materialsValueForPayload({
  required bool isService,
  required bool offersInstallation,
  required bool serviceUsesMaterials,
  required bool? includesMaterials,
}) =>
    materialsChoiceRequired(
      isService: isService,
      offersInstallation: offersInstallation,
      serviceUsesMaterials: serviceUsesMaterials,
    )
        ? includesMaterials
        : null;
