/// Orden y presencia de las secciones de catálogo del perfil de un negocio —
/// espejo exacto de `profileSections` en `src/lib/storefront.ts` (web,
/// `jayalo-main`). La paridad se mide, no se razona (lección del guard
/// anti-elusión, donde TS y SQL divergían en 6 codepoints): los casos de
/// `test/profile_sections_test.dart` son copia literal de
/// `src/lib/storefront.test.ts`.
library;

/// Las tres secciones de catálogo que puede tener un perfil de negocio.
enum ProfileSection { productos, servicios, paquetes }

/// Orden de las secciones según lo que el negocio ofrece. `offers` se INFIERE
/// de las categorías (no lo declara el proveedor), así que puede equivocarse.
const Map<String, List<ProfileSection>> _order = <String, List<ProfileSection>>{
  'servicios': [
    ProfileSection.servicios,
    ProfileSection.paquetes,
    ProfileSection.productos,
  ],
  'productos': [
    ProfileSection.productos,
    ProfileSection.servicios,
    ProfileSection.paquetes,
  ],
  'ambos': [
    ProfileSection.productos,
    ProfileSection.servicios,
    ProfileSection.paquetes,
  ],
};

/// Qué secciones pinta el perfil, y en qué orden.
///
/// REGLA ANTI-INFERENCIA (decisión PO 2026-08-14): una sección aparece si
/// TIENE FILAS. `offers` solo decide el ORDEN y, cuando no hay nada que
/// mostrar, cuál es la sección que enseña el estado vacío.
///
/// El motivo es que `offers` puede estar mal: si gobernara la visibilidad, un
/// técnico que además vende repuestos vería su propio catálogo escondido ante
/// el cliente, sin manera de darse cuenta.
///
/// [includeEmpty]: el DUEÑO ve TODAS las secciones aunque estén vacías, para
/// poder publicar desde su propio perfil (decisión PO 2026-08-15). El
/// visitante NO: para él sigue mandando la regla anti-inferencia (sección con
/// filas).
List<ProfileSection> profileSections({
  required String? offers,
  required int productCount,
  required int serviceCount,
  required int packageCount,
  bool includeEmpty = false,
}) {
  final order = _order[offers ?? ''] ?? _order['ambos']!;
  if (includeEmpty) return order;
  final counts = <ProfileSection, int>{
    ProfileSection.productos: productCount,
    ProfileSection.servicios: serviceCount,
    ProfileSection.paquetes: packageCount,
  };
  final withContent = order.where((s) => counts[s]! > 0).toList();
  return withContent;
}
