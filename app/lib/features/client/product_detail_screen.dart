import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
import '../../domain/interest_message.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

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
    required this.businessRevealed,
  });

  final Map<String, dynamic> product;
  final BusinessLite? business;

  /// Ya existe una fila de interés del cliente actual para este producto
  /// (idempotente — alimenta el botón "Solicitud enviada").
  final bool hasInterest;

  /// El usuario actual es el dueño del producto (nunca se le ofrece
  /// interesarse en lo suyo).
  final bool isOwner;

  /// Gate de identidad (paridad web): el nombre/logo del negocio solo se
  /// revela si es el propio dueño o si algún proveedor ya pagó por
  /// desbloquear el interés de este cliente en este producto. Antes de eso
  /// se muestra un negocio genérico — nunca se regala la identidad gratis.
  final bool businessRevealed;
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
          ? Future.value((exists: false, unlocked: false))
          : productInterestStatus(widget.productId),
    ]);
    final business = results[0] as BusinessLite?;
    final interest = results[1] as ({bool exists, bool unlocked});
    return ProductDetailData(
      product: product,
      business: business,
      hasInterest: interest.exists,
      isOwner: isOwner,
      businessRevealed: isOwner || interest.unlocked,
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
          final title = (snap.data?.product['name'] as String?) ?? 'Producto';
          return Scaffold(
            appBar: AppBar(
                title: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: switch (snap.connectionState) {
              ConnectionState.done => snap.hasError
                  ? ErrorRetry(onRetry: () async => _refetch())
                  : snap.data == null
                      ? EmptyState(
                          message: 'No encontramos este producto.\n\n'
                              'Puede que ya no esté disponible.',
                        )
                      : ProductDetailView(
                          data: snap.data!, onInterestSent: _refetch),
              _ => const SkeletonList(),
            },
          );
        },
      );
}

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
    final images = (p['image_urls'] as List?)?.cast<String>() ?? const [];
    final priceLabel = catalogPriceLabel(
      price: p['price'] as num?,
      priceMin: p['price_min'] as num?,
      priceMax: p['price_max'] as num?,
    );
    final condition = p['condition'] as String?;
    final conditionLabel =
        condition == 'nuevo' ? 'Nuevo' : condition == 'usado' ? 'Usado' : null;
    final color = p['color'] as String?;
    final offersShipping = p['offers_shipping'] == true;
    final offersInstallation = p['offers_installation'] == true;
    final rubro = p['rubro'] as String?;

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        _Gallery(
          images: images,
          activeIndex: _activeImg,
          onSelect: (i) => setState(() => _activeImg = i),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rubro != null && rubro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.category_outlined, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(rubro,
                        style: TextStyle(fontSize: 12, color: cs.primary)),
                  ]),
                ),
              Text(name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(priceLabel,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.primary)),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(description,
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (conditionLabel != null)
                  _Tag(icon: Icons.sell_outlined, label: conditionLabel),
                if (color != null && color.isNotEmpty)
                  _Tag(icon: Icons.palette_outlined, label: color),
                if (offersShipping)
                  const _Tag(
                      icon: Icons.local_shipping_outlined,
                      label: 'Envío disponible'),
                if (offersInstallation)
                  const _Tag(
                      icon: Icons.build_outlined, label: 'Instalación incluida'),
              ]),
            ],
          ),
        ),
        if (widget.data.business != null)
          _BusinessCard(
                  business: widget.data.business!,
                  revealed: widget.data.businessRevealed)
              .cascadeIn(0),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _CtaArea(data: widget.data, onOpenInterest: _openInterest),
        ),
      ],
    );
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

class _Gallery extends StatelessWidget {
  const _Gallery(
      {required this.images, required this.activeIndex, required this.onSelect});
  final List<String> images;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, size: 48, color: cs.onSurfaceVariant));
    final main = images.isEmpty ? null : images[activeIndex.clamp(0, images.length - 1)];
    return Column(children: [
      AspectRatio(
        aspectRatio: 1,
        child: main == null
            ? placeholder()
            : Image.network(main,
                fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder()),
      ),
      if (images.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: i == activeIndex ? cs.primary : cs.outlineVariant,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(images[i],
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

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

/// "Ofrecido por" — antes de [revealed] muestra un negocio genérico (nunca
/// se regala la identidad gratis, paridad `products.$productId.tsx`). Sin
/// `onTap`: la app no tiene una pantalla pública de negocio ajeno (solo
/// `/provider/business` para el DUEÑO), a diferencia de la web.
class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business, required this.revealed});
  final BusinessLite business;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight;
    final logoUrl = revealed ? business.logoUrl : null;
    return JayaloCard(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: cs.surfaceContainerHighest,
          backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
          child: logoUrl == null
              ? Icon(
                  revealed ? Icons.storefront_outlined : Icons.help_outline,
                  color: cs.onSurfaceVariant)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ofrecido por',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text(revealed ? business.name : 'Proveedor',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (revealed && business.verified) ...[
                const SizedBox(height: 4),
                StatusChip(
                    label: 'Negocio verificado',
                    icon: Icons.verified,
                    tone: tone),
              ],
            ],
          ),
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
    if (data.hasInterest) {
      return Column(children: [
        FilledButton(
          onPressed: null,
          child: const Text('Solicitud enviada'),
        ),
        const SizedBox(height: 8),
        Text('Te avisaremos si el proveedor te escribe.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]);
    }
    return Column(children: [
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
    ]);
  }
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
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_isServicio ? 'Solicitar servicio' : 'Confirmar solicitud',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            _isServicio
                ? 'Cuéntale al proveedor qué necesitas para que responda con precio y disponibilidad.'
                : 'Ayuda al proveedor con detalles claros para una mejor respuesta.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
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
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _quantityField() => _fieldCard(
        label: 'Cantidad',
        child: Row(children: [
          IconButton(
            onPressed: _quantity > 1
                ? () => setState(() => _quantity--)
                : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$_quantity',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: _quantity < 999
                ? () => setState(() => _quantity++)
                : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      );

  Widget _brandField() => _fieldCard(
        label: _isServicio ? 'Preferencias (opcional)' : 'Marca / preferencia',
        child: TextField(
          controller: _brandCtrl,
          maxLength: 120,
          decoration: InputDecoration(
            border: InputBorder.none,
            counterText: '',
            hintText: _isServicio
                ? 'Ej. horario de tarde, marca específica, presupuesto…'
                : 'Ej. Samsung, LG…',
          ),
        ),
      );

  Widget _urgencyField() => _fieldCard(
        label: _isServicio ? '¿Cuándo lo necesitas?' : '¿Cuándo quieres comprar?',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final u in InterestUrgency.values)
            ChoiceChip(
              label: Text(u.chipLabel),
              selected: _urgency == u,
              onSelected: (_) => setState(() => _urgency = u),
            ),
        ]),
      );

  Widget _colorField() => _fieldCard(
        label: 'Color',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in interestColors)
            ChoiceChip(
              label: Text(c.label),
              selected: _colorKey == c.key,
              onSelected: (sel) =>
                  setState(() => _colorKey = sel ? c.key : null),
            ),
        ]),
      );

  Widget _addressField() => _fieldCard(
        label: 'Dirección de entrega',
        child: _addressPicker(),
      );

  Widget _serviceLocationField() => _fieldCard(
        label: 'Lugar del servicio',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('En mi dirección'),
                selected: _serviceLocation == 'cliente',
                onSelected: (_) => setState(() => _serviceLocation = 'cliente'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Local / a coordinar'),
                selected: _serviceLocation == 'proveedor',
                onSelected: (_) =>
                    setState(() => _serviceLocation = 'proveedor'),
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
        const SizedBox(height: 4),
        TextField(
          controller: _addressCtrl,
          maxLength: 160,
          decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              hintText: 'Calle, número, sector, ciudad…'),
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
          decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              hintText: 'Calle, número, sector, ciudad…'),
        ),
    ]);
  }

  Widget _serviceNeedField() {
    final len = _needCtrl.text.trim().length;
    return _fieldCard(
      label: '¿Qué necesitas? *',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _needCtrl,
          maxLength: 400,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: InputBorder.none,
            counterText: '',
            hintText:
                'Ej. Mi aire de 24k no enfría, hace ruido al encender. Vivo en un 3er piso.',
          ),
        ),
        Text(
          len < 15 ? 'Mínimo 15 caracteres ($len/15)' : 'Listo',
          style: TextStyle(
              fontSize: 11,
              color: len < 15 ? Colors.amber.shade800 : null),
        ),
      ]),
    );
  }

  Widget _photoField() => _fieldCard(
        label: 'Foto de referencia (opcional)',
        child: _photo == null
            ? OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Agregar foto'),
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

  Widget _fieldCard({required String label, required Widget child}) =>
      JayaloCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .4)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
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
