import 'package:flutter/material.dart';

import '../../domain/search_fold.dart';
import 'brand_kit.dart' show offerBadgeTone;

/// Máximo de chips de servicios por negocio (Task 5, 2026-08-09). Un negocio
/// no anuncia 40 servicios en una tarjeta; 20 ya es generoso.
const int kMaxServiceChips = 20;

/// Largo máximo de un chip individual. Un string de 61+ caracteres se
/// RECHAZA con aviso (no se recorta) — decisión del plan: recortar en
/// silencio esconde que el proveedor escribió más de lo que se guardó.
const int kMaxServiceChipLen = 60;

/// Bottom sheet para editar los chips de servicios del negocio ("Mi
/// negocio", solo dueño). Devuelve la lista final al tocar "Guardar", o
/// `null` si se canceló o se cerró arrastrando — mismo contrato que
/// `showTextEditorSheet` (Task 4).
Future<List<String>?> showServiceChipsEditor(
  BuildContext context, {
  required List<String> initial,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ServiceChipsEditorSheet(initial: initial),
  );
}

class _ServiceChipsEditorSheet extends StatefulWidget {
  const _ServiceChipsEditorSheet({required this.initial});
  final List<String> initial;

  @override
  State<_ServiceChipsEditorSheet> createState() =>
      _ServiceChipsEditorSheetState();
}

class _ServiceChipsEditorSheetState extends State<_ServiceChipsEditorSheet> {
  late final List<String> _chips = List.of(widget.initial);
  late final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// `onSubmitted` del `TextField`: trim, valida largo, tope y dedupe por
  /// `searchFold` (tildes/mayúsculas no crean chips distintos — "Destapes"
  /// y "destapés" son el mismo; se conserva el primero que se escribió).
  void _add(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (text.length > kMaxServiceChipLen) {
      _toast('Máximo $kMaxServiceChipLen caracteres por servicio.');
      return;
    }
    if (_chips.length >= kMaxServiceChips) {
      _toast('Ya llegaste al máximo de $kMaxServiceChips servicios.');
      return;
    }
    final folded = searchFold(text);
    if (_chips.any((c) => searchFold(c) == folded)) {
      _controller.clear();
      return;
    }
    setState(() {
      _chips.add(text);
      _controller.clear();
    });
  }

  void _remove(String chip) => setState(() => _chips.remove(chip));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final atMax = _chips.length >= kMaxServiceChips;
    return Padding(
      // `viewInsets.bottom` empuja la hoja por encima del teclado — mismo
      // patrón que `text_editor_sheet.dart`/`otp_sheet.dart`. El
      // `SingleChildScrollView` es propio de esta hoja: con 20 chips el
      // contenido no cabe en pantallas chicas (`RenderFlex overflowed`
      // confirmado en el paso 2 de TDD), a diferencia de la hoja de texto
      // libre de la Task 4, que nunca crece tanto.
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('Servicios',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Text('${_chips.length}/$kMaxServiceChips',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: atMax ? cs.error : cs.onSurfaceVariant,
                  )),
            ]),
            const SizedBox(height: 14),
            if (_chips.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _chips)
                    InputChip(label: Text(c), onDeleted: () => _remove(c)),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _controller,
              enabled: !atMax,
              autofocus: !atMax,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: _add,
              decoration: InputDecoration(
                hintText: atMax
                    ? 'Llegaste al máximo de $kMaxServiceChips servicios'
                    : 'Añadir servicio',
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    // BUG PO 08-09: el usuario escribe un servicio y toca
                    // "Guardar" sin dar Enter — se perdía porque nunca pasaba
                    // por `onSubmitted`. Se comitea el texto pendiente con
                    // las MISMAS reglas que Enter (largo/tope/dedupe) antes
                    // de cerrar. Si es inválido (>60 chars), `_add` ya avisó
                    // con el toast de siempre y deja el campo intacto — no se
                    // bloquea el guardado de los chips ya válidos por un
                    // error de tipeo pendiente, se guarda el resto igual.
                    _add(_controller.text);
                    Navigator.pop(context, _chips);
                  },
                  child: const Text('Guardar'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Wrap de servicios SOLO LECTURA — la tienda pública (Task 5) pinta esto
/// bajo la descripción del negocio, sin ningún indicio de edición (ni el
/// "+", ni `onTap`). Vacío → no dibuja nada (la tienda ajena no ofrece un
/// CTA de crear). "Mi negocio" NO usa este widget tal cual: envuelve su
/// propia tarjeta tocable (con la píldora "+ Añadir servicios" cuando está
/// vacía) alrededor de este mismo Wrap para el caso con chips.
class ServiceChipsWrap extends StatelessWidget {
  const ServiceChipsWrap({super.key, required this.services});
  final List<String> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) return const SizedBox.shrink();
    // Píldoras VIOLETA con el tono de «Desbloqueada» (pedido PO 2026-08-10),
    // en vez del Chip gris de Material que no hablaba el idioma de la marca.
    final tone = offerBadgeTone(context, 'unlocked');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in services)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              s,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tone.ink,
              ),
            ),
          ),
      ],
    );
  }
}
