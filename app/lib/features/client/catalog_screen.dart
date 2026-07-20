import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Signature de la fuente de datos del catálogo (paridad `productHitsQ` de la
/// web). Inyectada en [CatalogView] para poder probar la pantalla sin red —
/// mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind, String? search});

/// Task 6 (2026-07-18): SOLO el listado. El detalle del producto y el botón
/// "Me interesa" son la tarea siguiente — por eso las tarjetas de esta
/// pantalla no navegan a ningún lado todavía. El cableado de la pestaña en la
/// barra flotante es posterior (no se toca `nav_destinations.dart`); hoy se
/// llega aquí navegando a `/catalog` a mano, como `/provider/business`.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, this.autofocusSearch = false});

  /// Cuando se llega tocando el buscador de otra pantalla (p. ej. "Buscar en
  /// Jayalo" de Mis solicitudes), el buscador del catálogo abre con el foco
  /// puesto y el teclado arriba, listo para escribir.
  final bool autofocusSearch;

  @override
  Widget build(BuildContext context) =>
      CatalogView(fetch: catalogProductsWithRatings, autofocusSearch: autofocusSearch);
}

/// Dibuja el toggle Producto/Servicio, la búsqueda y la rejilla. StatefulWidget
/// con su propio [ScrollController] (nunca `homeScrollController`: esta
/// pantalla todavía no es una pestaña raíz del shell, mismo motivo que
/// `ReputationView`/`StatsView` — el `AnimatedSwitcher` del shell y `BackGuard`
/// revientan si dos pantallas comparten un único controller).
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.fetch,
    this.actions = const [HeaderBell()],
    this.autofocusSearch = false,
  });

  final CatalogFetch fetch;
  final List<Widget> actions;
  final bool autofocusSearch;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String _kind = 'producto';
  String? _search;
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  late Future<List<Map<String, dynamic>>> _load =
      widget.fetch(kind: _kind, search: _search);

  // Bloque, no expresión: el mismo gotcha documentado en inbox_screen.dart —
  // `setState(() => _load = future)` hace que la closure DEVUELVA el Future.
  //
  // `.ignore()`: `setState` no reconstruye sincrónicamente (recién en el
  // próximo frame `FutureBuilder` reengancha su listener sobre el `Future`
  // nuevo), así que si `next` se resuelve en error ANTES de ese frame, la
  // zona de Dart lo reporta como "no manejado" aunque `FutureBuilder` sí lo
  // vaya a mostrar bien vía `snapshot.hasError` un instante después. Marca
  // el `Future` como atendido sin tocar su valor — `FutureBuilder` sigue
  // escuchando la MISMA instancia por su cuenta.
  void _refetch() {
    final next = widget.fetch(kind: _kind, search: _search)..ignore();
    setState(() {
      _load = next;
    });
  }

  void _applySearch() {
    final term = _searchCtrl.text.trim();
    setState(() => _search = term.isEmpty ? null : term);
    _refetch();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _search = null);
    _refetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          // Header violeta: segmento Producto/Servicio a la izquierda, título
          // "Catálogo" a la derecha, campana, y el buscador (funcional) debajo.
          VioletHeader(
            // Como pantalla "Otros proveedores" (apilada desde el menú del
            // proveedor) se antepone una flecha de atrás SIN perder el toggle
            // Producto/Servicio; como pestaña del cliente (sin apilar) va solo
            // el segmentado. `Navigator.canPop` para funcionar bajo un
            // Navigator pelado en los tests.
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              if (Navigator.of(context).canPop()) ...[
                HeaderCircleButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Atrás',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
              ],
              HeaderSegmented(
                options: const ['Producto', 'Servicio'],
                index: _kind == 'producto' ? 0 : 1,
                onChanged: (i) {
                  setState(() => _kind = i == 0 ? 'producto' : 'servicio');
                  _refetch();
                },
              ),
            ]),
            title: 'Catálogo',
            titleAlign: HeaderTitleAlign.end,
            actions: widget.actions,
            below: _HeaderSearchField(
              controller: _searchCtrl,
              hint: 'Buscar en el catálogo',
              autofocus: widget.autofocusSearch,
              onSubmitted: _applySearch,
              onClear: _clearSearch,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refetch(),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _load,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const JayaloLoaderBlock();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(onRetry: () async => _refetch());
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return EmptyState(
                      controller: _scrollController,
                      message: _search != null
                          ? 'No hay artículos que coincidan con tu búsqueda.'
                          : 'Aún no hay artículos publicados en esta '
                              'categoría.\n\nVuelve más tarde: los '
                              'proveedores publican todos los días.',
                      ctaLabel: _search != null ? 'Quitar búsqueda' : null,
                      onCta: _search != null ? _clearSearch : null,
                    );
                  }
                  // Lista a todo el ancho (no rejilla): cada ítem es una
                  // "tarjeta que respira" horizontal — foto a la izquierda,
                  // categoría + nombre + descripción + precio a la derecha. Es
                  // el idioma del resto de la app (Mis solicitudes, etc.) y deja
                  // ver mucho más detalle por ítem que la rejilla de 2 columnas.
                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                        top: 8, bottom: 12 + navBarReservedSpace(context)),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _CatalogCard(item: items[i]).cascadeIn(i),
                  );
                },
              ),
            ),
          ),
        ]),
      );
}

/// Buscador funcional del catálogo, vestido de píldora blanca para el header
/// violeta (a diferencia del buscador del home, este SÍ filtra).
class _HeaderSearchField extends StatelessWidget {
  const _HeaderSearchField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    required this.onClear,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.only(left: 16, right: 6),
      child: Row(children: [
        Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmitted(),
            style: TextStyle(fontSize: 14, color: cs.onSurface),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
              filled: false,
              border: InputBorder.none,
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => value.text.isEmpty
              ? const SizedBox(width: 8)
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                  onPressed: onClear,
                ),
        ),
      ]),
    );
  }
}

/// Tarjeta del catálogo: foto (con placeholder/error, nunca ícono roto),
/// nombre y precio (`catalogPriceLabel`, fijo o rango — paridad
/// `ProductHitCard.tsx`). Task 7 (2026-07-19): ya navega al detalle
/// (`/catalog/:id`) — antes (Task 6) no tenía `onTap` porque el detalle no
/// existía todavía.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final desc = (item['description'] as String? ?? '').trim();
    final catName = categoryNameById(item['category_id'] as String?);
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return JayaloCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.push('/catalog/${item['id']}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(kCardRadius - 6),
            child: SizedBox(
              width: 104,
              height: 104,
              child: img == null
                  ? _imagePlaceholder(cs)
                  : Image.network(
                      img,
                      fit: BoxFit.cover,
                      // Fundido suave al cargar (doctrina de movimiento).
                      frameBuilder: (_, child, frame, wasSync) => wasSync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: child,
                            ),
                      errorBuilder: (_, _, _) => _imagePlaceholder(cs),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (catName != null) ...[
                  Text(catName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .8,
                          color: cs.primary)),
                  const SizedBox(height: 3),
                ],
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: jayaloHead(context))),
                ?_ratingLine(context, cs),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // onSurface (no onSurfaceVariant): el muted #847D8F sobre
                      // la tarjeta blanca queda ~3.2:1, bajo el mínimo 4.5:1.
                      // El peso normal + tamaño menor ya lo separan del nombre.
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: cs.onSurface)),
                ],
                const SizedBox(height: 8),
                _priceLine(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reputación del proveedor: ★ + promedio a 1 decimal + conteo (misma
  /// convención que Estadísticas/Reputación — escala de la app, no 5 estrellas).
  /// Devuelve `null` (fila oculta) si el proveedor aún no tiene reseñas, para no
  /// mostrar un "0.0" que parezca mala nota.
  Widget? _ratingLine(BuildContext context, ColorScheme cs) {
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;
    if (avg <= 0 || count <= 0) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
        const SizedBox(width: 3),
        Text(avg.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context))),
        const SizedBox(width: 4),
        Text('($count)',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// Precio protagonista (20px, bold, violeta de marca). Un [FittedBox] deja
  /// que un rango largo ("RD$500 – RD$1,200") se encoja a una sola línea sin
  /// que los precios cortos se vean pequeños. "desde" va como prefijo tenue y
  /// "Consultar precio" en gris (no es una cifra: no debe gritar en violeta).
  Widget _priceLine(ColorScheme cs) {
    final price = item['price'] as num?;
    final min = item['price_min'] as num?;
    final max = item['price_max'] as num?;
    final big = TextStyle(
      fontSize: 20,
      height: 1,
      fontWeight: FontWeight.w700,
      color: cs.primary,
      letterSpacing: -.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (price == null && min == null) {
      return Text('Consultar precio',
          maxLines: 1,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant));
    }

    final Widget line;
    if (price != null) {
      line = Text(fmtRD(price), maxLines: 1, style: big);
    } else if (max != null) {
      // Guion simple con espacios: paridad EXACTA con `catalogPriceLabel` /
      // `formatProductHitPrice` de la web (no un guion largo tipográfico).
      line = Text('${fmtRD(min)} - ${fmtRD(max)}', maxLines: 1, style: big);
    } else {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('desde ',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant)),
          Text(fmtRD(min), style: big),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
          fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: line),
    );
  }

  Widget _imagePlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
      );
}
