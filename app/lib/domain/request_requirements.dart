/// Los requisitos que el CLIENTE marca al crear una solicitud, y sus etiquetas.
///
/// Módulo PURO a propósito: sin Flutter y sin Supabase, para que "qué exige
/// esta solicitud" se pueda probar sin montar ninguna pantalla. Espejo de
/// `src/lib/requestRequirements.ts` de la web; los textos se copian LITERALES
/// para que el mismo requisito se lea igual en los dos frentes.
///
/// Incluye también el lado del PROVEEDOR (`OfferCapabilities`) y el cotejo
/// entre ambos (`unmetRequirements`): qué pide el cliente, qué declara la
/// oferta, y qué falta. Las dos mitades viven juntas a propósito — separarlas
/// invitaría a que cada una redactara sus etiquetas por su cuenta.
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

/// Lo que el PROVEEDOR declara en su oferta (columnas de `provider_offers`).
class OfferCapabilities {
  const OfferCapabilities({
    this.offersShipping = false,
    this.offersInstallation = false,
    this.hasFiscalReceipt = false,
    this.isStateSupplier = false,
  });

  final bool offersShipping;
  final bool offersInstallation;
  final bool hasFiscalReceipt;
  final bool isStateSupplier;

  /// Oferta que no declara nada. Es el default seguro: si la lectura de las
  /// capacidades del negocio falla, se avisa de más (el proveedor lo marca y
  /// sigue) y nunca se afirma de menos en su nombre.
  static const none = OfferCapabilities();

  bool covers(Requirement r) => switch (r) {
    Requirement.shipping => offersShipping,
    Requirement.installation => offersInstallation,
    Requirement.fiscal => hasFiscalReceipt,
    Requirement.state => isStateSupplier,
    // La evaluación no es cotejable: ver `verifiableRequirements`. Nadie
    // debería preguntarlo, pero el `switch` tiene que ser exhaustivo y
    // responder algo honesto — "esta oferta no la cubre" es lo único cierto.
    Requirement.evaluation => false,
  };
}

/// Los cuatro requisitos que SÍ se pueden cotejar contra lo que declara una
/// oferta.
///
/// La evaluación queda fuera **a propósito**. En la solicitud significa "quiero
/// que vengan a ver antes de cotizar"; en la oferta, "necesito ir a ver para
/// poder dar precio". Que el proveedor NO la marque quiere decir que da precio
/// en firme sin visita — eso favorece al cliente. Avisarlo como incumplimiento
/// sería regañar al proveedor por hacerlo bien.
const verifiableRequirements = <Requirement>[
  Requirement.shipping,
  Requirement.installation,
  Requirement.fiscal,
  Requirement.state,
];

/// Los requisitos cotejables que el cliente pidió y esta oferta NO cubre, en
/// orden canónico. Nunca reporta la evaluación ni las capacidades que la oferta
/// ofrece de más.
List<Requirement> unmetRequirements(
  RequestRequirements req,
  OfferCapabilities cap,
) => [
  for (final r in activeRequirements(req, keys: verifiableRequirements))
    if (!cap.covers(r)) r,
];

/// "envío, comprobante fiscal y suplidor del Estado" — para el aviso previo al
/// envío. Usa los textos `short`, no los de chip: va dentro de una frase.
String unmetRequirementsMessage(List<Requirement> keys) {
  final partes = [for (final k in keys) requirementLabel(k).short];
  if (partes.isEmpty) return '';
  if (partes.length == 1) return partes.first;
  return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
}
