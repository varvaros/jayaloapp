import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show BusinessCardInfo;
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/product_list_card.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_portada_secciones.dart';

/// Portada del catálogo (PO 2026-09-05, camino 3): secciones apiladas sobre
/// los 60 ítems ya cargados — «Recién publicados», «Tiendas», «Por categoría»
/// y hasta tres carruseles por categoría. Pura: recibe datos y callbacks; no
/// pide nada a la red. Se pinta solo cuando NO hay filtro activo (la regla
/// vive en `CatalogView`). [header] es la tira de chips: va dentro de la
/// lista para desplazarse con ella.
class CatalogPortada extends StatelessWidget {
  const CatalogPortada({
    super.key,
    required this.items,
    required this.negocios,
    required this.counts,
    required this.onVerTodo,
    required this.onCategory,
    required this.onStore,
    this.header,
    this.controller,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;
  final Map<String, int>? counts;
  final VoidCallback onVerTodo;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onStore;
  final Widget? header;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final tiendas = portadaTiendas(items, negocios);
    final categorias = portadaCategorias(counts);
    final carruseles = portadaCarruseles(items);
    var i = 0;
    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
      children: [
        ?header,
        if (items.isNotEmpty) ...[
          SeccionTitulo('Recién publicados', onMore: onVerTodo).cascadeIn(i++),
          _Carrusel(
            items: items.take(kPortadaRecientes).toList(),
            negocios: negocios,
          ).cascadeIn(i++),
        ],
        if (tiendas.isNotEmpty) ...[
          const SeccionTitulo('Tiendas').cascadeIn(i++),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final id in tiendas) ...[
                  _StoreCircle(
                    negocio: negocios[id]!,
                    onTap: () => onStore(id),
                  ),
                  const SizedBox(width: 14),
                ],
              ],
            ),
          ).cascadeIn(i++),
        ],
        if (categorias.isNotEmpty) ...[
          const SeccionTitulo('Por categoría').cascadeIn(i++),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              // Sin `padding` explícito un scrollable anidado se apropia de
              // los insets del MediaQuery (barra de estado + reserva de la
              // navbar) y deja un hueco de ~170 px bajo los tiles (PO 09-06).
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 56,
              ),
              itemCount: categorias.length,
              itemBuilder: (_, k) => CategoryTile(
                conteo: categorias[k],
                onTap: () => onCategory(categorias[k].categoria.id),
              ),
            ),
          ).cascadeIn(i++),
        ],
        for (final c in carruseles) ...[
          SeccionTitulo(
            c.categoria.name,
            onMore: () => onCategory(c.categoria.id),
          ).cascadeIn(i++),
          _Carrusel(items: c.items, negocios: negocios).cascadeIn(i++),
        ],
      ],
    );
  }
}

/// Cabecera de sección: título 14 w600 en tinta de título y, si hay [onMore],
/// «Ver todo» en violeta a la derecha.
class SeccionTitulo extends StatelessWidget {
  const SeccionTitulo(this.titulo, {super.key, this.onMore});
  final String titulo;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Ritmo vertical (smoke PO 2026-09-06, «está todo muy pegado»): 24 de
    // aire sobre el título y 10 debajo, y la fila mide SIEMPRE 44 (la altura
    // del área táctil de «Ver todo»), así los títulos sin enlace respiran
    // igual que los que lo llevan.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 12, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context),
                ),
              ),
            ),
            if (onMore != null)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: InkWell(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Text(
                      'Ver todo',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila horizontal de [ProductCarouselCard]. `IntrinsicHeight` + `stretch`:
/// todas las tarjetas de la fila miden lo que mida la más alta, sin extent
/// fijo (crece con la fuente del sistema).
class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.items, required this.negocios});
  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items) ...[
            ProductCarouselCard(item: it, negocio: negocios[it['business_id']]),
            const SizedBox(width: 10),
          ],
        ],
      ),
    ),
  );
}

/// Círculo de tienda: logo `cover` o la inicial sobre lila, y el nombre a dos
/// líneas debajo. Tocar abre la tienda del proveedor (lo decide el caller).
class _StoreCircle extends StatelessWidget {
  const _StoreCircle({required this.negocio, required this.onTap});
  final BusinessCardInfo negocio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inicial = negocio.name.trim().isEmpty
        ? '?'
        : negocio.name.trim()[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer,
                boxShadow: const [
                  BoxShadow(
                    color: JayaloColors.warmShadow,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: negocio.logoUrl == null
                  ? Text(
                      inicial,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    )
                  : JayaloNetworkImage(
                      negocio.logoUrl!,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              negocio.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile de «Por categoría»: pastilla lila con la inicial, nombre y «n
/// artículos». `kCategories` no trae icono (es un mock portado de la web),
/// por eso la inicial.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.conteo, required this.onTap});
  final CategoriaConteo conteo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = conteo.categoria.name;
    return JayaloCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              name[0].toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
                Text(
                  articulosLabel(conteo.n),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
