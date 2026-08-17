/// ¿Esta oferta tiene que declarar si la cotización incluye los materiales?
///
/// Decisión PO 2026-08-17: en SERVICIO siempre, y en PRODUCTO solo cuando el
/// proveedor ofrece instalación. Un producto pelado no tiene la pregunta: lo que
/// se vende ES el material.
///
/// Espejo TS en `src/lib/offerMaterials.ts` del repo web. Si tocas una, toca la
/// otra: los dos formularios tienen que aceptar y rechazar exactamente lo mismo.
library;

bool materialsChoiceRequired({
  required bool isService,
  required bool offersInstallation,
}) =>
    isService || offersInstallation;

/// Valor que va a `provider_offers.includes_materials`.
///
/// `null` = "no aplica" o "sin contestar", distinto de `false` = "no los
/// incluye". Cuando la pregunta no aplica se manda `null` y NO lo que el
/// proveedor tuviera elegido de antes: afirmar algo sobre los materiales de una
/// instalación que ya no ofrece sería inventar un dato.
bool? materialsValueForPayload({
  required bool isService,
  required bool offersInstallation,
  required bool? includesMaterials,
}) =>
    materialsChoiceRequired(
            isService: isService, offersInstallation: offersInstallation)
        ? includesMaterials
        : null;
