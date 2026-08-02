/// Los requisitos que el CLIENTE marca al crear una solicitud, y sus etiquetas.
///
/// Módulo PURO a propósito: sin Flutter y sin Supabase, para que "qué exige
/// esta solicitud" se pueda probar sin montar ninguna pantalla. Espejo de
/// `src/lib/requestRequirements.ts` de la web; los textos se copian LITERALES
/// para que el mismo requisito se lea igual en los dos frentes.
///
/// Lo que NO está aquí, a propósito: `OfferCapabilities` y el cotejo contra lo
/// que declara una oferta (`unmetRequirements`). Eso lo necesita la tanda B
/// —declarar capacidades del proveedor y avisar antes de enviar la oferta— y
/// escribirlo ahora sería código muerto.
library;

/// El orden de declaración ES el orden canónico de presentación: lo respetan
/// los chips del detalle y los símbolos del listado, en las seis pantallas.
enum Requirement { shipping, installation, evaluation, fiscal, state }

/// `chip` = texto completo, el que se lee en el detalle.
/// `short` = la misma idea suelta, para armar una frase enumerando varios.
/// `hint` = la explicación larga, para el tooltip.
typedef RequirementLabel = ({String chip, String short, String hint});

/// Lo que el cliente pide, tal como está en las columnas de `customer_requests`.
class RequestRequirements {
  const RequestRequirements({
    this.withShipping = false,
    this.withInstallation = false,
    this.requiresEvaluation = false,
    this.requiresFiscalReceipt = false,
    this.requiresStateSupplier = false,
  });

  final bool withShipping;
  final bool withInstallation;
  final bool requiresEvaluation;
  final bool requiresFiscalReceipt;
  final bool requiresStateSupplier;

  /// Solicitud que no exige nada. Es el valor por defecto donde el dato aún no
  /// llegó, y el default seguro: no se le reclama al proveedor algo que el
  /// cliente nunca marcó.
  static const none = RequestRequirements();

  bool has(Requirement r) => switch (r) {
    Requirement.shipping => withShipping,
    Requirement.installation => withInstallation,
    Requirement.evaluation => requiresEvaluation,
    Requirement.fiscal => requiresFiscalReceipt,
    Requirement.state => requiresStateSupplier,
  };
}

/// Mapea una fila de `customer_requests`. NUNCA lanza: la clave ausente, el
/// `null` y cualquier tipo inesperado caen todos en "no lo pide" gracias al
/// `== true`. Una fila de la RPC del inbox —que no trae estas columnas— da
/// `none`, que es exactamente lo que se quiere hasta que llegue la oleada B.
RequestRequirements requirementsFromRow(Map<String, dynamic> row) =>
    RequestRequirements(
      withShipping: row['with_shipping'] == true,
      withInstallation: row['with_installation'] == true,
      requiresEvaluation: row['requires_evaluation'] == true,
      requiresFiscalReceipt: row['requires_fiscal_receipt'] == true,
      requiresStateSupplier: row['requires_state_supplier'] == true,
    );

/// Los requisitos activos, SIEMPRE en orden canónico. [keys] acota el conjunto
/// (por defecto, los cinco). Se itera `Requirement.values` y se filtra por
/// [keys], no al revés: así el orden lo fija la declaración del enum y no el
/// orden en que quien llama pasó las claves.
List<Requirement> activeRequirements(
  RequestRequirements req, {
  Iterable<Requirement> keys = Requirement.values,
}) => [
  for (final r in Requirement.values)
    if (keys.contains(r) && req.has(r)) r,
];

/// `true` si [req] tiene al menos un requisito activo. Pensado como guarda de
/// layout: `RequestRequirementBadges` pinta `SizedBox.shrink()` cuando no hay
/// nada, pero un hijo de ancho cero dentro de un `Wrap` igual consume su
/// `spacing` y corre a los chips que van después. Quien lista tarjetas debe
/// usar esto para no meter el widget en el `Wrap` cuando no hace falta.
bool hasAnyRequirement(RequestRequirements req) =>
    activeRequirements(req).isNotEmpty;

const _labels = <Requirement, RequirementLabel>{
  Requirement.shipping: (
    chip: 'Requiere envío',
    short: 'envío',
    hint: 'El cliente necesita que le lleven el producto.',
  ),
  Requirement.installation: (
    chip: 'Requiere instalación',
    short: 'instalación',
    hint: 'El cliente necesita que se lo instalen.',
  ),
  Requirement.evaluation: (
    chip: 'Requiere evaluación previa',
    short: 'evaluación previa',
    hint: 'El cliente pide una visita para cotizar antes.',
  ),
  Requirement.fiscal: (
    chip: 'Requiere comprobante fiscal',
    short: 'comprobante fiscal',
    hint: 'El proveedor debe poder emitir comprobante fiscal (NCF).',
  ),
  Requirement.state: (
    chip: 'Requiere suplidor del Estado',
    short: 'suplidor del Estado',
    hint: 'El proveedor debe estar registrado como suplidor del Estado.',
  ),
};

RequirementLabel requirementLabel(Requirement r) => _labels[r]!;
