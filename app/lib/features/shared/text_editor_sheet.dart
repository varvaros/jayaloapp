import 'package:flutter/material.dart';

/// Hoja genérica para editar un bloque de texto libre (título + campo +
/// Cancelar/Guardar). La estrenó "Sobre el negocio" (Task 4, 2026-08-09) y la
/// reusará la Task 7 para descripciones largas de productos/servicios — de
/// ahí que viva en `shared/` y no dentro de `provider/`.
///
/// Devuelve el texto (recortado con `.trim()`) al guardar, o `null` si se
/// canceló o se cerró la hoja arrastrando hacia abajo. El llamador decide si
/// el texto cambió respecto al original antes de pegarle a la red.
Future<String?> showTextEditorSheet(
  BuildContext context, {
  required String title,
  required String initial,
  int maxLines = 6,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TextEditorSheet(
      title: title,
      initial: initial,
      maxLines: maxLines,
    ),
  );
}

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.title,
    required this.initial,
    required this.maxLines,
  });

  final String title;
  final String initial;
  final int maxLines;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `viewInsets.bottom` empuja la hoja por encima del teclado — sin esto
      // el campo de texto queda tapado apenas se abre el teclado (mismo
      // patrón que `otp_sheet.dart`).
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLines: widget.maxLines,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
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
                onPressed: () =>
                    Navigator.pop(context, _controller.text.trim()),
                child: const Text('Guardar'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
