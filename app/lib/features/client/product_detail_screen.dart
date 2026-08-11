import 'dart:io';

import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../core/safe_image_picker.dart';
import '../../domain/image_pick.dart';
import '../../domain/interest_message.dart';
import '../../domain/money.dart';
import '../../domain/offer_defaults.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/collapsing_photo_panel.dart';
import '../shared/detail_tiles.dart';
import '../../core/motion.dart';

/// `/catalog/:id` (Task 7): detalle del producto/servicio + "Me interesa".
///
/// Fuentes de paridad (web): `src/routes/products.$productId.tsx` (qué se
/// muestra) y `src/components/marketplace/InterestConfirmDialog.tsx` (el
/// formulario y el FORMATO EXACTO del mensaje — ver `domain/interest_message.dart`).
///
/// AppBar SIN campana/avatar: mismo patrón que `/client/request/:id`
/// (`request_status_screen.dart`) — las pantallas de DETALLE de esta app no
/// llevan esas acciones, solo las pestañas raíz del shell.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

/// Todo lo que la pantalla necesita en un solo viaje (3 queries en paralelo).
class ProductDetailData {
  const ProductDetailData({
    required this.product,
    required this.business,
    required this.hasInterest,
    required this.isOwner,
  });

  final Map<String, dynamic> product;
  final BusinessLite? business;

  /// Ya existe una fila de interés del cliente actual para este producto
  /// (idempotente — alimenta el botón "Solicitud enviada").
  final bool hasInterest;

  /// El usuario actual es el dueño del producto (nunca se le ofrece
  /// interesarse en lo suyo).
  final bool isOwner;
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<ProductDetailData?> _load = _fetch();

  Future<ProductDetailData?> _fetch() async {
    final product = await productDetail(widget.productId);
    if (product == null) return null;
    final ownerUserId = product['user_id'] as String;
    final businessId = product['business_id'] as String?;
    final uid = supa.auth.currentUser?.id;
    final isOwner = uid != null && uid == ownerUserId;
    final results = await Future.wait([
      businessId != null
          ? businessLite(businessId)
          : businessLiteByOwner(ownerUserId),
      isOwner
          ? Future.value(false)
          : productInterestExists(widget.productId),
    ]);
    final business = results[0] as BusinessLite?;
    final hasInterest = results[1] as bool;
    return ProductDetailData(
      product: product,
      business: business,
      hasInterest: hasInterest,
      isOwner: isOwner,
    );
  }

  // Bloque, no expresión (mismo gotcha de `inbox_screen.dart`/`catalog_screen.dart`):
  // `setState(() => _load = future)` haría que la closure DEVUELVA el Future.
  void _refetch() {
    setState(() => _load = _fetch());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProductDetailData?>(
        future: _load,
        builder: (context, snap) {
          // Cargado: la vista trae su PROPIO panel ámbar con el atrás dentro
          // (misma anatomía que el detalle de solicitud). Los demás estados
          // (esqueleto/vacío/error) flotan el atrás sobre el contenido.
          if (snap.connectionState == ConnectionState.done &&
              !snap.hasError &&
              snap.data != null) {
            return Scaffold(
              body: ProductDetailView(
                  data: snap.data!, onInterestSent: _refetch),
            );
          }
          final Widget content = switch (snap.connectionState) {
            ConnectionState.done => snap.hasError
                ? ErrorRetry(onRetry: () async => _refetch())
                : EmptyState(
                    message: 'No encontramos este producto.\n\n'
                        'Puede que ya no esté disponible.',
                  ),
            _ => const JayaloLoaderBlock(),
          };
          return Scaffold(
            body: Stack(children: [
              content,
              SafeArea(child: productBackFab(context)),
            ]),
          );
        },
      );
}

/// Atrás flotante sobre la galería del producto (mismo gesto que el detalle de
/// solicitud: en el detalle no hay header violeta, solo el atrás).
Widget productBackFab(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, left: 16),
      child: Align(
        alignment: Alignment.topLeft,
        child: productBackButton(context),
      ),
    );

/// El botón PELADO, sin posicionar: va al `leading` de la barra plegable —donde
/// sigue tocable con el panel encogido— mientras que [productBackFab] lo coloca
/// en el `Stack` de las pantallas de carga/error, que sí necesitan situarlo.
Widget productBackButton(BuildContext context) => Center(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        child: InkWell(
          onTap: () => context.pop(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.arrow_back_ios_new,
                size: 18, color: jayaloHead(context)),
          ),
        ),
      ),
    );

/// Solo dibuja — recibe los datos ya resueltos. Stateful por la galería
/// (imagen activa) y por su propio [ScrollController] (nunca el singleton
/// `homeScrollController`: esta pantalla es un DETALLE, no una pestaña raíz
/// del shell — mismo motivo documentado en `catalog_screen.dart`).
class ProductDetailView extends StatefulWidget {
  const ProductDetailView({
    super.key,
    required this.data,
    required this.onInterestSent,
    this.sendInterest = sendProductInterest,
    this.loadAddress = myDeliveryAddress,
    this.uploadPhoto = uploadInterestImage,
  });

  final ProductDetailData data;

  /// Se llama tras enviar el interés con éxito, para que el padre refresque
  /// `hasInterest` (idempotencia) sin recargar toda la pantalla a mano.
  final VoidCallback onInterestSent;

  /// Inyectables (mismo patrón que `CatalogFetch` en `catalog_screen.dart`):
  /// por defecto pegan a Supabase vía `repos.dart`; los tests pasan fakes.
  final Future<({bool ok, bool alreadyExists, String? id})> Function(
      String productId, String message) sendInterest;
  final Future<String?> Function() loadAddress;
  final Future<String> Function(String filePath) uploadPhoto;

  @override
  State<ProductDetailView> createState() => _ProductDetailViewState();
}

class _ProductDetailViewState extends State<ProductDetailView> {
  final _scroll = ScrollController();
  int _activeImg = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.data.product;
    final name = p['name'] as String? ?? '';
    final description = p['description'] as String?;
    final images = ((p['image_urls'] as List?)?.cast<String>() ?? const [])
        .where((u) => u.isNotEmpty)
        .toList();
    final priceLabel = catalogPriceLabel(
      price: p['price'] as num?,
      priceMin: p['price_min'] as num?,
      priceMax: p['price_max'] as num?,
    );
    final condition = p['condition'] as String?;
    final conditionLabel =
        condition == 'nuevo' ? 'Nuevo' : condition == 'usado' ? 'Usado' : null;
    final brand = p['brand'] as String?;
    final warranty = p['warranty'] as String?;
    final requiresEvaluation = p['requires_evaluation'] == true;
    final offersShipping = p['offers_shipping'] == true;
    final offersInstallation = p['offers_installation'] == true;
    final rubro = p['rubro'] as String?;
    final isServicio = (p['kind'] as String?) == 'servicio';
    // Rediseño en chips (pedido PO 2026-08-09): "tiempo de entrega" y la
    // lista completa de colores solo viven en el jsonb `offer_defaults` (ver
    // `OfferDefaults`, `add_store_item_screen.dart`) — `color` (columna real,
    // singular) es el PRIMERO de esa lista cuando el proveedor usó el
    // selector múltiple, así que la lista gana cuando existe; `color` queda
    // de fallback para productos guardados antes de que `offer_defaults`
    // existiera.
    final offerDefaults =
        (p['offer_defaults'] as Map?)?.cast<String, dynamic>() ?? const {};
    final colorsList =
        (offerDefaults[OfferDefaults.colors] as List?)?.cast<String>() ??
            const [];
    final colorsLabel = colorsList.isNotEmpty
        ? colorsList.join(', ')
        : (p['color'] as String?);
    final delivery = offerDefaults[OfferDefaults.delivery] as String?;
    final hasPrice = p['price'] != null ||
        p['price_min'] != null ||
        p['price_max'] != null;
    // Variante B aprobada (PO 2026-08-11): los atributos dejan los chips y
    // pasan a las MISMAS tarjetas horizontales de la hoja de oferta
    // (`detailTileBlock`) — catálogo y oferta se leen igual. Mismos íconos y
    // mismo orden que `_detailRows()` de `offer_actions.dart`; envío e
    // instalación son capacidades (check verde), la evaluación es una
    // condición y va sin check. El rubro sale de aquí: es la etiqueta más
    // "titular" y sube como chip encima del nombre.
    final detailRows = <(IconData, String, String, bool)>[
      if (conditionLabel != null)
        (Icons.inventory_2_outlined, 'Estado', conditionLabel, false),
      if (brand != null && brand.isNotEmpty)
        (Icons.sell_outlined, 'Marca', brand, false),
      if (colorsLabel != null && colorsLabel.isNotEmpty)
        (Icons.palette_outlined, 'Color', colorsLabel, false),
      if (warranty != null && warranty.isNotEmpty)
        (Icons.gpp_good_outlined, 'Garantía', warranty, false),
      if (delivery != null && delivery.isNotEmpty)
        (Icons.schedule_outlined, 'Entrega', delivery, false),
      if (offersShipping)
        (Icons.local_shipping_outlined, 'Envío', 'Disponible', true),
      if (offersInstallation)
        (Icons.build_outlined, 'Instalación', 'Incluida', true),
      if (requiresEvaluation)
        (Icons.fact_check_outlined, 'Evaluación', 'Requerida', false),
    ];

    // Misma anatomía que el detalle de solicitud: panel ámbar con la foto que
    // LLENA (cover) arriba y una hoja blanca redondeada abajo con los datos y
    // el CTA "Solicitar". Con 2+ fotos, una tira de miniaturas cambia la que
    // llena el panel (el detalle de solicitud no tiene varias, el producto sí).
    return CustomScrollView(controller: _scroll, slivers: [
      // Mismo panel que el detalle de solicitud y el de estado: la foto se
      // PLIEGA al hacer scroll en vez de quedarse fija (pedido PO 2026-08-03 —
      // era la única de las tres pantallas de detalle que no lo hacía).
      // `activeIndex` conserva lo que el catálogo sí tenía y las otras no: la
      // tira de miniaturas elige qué foto llena el panel.
      CollapsingPhotoPanel(
        images: images,
        fallbackIcon:
            isServicio ? Icons.handyman_outlined : Icons.inventory_2_outlined,
        activeIndex: _activeImg,
        leading: productBackButton(context),
        onOpenViewer: (i) =>
            showPhotoViewer(context, images, initialIndex: i),
        // Variante B: las miniaturas se MONTAN sobre la foto (abajo a la
        // izquierda) con el contador arriba a la derecha — desaparece la fila
        // aparte que vivía en la hoja.
        overlay: images.length > 1
            ? _PhotoOverlay(
                images: images,
                activeIndex: _activeImg,
                onSelect: (i) => setState(() => _activeImg = i),
              )
            : null,
      ),
      SliverFillRemaining(
        // El contenido decide su alto y, si sobra pantalla, la hoja la rellena
        // igual — que es lo que hacía el `Expanded` de antes.
        hasScrollBody: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              22, 22, 22, 24 + navBarReservedSpace(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El rubro como chip pequeño ENCIMA del nombre (Variante B): es
              // la etiqueta más "titular", no un atributo más de la lista.
              if (rubro != null && rubro.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(rubro.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                ),
                const SizedBox(height: 10),
              ],
              Text(name,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
              const SizedBox(height: 16),
              // Orden de la hoja de oferta (Variante B): PRIMERO los detalles
              // en tarjetas, DESPUÉS el precio en su tarjeta lila cerrando el
              // bloque — catálogo y oferta se leen igual. Sin precio fijo ni
              // rango, `catalogPriceLabel` cae en "Consultar precio" — no es
              // una cifra, así que la tarjeta lo pinta discreto.
              ...detailTileBlock(context,
                  eyebrow: 'DETALLES DEL PRODUCTO', rows: detailRows),
              if (detailRows.isNotEmpty) const SizedBox(height: 15),
              detailPriceCard(context,
                  value: priceLabel, emphasized: hasPrice),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(description,
                    style: TextStyle(
                        fontSize: 14, height: 1.4, color: cs.onSurfaceVariant)),
              ],
              if (widget.data.business != null)
                _BusinessCard(business: widget.data.business!).cascadeIn(0),
              const SizedBox(height: 20),
              _CtaArea(data: widget.data, onOpenInterest: _openInterest),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _openInterest() async {
    await showInterestSheet(
      context,
      data: widget.data,
      sendInterest: widget.sendInterest,
      loadAddress: widget.loadAddress,
      uploadPhoto: widget.uploadPhoto,
      onSent: widget.onInterestSent,
    );
  }
}


/// Miniaturas MONTADAS sobre la foto del panel (abajo a la izquierda) más el
/// contador «n / total» (arriba a la derecha) — Variante B aprobada PO
/// 2026-08-11. Solo se usa con 2+ fotos; la activa lleva borde blanco. Va en
/// el `overlay` de [CollapsingPhotoPanel], así que se pliega con la foto.
class _PhotoOverlay extends StatelessWidget {
  const _PhotoOverlay(
      {required this.images,
      required this.activeIndex,
      required this.onSelect});
  final List<String> images;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined,
            size: 20, color: cs.onSurfaceVariant));
    return Stack(children: [
      // Contador bajo la barra de estado, a la derecha (donde vivía el peek).
      Positioned(
        top: 30,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text('${activeIndex + 1} / ${images.length}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white)),
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 18,
        child: SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: i == activeIndex
                          ? Colors.white
                          : Colors.white.withValues(alpha: .35),
                      width: i == activeIndex ? 2.5 : 1),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 12,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: JayaloNetworkImage(images[i],
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => placeholder()),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Ofrecido por" — nombre y logo reales SIEMPRE (PO 2026-07-28: el cliente
/// ve la identidad del proveedor sin desbloquear nada; paridad
/// `products.$productId.tsx`, Task 8 ya aplicada en la web). Tocarlo abre la
/// tienda del proveedor: productos, servicios y trabajos, sin revelar el
/// contacto (eso sigue detrás del desbloqueo pagado).
class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business});
  final BusinessLite business;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight;
    final logoUrl = business.logoUrl;
    return JayaloCard(
      margin: const EdgeInsets.only(top: 20),
      onTap: () => context.push('/store/${business.id}'),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: cs.surfaceContainerHighest,
          backgroundImage:
              logoUrl != null ? jayaloAvatarImage(logoUrl, 48, context) : null,
          child: logoUrl == null
              ? Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Micro-etiqueta en mayúsculas: mismo trato que las etiquetas de
              // las tarjetas de detalle (Variante B).
              Text('OFRECIDO POR',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant)),
              Text(business.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              if (business.verified) ...[
                const SizedBox(height: 4),
                StatusChip(
                    label: 'Negocio verificado',
                    icon: Icons.verified,
                    tone: tone),
              ],
            ],
          ),
        ),
        // Píldora "Ver tienda" en vez del chevron mudo (Variante B aprobada
        // PO 2026-08-11): dice A DÓNDE lleva el toque. La fila entera sigue
        // tocable (`onTap` arriba, sin cambios); la píldora es solo el aviso.
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text('Ver tienda',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
        ),
      ]),
    );
  }
}

/// Botón de acción según quién mira: dueño (nada que ofertar), ya
/// interesado (estado amable, idempotente) o CTA. Copy EXACTO de
/// `InterestButton.tsx` (default sin `label`/`sentLabel` — el que usa
/// `products.$productId.tsx`): "Solicitar" / "Solicitud enviada", con el
/// mismo ícono `ShoppingBag`.
class _CtaArea extends StatelessWidget {
  const _CtaArea({required this.data, required this.onOpenInterest});
  final ProductDetailData data;
  final Future<void> Function() onOpenInterest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.isOwner) {
      return Text('Este es tu producto.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant));
    }
    // El botón y su nota van dentro de la MISMA tarjeta (pedido PO
    // 2026-08-09: "la nota se integra, no cuelga suelta") — `surfaceContainerHigh`
    // ya está calibrado para las dos superficies del tema (claro/oscuro) por
    // `jayaloScheme`, así que el ancla no pierde contraste en oscuro.
    if (data.hasInterest) {
      return _anchor(
        cs,
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: null,
              child: const Text('Solicitud enviada'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Te avisaremos si el proveedor te escribe.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      );
    }
    return _anchor(
      cs,
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => onOpenInterest(),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Solicitar'),
          ),
        ),
        const SizedBox(height: 8),
        Text('Le avisaremos al proveedor por correo y desde la app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _anchor(ColorScheme cs, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

// ── El formulario "Me interesa" ─────────────────────────────────────────────

/// Abre el bottom sheet de interés. Decisión de layout (móvil, sin
/// `HoldToConfirmButton` en la app — ver informe): bottom sheet
/// `isScrollControlled` (mismo patrón que `offer_actions.dart`), con un
/// `AlertDialog` de confirmación antes de mandar la RPC (mismo patrón que
/// `_accept()`/`_reject()` de `offer_actions.dart`) en vez de un botón de
/// "mantén para confirmar" que esta app todavía no tiene.
Future<void> showInterestSheet(
  BuildContext context, {
  required ProductDetailData data,
  required Future<({bool ok, bool alreadyExists, String? id})> Function(
          String productId, String message)
      sendInterest,
  required Future<String?> Function() loadAddress,
  required Future<String> Function(String filePath) uploadPhoto,
  required VoidCallback onSent,
}) {
  return showModalBottomSheet(
    sheetAnimationStyle: JayaloMotion.sheetRise,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Por el navigator RAÍZ: sin esto el sheet se apila en el navigator del
    // shell y la barra flotante tapa el botón "Solicitar" por abajo (mismo
    // gotcha documentado en offer_actions.dart). El padding suma el inset del
    // sistema por la misma razón.
    useRootNavigator: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.paddingOf(ctx).bottom +
              16),
      // `isScrollControlled` por sí solo NO acota la altura del sheet a la
      // pantalla — sin este `ConstrainedBox` el `SingleChildScrollView` de
      // abajo se estira al alto TOTAL del contenido (con muchos campos,
      // más allá del borde inferior) en vez de quedar acotado y scrollear
      // por dentro. 90%: deja ver el drag handle arriba.
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
        child: _InterestSheetBody(
          data: data,
          sendInterest: sendInterest,
          loadAddress: loadAddress,
          uploadPhoto: uploadPhoto,
          onSent: onSent,
        ),
      ),
    ),
  );
}

class _InterestSheetBody extends StatefulWidget {
  const _InterestSheetBody({
    required this.data,
    required this.sendInterest,
    required this.loadAddress,
    required this.uploadPhoto,
    required this.onSent,
  });

  final ProductDetailData data;
  final Future<({bool ok, bool alreadyExists, String? id})> Function(
      String productId, String message) sendInterest;
  final Future<String?> Function() loadAddress;
  final Future<String> Function(String filePath) uploadPhoto;
  final VoidCallback onSent;

  @override
  State<_InterestSheetBody> createState() => _InterestSheetBodyState();
}

class _InterestSheetBodyState extends State<_InterestSheetBody> {
  late final bool _isServicio =
      (widget.data.product['kind'] as String?) == 'servicio';

  int _quantity = 1;
  InterestUrgency _urgency = InterestUrgency.semana;
  final _brandCtrl = TextEditingController();
  String? _colorKey;
  String? _profileAddress;
  bool _useProfileAddress = true;
  final _addressCtrl = TextEditingController();
  bool _loadingAddress = true;

  final _needCtrl = TextEditingController();
  String _serviceLocation = 'cliente'; // 'cliente' | 'proveedor'
  XFile? _photo;
  bool _photoUploading = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.loadAddress().then((addr) {
      if (!mounted) return;
      setState(() {
        _profileAddress = addr;
        _useProfileAddress = addr != null;
        _loadingAddress = false;
        if (addr == null) _serviceLocation = 'proveedor';
      });
    });
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _addressCtrl.dispose();
    _needCtrl.dispose();
    super.dispose();
  }

  String get _effectiveAddress =>
      _useProfileAddress ? (_profileAddress ?? '') : _addressCtrl.text.trim();

  bool get _canSubmit =>
      !_busy && (!_isServicio || canSubmitServiceInterest(_needCtrl.text));

  @override
  Widget build(BuildContext context) {
    final p = widget.data.product;
    final priceLabel = catalogPriceLabel(
      price: p['price'] as num?,
      priceMin: p['price_min'] as num?,
      priceMax: p['price_max'] as num?,
    );
    final condition = p['condition'] as String?;
    final conditionLabel =
        condition == 'nuevo' ? 'Nuevo' : condition == 'usado' ? 'Usado' : null;
    final businessName = widget.data.business?.name;

    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado con la LÍNEA GRÁFICA de la app: banda violeta + ícono en
          // círculo blanco translúcido + título/subtítulo blancos, igual que el
          // VioletHeader del resto de pantallas (pedido PO 2026-07-22:
          // "Confirmar solicitud" debe tener el diseño de la app).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    _isServicio
                        ? Icons.handyman_outlined
                        : Icons.shopping_bag_outlined,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _isServicio
                            ? 'Solicitar servicio'
                            : 'Confirmar solicitud',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      _isServicio
                          ? 'Cuéntale al proveedor qué necesitas.'
                          : 'Da detalles claros para una mejor respuesta.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: .85)),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          JayaloCard(
            margin: EdgeInsets.zero,
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] as String? ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text([
                      priceLabel,
                      ?conditionLabel,
                      if (businessName != null && businessName.isNotEmpty)
                        businessName,
                    ].join(' · '), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_isServicio) _serviceNeedField(),
          const SizedBox(height: 12),
          if (!_isServicio) ...[
            _quantityField(),
            const SizedBox(height: 12),
          ],
          _brandField(),
          const SizedBox(height: 12),
          _urgencyField(),
          const SizedBox(height: 12),
          if (!_isServicio) ...[_colorField(), const SizedBox(height: 12)],
          if (_isServicio) ...[_serviceLocationField(), const SizedBox(height: 12)]
          else
            _addressField(),
          if (_isServicio) ...[const SizedBox(height: 12), _photoField()],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _canSubmit ? _onSubmitPressed : null,
                child: _busy
                    ? const JayaloSpinner(size: 16)
                    : Text(_photoUploading ? 'Subiendo foto…' : 'Enviar'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _quantityField() => _section(
        label: 'Cantidad',
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              onPressed: _quantity > 1
                  ? () => setState(() => _quantity--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_quantity',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: _quantity < 999
                  ? () => setState(() => _quantity++)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ]),
        ),
      );

  Widget _brandField() => TextField(
        controller: _brandCtrl,
        maxLength: 120,
        decoration: filledField(
          context,
          _isServicio ? 'Preferencias (opcional)' : 'Marca / preferencia',
          hint: _isServicio
              ? 'Ej. horario de tarde, marca específica, presupuesto…'
              : 'Ej. Samsung, LG…',
        ).copyWith(counterText: ''),
      );

  Widget _urgencyField() => _section(
        label: _isServicio ? '¿Cuándo lo necesitas?' : '¿Cuándo quieres comprar?',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final u in InterestUrgency.values)
            _pillChip(
              label: u.chipLabel,
              selected: _urgency == u,
              onTap: () => setState(() => _urgency = u),
            ),
        ]),
      );

  Widget _colorField() => _section(
        label: 'Color',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in interestColors)
            _pillChip(
              label: c.label,
              selected: _colorKey == c.key,
              onTap: () => setState(
                  () => _colorKey = _colorKey == c.key ? null : c.key),
            ),
        ]),
      );

  Widget _addressField() => _section(
        label: 'Dirección de entrega',
        child: _addressPicker(),
      );

  Widget _serviceLocationField() => _section(
        label: 'Lugar del servicio',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: _pillChip(
                label: 'En mi dirección',
                selected: _serviceLocation == 'cliente',
                centered: true,
                onTap: () => setState(() => _serviceLocation = 'cliente'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _pillChip(
                label: 'Local / a coordinar',
                selected: _serviceLocation == 'proveedor',
                centered: true,
                onTap: () => setState(() => _serviceLocation = 'proveedor'),
              ),
            ),
          ]),
          if (_serviceLocation == 'cliente') ...[
            const SizedBox(height: 8),
            _addressPicker(),
          ],
        ]),
      );

  Widget _addressPicker() {
    if (_loadingAddress) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: JayaloSpinner(size: 16));
    }
    if (_profileAddress == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('No tienes dirección en tu perfil.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _addressCtrl,
          maxLength: 160,
          decoration: filledField(context, 'Dirección',
                  hint: 'Calle, número, sector, ciudad…')
              .copyWith(counterText: ''),
        ),
      ]);
    }
    return Column(children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _useProfileAddress,
        onChanged: (v) => setState(() => _useProfileAddress = v ?? true),
        title: const Text('Usar mi dirección', style: TextStyle(fontSize: 13)),
        subtitle: Text(_profileAddress!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
      ),
      if (!_useProfileAddress)
        TextField(
          controller: _addressCtrl,
          maxLength: 160,
          decoration: filledField(context, 'Dirección',
                  hint: 'Calle, número, sector, ciudad…')
              .copyWith(counterText: ''),
        ),
    ]);
  }

  Widget _serviceNeedField() {
    final len = _needCtrl.text.trim().length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _needCtrl,
        maxLength: 400,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: filledField(context, '¿Qué necesitas? *',
                hint:
                    'Ej. Mi aire de 24k no enfría, hace ruido al encender. Vivo en un 3er piso.')
            .copyWith(counterText: ''),
      ),
      const SizedBox(height: 4),
      Text(
        len < 15 ? 'Mínimo 15 caracteres ($len/15)' : 'Listo',
        style: TextStyle(
            fontSize: 11,
            color: len < 15 ? Colors.amber.shade800 : null),
      ),
    ]);
  }

  Widget _photoField() => _section(
        label: 'Foto de referencia (opcional)',
        child: _photo == null
            ? Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Agregar foto'),
                ),
              )
            : Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_photo!.path),
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _photo = null),
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar',
                ),
              ]),
      );

  /// Línea gráfica del form de "hacer oferta" (pedido PO 2026-07-21): etiqueta
  /// de sección (13/w600 en el tono de encabezado) + contenido debajo, y los
  /// TextField con `filledField` — se retiró la tarjeta blanca con micro-label
  /// en mayúsculas que usaba esta hoja.
  Widget _section({required String label, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
          const SizedBox(height: 8),
          child,
        ],
      );

  /// Chip pastilla como las del form de oferta (violeta lleno al elegir).
  Widget _pillChip(
      {required String label,
      required bool selected,
      required VoidCallback onTap,
      bool centered = false}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            textAlign: centered ? TextAlign.center : null,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurface)),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final picked = await guardedPick((p) => p.pickImage(
        source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85));
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final res = validatePickedImage(
        sizeBytes: bytes.length, path: picked.path, currentCount: 0, maxCount: 1);
    if (res is ImagePickError) {
      _toast(res.message);
      return;
    }
    if (mounted) setState(() => _photo = picked);
  }

  Future<void> _onSubmitPressed() async {
    if (_busy) return;
    if (_isServicio && !canSubmitServiceInterest(_needCtrl.text)) {
      _toast('Describe qué necesitas (mínimo 15 caracteres).');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(_isServicio ? 'Solicitar servicio' : '¿Enviar tu interés?'),
        content: const Text(
            'El proveedor verá tu solicitud y podrá contactarte por Jayalo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Sí, enviar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      String? photoUrl;
      if (_isServicio && _photo != null) {
        setState(() => _photoUploading = true);
        try {
          photoUrl = await widget.uploadPhoto(_photo!.path);
        } catch (_) {
          if (mounted) {
            _toast('No se pudo subir la foto');
            setState(() {
              _photoUploading = false;
              _busy = false;
            });
          }
          return;
        }
        if (mounted) setState(() => _photoUploading = false);
      }

      final message = _isServicio
          ? buildServiceInterestMessage(
              need: _needCtrl.text,
              urgency: _urgency,
              locationText: serviceLocationText(
                  atProvider: _serviceLocation == 'proveedor',
                  address: _effectiveAddress),
              preferences: _brandCtrl.text,
              photoUrl: photoUrl,
            )
          : buildProductInterestMessage(
              quantity: _quantity,
              urgency: _urgency,
              brand: _brandCtrl.text,
              colorKey: _colorKey,
              address: _effectiveAddress,
            );

      final res = await widget.sendInterest(
          widget.data.product['id'] as String, truncateInterestMessage(message));
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSent();
      final kindWord = _isServicio ? 'servicio' : 'producto';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.alreadyExists
              ? 'Ya enviaste tu solicitud por este $kindWord.'
              : '¡Interés enviado! El proveedor te contactará pronto.')));
    } catch (_) {
      if (mounted) {
        _toast('No se pudo enviar tu solicitud.');
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }
}
