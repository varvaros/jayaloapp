/// ¿Es el proveedor dueño de esta tienda? Puro, sin red.
///
/// Bug I-5 (revisión final 09-20): `ProviderStoreScreen._esDueno` decidía con
/// `myBusinessId() == widget.businessId`, y `myBusinessId()` (`data/repos.dart`)
/// hace `.select('id').eq('user_id', uid).limit(1)` SIN `ORDER BY` sobre
/// `provider_businesses` — devuelve UNO cualquiera de los negocios del
/// usuario. Un proveedor con DOS negocios podía ver «Pedir cotización» en su
/// propia segunda tienda (la consulta devolvía el otro negocio, y la
/// comparación por igualdad simple salía en falso) y crear una solicitud
/// dirigida a sí mismo. Paridad con la web: compara IDENTIDAD
/// (`user?.id === biz.user_id`), no un único id de negocio elegido al azar.
///
/// El arreglo compara [businessId] contra TODOS los negocios del proveedor
/// (`myBusinessesForAssistant()`, que ya lee la lista completa), no contra
/// uno solo.
library;

bool esDuenoDe(List<String> misNegocios, String businessId) =>
    misNegocios.contains(businessId);
