import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
import '../../domain/offer_message.dart';
import '../../domain/pricing.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';

const _maxOfferPhotos = 5;

class ProviderRequestDetailScreen extends StatefulWidget {
  const ProviderRequestDetailScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<ProviderRequestDetailScreen> createState() =>
      _ProviderRequestDetailScreenState();
}

class _ProviderRequestDetailScreenState
    extends State<ProviderRequestDetailScreen> {
  Map<String, dynamic>? _req;
  String? _businessId;
  bool _busy = false;
  // Producto: precio fijo vs rango. Servicio: 4 modos (ver [_svcModes]).
  bool _fixed = true;
  int _svcMode = 0;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  // Servicio: por hora + disponibilidad/duración.
  final _hourly = TextEditingController();
  final _hours = TextEditingController();
  final _availability = TextEditingController();
  final _duration = TextEditingController();
  // Producto: envío / instalación / evaluación (paridad web).
  bool _offersShipping = false;
  final _shipping = TextEditingController();
  bool _offersInstallation = false;
  final _installation = TextEditingController();
  bool _requiresEvaluation = false;
  final _evaluation = TextEditingController();
  final List<XFile> _photos = [];

  /// Modos de precio del formulario de SERVICIO (paridad web: fijo / rango /
  /// por hora / a evaluar en sitio). El índice es [_svcMode].
  static const _svcModes = ['fixed', 'range', 'hourly', 'needs_evaluation'];

  bool get _isService => _req?['kind'] == 'servicio';
  String get _pricingMode =>
      _isService ? _svcModes[_svcMode] : (_fixed ? 'fixed' : 'range');

  @override
  void initState() {
    super.initState();
    requestById(widget.requestId)
        .then((r) => mounted ? setState(() => _req = r) : null);
    myBusinessId().then((b) => mounted ? setState(() => _businessId = b) : null);
  }

  @override
  void dispose() {
    for (final c in [
      _price, _min, _max, _hourly, _hours,
      _availability, _duration, _shipping, _installation, _evaluation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _estimatedCost {
    final mode = _pricingMode;
    return pointsForOffer(
      price: mode == 'fixed' ? double.tryParse(_price.text) : null,
      priceMin: mode == 'range' ? double.tryParse(_min.text) : null,
      priceMax: mode == 'range' ? double.tryParse(_max.text) : null,
      pricingMode: mode,
      hourlyRate: mode == 'hourly' ? double.tryParse(_hourly.text) : null,
      estimatedHours: mode == 'hourly' ? double.tryParse(_hours.text) : null,
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    final res = validatePickedImage(
        sizeBytes: await picked.length(),
        path: picked.path,
        currentCount: _photos.length,
        maxCount: _maxOfferPhotos);
    if (res is ImagePickError) return _toast(res.message);
    if (mounted) setState(() => _photos.add(picked));
  }

  Future<void> _submit() async {
    final req = _req!;
    final isService = _isService;
    final mode = _pricingMode;

    double? p, mn, mx, hr, hrs;
    switch (mode) {
      case 'fixed':
        p = double.tryParse(_price.text);
        if (p == null || p <= 0) return _toast('Pon el precio en RD\$.');
      case 'range':
        mn = double.tryParse(_min.text);
        mx = double.tryParse(_max.text);
        if (mn == null || mx == null || mx < mn) {
          return _toast('Revisa el rango de precio.');
        }
      case 'hourly':
        hr = double.tryParse(_hourly.text);
        hrs = double.tryParse(_hours.text);
        if (hr == null || hr <= 0) return _toast('Pon la tarifa por hora.');
        if (hrs == null || hrs <= 0) return _toast('Pon las horas estimadas.');
      // 'needs_evaluation' (solo servicio): el precio se define en sitio, sin
      // validación de precio aquí.
    }

    // El mensaje ya no es texto libre: se arma desde los datos (decisión PO).
    final evalOn = isService ? mode == 'needs_evaluation' : _requiresEvaluation;
    final message = composeOfferMessage(
      isService: isService,
      offersShipping: _offersShipping,
      shippingPrice: double.tryParse(_shipping.text),
      offersInstallation: _offersInstallation,
      installationPrice: double.tryParse(_installation.text),
      requiresEvaluation: evalOn,
      evaluationPrice: double.tryParse(_evaluation.text),
      availabilityNote: _availability.text,
      estimatedDuration: _duration.text,
    );

    setState(() => _busy = true);
    try {
      // Subir las fotos a Storage antes de insertar (nunca base64 en la BD).
      final imageUrls =
          await Future.wait(_photos.map((x) => uploadOfferImage(x.path)));
      await makeOffer(
        request: req,
        businessId: _businessId!,
        price: p,
        priceMin: mn,
        priceMax: mx,
        message: message,
        imageUrls: imageUrls,
        pricingMode: mode,
        // Los toggles de logística solo aplican a producto.
        offersShipping: isService ? false : _offersShipping,
        shippingPrice: double.tryParse(_shipping.text),
        offersInstallation: isService ? false : _offersInstallation,
        installationPrice: double.tryParse(_installation.text),
        requiresEvaluation: evalOn,
        evaluationPrice: double.tryParse(_evaluation.text),
        hourlyRate: hr,
        estimatedHours: hrs,
        availabilityNote: isService ? _availability.text.trim() : '',
        estimatedDuration: isService ? _duration.text.trim() : '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('¡Oferta enviada! Te avisamos si te aceptan. 🚀')));
      context.go('/provider');
    } catch (e) {
      if (mounted) _showSubmitError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nunca esconder el porqué real de un fallo al ofertar. El caso dominante es
  /// el trigger `enforce_business_can_offer` (proveedor informal/técnico sin
  /// cédula → `ID_DOC_REQUIRED`): antes salía un genérico "no se pudo enviar" y
  /// el proveedor no tenía idea de qué le faltaba. Ahora mostramos el motivo y,
  /// para ese caso, un atajo para completar la identidad en la web.
  void _showSubmitError(Object e) {
    final msg = e is PostgrestException ? e.message : e.toString();
    if (msg.contains('ID_DOC_REQUIRED')) {
      final reason = msg.replaceFirst(RegExp(r'^ID_DOC_REQUIRED:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(reason),
        action: SnackBarAction(
          label: 'Completar',
          onPressed: () => launchUrl(
              Uri.parse('${AppConfig.siteUrl}/provider'),
              mode: LaunchMode.externalApplication),
        ),
      ));
      return;
    }
    _toast('No se pudo enviar la oferta.');
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: filledField(context, label),
      );

  Widget _textField(TextEditingController c, String label) => TextField(
        controller: c,
        decoration: filledField(context, label),
      );

  /// Campos de precio, ramificados por kind: producto = fijo/rango; servicio =
  /// 4 modos (fijo/rango/por hora/a evaluar), paridad con la web.
  List<Widget> _pricingFields(BuildContext context) {
    if (!_isService) {
      return [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Precio fijo')),
            ButtonSegment(value: false, label: Text('Rango')),
          ],
          selected: {_fixed},
          onSelectionChanged: (s) => setState(() => _fixed = s.first),
        ),
        const SizedBox(height: 12),
        if (_fixed)
          _numField(_price, 'Precio (RD\$)')
        else
          Row(children: [
            Expanded(child: _numField(_min, 'Desde (RD\$)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_max, 'Hasta (RD\$)')),
          ]),
      ];
    }
    return [
      PillSegmented(
        options: const ['Fijo', 'Rango', 'Por hora', 'A evaluar'],
        index: _svcMode,
        onChanged: (i) => setState(() => _svcMode = i),
      ),
      const SizedBox(height: 12),
      ..._svcModeFields(context),
    ];
  }

  List<Widget> _svcModeFields(BuildContext context) {
    switch (_svcModes[_svcMode]) {
      case 'fixed':
        return [_numField(_price, 'Precio (RD\$)')];
      case 'range':
        return [
          Row(children: [
            Expanded(child: _numField(_min, 'Desde (RD\$)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_max, 'Hasta (RD\$)')),
          ]),
        ];
      case 'hourly':
        return [
          Row(children: [
            Expanded(child: _numField(_hourly, 'RD\$ por hora')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_hours, 'Horas est.')),
          ]),
        ];
      default: // needs_evaluation
        final cs = Theme.of(context).colorScheme;
        return [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
                'El precio se define tras revisar en sitio; el cliente lo verá como "a evaluar".',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ];
    }
  }

  /// Toggles de logística de PRODUCTO (envío/instalación/evaluación), cada uno
  /// con su costo opcional y la etiqueta "Gratis" cuando el costo es 0.
  List<Widget> _productExtras(BuildContext context) => [
        _toggleRow(
          title: 'Ofrezco envío',
          subtitle: 'Puedes llevar el producto al cliente.',
          value: _offersShipping,
          onChanged: (v) => setState(() => _offersShipping = v),
          cost: _shipping,
          costLabel: 'Costo de envío (RD\$)',
        ),
        _toggleRow(
          title: 'Ofrezco instalación',
          subtitle: 'Incluyes el servicio de instalación.',
          value: _offersInstallation,
          onChanged: (v) => setState(() => _offersInstallation = v),
          cost: _installation,
          costLabel: 'Costo de instalación (RD\$)',
        ),
        _toggleRow(
          title: 'Requiere evaluación',
          subtitle: 'El precio depende de revisar en sitio.',
          value: _requiresEvaluation,
          onChanged: (v) => setState(() => _requiresEvaluation = v),
          cost: _evaluation,
          costLabel: 'Costo de evaluación (RD\$)',
        ),
      ];

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required TextEditingController cost,
    required String costLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final free = (double.tryParse(cost.text) ?? 0) <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: _busy ? null : onChanged),
        ]),
        if (value)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              Expanded(child: _numField(cost, costLabel)),
              const SizedBox(width: 12),
              if (free)
                Text('Gratis',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? JayaloColors.dSuccess
                            : JayaloColors.success)),
            ]),
          ),
      ]),
    );
  }

  Widget _thumb(File file, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file,
              width: 76, height: 76, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.cancel, size: 22),
            onPressed:
                _busy ? null : () => setState(() => _photos.removeAt(index)),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final req = _req;
    if (req == null) {
      return Scaffold(
        body: Stack(children: [
          const JayaloLoaderBlock(),
          SafeArea(child: _backFab(context)),
        ]),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amberPanel = dark ? const Color(0xFF3A2C12) : const Color(0xFFF0C48C);
    final amberInk = dark ? const Color(0xFFF0C48C) : const Color(0xFF6B4514);
    final bullets = List<String>.from(req['bullets'] as List? ?? const []);
    final images =
        ((req['image_urls'] as List?)?.cast<String>() ?? const <String>[])
            .where((u) => u.isNotEmpty)
            .toList();
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(children: [
        // Panel ámbar del detalle. La FOTO LLENA todo el panel (cover) IGUAL
        // que en el detalle del cliente (`request_status_screen._AmberPanel`).
        // Sin foto, el panel se pinta LILA CLARO con el ícono violeta (pedido
        // PO 2026-07-19, mismo criterio que el detalle del cliente).
        Container(
          height: 300 + topInset,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: images.isEmpty
                ? (dark
                        ? JayaloStatus.respondedDark
                        : JayaloStatus.respondedLight)
                    .bg
                : amberPanel,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(30)),
          ),
          child: Stack(children: [
            // Tocar la foto abre el visor a pantalla completa.
            Positioned.fill(
              child: images.isEmpty
                  ? Center(
                      child: Icon(
                          req['kind'] == 'servicio'
                              ? Icons.handyman_outlined
                              : Icons.inventory_2_outlined,
                          size: 120,
                          color: (dark
                                  ? JayaloStatus.respondedDark
                                  : JayaloStatus.respondedLight)
                              .ink))
                  : GestureDetector(
                      onTap: () => showPhotoViewer(context, images),
                      child: Image.network(images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                              child: Icon(
                                  req['kind'] == 'servicio'
                                      ? Icons.handyman_outlined
                                      : Icons.inventory_2_outlined,
                                  size: 120,
                                  color: amberInk))),
                    ),
            ),
            // Miniatura de la 2ª foto pegada al borde derecho (máx. 2 visibles).
            if (images.length > 1)
              Positioned(
                top: topInset + 30,
                right: 0,
                child: GestureDetector(
                  onTap: () =>
                      showPhotoViewer(context, images, initialIndex: 1),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16)),
                    child: Image.network(images[1],
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                            width: 76, height: 76, color: amberPanel)),
                  ),
                ),
              ),
            SafeArea(child: _backFab(context)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: ListView(
                padding: EdgeInsets.fromLTRB(
                    22, 22, 22, 16 + navBarReservedSpace(context)),
                children: [
                  Text(req['title'] as String,
                      style: TextStyle(
                          fontSize: 21,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  if (req['is_wholesale'] == true)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: StatusChip(
                              label: 'Al por mayor',
                              icon: Icons.storefront_outlined,
                              tone: dark
                                  ? JayaloStatus.respondedDark
                                  : JayaloStatus.respondedLight),
                        )),
                  if (bullets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Detalles',
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final b in bullets)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(b,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurface)),
                        ),
                    ]),
                  ],
                  const Divider(height: 32),
                  if (_businessId == null)
          FilledButton(
            onPressed: () => launchUrl(Uri.parse('${AppConfig.siteUrl}/provider'),
                mode: LaunchMode.externalApplication),
            child: const Text('Completa tu negocio en jayalo.com para ofertar'),
          )
        else ...[
          Text('Tu oferta', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._pricingFields(context),
          if (_isService) ...[
            const SizedBox(height: 12),
            _textField(_availability, 'Disponibilidad (ej: Lun a Vie)'),
            const SizedBox(height: 8),
            _textField(_duration, 'Duración estimada (ej: 2 días)'),
          ] else ...[
            const SizedBox(height: 12),
            ..._productExtras(context),
          ],
          const SizedBox(height: 16),
          Text(
              _isService
                  ? 'Fotos de tu trabajo (hasta $_maxOfferPhotos)'
                  : 'Fotos de tu producto (hasta $_maxOfferPhotos)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_photos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  _thumb(File(_photos[i].path), i),
              ],
            ),
          if (_photos.length < _maxOfferPhotos)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Cámara'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          if (_estimatedCost > 0)
            Builder(builder: (context) {
              // Ámbar = dinero: el costo del unlock se ve claro ANTES de
              // ofertar, sin asustar (ofertar sigue siendo gratis).
              final tone = Theme.of(context).brightness == Brightness.dark
                  ? JayaloStatus.acceptedDark
                  : JayaloStatus.acceptedLight;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                    'Ofertar es GRATIS. Si te aceptan, desbloquear el contacto '
                    'te costará ~$_estimatedCost crédito${_estimatedCost == 1 ? '' : 's'}.',
                    style: TextStyle(fontSize: 12, color: tone.ink)),
              );
            }),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Enviar oferta (gratis)')),
        ],
              ]),
            ),
          ),
        ]),
      );
  }

  /// Atrás flotante sobre el panel ámbar (mismo gesto que el detalle del
  /// cliente: en el detalle no hay header violeta, solo el atrás).
  Widget _backFab(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 16),
        child: Align(
          alignment: Alignment.topLeft,
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
        ),
      );
}
