import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_chip_strip.dart';
import 'catalog_filter_sheet.dart';
import 'catalog_header_widgets.dart';
import 'catalog_portada.dart';

/// Signature de la fuente de datos del catálogo (paridad `productHitsQ` de la
/// web). Inyectada en [CatalogView] para poder probar la pantalla sin red —
/// mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind,
    String? search,
    String? categoryId,
    String? rubro,
    bool wholesale});

/// Cabecera de los negocios dueños de los ítems, por lote (nombre, logo, local).
/// Best-effort: si falla, la pantalla se pinta sin tienda.
typedef CatalogBusinessesFetch = Future<Map<String, BusinessCardInfo>> Function(
    List<String> businessIds);

/// Conteo de artículos por categoría del kind (RPC `get_product_counts`).
/// `null` = no llegó: chips completos y sin sección «Por categoría».
typedef CatalogCountsFetch = Future<Map<String, int>?> Function(String kind);

/// Una carga del catálogo: los ítems y la cabecera de sus negocios.
typedef CatalogPage = ({
  List<Map<String, dynamic>> items,
  Map<String, BusinessCardInfo> negocios
});

/// Pestaña Catálogo. `?focus=1` (desde el buscador de Mis solicitudes) abre
/// con el buscador enfocado.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, this.autofocusSearch = false});
  final bool autofocusSearch;

  @override
  Widget build(BuildContext context) => CatalogView(
      fetch: catalogProductsWithRatings, autofocusSearch: autofocusSearch);
}

/// Cabecera + tira de chips + UN cuerpo de dos posibles (PO 2026-09-05,
/// camino 3): la PORTADA por secciones cuando no hay filtro, la REJILLA de dos
/// columnas cuando lo hay (categoría, mayoreo, búsqueda o «Ver todo»).
/// StatefulWidget con su propio [ScrollController] (nunca
/// `homeScrollController`: el `AnimatedSwitcher` del shell y `BackGuard`
/// revientan si dos pantallas comparten un único controller).
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.fetch,
    this.businesses = businessesCardInfo,
    this.counts = categoryCountsForKind,
    this.actions = const [HeaderBell()],
    this.autofocusSearch = false,
  });

  final CatalogFetch fetch;
  final CatalogBusinessesFetch businesses;
  final CatalogCountsFetch counts;
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

  /// «Ver todo» de Recién publicados: la rejilla SIN filtro. Se apaga al tocar
  /// «Todo» o al cambiar de kind. No re-pide nada: misma carga, otro cuerpo.
  bool _verTodo = false;

  /// Conteos por categoría del kind activo; `null` mientras llegan o si la
  /// RPC falló. Se piden una vez por kind.
  Map<String, int>? _counts;

  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  /// Header plegado al navegar (pedido PO: TODO el header se esconde y queda
  /// la flecha — mismo gesto que Tus solicitudes).
  bool _headerHidden = false;

  /// Regla de la spec §2.3: con cualquier filtro se pinta la rejilla.
  bool get _filtrado =>
      _categoryId != null || _wholesale || _search != null || _verTodo;

  /// Esconde/muestra el header COMPLETO según la DIRECCIÓN del gesto (calco de
  /// `my_requests_screen`). Solo `UserScrollNotification` — ignora el relayout
  /// del propio colapso, que antes reabría el header solo (bug 2026-07-21).
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

  late Future<CatalogPage> _load = _fetchPage();

  /// Productos (+ valoraciones, ya horneadas por `fetch`) y, en una segunda
  /// llamada por lote, la cabecera de sus negocios. La segunda es un adorno:
  /// si falla, se sigue sin tienda — NUNCA se tira la pantalla a error.
  Future<CatalogPage> _fetchPage() async {
    final items = await widget.fetch(
        kind: _kind,
        search: _search,
        categoryId: _categoryId,
        rubro: _rubro,
        wholesale: _wholesale);
    final ids = <String>{
      for (final it in items)
        if (it['business_id'] is String) it['business_id'] as String,
    }.toList();
    final negocios = await widget
        .businesses(ids)
        .catchError((_) => <String, BusinessCardInfo>{});
    return (items: items, negocios: negocios);
  }

  void _loadCounts() {
    final kind = _kind;
    widget.counts(kind).then((c) {
      if (mounted && _kind == kind) setState(() => _counts = c);
    }, onError: (_) {});
  }

  // Bloque, no expresión: el mismo gotcha documentado en inbox_screen.dart —
  // `setState(() => _load = future)` hace que la closure DEVUELVA el Future.
  // `.ignore()`: si `next` falla ANTES del frame en que `FutureBuilder`
  // reengancha su listener, Dart lo reportaría como no manejado aunque la UI
  // sí lo muestre después vía `snapshot.hasError`.
  void _refetch() {
    final next = _fetchPage()..ignore();
    setState(() {
      _load = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadCounts();
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

  /// Mutador de categoría/rubro: reemplaza ambos a la vez porque un rubro
  /// siempre vive dentro de una categoría.
  void _applyFilter({String? categoryId, String? rubro}) {
    setState(() {
      _categoryId = categoryId;
      _rubro = rubro;
      _verTodo = false;
    });
    _refetch();
  }

  /// Chip «Todo»: quita categoría/rubro y apaga «Ver todo». Solo re-pide si
  /// había categoría (apagar «Ver todo» no cambia la carga).
  void _volverAPortada() {
    final habiaCategoria = _categoryId != null || _rubro != null;
    setState(() {
      _categoryId = null;
      _rubro = null;
      _verTodo = false;
    });
    if (habiaCategoria) _refetch();
  }

  /// «Quitar filtro» del estado vacío: limpia TODO y vuelve a la portada.
  void _quitarTodo() {
    _searchCtrl.clear();
    setState(() {
      _search = null;
      _categoryId = null;
      _rubro = null;
      _wholesale = false;
      _verTodo = false;
    });
    _refetch();
  }

  Future<void> _openFilter() async {
    final res = await showCatalogFilterSheet(context,
        kind: _kind, categoryId: _categoryId, rubro: _rubro);
    if (res != null) _applyFilter(categoryId: res.categoryId, rubro: res.rubro);
  }

  void _toggleWholesale(bool on) {
    setState(() => _wholesale = on);
    _refetch();
  }

  void _changeKind(int i) {
    setState(() {
      _kind = i == 0 ? 'producto' : 'servicio';
      _categoryId = null; // cambiar de kind limpia el filtro
      _rubro = null;
      _verTodo = false;
      _counts = null;
      // El mayoreo es SOLO de productos (paridad web).
      if (_kind == 'servicio') _wholesale = false;
    });
    _refetch();
    _loadCounts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _chips() => CatalogChipStrip(
        categorias: categoriasNavegables(kCategories, _counts?.keys.toSet(),
            seleccionada: _categoryId),
        categoryId: _categoryId,
        wholesale: _kind == 'producto' ? _wholesale : null,
        onWholesale: _toggleWholesale,
        onCategory: (id) => _applyFilter(categoryId: id),
        onTodo: _volverAPortada,
      );

  Widget _rejilla(CatalogPage page) => LayoutBuilder(builder: (context, box) {
        final cellWidth = (box.maxWidth - 32 - 11) / 2;
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _chips()),
            SliverPadding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: 12 + navBarReservedSpace(context)),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 11,
                  mainAxisSpacing: 11,
                  mainAxisExtent: catalogGridCardExtent(context, cellWidth),
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ProductGridCard(
                    item: page.items[i],
                    negocio: page.negocios[page.items[i]['business_id']],
                  ).cascadeIn(i),
                  childCount: page.items.length,
                ),
              ),
            ),
          ],
        );
      });

  Widget _portada(CatalogPage page) => CatalogPortada(
        controller: _scrollController,
        header: _chips(),
        items: page.items,
        negocios: page.negocios,
        counts: _counts,
        onVerTodo: () => setState(() => _verTodo = true),
        onCategory: (id) => _applyFilter(categoryId: id),
        onStore: (id) => context.push('/store/$id'),
      );

  Widget _vacio() => Column(children: [
        _chips(),
        Expanded(
          child: EmptyState(
            controller: _scrollController,
            message: _filtrado
                ? 'No hay artículos que coincidan con tu filtro.'
                : 'Aún no hay artículos publicados en esta '
                    'categoría.\n\nVuelve más tarde: los '
                    'proveedores publican todos los días.',
            ctaLabel: _filtrado ? 'Quitar filtro' : null,
            onCta: _filtrado ? _quitarTodo : null,
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) => OnboardingGuide(
        guideKey: 'client.catalog.v1',
        steps: onboardingCopy['client.catalog.v1']!,
        mode: OnboardingMode.welcome,
        child: Scaffold(
          body: Column(children: [
            // Misma anatomía que las demás pestañas: avatar (o atrás si viene
            // apilada como «Otros proveedores»), título a la izquierda,
            // segmentado compacto y campana; debajo, UNA fila con buscador y
            // Filtrar. Se pliega completo al navegar (PO 2026-07-21).
            CollapsibleHeader(
              hidden: _headerHidden,
              onReveal: () => setState(() => _headerHidden = false),
              child: VioletHeader(
                leading: const HeaderLeading(),
                title: 'Catálogo',
                actions: [
                  HeaderSegmented(
                    compact: true,
                    options: const ['Producto', 'Servicio'],
                    index: _kind == 'producto' ? 0 : 1,
                    onChanged: _changeKind,
                  ),
                  const SizedBox(width: 8),
                  ...widget.actions,
                ],
                below: Row(children: [
                  Expanded(
                    child: CatalogSearchField(
                      controller: _searchCtrl,
                      hint: 'Buscar en el catálogo',
                      autofocus: widget.autofocusSearch,
                      onSubmitted: _applySearch,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CatalogFilterPill(
                    label: _categoryId == null
                        ? 'Filtrar'
                        : (categoryNameById(_categoryId) ?? 'Filtrar'),
                    active: _categoryId != null,
                    onTap: _openFilter,
                    onClear: _categoryId != null ? _volverAPortada : null,
                  ),
                ]),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onListScroll,
                child: JayaloRefresh(
                  onRefresh: () async => _refetch(),
                  child: FutureBuilder<CatalogPage>(
                    future: _load,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const JayaloLoaderBlock();
                      }
                      if (snap.hasError) {
                        return ErrorRetry(onRetry: () async => _refetch());
                      }
                      final page = snap.data ??
                          (items: const <Map<String, dynamic>>[], negocios: const <String, BusinessCardInfo>{});
                      if (page.items.isEmpty) return _vacio();
                      return _filtrado ? _rejilla(page) : _portada(page);
                    },
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
