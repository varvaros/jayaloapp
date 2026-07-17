import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
import '../../domain/pricing.dart';

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
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final bullets = List<String>.from(req['bullets'] as List? ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de solicitud')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(req['title'] as String, style: Theme.of(context).textTheme.titleLarge),
        if (req['is_wholesale'] == true)
          const Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Al por mayor'))),
        const SizedBox(height: 8),
        for (final b in bullets) Text('• $b'),
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
                decoration: const InputDecoration(
                    labelText: 'Precio (RD\$)', border: OutlineInputBorder()))
          else
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Desde (RD\$)',
                          border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Hasta (RD\$)',
                          border: OutlineInputBorder()))),
            ]),
          const SizedBox(height: 12),
          TextField(
              controller: _msg,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Mensaje al cliente', border: OutlineInputBorder())),
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
            Text(
                'Ofertar es GRATIS. Si te aceptan, desbloquear el contacto te '
                'costará ~$_estimatedCost crédito${_estimatedCost == 1 ? '' : 's'}.',
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Enviar oferta (gratis)')),
        ],
      ]),
    );
  }
}
