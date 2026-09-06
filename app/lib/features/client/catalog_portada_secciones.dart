/// Lógica PURA de la portada del catálogo (PO 2026-09-05, camino 3): qué
/// tiendas, qué categorías y qué carruseles salen de los 60 ítems ya cargados
/// y de los conteos de `get_product_counts`. Sin widgets ni red, para
/// probarse con `test()` a secas. Los topes son los de la spec §2.4.
library;

import '../../data/repos.dart' show BusinessCardInfo;
import '../../domain/catalog.dart';

const int kPortadaRecientes = 8;
const int kPortadaTiendas = 12;
const int kPortadaCategorias = 6;
const int kPortadaCarruseles = 3;
const int kPortadaItemsPorCarrusel = 8;

typedef CategoriaConteo = ({Category categoria, int n});
typedef CarruselCategoria = ({
  Category categoria,
  List<Map<String, dynamic>> items,
});

/// Ids de negocio DISTINTOS de los ítems, en orden de aparición, solo los que
/// resolvieron en [negocios] (un negocio borrado o una consulta caída no
/// producen un círculo vacío). Tope [kPortadaTiendas].
List<String> portadaTiendas(
  List<Map<String, dynamic>> items,
  Map<String, BusinessCardInfo> negocios,
) {
  final out = <String>[];
  for (final it in items) {
    final id = it['business_id'];
    if (id is String && negocios.containsKey(id) && !out.contains(id)) {
      out.add(id);
      if (out.length == kPortadaTiendas) break;
    }
  }
  return out;
}

/// Categorías navegables con su conteo, ordenadas por conteo desc; a igual
/// conteo gana la que va antes en `kCategories` (orden estable a mano:
/// `List.sort` no garantiza estabilidad). Ids que no existen en `kCategories`
/// y conteos en cero se ignoran. `null` ⇒ vacío (la sección se oculta).
List<CategoriaConteo> portadaCategorias(Map<String, int>? counts) {
  if (counts == null) return const [];
  final vivas = categoriasNavegables(kCategories, counts.keys.toSet());
  final indexed = <(int, CategoriaConteo)>[
    for (var i = 0; i < vivas.length; i++)
      if ((counts[vivas[i].id] ?? 0) > 0)
        (i, (categoria: vivas[i], n: counts[vivas[i].id]!)),
  ];
  indexed.sort((a, b) {
    final byN = b.$2.n.compareTo(a.$2.n);
    return byN != 0 ? byN : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(kPortadaCategorias)) e.$2];
}

/// Un carrusel por cada una de las [kPortadaCarruseles] categorías con más
/// ítems ENTRE LOS CARGADOS (no por el conteo global: así nunca sale un
/// carrusel vacío). Una categoría necesita ≥ 2 ítems (con uno solo ya está en
/// «Recién publicados»). A igual tamaño gana la que apareció antes. Cada
/// carrusel lleva hasta [kPortadaItemsPorCarrusel] ítems en su orden original.
List<CarruselCategoria> portadaCarruseles(List<Map<String, dynamic>> items) {
  final porCat = <String, List<Map<String, dynamic>>>{};
  for (final it in items) {
    final c = it['category_id'];
    if (c is String) (porCat[c] ??= []).add(it);
  }
  final candidatas = <(int, String, List<Map<String, dynamic>>)>[];
  var orden = 0;
  for (final e in porCat.entries) {
    if (e.value.length >= 2 && categoryNameById(e.key) != null) {
      candidatas.add((orden, e.key, e.value));
    }
    orden++;
  }
  candidatas.sort((a, b) {
    final bySize = b.$3.length.compareTo(a.$3.length);
    return bySize != 0 ? bySize : a.$1.compareTo(b.$1);
  });
  return [
    for (final c in candidatas.take(kPortadaCarruseles))
      (
        categoria: (id: c.$2, name: categoryNameById(c.$2)!),
        items: c.$3.take(kPortadaItemsPorCarrusel).toList(),
      ),
  ];
}

/// «1 artículo» / «n artículos».
String articulosLabel(int n) => n == 1 ? '1 artículo' : '$n artículos';
