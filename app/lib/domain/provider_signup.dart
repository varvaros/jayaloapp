// Reglas del alta de proveedor que no dependen de Flutter.
//
// Viven aparte de la pantalla porque `ProviderOnboardingScreen` habla con
// Supabase en su `initState`, y montarla en un test para comprobar una regla
// de validación sería pagar una red por una condición booleana.

/// ¿Se puede pasar del paso 1 («Tu negocio»)?
///
/// La **profesión u oficio es obligatoria para los tres tipos de negocio**
/// (PO 2026-08-20). Antes solo se pedía —y encima como «(opcional)»— cuando el
/// tipo era `tecnico`, así que informales y formales llegaban a producción sin
/// ella y el cliente no veía en la ficha a qué se dedica el proveedor.
///
/// El RNC, en cambio, sí es exclusivo del negocio formal: es lo que significa
/// serlo.
bool providerStep1Valid({
  required String businessName,
  required String profession,
  required String businessType,
  required String rnc,
}) =>
    businessName.trim().isNotEmpty &&
    profession.trim().isNotEmpty &&
    (businessType != 'formal' || rnc.trim().isNotEmpty);
