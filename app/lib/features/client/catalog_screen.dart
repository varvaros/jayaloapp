import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_filter_sheet.dart';

/// Signature de la fuente de datos del catálogo (paridad `productHitsQ` de la
/// web). Inyectada en [CatalogView] para poder probar la pantalla sin red —
/// mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale});

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
  String? _categoryId;
  String? _rubro;
  bool _wholesale = false;
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  /// Header plegado al navegar (pedido PO: TODO el header se esconde y queda
  /// la flecha — mismo gesto que Tus solicitudes).
  bool _headerHidden = false;

  /// Esconde/muestra el header COMPLETO según la DIRECCIÓN del gesto (calco de
  /// `my_requests_screen`): arrastrar hacia arriba pliega, hacia abajo baja.
  /// Solo `UserScrollNotification` — ignora el relayout del propio colapso, que
  /// antes reabría el header solo (bug "no se oculta", 2026-07-21).
  bool _onListScroll(ScrollNotification n) {
    if (n is! UserScrollNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && !_headerHidden) {
      setState(() => _headerHidden = true);
    } else if (n.direction == ScrollDirection.forward && _headerHidden) {
      setState(() => _headerHidden = false);
    }
    return false;
  }

  late Future<List<Map<String, dynamic>>> _load = widget.fetch(
      kind: _kind,
      search: _search,
      categoryId: _categoryId,
      rubro: _rubro,
      wholesale: _wholesale);

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
    final next = widget.fetch(
        kind: _kind,
        search: _search,
        categoryId: _categoryId,
        rubro: _rubro,
        wholesale: _wholesale)
      ..ignore();
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

  /// Mutador de categoría/rubro (lo usan los filtros de Task 5/6): reemplaza
  /// ambos a la vez porque un rubro siempre vive dentro de una categoría — no
  /// tiene sentido aplicar uno sin el otro.
  void _applyFilter({String? categoryId, String? rubro}) {
    setState(() {
      _categoryId = categoryId;
      _rubro = rubro;
    });
    _refetch();
  }

  /// Abre la hoja de filtro (Task 6) y aplica el resultado — `null` significa
  /// que el usuario cerró sin cambiar nada.
  Future<void> _openFilter() async {
    final res = await showCatalogFilterSheet(context,
        categoryId: _categoryId, rubro: _rubro);
    if (res != null) _applyFilter(categoryId: res.categoryId, rubro: res.rubro);
  }

  void _toggleWholesale(bool on) {
    setState(() => _wholesale = on);
    _refetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingGuide(
        guideKey: 'client.catalog.v1',
        steps: onboardingCopy['client.catalog.v1']!,
        mode: OnboardingMode.welcome,
        child: Scaffold(
        body: Column(children: [
          // Header violeta: segmento Producto/Servicio a la izquierda, título
          // "Catálogo" a la derecha, campana, y el buscador (funcional) debajo.
          // Se pliega completo al navegar la lista (pedido PO 2026-07-21).
          CollapsibleHeader(
            hidden: _headerHidden,
            onReveal: () => setState(() => _headerHidden = false),
            child: VioletHeader(
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
                  setState(() {
                    _kind = i == 0 ? 'producto' : 'servicio';
                    _categoryId = null; // cambiar de kind limpia el filtro
                    _rubro = null;
                    // El mayoreo es SOLO de productos (paridad web): al pasar a
                    // servicio se apaga para que el toggle oculto no deje un
                    // filtro invisible activo.
                    if (_kind == 'servicio') _wholesale = false;
                  });
                  _refetch();
                },
              ),
            ]),
            title: 'Catálogo',
            titleAlign: HeaderTitleAlign.end,
            actions: widget.actions,
            below: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "Al detalle / Al por mayor" es SOLO de productos (paridad
                // web: el mayoreo no aplica a servicios). En Servicio se oculta;
                // la distinción de servicios (Único/Por contrato) llegará con la
                // Tienda del proveedor — hoy no hay dato para filtrarla.
                if (_kind == 'producto') ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HeaderSegmented(
                      options: const ['Al detalle', 'Al por mayor'],
                      index: _wholesale ? 1 : 0,
                      onChanged: (i) => _toggleWholesale(i == 1),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  Expanded(
                    child: _HeaderSearchField(
                      controller: _searchCtrl,
                      hint: 'Buscar en el catálogo',
                      autofocus: widget.autofocusSearch,
                      onSubmitted: _applySearch,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: _categoryId == null
                        ? 'Filtrar'
                        : (categoryNameById(_categoryId) ?? 'Filtrar'),
                    active: _categoryId != null,
                    onTap: _openFilter,
                    onClear:
                        _categoryId != null ? () => _applyFilter() : null,
                  ),
                ]),
              ],
            ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onListScroll,
              child: JayaloRefresh(
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
                      message: (_search != null || _categoryId != null)
                          ? 'No hay artículos que coincidan con tu filtro.'
                          : 'Aún no hay artículos publicados en esta '
                              'categoría.\n\nVuelve más tarde: los '
                              'proveedores publican todos los días.',
                      ctaLabel: (_search != null || _categoryId != null)
                          ? 'Quitar filtro'
                          : null,
                      onCta: (_search != null || _categoryId != null)
                          ? () {
                              _searchCtrl.clear();
                              setState(() {
                                _search = null;
                                _categoryId = null;
                                _rubro = null;
                              });
                              _refetch();
                            }
                          : null,
                    );
                  }
                  // Rejilla de tienda a 2 columnas (mockup aprobado PO
                  // 2026-08-10): la foto manda y se ve el doble de artículos
                  // por pantalla — sustituye a la lista ancha de una columna.
                  return GridView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 10,
                        bottom: 12 + navBarReservedSpace(context)),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 11,
                      mainAxisSpacing: 11,
                      // 238 → 256: hueco para la fila de atributos
                      // (envío/estado/color) de la Variante A (PO 2026-08-11).
                      // Ese 256 era fijo y el precio se salía por abajo con la
                      // fuente del sistema en grande: ahora lo calcula la
                      // tarjeta a partir de la escala tipográfica.
                      mainAxisExtent: catalogGridCardExtent(context),
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        ProductGridCard(item: items[i]).cascadeIn(i),
                  );
                },
              ),
            ),
            ),
          ),
        ]),
        ),
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

/// Píldora "Filtrar" de la fila de búsqueda (Task 6): abre
/// [showCatalogFilterSheet]; cuando hay categoría activa muestra su nombre y
/// una ✕ para limpiar sin reabrir la hoja.
class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.label,
      required this.active,
      required this.onTap,
      this.onClear});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.onPrimaryContainer,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.tune, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white)),
            ),
            if (active && onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
