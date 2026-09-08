/// Cuerpos de `CatalogView` (Boy Scout de `catalog_screen.dart`, revisión
/// final I-2, 2026-09-07): la rejilla, la lista de proveedores, el aviso
/// «solo coinciden por nombre» y el estado vacío. Funciones de nivel
/// superior que reciben todo explícito (`chips` ya construido, el
/// `ScrollController`, los callbacks) — sin acceso al estado de
/// `_CatalogViewState`, mismo patrón que `catalog_secciones.dart`.
library;

import 'package:flutter/material.dart';

import '../../data/repos.dart' show BusinessCardInfo, negocioCatalogoDe;
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../shared/product_list_card.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_articulos.dart';
import 'catalog_chip_strip.dart';
import 'catalog_secciones.dart';
import 'catalog_tipo_strip.dart';

/// Tira de tipo (Todos · Productos · Servicios · Paquetes · Proveedores) +
/// tira de chips de categoría/rubro/mayoreo — la cabecera que llevan los
/// cuatro cuerpos de [CatalogScreen].
Widget chipsCatalogo({
  required String tipo,
  required Map<String, int> conteos,
  required String? categoryId,
  required Set<String>? categoriasVistas,
  required bool? wholesale,
  required List<String> rubros,
  required String? rubro,
  required ValueChanged<String> onTipo,
  required ValueChanged<bool> onWholesale,
  required ValueChanged<String> onCategory,
  required VoidCallback onTodo,
  required ValueChanged<String?> onRubro,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    CatalogTipoStrip(tipo: tipo, conteos: conteos, onTipo: onTipo),
    CatalogChipStrip(
      categorias: categoriasNavegables(
        kCategories,
        categoriasVistas,
        seleccionada: categoryId,
      ),
      categoryId: categoryId,
      wholesale: wholesale,
      onWholesale: onWholesale,
      onCategory: onCategory,
      onTodo: onTodo,
      rubros: rubros,
      rubro: rubro,
      onRubro: onRubro,
    ),
  ],
);

/// Rejilla de dos columnas de un tipo (o de todos): cabecera [chips], y si
/// [conBusqueda], los proveedores que coinciden por nombre encima. `esPaquete`
/// deja sitio a la fila de «Incluye» en la tarjeta.
Widget rejillaCatalogo({
  required ScrollController controller,
  required Widget chips,
  required List<Map<String, dynamic>> items,
  required Map<String, BusinessCardInfo> negocios,
  required List<Proveedor> coinciden,
  required bool conBusqueda,
  required bool esPaquete,
  required ValueChanged<String> onStore,
}) => LayoutBuilder(
  builder: (context, box) {
    final cellWidth = (box.maxWidth - 32 - 11) / 2;
    final alto = catalogGridCardExtent(
      context,
      cellWidth,
      conIncluido: esPaquete,
    );
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverToBoxAdapter(child: chips),
        if (conBusqueda)
          SliverToBoxAdapter(
            child: ProveedoresCoinciden(
              proveedores: coinciden,
              onStore: onStore,
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            12 + navBarReservedSpace(context),
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 11,
              mainAxisSpacing: 11,
              mainAxisExtent: alto,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => ProductGridCard(
              item: items[i],
              negocio: negocios[items[i]['business_id']],
              showTypeTag: true,
            ).cascadeIn(i),
          ),
        ),
      ],
    );
  },
);

/// Un tipo/[tipo] sin nombre plural propio (categoría, «todos») cae en
/// «artículos» — el copy genérico que ya tenía la pantalla.
String _pluralDeTipo(String tipo) => switch (tipo) {
  'producto' => 'productos',
  'servicio' => 'servicios',
  'paquete' => 'paquetes',
  _ => 'artículos',
};

/// Sin artículos del tipo activo pero con proveedores que coinciden por
/// nombre (búsqueda tipo «ferreter» sobre «Ferretería Central» sin artículos
/// propios en el filtro actual): la píldoras + un aviso, en vez del vacío.
/// El copy nombra el tipo activo (revisión final M-3): en la pestaña
/// Paquetes dice «Sin paquetes…», no «Sin artículos…» cuando lo que falta es
/// justo eso.
Widget soloCoincidenPorNombre({
  required BuildContext context,
  required ScrollController controller,
  required Widget chips,
  required List<Proveedor> coinciden,
  required String search,
  required String tipo,
  required ValueChanged<String> onStore,
}) => ListView(
  controller: controller,
  padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
  children: [
    chips,
    ProveedoresCoinciden(proveedores: coinciden, onStore: onStore),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'Sin ${_pluralDeTipo(tipo)} para «$search»; estos proveedores '
        'coinciden por nombre.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  ],
);

/// Lista del tipo Proveedores: los que coinciden por nombre con la búsqueda
/// primero, luego los demás dueños de ítems, sin repetidos.
Widget listaProveedoresCatalogo({
  required BuildContext context,
  required ScrollController controller,
  required Widget chips,
  required List<Proveedor> ps,
  required List<Proveedor> coinciden,
  required ValueChanged<String> onStore,
}) {
  final vistos = <String>{};
  final lista = [
    for (final p in [...coinciden, ...ps])
      if (vistos.add(p.id)) p,
  ];
  return ListView(
    controller: controller,
    padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
    children: [
      chips,
      const SizedBox(height: 6),
      for (var i = 0; i < lista.length; i++)
        ProveedorCard(
          p: lista[i],
          onTap: () => onStore(lista[i].id),
        ).cascadeIn(i),
    ],
  );
}

/// Estado vacío: cabecera [chips] + el aviso, con «Quitar filtro» solo si
/// [filtrado].
Widget vacioCatalogo({
  required ScrollController controller,
  required Widget chips,
  required String tipo,
  required bool filtrado,
  required VoidCallback onQuitarFiltro,
}) => Column(
  children: [
    chips,
    Expanded(
      child: EmptyState(
        controller: controller,
        message: tipo == 'proveedor'
            ? 'No hay proveedores que coincidan con tu filtro.'
            : filtrado
            ? 'No hay artículos que coincidan con tu filtro.'
            : 'Aún no hay artículos publicados en esta '
                  'categoría.\n\nVuelve más tarde: los '
                  'proveedores publican todos los días.',
        ctaLabel: filtrado ? 'Quitar filtro' : null,
        onCta: filtrado ? onQuitarFiltro : null,
      ),
    ),
  ],
);

/// Cuerpo con los derivados PUROS de la carga (`catalog_articulos.dart`):
/// nada pide red, todo sale de [items]/[negocios]/[nombres] ya cargados y de
/// los filtros vigentes. El tope 90 es para la LISTA del tipo Proveedores
/// (el riel de [CatalogSecciones] recorta por su cuenta). [chips] construye
/// la cabecera con los conteos ya calculados (distintos por cuerpo).
Widget cuerpoCatalogo({
  required BuildContext context,
  required ScrollController controller,
  required List<Map<String, dynamic>> items,
  required Map<String, BusinessCardInfo> negocios,
  required List<Proveedor> nombres,
  required FiltrosLateral filtros,
  required String tipo,
  required bool verSecciones,
  required String? search,
  required bool filtrado,
  required Widget Function(Map<String, int> conteos) chips,
  required ValueChanged<String> onVerTodos,
  required ValueChanged<String> onStore,
  required VoidCallback onQuitarFiltro,
}) {
  final negociosCat = {
    for (final e in negocios.entries) e.key: negocioCatalogoDe(e.value),
  };
  final hits = ordenarCatalogo(filtrarLateral(items, negociosCat, filtros));
  final proveedores = proveedoresDeItems(hits, negociosCat, tope: 90);
  // Antes de decidir si hay algo que pintar: los proveedores que coinciden
  // por NOMBRE con la búsqueda son alcanzables aunque 0 artículos matcheen.
  final coinciden = proveedoresQueCoinciden(proveedores, nombres, search);
  int n(String k) => hits.where((it) => tipoDeItem(it) == k).length;
  final conteos = {
    'todos': hits.length,
    'producto': n('producto'),
    'servicio': n('servicio'),
    'paquete': n('paquete'),
    'proveedor': proveedores.length,
  };
  final hitsDeTipo = tipo == 'todos'
      ? hits
      : hits.where((it) => tipoDeItem(it) == tipo).toList();
  final hayQuePintar = tipo == 'proveedor'
      ? (proveedores.isNotEmpty || coinciden.isNotEmpty)
      : (hitsDeTipo.isNotEmpty || coinciden.isNotEmpty);

  if (!hayQuePintar) {
    return vacioCatalogo(
      controller: controller,
      chips: chips(conteos),
      tipo: tipo,
      filtrado: filtrado,
      onQuitarFiltro: onQuitarFiltro,
    );
  }
  if (verSecciones) {
    return CatalogSecciones(
      controller: controller,
      header: chips(conteos),
      items: hits,
      negocios: negocios,
      proveedores: proveedores,
      conteos: (
        productos: conteos['producto']!,
        servicios: conteos['servicio']!,
        paquetes: conteos['paquete']!,
        proveedores: proveedores.length,
      ),
      onVerTodos: onVerTodos,
      onStore: onStore,
    );
  }
  if (tipo == 'proveedor') {
    return listaProveedoresCatalogo(
      context: context,
      controller: controller,
      chips: chips(conteos),
      ps: proveedores,
      coinciden: coinciden,
      onStore: onStore,
    );
  }
  if (hitsDeTipo.isEmpty && coinciden.isNotEmpty) {
    return soloCoincidenPorNombre(
      context: context,
      controller: controller,
      chips: chips(conteos),
      coinciden: coinciden,
      search: search!,
      tipo: tipo,
      onStore: onStore,
    );
  }
  return rejillaCatalogo(
    controller: controller,
    chips: chips(conteos),
    items: hitsDeTipo,
    negocios: negocios,
    coinciden: coinciden,
    conBusqueda: search != null,
    esPaquete: tipo == 'paquete',
    onStore: onStore,
  );
}
