import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/safe_image_picker.dart';
import '../../data/repos.dart';
import '../shared/brand_kit.dart';
import '../../core/motion.dart';

/// Hoja para registrar la cédula del proveedor informal/técnico (Ajustes →
/// "Validar negocio"). Número + foto → `uploadIdDocPhoto` (bucket privado) +
/// `saveIdDoc`. Con esto el trigger `enforce_business_can_offer` deja de
/// bloquear las ofertas. Devuelve `true` si se guardó.
Future<bool> showIdDocSheet(
  BuildContext context, {
  required String businessId,
  String? currentNumber,
}) async {
  final saved = await showModalBottomSheet<bool>(
    sheetAnimationStyle: JayaloMotion.sheetRise,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: _IdDocBody(businessId: businessId, currentNumber: currentNumber),
    ),
  );
  return saved ?? false;
}

class _IdDocBody extends StatefulWidget {
  const _IdDocBody({required this.businessId, this.currentNumber});
  final String businessId;
  final String? currentNumber;
  @override
  State<_IdDocBody> createState() => _IdDocBodyState();
}

class _IdDocBodyState extends State<_IdDocBody> {
  late final _number = TextEditingController(text: widget.currentNumber ?? '');
  XFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await guardedPick(
        (p) => p.pickImage(source: source, maxWidth: 1600, imageQuality: 85));
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty) {
      return _snack('Escribe tu número de cédula.');
    }
    if (_photo == null) return _snack('Sube la foto de tu cédula.');
    setState(() => _busy = true);
    try {
      final path = await uploadIdDocPhoto(_photo!.path, widget.businessId);
      await saveIdDoc(
          businessId: widget.businessId,
          idNumber: _number.text.trim(),
          idPhotoPath: path);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Identificación guardada. Ya puedes enviar ofertas.')));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('No se pudo guardar. Intenta de nuevo.');
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Validar tu negocio',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
            'Registra tu cédula para poder enviar ofertas. Solo el equipo de Jayalo la ve.'),
        const SizedBox(height: 16),
        TextField(
          controller: _number,
          keyboardType: TextInputType.number,
          decoration: filledField(context, 'Número de cédula',
              hint: '000-0000000-0'),
        ),
        const SizedBox(height: 14),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(_photo!.path),
                height: 160, width: double.infinity, fit: BoxFit.cover),
          )
        else
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                child: Text('Foto de la cédula',
                    style: TextStyle(color: cs.onSurfaceVariant))),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Cámara'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galería'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const JayaloSpinner(size: 18)
              : const Text('Guardar identificación'),
        ),
      ],
    );
  }
}
