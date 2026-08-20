// La PROFESIÓN del proveedor: qué ES, no qué hace.
//
// «Rubro» es lo que hace (*Destape de tuberías*); «oficio» es lo que es
// (*Plomero*). El catálogo es CERRADO y lo cura el admin: se elige de una
// lista, nunca se escribe a mano. Ésa es la razón de existir de todo esto —
// con texto libre acabábamos con `Plomero`, `plomero`, `Plomería` y `Tec. en
// plomería` como cuatro cosas distintas que ni filtran ni agrupan ni rutean.
//
// La lista NO se filtra por categoría (decisión PO 2026-08-20): es un selector
// de profesiones y ya. Las especialidades no se catalogan — quien busca un
// «abogado penalista» le llega a los abogados.

/// Una entrada del catálogo. `slug` es la clave estable que viaja a la BD;
/// `name` es lo único que ve el usuario.
class Oficio {
  const Oficio({required this.slug, required this.name});

  final String slug;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is Oficio && other.slug == slug && other.name == name;

  @override
  int get hashCode => Object.hash(slug, name);
}

/// Filas crudas de `public.oficios` → catálogo. Descarta lo que no tenga slug
/// y nombre: una fila a medias pintaría un chip vacío que no se puede quitar.
List<Oficio> oficiosFromRows(List<Map<String, dynamic>> rows) {
  final out = <Oficio>[];
  for (final r in rows) {
    final slug = (r['slug'] as String?)?.trim() ?? '';
    final name = (r['name'] as String?)?.trim() ?? '';
    if (slug.isEmpty || name.isEmpty) continue;
    out.add(Oficio(slug: slug, name: name));
  }
  return out;
}

/// Tope de oficios por negocio. Lo impone además el trigger
/// `trg_max_four_business_oficios` y la RPC `set_business_oficios`; aquí está
/// para poder decírselo al usuario ANTES de que el servidor le grite.
const int kMaxOficios = 4;

/// Los nombres a pintar en la ficha pública de un negocio.
///
/// Lee el embebido `provider_business_oficios(approved_at, oficios(name))` del
/// select. Sólo los APROBADOS: la RLS ya esconde los ajenos sin aprobar, pero
/// el dueño SÍ ve los suyos pendientes, y su ficha no debe prometer al público
/// algo que el público no ve.
List<String> approvedOficioNames(Map<String, dynamic> business) {
  final raw = business['provider_business_oficios'];
  if (raw is! List) return const [];
  final out = <String>[];
  for (final row in raw) {
    if (row is! Map) continue;
    if (row['approved_at'] == null) continue;
    final oficio = row['oficios'];
    if (oficio is! Map) continue;
    final name = (oficio['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) out.add(name);
  }
  out.sort();
  return out;
}
