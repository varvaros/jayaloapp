import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error_reporter.dart';
import '../../core/safe_image_picker.dart';
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
import '../../domain/contact_info.dart' show contactInfoMessage, isContactInfoError;
import 'add_store_item_screen.dart' show parseStoreItemPrice;
import '../shared/brand_kit.dart';
import '../shared/local_image_guard.dart';
import '../shared/network_image.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Alta O EDICIÓN de un paquete/plan del negocio (Task 7, 2026-08-09) — espejo
/// simplificado de `PackageEditorDialog.tsx` de la web: nombre, descripción,
/// precio, lista de items ("Qué incluye") y UNA foto. Sin `is_featured`
/// ("Más popular"): el brief de esta tarea no lo pidió, así que no se agrega
/// un control sin efecto server-side conocido.
///
/// Con [initial] (fila de `provider_packages`, columnas [packageCols])
/// precarga todo y "Guardar" hace `UPDATE`; sin él es un alta nueva.
class PackageEditorScreen extends StatefulWidget {
  const PackageEditorScreen({
    super.key,
    required this.businessId,
    this.initial,
    this.save = savePackage,
    this.uploadImage = uploadPackageImage,
  });

  /// Viene de "Mi negocio", que ya lo tiene cargado.
  final String businessId;

  /// Fila completa de `provider_packages` (columnas [packageCols]) al
  /// EDITAR un paquete propio. `null` = alta nueva.
  final Map<String, dynamic>? initial;

  /// Inyectables para probar sin red — defaults a las implementaciones
  /// reales de `repos.dart` (mismo patrón que `AddStoreItemScreen`).
  final Future<void> Function({
    String? id,
    required String businessId,
    required String name,
    String description,
    double? price,
    required List<String> items,
    String? imageUrl,
  })
  save;
  final Future<String> Function(String filePath) uploadImage;

  @override
  State<PackageEditorScreen> createState() => _PackageEditorScreenState();
}

class _PackageEditorScreenState extends State<PackageEditorScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();

  /// Filas dinámicas de "Qué incluye" — siempre al menos una (mismo criterio
  /// que `PackageEditorDialog.tsx`, que arranca con `[""]`).
  final List<TextEditingController> _items = [];

  /// Foto local recién elegida (aún sin subir).
  XFile? _photo;

  /// URL ya subida: la de `initial['image_url']`, o la que dejó una subida
  /// de ESTA sesión. `null` = sin foto.
  String? _keptUrl;

  /// Ruta local → URL ya subida, para no re-subir el mismo fichero si el
  /// guardado falla y el usuario reintenta (mismo patrón que
  /// `AddStoreItemScreen._uploaded`).
  final Map<String, String> _uploaded = {};

  bool _busy = false;
  bool _saved = false;

  bool get _editing => widget.initial != null;

  /// Estado "limpio" del formulario, para el guard sin-guardar — mismo
  /// contrato que `_cleanSnapshot` en `AddStoreItemScreen` (compara contra lo
  /// que dejó [_prefill], no contra cadenas vacías).
  String _cleanSnapshot = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _prefill(initial);
    } else {
      _items.add(TextEditingController());
    }
    _cleanSnapshot = _formSnapshot();
    takeUnsavedGuard(
      owner: this,
      check: _hasUnsavedWork,
      message: 'Perderás lo que escribiste aquí.',
    );
  }

  void _prefill(Map<String, dynamic> item) {
    _name.text = (item['name'] as String?) ?? '';
    _desc.text = (item['description'] as String?) ?? '';
    final price = item['price'] as num?;
    if (price != null) _price.text = '$price';
    final items = (item['items'] as List?)?.cast<String>() ?? const [];
    if (items.isEmpty) {
      _items.add(TextEditingController());
    } else {
      _items.addAll(items.map((s) => TextEditingController(text: s)));
    }
    final url = item['image_url'] as String?;
    if (url != null && url.isNotEmpty) _keptUrl = url;
  }

  @override
  void dispose() {
    releaseUnsavedGuard(this);
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    for (final c in _items) {
      c.dispose();
    }
    super.dispose();
  }

  /// Serializa TODO lo que el usuario puede cambiar. Usa la RUTA de la foto
  /// local (no un conteo): un conteo estable con una foto DISTINTA se leería
  /// como "sin cambios" (hallazgo del revisor de la Task 6 sobre
  /// `add_store_item_screen.dart`, aplicado aquí desde el inicio).
  String _formSnapshot() => [
    _name.text,
    _desc.text,
    _price.text,
    for (final c in _items) c.text,
    _photo?.path ?? '',
    _keptUrl ?? '',
  ].join('|');

  bool _hasUnsavedWork() => !_saved && _formSnapshot() != _cleanSnapshot;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _addItem() => setState(() => _items.add(TextEditingController()));

  void _removeItem(int index) {
    // Siempre queda al menos una fila — mismo criterio que la web
    // (`items.length > 1` antes de ofrecer el botón de quitar).
    if (_items.length <= 1) return;
    setState(() => _items.removeAt(index).dispose());
  }

  Future<void> _pickPhoto() async {
    final picked = await guardedPick(
        (p) => p.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85));
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final err = validateLocalImage(file);
    if (err != null) return _toast(err);
    setState(() {
      _photo = picked;
      _keptUrl = null;
    });
  }

  void _removePhoto() => setState(() {
    _photo = null;
    _keptUrl = null;
  });

  Future<void> _save() async {
    final nombre = _name.text.trim();
    if (nombre.isEmpty) {
      _toast('Ponle un nombre al paquete.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? imageUrl = _keptUrl;
      final photo = _photo;
      if (photo != null) {
        imageUrl = _uploaded[photo.path] ??= await widget.uploadImage(photo.path);
      }
      final cleanItems = _items
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await widget.save(
        id: widget.initial?['id'] as String?,
        businessId: widget.businessId,
        name: nombre,
        description: _desc.text.trim(),
        price: parseStoreItemPrice(_price.text)?.toDouble(),
        items: cleanItems,
        imageUrl: imageUrl,
      );
      _saved = true;
      releaseUnsavedGuard(this);
      if (!mounted) return;
      _toast(_editing ? 'Cambios guardados.' : 'Paquete agregado.');
      context.pop(true);
    } catch (e, s) {
      if (isContactInfoError(e)) {
        _toast(contactInfoMessage);
      } else {
        unawaited(reportError(e, s));
        _toast('No se pudo guardar. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () async {
              if (_hasUnsavedWork()) {
                final salir = await confirmDiscard(context);
                if (!salir) return;
                if (!context.mounted) return;
              }
              context.pop();
            },
          ),
          title: _editing ? 'Editar paquete' : 'Añadir paquete',
          titleAlign: HeaderTitleAlign.center,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 24 + navBarReservedSpace(context)),
            children: [
              _photoField(context),
              const SizedBox(height: 16),
              TextField(
                key: const Key('campo-nombre-paquete'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre del paquete'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('campo-descripcion-paquete'),
                controller: _desc,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('campo-precio-paquete'),
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: filledField(context, 'Precio (RD\$)'),
              ),
              const SizedBox(height: 20),
              _itemsSection(context),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
              const SizedBox(height: 8),
              Text(
                'Luego podrás adjuntarlo a tus ofertas con un solo toque.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _photoField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = _keptUrl;
    if (_photo == null && (url == null || url.isEmpty)) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : _pickPhoto,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Agregar foto (opcional)'),
      );
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _photo != null
            ? Image.file(File(_photo!.path), width: 96, height: 96, fit: BoxFit.cover)
            : JayaloNetworkImage(url!,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                    width: 96, height: 96, color: cs.surfaceContainerHighest)),
      ),
      Positioned(
        top: 2,
        right: 2,
        child: InkWell(
          onTap: _busy ? null : _removePhoto,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      ),
    ]);
  }

  Widget _itemsSection(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
          child: Text('Qué incluye',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        TextButton.icon(
          key: const Key('boton-agregar-item'),
          onPressed: _busy ? null : _addItem,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar'),
        ),
      ]),
      for (var i = 0; i < _items.length; i++) _itemRow(i),
    ]);
  }

  Widget _itemRow(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            key: Key('campo-item-$i'),
            controller: _items[i],
            decoration: InputDecoration(labelText: 'Item ${i + 1}'),
          ),
        ),
        if (_items.length > 1)
          IconButton(
            key: Key('boton-quitar-item-$i'),
            tooltip: 'Quitar item',
            onPressed: _busy ? null : () => _removeItem(i),
            icon: const Icon(Icons.delete_outline),
          ),
      ]),
    );
  }
}
