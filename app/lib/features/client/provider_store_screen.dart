import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/profile_sections.dart';
import '../shared/brand_kit.dart';
import '../shared/business_cover_hero.dart';
import '../shared/business_details_card.dart';
import '../shared/open_in_maps_button.dart';
import '../shared/portfolio_gallery_viewer.dart';
import '../shared/product_list_card.dart';
import '../shared/service_chips_editor.dart';
import '../shared/team_gallery_block.dart';
import '../shared/tile_carril.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Tienda de un proveedor: al tocar el nombre del proveedor en una oferta o
/// en el catálogo, el cliente ve los productos, servicios, paquetes y
/// trabajos anteriores del negocio, con su identidad real (PO 2026-07-28:
/// nombre y logo sin desbloquear nada — el contacto sigue sin ser
/// accesible). `provider_products` y `provider_portfolio_items` tienen
/// lectura pública, así que se leen por `business_id` sin exponer datos de
/// contacto; `provider_packages` la obtuvo con la migración
/// `20260809130000_packages_public_read.sql` (pedido PO 2026-08-09).
///
/// Pedido PO 2026-08-09: "Debería verse como una sola página, con todo, y
/// los paquetes y trabajos con scroll horizontal, con todo lo que se ha
/// hecho del lado del proveedor, pero debe verse del lado del cliente" — ya
/// no hay pestañas (`HeaderSegmented`/`_Section`, retirados en esta tarea):
/// TODAS las secciones se pintan una debajo de otra en el mismo scroll, en
/// un orden fijo (antes se reordenaba según el tipo de negocio; el PO pidió
/// un único orden para todos).
class ProviderStoreScreen extends StatefulWidget {
  const ProviderStoreScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<ProviderStoreScreen> createState() => _ProviderStoreScreenState();
}

class _ProviderStoreScreenState extends State<ProviderStoreScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _productos = const [];
  List<Map<String, dynamic>> _servicios = const [];
  List<Map<String, dynamic>> _portfolio = const [];
  List<Map<String, dynamic>> _paquetes = const [];
  // Bloque de confianza bajo el nombre (adorno, no bloquea la tienda si falla):
  // rating, trabajos completados, tiempo de respuesta, miembro-desde y sellos.
  BusinessStorefrontStats? _stats;
  // Identidad real del negocio (PO 2026-07-28). `null` mientras carga o si
  // falla — degrada a "Proveedor" sin logo, nunca rompe la pantalla.
  BusinessIdentity? _identity;

  /// Sello "Tienda física" (PO 2026-08-12), AUTODECLARADO — ver doc de
  /// `businessesPhysicalLocation`. Vive fuera de `_identity` a propósito: esa
  /// consulta no pide la columna nueva, así que aunque la migración que la
  /// crea todavía no esté aplicada, el nombre/logo/servicios del negocio
  /// siguen cargando con normalidad.
  bool _hasPhysicalLocation = false;

  /// Coordenadas del negocio para el boton "Ver en el mapa" (Task 11). Null
  /// mientras carga, si la reja de `get_business_location` no deja pasar al
  /// cliente, o si el negocio no las tiene — `businessLocation` (repos.dart)
  /// ya colapsa las dos formas de "sin coordenadas" (lista vacia o fila con
  /// `lat`/`lng` en null) a un solo `null`.
  ({double lat, double lng})? _location;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Bloque de confianza: adorno bajo el nombre. Si la RPC falla, el bloque
      // simplemente no aparece — nunca se tira la tienda a la pantalla de error.
      final statsF = businessStorefrontStats(widget.businessId)
          .catchError((_) => null);
      // Identidad: si falla, degrada a "Proveedor" sin logo (no rompe la
      // pantalla — mismo trato best-effort que el resto de este bloque).
      final identityF =
          businessPublicIdentity(widget.businessId).catchError((_) => null);
      // Paquetes: mientras la migración `20260809130000_packages_public_read
      // .sql` no esté aplicada, RLS filtra a lista vacía sin lanzar — igual
      // trato best-effort, la sección de PAQUETES simplemente no se pinta.
      final paquetesF = storePackages(widget.businessId)
          .catchError((_) => <Map<String, dynamic>>[]);
      // `businessesPhysicalLocation` ya degrada a `{}` internamente si la
      // columna aún no existe — no hace falta `.catchError` aquí.
      final physicalF = businessesPhysicalLocation([widget.businessId]);
      // `businessLocation` (Task 11) ya captura sus propios errores y
      // colapsa "sin permiso"/"sin coordenadas" a null — no hace falta
      // `.catchError` aqui tampoco.
      final locationF = businessLocation(widget.businessId);
      final results = await Future.wait([
        myStoreProducts(widget.businessId),
        myPortfolioItems(widget.businessId),
      ]);
      final (prod, serv) = partitionStoreItems(results[0]);
      final portfolio = results[1];
      final stats = await statsF;
      final identity = await identityF;
      final paquetes = await paquetesF;
      final physical = await physicalF;
      final location = await locationF;
      if (!mounted) return;
      setState(() {
        _productos = prod;
        _servicios = serv;
        _portfolio = portfolio;
        _paquetes = paquetes;
        _stats = stats;
        _identity = identity;
        _hasPhysicalLocation = physical[widget.businessId] ?? false;
        _location = location;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          VioletHeader(
            leading: HeaderCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Atrás',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: _identity?.name ?? 'Proveedor',
            subtitle: 'Tienda del proveedor',
          ),
          Expanded(
            child: _loading
                ? const JayaloLoaderBlock()
                : ProviderStoreView(
                    identity: _identity,
                    stats: _stats,
                    hasPhysicalLocation: _hasPhysicalLocation,
                    location: _location,
                    productos: _productos,
                    servicios: _servicios,
                    paquetes: _paquetes,
                    trabajos: _portfolio,
                  ),
          ),
        ]),
      );
}

/// Solo dibuja, sin fetch propio — separada de [ProviderStoreScreen] (que
/// carga por red) para poder probarla con datos ya en mano, mismo patrón que
/// `MyBusinessView`/`MyBusinessScreen`. Pinta portada, chips de servicios,
/// tarjeta de confianza y ficha SIEMPRE; PRODUCTOS/SERVICIOS/PAQUETES/
/// TRABAJOS solo si tienen contenido — el cliente no necesita ver huecos de
/// catálogo. Si las CUATRO secciones de catálogo están vacías, un único
/// texto lo avisa (nada de un aviso por sección).
class ProviderStoreView extends StatelessWidget {
  const ProviderStoreView({
    super.key,
    required this.identity,
    required this.stats,
    required this.hasPhysicalLocation,
    required this.location,
    required this.productos,
    required this.servicios,
    required this.paquetes,
    required this.trabajos,
  });

  final BusinessIdentity? identity;
  final BusinessStorefrontStats? stats;

  /// Sello "Tienda física" (PO 2026-08-12) — AUTODECLARADO, ver doc de
  /// `businessesPhysicalLocation`. Independiente de `stats`: un negocio sin
  /// ningún sello de verificación puede igual tener este marcado.
  final bool hasPhysicalLocation;

  /// Coordenadas del negocio (Task 11) para el boton "Ver en el mapa". Null =
  /// no se monta ningun boton (ver [_locationButton]).
  final ({double lat, double lng})? location;

  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<Map<String, dynamic>> paquetes;
  final List<Map<String, dynamic>> trabajos;

  static String _fmtResp(double minutes) {
    final m = minutes.round();
    if (m < 60) return '~$m min';
    final h = (m / 60).round();
    if (h < 24) return '~$h h';
    final d = (h / 24).round();
    return '~$d ${d == 1 ? 'día' : 'días'}';
  }

  /// Bloque de confianza bajo el nombre (paridad con la tienda web): logo
  /// real del proveedor (PO 2026-07-28: identidad siempre visible, sin
  /// desbloquear nada) + grid de rating / trabajos completados / tiempo de
  /// respuesta / miembro-desde + sellos de verificación. `null` mientras
  /// carga o si no hay datos.
  Widget? _repCard(BuildContext context) {
    final s = stats;
    if (s == null) return null;
    final cs = Theme.of(context).colorScheme;
    final hasRating = s.avgRating != null && s.reviewsCount > 0;
    final badges = <(IconData, String)>[
      if (s.identityVerified || s.businessVerified || s.whatsappVerified)
        (Icons.verified_outlined, 'Proveedor verificado'),
      if (s.identityVerified) (Icons.badge_outlined, 'Identidad verificada'),
      if (s.businessVerified) (Icons.apartment_outlined, 'RNC verificado'),
      if (s.whatsappVerified) (Icons.chat_outlined, 'WhatsApp verificado'),
    ];
    return JayaloCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      // El logo y el nombre YA no van aquí: los carga `BusinessCoverHero`
      // desde el 2026-08-01. Repetirlos era verlos dos veces seguidas.
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _statCell(
              context,
              hasRating ? s.avgRating!.toStringAsFixed(1) : 'Nuevo',
              hasRating
                  ? '${s.reviewsCount} reseña${s.reviewsCount == 1 ? '' : 's'}'
                  : 'sin reseñas aún',
              star: hasRating,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCell(context, '${s.completedJobs}',
                s.completedJobs == 1 ? 'trabajo completado' : 'trabajos completados'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _statCell(
              context,
              s.medianResponseMinutes != null
                  ? _fmtResp(s.medianResponseMinutes!)
                  : '—',
              'tiempo de respuesta',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCell(
              context,
              s.memberSinceYear?.toString() ?? '—',
              'miembro desde',
            ),
          ),
        ]),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final (icon, label) in badges)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 15, color: JayaloColors.success),
                  const SizedBox(width: 5),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JayaloColors.success)),
                ]),
            ],
          ),
        ],
      ]),
    );
  }

  /// Sello "Tienda física" (PO 2026-08-12), AUTODECLARADO — píldora teal
  /// `requisito`, NUNCA junto al ✓ verde de `_repCard` (aquello sí lo
  /// comprueba Jayalo, esto lo dice el proveedor). Deliberadamente
  /// independiente de `_repCard`/`stats`: la RPC de confianza y la consulta
  /// de esta columna son dos llamadas distintas con degradación best-effort
  /// propia cada una — si `businessStorefrontStats` falla, `_repCard` entero
  /// desaparece, pero este sello (que viene de `businessesPhysicalLocation`,
  /// ya blindado) debe seguir visible igual.
  Widget? _physicalLocationBadge(BuildContext context) {
    if (!hasPhysicalLocation) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Tienda física',
          icon: Icons.storefront_outlined,
          tone: dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight,
        ),
      ),
    );
  }

  /// Boton "Ver en el mapa" (Task 11) — null si [location] no llego (reja del
  /// servidor o negocio sin coordenadas): nunca se monta un boton
  /// deshabilitado, la seccion entera desaparece.
  Widget? _locationButton() {
    final loc = location;
    if (loc == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OpenInMapsButton(lat: loc.lat, lng: loc.lng, label: 'Ver en el mapa'),
      ),
    );
  }

  /// Categoría y ciudad en una línea bajo el nombre de la portada, igual que
  /// en Mi negocio. Nulo si el negocio no declara ninguna de las dos.
  String? _subtitle() {
    final raw = identity?.raw;
    if (raw == null) return null;
    final cat = categoryNameById((raw['category_id'] as String?)?.trim());
    final city = (raw['city'] as String?)?.trim();
    final partes = [
      ?cat,
      if (city != null && city.isNotEmpty) city,
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  /// Sellos para la portada. Salen de `stats` (la RPC de confianza), no de
  /// `identity`: las marcas de verificación NO están en los grants por
  /// columna de `provider_businesses` para un tercero.
  List<String> _sealLabels() {
    final s = stats;
    if (s == null) return const [];
    return [
      if (s.identityVerified) 'Identidad verificada',
      if (s.businessVerified) 'RNC verificado',
      if (s.whatsappVerified) 'WhatsApp verificado',
    ];
  }

  /// Celda de un indicador del grid: cifra grande (con estrella opcional) + una
  /// etiqueta corta debajo, sobre una píldora tenue.
  Widget _statCell(BuildContext context, String value, String label,
      {bool star = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (star) ...[
            const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5A623)),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: jayaloHead(context))),
          ),
        ]),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// Chips de servicios (Task 5, 2026-08-09) — solo lectura, bajo la
  /// portada, en el mismo lugar donde iría la descripción del negocio (esta
  /// pantalla no la pinta hoy en ningún sitio). Sin chips no dibuja nada:
  /// la tienda ajena nunca ofrece un "+" de edición.
  Widget? _servicesBlock() {
    final services = identity?.services ?? const [];
    if (services.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ServiceChipsWrap(services: services),
    );
  }

  /// Orden y presencia de PRODUCTOS/SERVICIOS (regla anti-inferencia, puerto
  /// Dart de `profileSections`): una sección se pinta si tiene filas;
  /// `offers` solo decide el orden y, con todo vacío, cuál sección enseña el
  /// estado vacío. PAQUETES/TRABAJOS quedan FUERA de este orden — mismo
  /// tratamiento que `business.$id.tsx` (web): siguen su bloque propio, sin
  /// reordenarse, siempre después de productos/servicios.
  List<ProfileSection> get _catalogOrder => profileSections(
        offers: identity?.raw['offers'] as String?,
        productCount: productos.length,
        serviceCount: servicios.length,
        packageCount: paquetes.length,
      );

  @override
  Widget build(BuildContext context) {
    final repCard = _repCard(context);
    final physicalBadge = _physicalLocationBadge(context);
    final locationButton = _locationButton();
    final servicesBlock = _servicesBlock();
    final teamGallery = TeamGalleryBlock.maybe(
      businessType: identity?.raw['business_type'] as String?,
      teamPhotos: (identity?.raw['team_photos'] as List?)?.cast<String>(),
    );
    final catalogEmpty =
        productos.isEmpty && servicios.isEmpty && paquetes.isEmpty && trabajos.isEmpty;
    final order = _catalogOrder;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: BusinessCoverHero(
          name: identity?.name ?? 'Proveedor',
          coverUrl: identity?.coverUrl,
          logoUrl: identity?.logoUrl,
          subtitle: _subtitle(),
          seals: _sealLabels(),
        ),
      ),
      if (servicesBlock != null) SliverToBoxAdapter(child: servicesBlock),
      if (repCard != null) SliverToBoxAdapter(child: repCard),
      if (physicalBadge != null) SliverToBoxAdapter(child: physicalBadge),
      if (locationButton != null) SliverToBoxAdapter(child: locationButton),
      if (teamGallery != null) SliverToBoxAdapter(child: teamGallery),
      SliverToBoxAdapter(
        child: BusinessDetailsCard(business: identity?.raw ?? const {}),
      ),
      for (final section in order)
        if (section == ProfileSection.productos && productos.isNotEmpty)
          ..._itemsSection('PRODUCTOS', productos)
        else if (section == ProfileSection.servicios && servicios.isNotEmpty)
          ..._itemsSection('SERVICIOS', servicios),
      if (paquetes.isNotEmpty) ..._carrilSection('PAQUETES', paquetes,
          height: kPackageCarrilHeight,
          tileBuilder: (p) => PackageTile(
              item: p, onTap: () => context.push('/package/${p['id']}'))),
      if (trabajos.isNotEmpty) ..._carrilSection('TRABAJOS', trabajos,
          height: kPortfolioCarrilHeight,
          tileBuilder: (t) => PortfolioTile(
              item: t,
              onTap: () => showPortfolioGallery(
                    context,
                    images:
                        (t['image_urls'] as List?)?.cast<String>() ?? const [],
                    title: t['title'] as String? ?? '',
                    description: t['description'] as String?,
                  ))),
      if (catalogEmpty) _empty(context),
      SliverToBoxAdapter(
        child: SizedBox(height: 12 + navBarReservedSpace(context)),
      ),
    ]);
  }

  /// Encabezado + lista vertical de una sección de PRODUCTOS/SERVICIOS —
  /// mismo `ProductListCard` de siempre, sin `onTap`/`onLongPress` (tienda
  /// ajena: solo lectura, la tarjeta navega a su detalle público por
  /// defecto).
  List<Widget> _itemsSection(String title, List<Map<String, dynamic>> items) => [
        SliverToBoxAdapter(child: SectionHeader(text: title)),
        SliverPadding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => ProductListCard(item: items[i]).cascadeIn(i),
          ),
        ),
      ];

  /// Encabezado + carril horizontal de tarjetas compactas (PAQUETES/
  /// TRABAJOS) — [TileCarril] compartido con "Mi negocio"
  /// (`shared/tile_carril.dart`); en la tienda pública las tarjetas van sin
  /// `onLongPress` (solo lectura, sin editar ni borrar). `onTap` sí va
  /// cableado (pedido PO 2026-08-09: "El paquete no abre nada" /
  /// "Trabajos no abre") — un paquete abre su detalle (`/package/:id`), un
  /// trabajo abre la galería modal ([showPortfolioGallery]).
  List<Widget> _carrilSection(
    String title,
    List<Map<String, dynamic>> items, {
    required double height,
    required Widget Function(Map<String, dynamic> item) tileBuilder,
  }) => [
        SliverToBoxAdapter(child: SectionHeader(text: title)),
        SliverToBoxAdapter(
          child: TileCarril(items: items, height: height, tileBuilder: tileBuilder),
        ),
      ];

  Widget _empty(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Este proveedor aún no publica nada en su tienda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
