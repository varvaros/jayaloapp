import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
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
  bool _fixed = true;
  bool _busy = false;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _msg = TextEditingController();
  final List<XFile> _photos = [];

  @override
  void initState() {
    super.initState();
    requestById(widget.requestId)
        .then((r) => mounted ? setState(() => _req = r) : null);
    myBusinessId().then((b) => mounted ? setState(() => _businessId = b) : null);
  }

  int get _estimatedCost => pointsForOffer(
        price: _fixed ? double.tryParse(_price.text) : null,
        priceMin: _fixed ? null : double.tryParse(_min.text),
        priceMax: _fixed ? null : double.tryParse(_max.text),
      );

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
    final p = double.tryParse(_price.text);
    final mn = double.tryParse(_min.text);
    final mx = double.tryParse(_max.text);
    if (_fixed && (p == null || p <= 0)) return _toast('Pon el precio en RD\$.');
    if (!_fixed && (mn == null || mx == null || mx < mn)) {
      return _toast('Revisa el rango de precio.');
    }
    if (_msg.text.trim().isEmpty) {
      return _toast('Escribe un mensaje corto al cliente.');
    }
    setState(() => _busy = true);
    try {
      // Subir las fotos a Storage antes de insertar (nunca base64 en la BD).
      final imageUrls =
          await Future.wait(_photos.map((x) => uploadOfferImage(x.path)));
      await makeOffer(
          request: req,
          businessId: _businessId!,
          price: _fixed ? p : null,
          priceMin: _fixed ? null : mn,
          priceMax: _fixed ? null : mx,
          message: _msg.text.trim(),
          imageUrls: imageUrls);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('¡Oferta enviada! Te avisamos si te aceptan. 🚀')));
      context.go('/provider');
    } catch (_) {
      _toast('No se pudo enviar la oferta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
          const Padding(
              padding: EdgeInsets.only(top: 80), child: SkeletonList()),
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
        // Panel ámbar del detalle (doctrina: el detalle es cálido, no lila; la
        // foto de la solicitud manda, con solo el atrás flotando).
        Container(
          height: 210 + topInset,
          decoration: BoxDecoration(
            color: amberPanel,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(30)),
          ),
          child: Stack(children: [
            Positioned(
              top: topInset + 20,
              left: 20,
              right: 20,
              bottom: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: images.isEmpty
                    ? Center(
                        child: Icon(
                            req['kind'] == 'servicio'
                                ? Icons.handyman_outlined
                                : Icons.inventory_2_outlined,
                            size: 96,
                            color: amberInk))
                    : Image.network(images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(color: amberPanel)),
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
            TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: filledField(context, 'Precio (RD\$)'))
          else
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: filledField(context, 'Desde (RD\$)'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: filledField(context, 'Hasta (RD\$)'))),
            ]),
          const SizedBox(height: 12),
          TextField(
              controller: _msg,
              maxLines: 3,
              decoration: filledField(context, 'Mensaje al cliente')),
          const SizedBox(height: 16),
          Text('Fotos de tu producto (hasta $_maxOfferPhotos)',
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
