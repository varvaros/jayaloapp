import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/brand.dart';
import '../../core/editor_link_client.dart';
import '../../core/error_reporter.dart';
import '../../core/safe_image_picker.dart';
import '../../core/secure_web_launch.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/business_cover_hero.dart';
import '../shared/business_details_card.dart';
import '../shared/local_image_guard.dart';
import '../shared/product_list_card.dart';
import '../shared/service_chips_editor.dart';
import '../shared/text_editor_sheet.dart';
import '../shared/violet_header.dart';

/// Elige una foto de la galería con la guarda global de `image_picker`
/// (`safe_image_picker.dart`) — mismo patrón que `_pickAvatar` en
/// `profile_avatar_button.dart`. Default real de `MyBusinessView.pickImage`;
/// inyectable en tests para no depender del canal de plataforma del picker.
Future<XFile?> _pickBusinessImage() => guardedPick(
    (p) => p.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85));

/// Perfil del negocio para "Mi tienda" (espejo del record que devuelve
/// `myBusinessProfile()` en `repos.dart`): cabecera + detalles.
typedef StoreProfile = ({
  String id,
  String name,
  String? logoUrl,

  /// Portada del negocio. La app NO la leía en ningún sitio hasta el
  /// 2026-08-01, que es la mitad de por qué la tienda no se parecía a la web.
  String? coverUrl,
  bool verified,
  String? categoryId,
  String? city,
  bool wholesale,
  String? description,

  /// Sellos ya resueltos a etiqueta ("Identidad verificada", "RNC
  /// verificado", "WhatsApp verificado") para la portada.
  List<String> seals,

  /// Chips de servicios del negocio (Task 2, editable desde la app). Lista
  /// vacía mientras la migración de `provider_businesses.services` no esté
  /// aplicada en prod — ver `_myBusinessServices` en `repos.dart`.
  List<String> services,

  /// La fila cruda de `provider_businesses`, para `BusinessDetailsCard`: las
  /// columnas de detalle son de lectura pública y la ficha decide sola qué
  /// enseñar.
  Map<String, dynamic> raw,
});

/// "Mi tienda" (spec 2026-07-20-mi-tienda-solo-lectura): *Mi negocio* muestra el
/// escaparate — detalles del negocio + productos + servicios + opiniones — de
/// SOLO LECTURA salvo dos excepciones deliberadas: el agregador (PO
/// 2026-08-05, alta rápida de producto/servicio/trabajo) y, desde 2026-08-09,
/// la portada y el logo (tocar para cambiar, mantener presionado para
/// quitar). El resto de la edición sigue sin vivir en la app (V2): el botón
/// "Editar en la web" (Task 6) lleva a jayalo.com ya logueado.
class MyBusinessScreen extends StatefulWidget {
  const MyBusinessScreen({super.key});
  @override
  State<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

/// Todo lo que el escaparate necesita en un solo viaje.
class _StoreData {
  const _StoreData({
    required this.business,
    required this.productos,
    required this.servicios,
    required this.paquetes,
    required this.trabajos,
    required this.reviews,
    required this.rating,
  });
  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<Map<String, dynamic>> paquetes;
  final List<Map<String, dynamic>> trabajos;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;
}

class _MyBusinessScreenState extends State<MyBusinessScreen> {
  late Future<_StoreData> _load = _fetch();

  Future<_StoreData> _fetch() async {
    final business = await myBusinessProfile();
    if (business == null) {
      return const _StoreData(
        business: null,
        productos: [],
        servicios: [],
        paquetes: [],
        trabajos: [],
        reviews: [],
        rating: null,
      );
    }
    final results = await Future.wait([
      myStoreProducts(business.id),
      myPortfolioItems(business.id),
      businessReviews(business.id),
      businessRatings([business.id]),
      myPackages(business.id),
    ]);
    final (productos, servicios) =
        partitionStoreItems(results[0] as List<Map<String, dynamic>>);
    final ratings = results[3] as Map<String, BusinessRating>;
    return _StoreData(
      business: business,
      productos: productos,
      servicios: servicios,
      paquetes: results[4] as List<Map<String, dynamic>>,
      trabajos: results[1] as List<Map<String, dynamic>>,
      reviews: results[2] as List<BusinessReview>,
      rating: ratings[business.id],
    );
  }

  /// Abre el alta rápida del agregador y refresca al volver si hubo alta.
  Future<void> _openAdd(String businessId, String kind) async {
    final changed =
        await context.push<bool>('/provider/business/add?kind=$kind&bid=$businessId');
    if (changed == true) _refetch();
  }

  /// Abre el editor con `initial` (Task 6): tocar una tarjeta de
  /// producto/servicio PROPIA en "Mi negocio". Misma ruta que el alta, con
  /// la fila completa viajando por `extra` (no cabe en query params) — el
  /// `kind` sigue yendo por query, así el `GoRoute` no cambia de forma.
  Future<void> _openEdit(String businessId, Map<String, dynamic> item) async {
    final kind = item['kind'] == 'servicio' ? 'servicio' : 'producto';
    final changed = await context.push<bool>(
      '/provider/business/add?kind=$kind&bid=$businessId',
      extra: item,
    );
    if (changed == true) _refetch();
  }

  /// "Mantener presionada → Eliminar de tu tienda" (Task 6). Best-effort: un
  /// fallo se avisa con un toast genérico, sin tumbar la pantalla.
  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    try {
      await deleteStoreItem(id);
      _refetch();
    } catch (_) {
      _toast('No se pudo eliminar. Intenta de nuevo.');
    }
  }

  /// Abre el editor de paquetes vacío — "+ Añadir paquete" (Task 7). Mismo
  /// contrato de retorno que [_openAdd]: `true` = hubo alta, refrescar.
  Future<void> _openAddPackage(String businessId) async {
    final changed =
        await context.push<bool>('/provider/business/package?bid=$businessId');
    if (changed == true) _refetch();
  }

  /// Tocar un paquete propio abre el editor con `initial` (Task 7). Mismo
  /// patrón que [_openEdit]: la fila viaja por `extra`.
  Future<void> _openEditPackage(
      String businessId, Map<String, dynamic> item) async {
    final changed = await context.push<bool>(
      '/provider/business/package?bid=$businessId',
      extra: item,
    );
    if (changed == true) _refetch();
  }

  /// "Mantener presionado → Eliminar" un paquete propio (Task 7). Mismo
  /// criterio best-effort que [_deleteItem].
  Future<void> _deletePackage(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    try {
      await deletePackage(id);
      _refetch();
    } catch (_) {
      _toast('No se pudo eliminar. Intenta de nuevo.');
    }
  }

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
        _load = _fetch();
      });

  /// Pide el magic link a la web y lo abre en el navegador externo (ya
  /// logueado, redirige a /provider/business/:id). NO usa WebView (el CAPTCHA
  /// se quemó con MIUI, ADR-0032). La edición vive en la web (V2).
  Future<void> _openEditor(String businessId) async {
    final token = supa.auth.currentSession?.accessToken;
    if (token == null) {
      _toast('Inicia sesión de nuevo para editar.');
      return;
    }
    try {
      final url = await EditorLinkClient()
          .fetchEditorUrl(businessId: businessId, accessToken: token);
      // Custom Tabs, NO intent público: este URL también lleva un token de
      // sesión de un solo uso (ver `core/secure_web_launch.dart`).
      final ok = await launchAuthenticatedUrl(Uri.parse(url));
      if (!ok) _toast('No pudimos abrir el navegador.');
    } catch (_) {
      _toast('No se pudo abrir el editor. Intenta de nuevo.');
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          const VioletHeader(
            leading: HeaderAvatar(),
            title: 'Mi negocio',
            actions: [HeaderBell()],
          ),
          Expanded(
            child: FutureBuilder<_StoreData>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData) return const JayaloLoaderBlock();
                final data = snap.data!;
                return MyBusinessView(
                  business: data.business,
                  productos: data.productos,
                  servicios: data.servicios,
                  paquetes: data.paquetes,
                  trabajos: data.trabajos,
                  reviews: data.reviews,
                  rating: data.rating,
                  onEditWeb: data.business == null
                      ? null
                      : () => _openEditor(data.business!.id),
                  onAddItem: data.business == null
                      ? null
                      : (kind) => _openAdd(data.business!.id, kind),
                  onEditItem: data.business == null
                      ? null
                      : (item) => _openEdit(data.business!.id, item),
                  onDeleteItem: data.business == null ? null : _deleteItem,
                  onAddPackage: data.business == null
                      ? null
                      : () => _openAddPackage(data.business!.id),
                  onEditPackage: data.business == null
                      ? null
                      : (item) => _openEditPackage(data.business!.id, item),
                  onDeletePackage:
                      data.business == null ? null : _deletePackage,
                );
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja. Stateful solo por su `ScrollController` propio (nunca el
/// singleton `homeScrollController` — mismo motivo que `StatsView`/
/// `ReputationView`: `BackGuard` revienta con dos posiciones adjuntas).
class MyBusinessView extends StatefulWidget {
  const MyBusinessView({
    super.key,
    required this.business,
    required this.productos,
    required this.servicios,
    this.paquetes = const [],
    this.trabajos = const [],
    required this.reviews,
    required this.rating,
    this.onEditWeb,
    this.onAddItem,
    this.onEditItem,
    this.onDeleteItem,
    this.onAddPackage,
    this.onEditPackage,
    this.onDeletePackage,
    this.pickImage = _pickBusinessImage,
    this.updateCover = updateBusinessCover,
    this.updateLogo = updateBusinessLogo,
    this.clearCover = clearBusinessCover,
    this.clearLogo = clearBusinessLogo,
    this.updateDescription = updateBusinessDescription,
    this.updateServices = updateBusinessServices,
  });

  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<Map<String, dynamic>> paquetes;
  final List<Map<String, dynamic>> trabajos;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  /// Abre el editor en la web (magic-link SSO, Task 6). Nulo → el botón no se
  /// dibuja (p. ej. sin negocio). Inyectable para probar sin red.
  final Future<void> Function()? onEditWeb;

  /// Alta rápida del agregador (PO 2026-08-05): recibe el kind elegido en el
  /// chooser ('producto' | 'servicio' | 'trabajo'). Nulo → la tarjeta no se
  /// dibuja. Inyectable para probar sin router.
  final Future<void> Function(String kind)? onAddItem;

  /// Tocar una tarjeta de producto/servicio PROPIA abre el editor con esa
  /// fila (Task 6, 2026-08-09). `null` → las tarjetas navegan como el
  /// catálogo público (comportamiento previo a esta tarea).
  final Future<void> Function(Map<String, dynamic> item)? onEditItem;

  /// Mantener presionada una tarjeta propia → confirmar → borrar (Task 6).
  /// `null` → sin gesto de long-press (mismo criterio que [onEditItem]).
  final Future<void> Function(Map<String, dynamic> item)? onDeleteItem;

  /// "+ Añadir paquete" al final de la sección PAQUETES (Task 7). Sin
  /// chooser: los paquetes son un solo tipo, a diferencia del agregador de
  /// producto/servicio/trabajo. `null` → la fila no se dibuja.
  final Future<void> Function()? onAddPackage;

  /// Tocar un paquete propio abre el editor con esa fila (Task 7). Mismo
  /// criterio que [onEditItem].
  final Future<void> Function(Map<String, dynamic> item)? onEditPackage;

  /// Mantener presionado un paquete propio → confirmar → borrar (Task 7).
  /// Mismo criterio que [onDeleteItem].
  final Future<void> Function(Map<String, dynamic> item)? onDeletePackage;

  /// Portada y logo editables desde "Mi negocio" (2026-08-09): elegir,
  /// subir y quitar. Inyectables (patrón `CreditShopScreen.loadPackages`)
  /// para probar sin picker/red real; el default es la implementación real
  /// de `repos.dart` / `safe_image_picker.dart`.
  final Future<XFile?> Function() pickImage;
  final Future<String> Function(String businessId, String filePath) updateCover;
  final Future<String> Function(String businessId, String filePath) updateLogo;
  final Future<void> Function(String businessId) clearCover;
  final Future<void> Function(String businessId) clearLogo;

  /// Descripción editable desde "Mi negocio" (Task 4, 2026-08-09): la única
  /// pieza de texto del escaparate que se edita desde la app; el resto de la
  /// ficha sigue siendo solo lectura (V2 vive en la web). Inyectable para
  /// probar sin red; el default es la implementación real de `repos.dart`.
  final Future<void> Function(String businessId, String description)
      updateDescription;

  /// Chips de servicios editables desde "Mi negocio" (Task 5, 2026-08-09):
  /// mismo patrón inyectable que `updateDescription`; el default es
  /// `updateBusinessServices` de `repos.dart`.
  final Future<void> Function(String businessId, List<String> services)
      updateServices;

  @override
  State<MyBusinessView> createState() => _MyBusinessViewState();
}

class _MyBusinessViewState extends State<MyBusinessView> {
  final _scroll = ScrollController();

  /// Copia local de portada/logo: arrancan del negocio cargado y se
  /// actualizan tras subir/quitar, sin esperar a que la pantalla contenedora
  /// vuelva a pedir todo el escaparate a la red.
  String? _coverUrl;
  String? _logoUrl;
  bool _coverBusy = false;
  bool _logoBusy = false;

  /// Copia local de la descripción — mismo motivo que `_coverUrl`/`_logoUrl`.
  String? _description;
  bool _descriptionBusy = false;

  /// Copia local de los chips de servicios — mismo motivo que `_description`.
  List<String> _services = const [];
  bool _servicesBusy = false;

  @override
  void initState() {
    super.initState();
    _coverUrl = widget.business?.coverUrl;
    _logoUrl = widget.business?.logoUrl;
    _description = widget.business?.description;
    _services = widget.business?.services ?? const [];
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Diálogo «¿Quitar…?» — mismo patrón que `confirmDiscard`
  /// (`core/unsaved_guard.dart`): dos botones de texto, el destructivo en
  /// rojo (`cs.error`).
  ///
  /// [confirmLabel] por defecto es 'Quitar' (portada/logo: reversible, basta
  /// con subir otra foto). Un borrado PERMANENTE (paquete, Task 7) debe decir
  /// 'Eliminar' — hallazgo del revisor de la Task 6, que dejó "Quitar" en el
  /// borrado de producto/servicio de la tienda; no se retocó ESE call site
  /// aquí (fuera del alcance de esta tarea, y ya tiene su propio test que
  /// depende del texto actual), pero el parámetro queda disponible por si se
  /// corrige en una tarea futura.
  Future<bool> _confirmRemove(String title, String message,
      {String confirmLabel = 'Quitar'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel,
                style: TextStyle(color: Theme.of(c).colorScheme.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _changeCover() async {
    final b = widget.business;
    if (b == null || _coverBusy) return;
    final picked = await widget.pickImage();
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final err = validateLocalImage(file);
    if (err != null) return _toast(err);
    setState(() => _coverBusy = true);
    try {
      final url = await widget.updateCover(b.id, file.path);
      if (mounted) setState(() => _coverUrl = url);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) _toast('No se pudo subir la portada. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _removeCover() async {
    final b = widget.business;
    if (b == null || _coverBusy) return;
    final ok = await _confirmRemove(
        '¿Quitar la portada?', 'Tu negocio se mostrará sin portada.');
    if (!ok || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      await widget.clearCover(b.id);
      if (mounted) setState(() => _coverUrl = null);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) _toast('No se pudo quitar la portada. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _changeLogo() async {
    final b = widget.business;
    if (b == null || _logoBusy) return;
    final picked = await widget.pickImage();
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final err = validateLocalImage(file);
    if (err != null) return _toast(err);
    setState(() => _logoBusy = true);
    try {
      final url = await widget.updateLogo(b.id, file.path);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) _toast('No se pudo subir el logo. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    final b = widget.business;
    if (b == null || _logoBusy) return;
    final ok = await _confirmRemove(
        '¿Quitar el logo?', 'Tu negocio se mostrará sin logo.');
    if (!ok || !mounted) return;
    setState(() => _logoBusy = true);
    try {
      await widget.clearLogo(b.id);
      if (mounted) setState(() => _logoUrl = null);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) _toast('No se pudo quitar el logo. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  /// Abre la hoja de "Sobre el negocio" y guarda solo si el texto CAMBIÓ —
  /// evita una escritura (y un toast) de guardar sin haber tocado nada.
  Future<void> _editDescription() async {
    final b = widget.business;
    if (b == null || _descriptionBusy) return;
    final current = _description ?? '';
    final text = await showTextEditorSheet(context,
        title: 'Sobre el negocio', initial: current);
    if (text == null || !mounted || text == current) return;
    setState(() => _descriptionBusy = true);
    try {
      await widget.updateDescription(b.id, text);
      if (mounted) setState(() => _description = text);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) {
        _toast('No se pudo guardar la descripción. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _descriptionBusy = false);
    }
  }

  /// Abre el editor de chips de servicios con la lista actual. `null` =
  /// cancelado (mismo contrato que `_editDescription`, sin comparar con la
  /// lista anterior: el editor ya evita escrituras vacías por su cuenta —
  /// aquí cualquier no-null es una edición explícita del dueño, no hay un
  /// "no cambió nada" trivial de detectar con listas).
  Future<void> _editServices() async {
    final b = widget.business;
    if (b == null || _servicesBusy) return;
    final result = await showServiceChipsEditor(context, initial: _services);
    if (result == null || !mounted) return;
    setState(() => _servicesBusy = true);
    try {
      await widget.updateServices(b.id, result);
      if (mounted) setState(() => _services = result);
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (mounted) {
        _toast('No se pudo guardar los servicios. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _servicesBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    if (b == null) {
      return EmptyState(
        controller: _scroll,
        message: 'No encontramos tu negocio.\n\n'
            'Si el problema sigue, escríbenos desde Ajustes.',
      );
    }

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        // Portada editorial + ficha de detalles: las dos piezas del diseño web
        // que nunca se portaron (pedido PO 2026-08-01). Antes esto era una
        // tarjeta con logo y nombre, y tres chips sueltos.
        BusinessCoverHero(
          name: b.name,
          coverUrl: _coverUrl,
          logoUrl: _logoUrl,
          subtitle: _subtitleFor(b),
          seals: b.seals,
          // Editable siempre en "Mi negocio": esta pantalla SOLO muestra el
          // negocio propio (nunca el de otro proveedor). Quitar solo se
          // ofrece si hay algo que quitar.
          onCoverTap: _changeCover,
          onCoverLongPress:
              (_coverUrl != null && _coverUrl!.isNotEmpty) ? _removeCover : null,
          onLogoTap: _changeLogo,
          onLogoLongPress:
              (_logoUrl != null && _logoUrl!.isNotEmpty) ? _removeLogo : null,
          coverBusy: _coverBusy,
          logoBusy: _logoBusy,
        ).cascadeIn(0),
        const SectionHeader(text: 'SOBRE EL NEGOCIO'),
        _AboutCard(
          description: _description,
          busy: _descriptionBusy,
          onTap: _editDescription,
        ).cascadeIn(1),
        // Chips de servicios (Task 5, 2026-08-09): bajo la descripción,
        // dentro de la misma sección "SOBRE EL NEGOCIO" (no una nueva
        // `SectionHeader` — mismo trato que la descripción, un dato más de
        // la ficha del negocio, no un listado aparte).
        _ServicesCard(
          services: _services,
          busy: _servicesBusy,
          onTap: _editServices,
        ).cascadeIn(2),
        BusinessDetailsCard(business: b.raw).cascadeIn(3),
        if (widget.onEditWeb != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: FilledButton.icon(
              onPressed: () => widget.onEditWeb!.call(),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Editar en la web'),
            ),
          ),
        // El agregador (PO 2026-08-05): tarjeta vacía con ＋ que abre el
        // chooser producto/servicio/trabajo. Rompe a propósito el "solo
        // lectura" del spec 2026-07-20, decisión del PO: el alta mínima vive
        // en la app porque alimenta ofertas más rápidas.
        if (widget.onAddItem != null)
          _AddToStoreCard(onChoose: _chooseKind).cascadeIn(4),
        const SectionHeader(text: 'PRODUCTOS'),
        ..._itemsOrEmpty(widget.productos, 'Aún no tienes productos.'),
        const SectionHeader(text: 'SERVICIOS'),
        ..._itemsOrEmpty(widget.servicios, 'Aún no tienes servicios.'),
        const SectionHeader(text: 'PAQUETES'),
        ..._packagesOrAdd(widget.paquetes),
        const SectionHeader(text: 'TRABAJOS'),
        if (widget.trabajos.isEmpty)
          const _EmptyLine(text: 'Aún no tienes trabajos en tu portafolio.')
        else
          for (final t in widget.trabajos) _PortfolioTile(item: t),
        const SectionHeader(text: 'OPINIONES'),
        _ReviewsBlock(reviews: widget.reviews, rating: widget.rating),
      ],
    );
  }

  /// Chooser del agregador: hoja con las tres variantes del alta rápida.
  Future<void> _chooseKind() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Producto'),
            subtitle: const Text('Algo que vendes en tu tienda'),
            onTap: () => Navigator.pop(c, 'producto'),
          ),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: const Text('Servicio'),
            subtitle: const Text('Algo que ofreces hacer'),
            onTap: () => Navigator.pop(c, 'servicio'),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('Trabajo realizado'),
            subtitle: const Text('Para tu portafolio'),
            onTap: () => Navigator.pop(c, 'trabajo'),
          ),
        ]),
      ),
    );
    if (kind == null) return;
    await widget.onAddItem?.call(kind);
  }

  List<Widget> _itemsOrEmpty(List<Map<String, dynamic>> items, String empty) {
    if (items.isEmpty) return [_EmptyLine(text: empty)];
    return [
      for (final i in items)
        ProductListCard(
          item: i,
          onTap: widget.onEditItem == null ? null : () => widget.onEditItem!(i),
          onLongPress:
              widget.onDeleteItem == null ? null : () => _confirmDeleteItem(i),
        ),
    ];
  }

  /// «¿Eliminar de tu tienda?» — mismo diálogo de confirmación que
  /// portada/logo ([_confirmRemove]), con la etiqueta que pide el brief.
  Future<void> _confirmDeleteItem(Map<String, dynamic> item) async {
    final ok = await _confirmRemove(
        '¿Eliminar de tu tienda?', 'Esta acción no se puede deshacer.');
    if (!ok || !mounted) return;
    await widget.onDeleteItem?.call(item);
  }

  /// Paquetes propios + la fila «+ Añadir paquete» al final, SIEMPRE (Task
  /// 7) — a diferencia de PRODUCTOS/SERVICIOS (que solo muestran un aviso de
  /// texto cuando están vacíos), la sección de paquetes ofrece la alta
  /// directo ahí mismo porque no hay un chooser compartido que la cubra.
  List<Widget> _packagesOrAdd(List<Map<String, dynamic>> paquetes) => [
        for (final p in paquetes)
          _PackageTile(
            item: p,
            onTap: widget.onEditPackage == null
                ? null
                : () => widget.onEditPackage!(p),
            onLongPress: widget.onDeletePackage == null
                ? null
                : () => _confirmDeletePackage(p),
          ),
        if (widget.onAddPackage != null)
          _AddPackageTile(onTap: () => widget.onAddPackage!.call()),
      ];

  /// Borrado PERMANENTE de un paquete — el botón dice 'Eliminar', no
  /// 'Quitar' (constraint explícita de la Task 7).
  Future<void> _confirmDeletePackage(Map<String, dynamic> item) async {
    final ok = await _confirmRemove(
        '¿Eliminar este paquete?', 'Esta acción no se puede deshacer.',
        confirmLabel: 'Eliminar');
    if (!ok || !mounted) return;
    await widget.onDeletePackage?.call(item);
  }

  /// Categoría y ciudad en UNA línea bajo el nombre, como la web en móvil.
  /// Antes eran dos chips sueltos junto al de "Mayorista"; el mayorista pasó a
  /// ser una fila de la ficha de detalles ("Ventas: Al por mayor").
  static String? _subtitleFor(StoreProfile b) {
    final partes = [
      if (categoryNameById(b.categoryId) != null)
        categoryNameById(b.categoryId)!,
      if (b.city != null) b.city!,
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }
}

/// La tarjeta del agregador (PO 2026-08-05): "tarjeta vacía con un signo de
/// ＋". El ＋ va en un aro punteado-suave del color primario para leerse como
/// hueco por llenar, no como contenido.
class _AddToStoreCard extends StatelessWidget {
  const _AddToStoreCard({required this.onChoose});
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onChoose,
      child: Column(children: [
        const SizedBox(height: 6),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary, width: 2),
          ),
          child: Icon(Icons.add, size: 28, color: cs.primary),
        ),
        const SizedBox(height: 10),
        Text(
          'Haz ofertas más rápidas con tus productos en tus tiendas',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

/// "Sobre el negocio" (Task 4, 2026-08-09): la descripción del negocio,
/// tocable para editarla. Vacía → píldora "+ Añadir descripción" (mismo
/// tratamiento que `_AddPill` de `BusinessCoverHero`, en tarjeta en vez de
/// superpuesta a una foto); con texto → se muestra el texto y NO el "+".
/// Esta pantalla es SIEMPRE la del dueño, así que no hay variante ajena.
class _AboutCard extends StatelessWidget {
  const _AboutCard(
      {required this.description, required this.busy, required this.onTap});

  final String? description;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = description;
    final hasText = text != null && text.trim().isNotEmpty;
    return JayaloCard(
      onTap: busy ? null : onTap,
      child: busy
          ? const Center(child: JayaloSpinner(size: 18))
          : hasText
              ? Text(text,
                  style: TextStyle(fontSize: 13.5, color: jayaloHead(context)))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Añadir descripción',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                ]),
    );
  }
}

/// Chips de servicios (Task 5, 2026-08-09), bajo la descripción: mismo
/// tratamiento visual que `_AboutCard` — vacío → píldora "+ Añadir
/// servicios"; con chips → `ServiceChipsWrap` (compartida con la tienda
/// pública, allí en modo solo lectura). Tocar la tarjeta abre el editor con
/// la lista actual, sea cual sea su tamaño.
class _ServicesCard extends StatelessWidget {
  const _ServicesCard(
      {required this.services, required this.busy, required this.onTap});

  final List<String> services;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: busy ? null : onTap,
      child: busy
          ? const Center(child: JayaloSpinner(size: 18))
          : services.isEmpty
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Añadir servicios',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                ])
              : ServiceChipsWrap(services: services),
    );
  }
}

/// Trabajo del portafolio en el escaparate propio: miniatura + título. Más
/// simple que el carrusel de la tienda pública — aquí solo confirma al dueño
/// que su alta quedó.
class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return JayaloCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: img == null || img.isEmpty
              ? Container(
                  width: 56,
                  height: 56,
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.photo_outlined,
                      color: cs.onSurfaceVariant, size: 22),
                )
              : Image.network(img, width: 56, height: 56, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(item['title'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Paquete/plan propio en el escaparate: foto + nombre + precio. Tocar abre
/// el editor con la fila; mantener presionado pide confirmar el borrado
/// (Task 7). Mismo molde visual que [_PortfolioTile], con precio.
class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.item, this.onTap, this.onLongPress});
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = item['image_url'] as String?;
    final price = item['price'] as num?;
    return JayaloCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: img == null || img.isEmpty
              ? Container(
                  width: 56,
                  height: 56,
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.inventory_2_outlined,
                      color: cs.onSurfaceVariant, size: 22),
                )
              : Image.network(img, width: 56, height: 56, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item['name'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(price == null ? 'Consultar precio' : fmtRD(price),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cs.primary)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// «+ Añadir paquete» — mismo tratamiento visual que `_AboutCard`/
/// `_ServicesCard` en su estado vacío: fila con ícono `+` y texto en el color
/// primario. Va SIEMPRE al final de la sección PAQUETES, con o sin paquetes.
class _AddPackageTile extends StatelessWidget {
  const _AddPackageTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text('Añadir paquete',
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.primary)),
      ]),
    );
  }
}

/// Aviso discreto para una sección vacía (sin CTA de crear: eso es V2/web).
class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child:
          Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

/// Promedio + conteo (encabezado) y la lista de reseñas anónimas.
class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.reviews, required this.rating});
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (reviews.isEmpty) {
      return const _EmptyLine(text: 'Aún no tienes opiniones.');
    }
    final r = rating;
    return Column(children: [
      if (r != null && r.count > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5A623)),
            const SizedBox(width: 4),
            Text(r.avg.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('(${r.count} ${r.count == 1 ? 'reseña' : 'reseñas'})',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        ),
      for (final rev in reviews) _ReviewCard(review: rev),
    ]);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final BusinessReview review;

  @override
  Widget build(BuildContext context) {
    return JayaloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            for (var i = 0; i < 5; i++)
              Icon(
                  i < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFF5A623)),
          ]),
          if (review.comment != null) ...[
            const SizedBox(height: 6),
            Text(review.comment!, style: const TextStyle(fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}

/// Cabecera: logo (o ícono genérico), nombre y el sello "Negocio verificado"
/// si el RNC está aprobado. Mismo tono verde que Ajustes para "confirmado".
