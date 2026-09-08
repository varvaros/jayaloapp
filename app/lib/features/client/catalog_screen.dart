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
import 'catalog_articulos.dart';
import 'catalog_chip_strip.dart';
import 'catalog_filter_sheet.dart';
import 'catalog_header_widgets.dart';
import 'catalog_secciones.dart';
import 'catalog_tipo_strip.dart';

/// Fuente de datos del catálogo POR ARTÍCULOS (productos, servicios y paquetes
/// en la MISMA carga). Inyectada en [CatalogView] para probar la pantalla sin
/// red — mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch =
    Future<List<Map<String, dynamic>>> Function({
      String? kind,
      String? search,
      String? categoryId,
      String? rubro,
      bool wholesale,
      bool conPaquetes,
    });

/// Cabecera de los negocios dueños de los ítems, por lote.
typedef CatalogBusinessesFetch =
    Future<Map<String, BusinessCardInfo>> Function(List<String> businessIds);

/// Conteo por categoría de productos Y servicios juntos; `null` = no llegó.
typedef CatalogCountsFetch = Future<Map<String, int>?> Function();

/// Proveedores cuyo NOMBRE coincide con la búsqueda (no solo los dueños).
typedef CatalogNamesFetch = Future<List<Proveedor>> Function(String term);

/// Una carga: ítems, cabecera de sus negocios y proveedores que coinciden por
/// nombre con la búsqueda (vacío sin búsqueda).
typedef CatalogPage = ({
  List<Map<String, dynamic>> items,
  Map<String, BusinessCardInfo> negocios,
  List<Proveedor> nombres,
});

/// Pestaña Catálogo. `?focus=1` (desde el buscador de Mis solicitudes) abre
/// con el buscador enfocado.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, this.autofocusSearch = false});
  final bool autofocusSearch;

  @override
  Widget build(BuildContext context) =>
      CatalogView(autofocusSearch: autofocusSearch);
}

/// Cabecera + tira de tipo + tira de chips + UN cuerpo de tres posibles (PO
/// 2026-09-07, catálogo por artículos): las SECCIONES con «Todos» y sin
/// búsqueda ni mayoreo, la LISTA de proveedores en el tipo Proveedores, y la
/// REJILLA en cualquier otro caso. Crear una solicitud NO vive aquí: está en
/// el «+» de la navbar flotante (doctrina PO). StatefulWidget con su propio
/// [ScrollController] (nunca `homeScrollController`: el `AnimatedSwitcher` del
/// shell y `BackGuard` revientan si dos pantallas comparten uno).
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    this.fetch = catalogItemsWithRatings,
    this.businesses = businessesCardInfo,
    this.counts = categoryCountsUnion,
    this.names = catalogBusinessesByName,
    this.actions = const [HeaderBell()],
    this.autofocusSearch = false,
  });

  final CatalogFetch fetch;
  final CatalogBusinessesFetch businesses;
  final CatalogCountsFetch counts;
  final CatalogNamesFetch names;
  final List<Widget> actions;
  final bool autofocusSearch;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  /// `todos | producto | servicio | paquete | proveedor` (claves de
  /// [CatalogTipoStrip]). Filtra EN CLIENTE la misma carga: no re-pide.
  String _tipo = 'todos';
  String? _search;
  String? _categoryId;
  String? _rubro;
  bool _wholesale = false;

  /// Ciudad/precio/verificado/local: de cliente, como en la web.
  FiltrosLateral _filtros = kSinFiltros;

  /// Conteos por categoría; `null` mientras llegan o si la RPC falló.
  Map<String, int>? _counts;

  /// Rubros de la categoría activa (segunda fila de chips).
  List<String> _rubros = const [];

  /// Última página cargada, para poder derivar las ciudades de la hoja de
  /// filtros SIN mutar estado en `build`: la hoja se abre desde la cabecera,
  /// fuera del `FutureBuilder` que conoce los negocios.
  CatalogPage? _pagina;

  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  /// Header plegado al navegar (pedido PO: TODO el header se esconde y queda
  /// la flecha — mismo gesto que Tus solicitudes).
  bool _headerHidden = false;

  /// Las secciones son la portada: solo con «Todos», sin búsqueda y sin
  /// mayoreo (una categoría activa las conserva, ya filtradas).
  bool get _verSecciones => _tipo == 'todos' && _search == null && !_wholesale;

  /// Filtros del lateral puestos (para la píldora «Filtrar · n»).
  int get _nLateral =>
      (_filtros.ciudad != null ? 1 : 0) +
      (_filtros.precioMin > 0 ? 1 : 0) +
      (_filtros.precioMax > 0 ? 1 : 0) +
      (_filtros.soloVerificados ? 1 : 0) +
      (_filtros.conLocal ? 1 : 0);

  bool get _pildoraActiva => _categoryId != null || _nLateral > 0;

  /// Etiqueta de la píldora: la categoría, o cuántos filtros del lateral hay
  /// puestos, o «Filtrar» a secas.
  String get _pildoraLabel =>
      (_categoryId == null ? null : categoryNameById(_categoryId)) ??
      (_nLateral > 0 ? 'Filtrar · $_nLateral' : 'Filtrar');

  /// Hay algo que quitar: lo dice el CTA «Quitar filtro» del estado vacío.
  bool get _filtrado =>
      _tipo != 'todos' ||
      _categoryId != null ||
      _rubro != null ||
      _search != null ||
      _wholesale ||
      _filtros != kSinFiltros;

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

  /// Adorno de la carga: tope de 4 s y, ante cualquier fallo, [vacio] — nunca
  /// una pantalla de error. El `async` de [reificado] es OBLIGATORIO: un doble
  /// inyectado (test) cuyo cuerpo SOLO lanza se infiere como `Future<Never>`, y
  /// `.timeout()` DIRECTO sobre ese objeto revienta en tiempo de ejecución al
  /// comparar `onTimeout` contra `Never` (gotcha de Dart: covarianza de
  /// `Future`; `Future<T>.sync` NO basta, devuelve el mismo objeto).
  Future<T> _adorno<T>(Future<T> Function() pedir, T vacio) async {
    Future<T> reificado() async => pedir();
    try {
      return await reificado().timeout(
        const Duration(seconds: 4),
        onTimeout: () => vacio,
      );
    } catch (_) {
      return vacio;
    }
  }

  /// Artículos y, EN SERIE tras ellos (sus ids salen de ahí), los adornos: la
  /// cabecera de sus negocios y —solo con búsqueda— los proveedores por nombre.
  /// `kind`: con mayoreo solo hay productos (es de `provider_products`); sin
  /// él, los tres tipos. `conPaquetes`: un paquete no tiene categoría, rubro ni
  /// mayoreo en la base, así que con esos filtros no podría respetarlos.
  Future<CatalogPage> _fetchPage() async {
    final search = _search;
    final items = await widget.fetch(
      kind: _wholesale ? 'producto' : null,
      search: search,
      categoryId: _categoryId,
      rubro: _rubro,
      wholesale: _wholesale,
      conPaquetes: !_wholesale && _categoryId == null && _rubro == null,
    );
    final ids = <String>{
      for (final it in items)
        if (it['business_id'] is String) it['business_id'] as String,
    }.toList();
    final negocios = await _adorno(
      () => widget.businesses(ids),
      const <String, BusinessCardInfo>{},
    );
    final nombres = search == null
        ? const <Proveedor>[]
        : await _adorno(() => widget.names(search), const <Proveedor>[]);
    final page = (items: items, negocios: negocios, nombres: nombres);
    _pagina = page;
    return page;
  }

  void _loadCounts() {
    widget.counts().then((c) {
      if (mounted) setState(() => _counts = c);
    }, onError: (_) {});
  }

  /// Rubros de la categoría elegida. Best-effort: ante un fallo, fila vacía.
  void _loadRubros(String? categoryId) {
    setState(() => _rubros = const []);
    if (categoryId == null) return;
    rubrosForCategories([categoryId]).then((rows) {
      if (!mounted || _categoryId != categoryId) return;
      setState(() => _rubros = [for (final r in rows) r['name'] as String]);
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

  /// Tipo activo: NO re-pide nada — misma carga, otro cuerpo.
  void _setTipo(String tipo) {
    if (tipo == _tipo) return;
    setState(() => _tipo = tipo);
  }

  /// Categoría y rubro se reemplazan a la vez (un rubro vive dentro de una
  /// categoría) y SÍ re-piden: los filtra el servidor. Los rubros solo se
  /// vuelven a pedir si la categoría en sí cambió (evita una consulta de más
  /// al solo cambiar de rubro dentro de la misma categoría).
  void _applyFilter({String? categoryId, String? rubro}) {
    if (categoryId != _categoryId) _loadRubros(categoryId);
    setState(() {
      _categoryId = categoryId;
      _rubro = rubro;
    });
    _refetch();
  }

  /// ✕ de la píldora: quita lo que la píldora dice — categoría/rubro y los
  /// filtros del lateral, que también cuentan en su etiqueta.
  void _limpiarPildora() {
    setState(() => _filtros = kSinFiltros);
    if (_categoryId != null || _rubro != null) _applyFilter();
  }

  /// «Quitar filtro» del estado vacío: limpia TODO y vuelve a las secciones.
  void _quitarTodo() {
    _searchCtrl.clear();
    setState(() {
      _tipo = 'todos';
      _search = _categoryId = _rubro = null;
      _wholesale = false;
      _filtros = kSinFiltros;
      _rubros = const [];
    });
    _refetch();
  }

  /// La hoja devuelve TODO el filtro. Solo se re-pide si cambió lo que filtra
  /// el SERVIDOR: el lateral es de cliente.
  Future<void> _openFilter() async {
    final negocios = _pagina?.negocios ?? const <String, BusinessCardInfo>{};
    final negociosCat = {
      for (final e in negocios.entries) e.key: negocioCatalogoDe(e.value),
    };
    final ciudades = ciudadesDe(negociosCat, seleccionada: _filtros.ciudad);
    final res = await showCatalogFilterSheet(
      context,
      categoryId: _categoryId,
      rubro: _rubro,
      ciudades: ciudades,
      filtros: _filtros,
    );
    if (res == null || !mounted) return;
    final cambia = res.categoryId != _categoryId || res.rubro != _rubro;
    setState(() {
      _filtros = (
        ciudad: res.ciudad,
        precioMin: res.precioMin,
        precioMax: res.precioMax,
        soloVerificados: res.soloVerificados,
        conLocal: res.conLocal,
      );
      _categoryId = res.categoryId;
      _rubro = res.rubro;
    });
    if (cambia) {
      _refetch();
      _loadRubros(res.categoryId);
    }
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

  void _abrirTienda(String id) => context.push('/store/$id');

  Widget _chips(Map<String, int> conteos) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CatalogTipoStrip(tipo: _tipo, conteos: conteos, onTipo: _setTipo),
      CatalogChipStrip(
        categorias: categoriasNavegables(
          kCategories,
          _counts?.keys.toSet(),
          seleccionada: _categoryId,
        ),
        categoryId: _categoryId,
        // El mayoreo es SOLO de productos (paridad web), pero si el mayoreo
        // está encendido el chip se ve siempre: apagarlo es la única salida.
        wholesale: (_tipo == 'todos' || _tipo == 'producto' || _wholesale)
            ? _wholesale
            : null,
        onWholesale: _toggleWholesale,
        onCategory: (id) {
          if (id != _categoryId) _applyFilter(categoryId: id);
        },
        // «Todo»: sin categoría ni rubro no hay nada que re-pedir.
        onTodo: () {
          if (_categoryId != null || _rubro != null) _applyFilter();
        },
        rubros: _categoryId == null ? const [] : _rubros,
        rubro: _rubro,
        onRubro: (r) => _applyFilter(categoryId: _categoryId, rubro: r),
      ),
    ],
  );

  Widget _rejilla(
    List<Map<String, dynamic>> items,
    Map<String, BusinessCardInfo> negocios,
    Map<String, int> conteos,
    List<Proveedor> coinciden,
  ) => LayoutBuilder(
    builder: (context, box) {
      final cellWidth = (box.maxWidth - 32 - 11) / 2;
      final alto = catalogGridCardExtent(
        context,
        cellWidth,
        conIncluido: _tipo == 'paquete',
      );
      return CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: _chips(conteos)),
          if (_search != null)
            SliverToBoxAdapter(
              child: ProveedoresCoinciden(
                proveedores: coinciden,
                onStore: _abrirTienda,
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

  /// Sin artículos del tipo activo pero con proveedores que coinciden por
  /// nombre (búsqueda tipo «ferreter» sobre «Ferretería Central» sin
  /// artículos propios en el filtro actual): la píldoras + un aviso, en vez
  /// del vacío.
  Widget _soloCoinciden(List<Proveedor> coinciden, Map<String, int> conteos) =>
      ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
        children: [
          _chips(conteos),
          ProveedoresCoinciden(proveedores: coinciden, onStore: _abrirTienda),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Sin artículos para «$_search»; estos proveedores coinciden '
              'por nombre.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );

  /// Lista del tipo Proveedores: los que coinciden por nombre con la
  /// búsqueda primero, luego los demás dueños de ítems, sin repetidos.
  Widget _listaProveedores(
    List<Proveedor> ps,
    Map<String, int> conteos,
    List<Proveedor> coinciden,
  ) {
    final vistos = <String>{};
    final lista = [
      for (final p in [...coinciden, ...ps])
        if (vistos.add(p.id)) p,
    ];
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
      children: [
        _chips(conteos),
        const SizedBox(height: 6),
        for (var i = 0; i < lista.length; i++)
          ProveedorCard(
            p: lista[i],
            onTap: () => _abrirTienda(lista[i].id),
          ).cascadeIn(i),
      ],
    );
  }

  Widget _vacio(Map<String, int> conteos) => Column(
    children: [
      _chips(conteos),
      Expanded(
        child: EmptyState(
          controller: _scrollController,
          message: _tipo == 'proveedor'
              ? 'No hay proveedores que coincidan con tu filtro.'
              : _filtrado
              ? 'No hay artículos que coincidan con tu filtro.'
              : 'Aún no hay artículos publicados en esta '
                    'categoría.\n\nVuelve más tarde: los '
                    'proveedores publican todos los días.',
          ctaLabel: _filtrado ? 'Quitar filtro' : null,
          onCta: _filtrado ? _quitarTodo : null,
        ),
      ),
    ],
  );

  /// Cuerpo con los derivados PUROS de la carga (`catalog_articulos.dart`):
  /// nada pide red, todo sale de `page` y de los filtros vigentes. El tope 90
  /// es para la LISTA del tipo Proveedores (el riel recorta por su cuenta).
  Widget _cuerpo(CatalogPage page) {
    final negociosCat = {
      for (final e in page.negocios.entries) e.key: negocioCatalogoDe(e.value),
    };
    final hits = ordenarCatalogo(
      filtrarLateral(page.items, negociosCat, _filtros),
    );
    final proveedores = proveedoresDeItems(hits, negociosCat, tope: 90);
    // Antes de decidir si hay algo que pintar: los proveedores que coinciden
    // por NOMBRE con la búsqueda son alcanzables aunque 0 artículos matcheen.
    final coinciden = _coinciden(proveedores, page);
    int n(String k) => hits.where((it) => tipoDeItem(it) == k).length;
    final conteos = {
      'todos': hits.length,
      'producto': n('producto'),
      'servicio': n('servicio'),
      'paquete': n('paquete'),
      'proveedor': proveedores.length,
    };
    final hitsDeTipo = _tipo == 'todos'
        ? hits
        : hits.where((it) => tipoDeItem(it) == _tipo).toList();
    final hayQuePintar = _tipo == 'proveedor'
        ? (proveedores.isNotEmpty || coinciden.isNotEmpty)
        : (hitsDeTipo.isNotEmpty || coinciden.isNotEmpty);

    if (!hayQuePintar) return _vacio(conteos);
    if (_verSecciones) {
      return CatalogSecciones(
        controller: _scrollController,
        header: _chips(conteos),
        items: hits,
        negocios: page.negocios,
        proveedores: proveedores,
        conteos: (
          productos: conteos['producto']!,
          servicios: conteos['servicio']!,
          paquetes: conteos['paquete']!,
          proveedores: proveedores.length,
        ),
        onVerTodos: _setTipo,
        onStore: _abrirTienda,
      );
    }
    if (_tipo == 'proveedor') {
      return _listaProveedores(proveedores, conteos, coinciden);
    }
    if (hitsDeTipo.isEmpty && coinciden.isNotEmpty) {
      return _soloCoinciden(coinciden, conteos);
    }
    return _rejilla(hitsDeTipo, page.negocios, conteos, coinciden);
  }

  /// «Que coinciden» con la búsqueda: los de la consulta por nombre primero,
  /// luego los dueños de ítems cuyo nombre encaja, sin repetidos.
  List<Proveedor> _coinciden(List<Proveedor> deItems, CatalogPage page) {
    final q = _search;
    if (q == null) return const [];
    final vistos = <String>{};
    return [
      for (final p in [
        ...page.nombres,
        ...deItems.where((p) => coincideBusqueda(p.name, q)),
      ])
        if (vistos.add(p.id)) p,
    ];
  }

  /// Misma anatomía que las demás pestañas: avatar (o atrás si viene apilada
  /// como «Otros proveedores»), título a la izquierda y campana; debajo, UNA
  /// fila con buscador y Filtrar. El tipo de artículo ya NO vive aquí (lo manda
  /// la tira de chips). Se pliega completo al navegar (PO 2026-07-21).
  Widget _cabecera() => CollapsibleHeader(
    hidden: _headerHidden,
    onReveal: () => setState(() => _headerHidden = false),
    child: VioletHeader(
      leading: const HeaderLeading(),
      title: 'Catálogo',
      actions: widget.actions,
      below: Row(
        children: [
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
            label: _pildoraLabel,
            active: _pildoraActiva,
            onTap: _openFilter,
            onClear: _pildoraActiva ? _limpiarPildora : null,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => OnboardingGuide(
    guideKey: 'client.catalog.v1',
    steps: onboardingCopy['client.catalog.v1']!,
    mode: OnboardingMode.welcome,
    child: Scaffold(
      body: Column(
        children: [
          _cabecera(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onListScroll,
              child: JayaloRefresh(
                onRefresh: () async {
                  _refetch();
                  _loadCounts();
                },
                child: FutureBuilder<CatalogPage>(
                  future: _load,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const JayaloLoaderBlock();
                    }
                    if (snap.hasError) {
                      return ErrorRetry(onRetry: () async => _refetch());
                    }
                    return _cuerpo(
                      snap.data ??
                          (
                            items: const [],
                            negocios: const {},
                            nombres: const [],
                          ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
