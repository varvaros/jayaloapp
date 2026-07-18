import 'package:flutter/material.dart';
import '../../../data/repos.dart';
import '../../shared/jayalo_loader.dart';

class RatingPanel extends StatefulWidget {
  const RatingPanel({super.key, required this.convId, required this.customerId,
      required this.providerUserId, required this.onDone});
  final String convId;
  final String customerId;
  final String providerUserId;
  final VoidCallback onDone;

  @override
  State<RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends State<RatingPanel> {
  bool _expanded = false;
  int _overall = 0;
  bool _quality = true, _fulfillment = true, _service = true, _condition = true;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_overall < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una calificación general.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await submitConversationRating(
          convId: widget.convId,
          customerId: widget.customerId,
          providerUserId: widget.providerUserId,
          overall: _overall,
          quality: _quality,
          fulfillment: _fulfillment,
          service: _service,
          condition: _condition,
          comment: _comment.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Gracias por tu calificación!')));
        widget.onDone();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo enviar. Intenta de nuevo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_expanded) {
      return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: cs.primaryContainer.withValues(alpha: 0.3),
          child: Column(children: [
            const Text('¡Califica este proveedor!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Text('Tu opinión ayuda a otros clientes.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: () => setState(() => _expanded = true),
                icon: const Icon(Icons.star_outline),
                label: const Text('Calificar ahora')),
          ]));
    }
    return Container(
        padding: const EdgeInsets.all(16),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Al calificar a este proveedor, reconoces que la transacción fue realizada de forma privada. Jayalo no interviene en disputas comerciales ni garantiza la veracidad de la información intercambiada. Tu calificación ayuda a la comunidad a identificar proveedores responsables.',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          const Text('Califica esta transacción',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var n = 1; n <= 10; n++)
              InkWell(
                  onTap: () => setState(() => _overall = n),
                  child: Container(
                      width: 34, height: 34, alignment: Alignment.center,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: n <= _overall ? cs.primary : cs.outlineVariant),
                          color: n <= _overall ? cs.primary : null),
                      child: Text('$n',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: n <= _overall ? cs.onPrimary : Colors.grey)))),
          ]),
          const SizedBox(height: 8),
          for (final (label, val, set) in [
            ('Calidad cumplió', _quality, (bool v) => _quality = v),
            ('Cumplimiento cumplió', _fulfillment, (bool v) => _fulfillment = v),
            ('Servicio cumplió', _service, (bool v) => _service = v),
            ('Condición cumplió', _condition, (bool v) => _condition = v),
          ])
            CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: val,
                title: Text(label, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => set(v ?? true))),
          TextField(
              controller: _comment,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Comentario (opcional)…')),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const JayaloSpinner(size: 16)
                      : const Text('Enviar calificación'))),
        ])));
  }
}
