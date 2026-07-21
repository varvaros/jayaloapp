import 'package:flutter/material.dart';
import '../../../data/repos.dart';
import '../../shared/celebration.dart';
import '../../shared/jayalo_loader.dart';

/// Palabra cualitativa de una calificación en escala de 5 (proveedor→cliente).
String ratingWord5(int n) => switch (n) {
      1 => 'Malo',
      2 => 'Regular',
      3 => 'Bueno',
      4 => 'Muy bueno',
      _ => 'Excelente',
    };

/// Palabra cualitativa de una calificación en escala de 10 (cliente→proveedor).
String ratingWord10(int n) => n <= 0
    ? ''
    : n <= 3
        ? 'Malo'
        : n <= 5
            ? 'Regular'
            : n <= 7
                ? 'Bueno'
                : n <= 9
                    ? 'Muy bueno'
                    : 'Excelente';

/// Calificación del PROVEEDOR al CLIENTE (bilateral, pedido PO): 1-5 estrellas
/// + comentario opcional, como la web. Se muestra cuando el chat de una oferta
/// queda cerrado (por "completado" o por el cierre automático a las 72h).
class CustomerRatingPanel extends StatefulWidget {
  const CustomerRatingPanel({
    super.key,
    required this.offerId,
    required this.businessId,
    required this.customerId,
    required this.onDone,
  });
  final String offerId;
  final String businessId;
  final String customerId;
  final VoidCallback onDone;

  @override
  State<CustomerRatingPanel> createState() => _CustomerRatingPanelState();
}

class _CustomerRatingPanelState extends State<CustomerRatingPanel> {
  bool _expanded = false;
  int _rating = 5;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await submitCustomerReview(
        offerId: widget.offerId,
        businessId: widget.businessId,
        customerId: widget.customerId,
        rating: _rating,
        comment: _comment.text,
      );
      if (!mounted) return;
      await showRatingThanks(context); // ⭐ estrella + "Gracias por tu calificación"
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo enviar. Intenta de nuevo.')));
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
            const Text('¡Califica a este cliente!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('Tu opinión ayuda a otros proveedores.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Califica al cliente',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          for (var n = 1; n <= 5; n++)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _rating = n),
              icon: Icon(n <= _rating ? Icons.star : Icons.star_border,
                  color: n <= _rating ? cs.primary : cs.outline, size: 30),
            ),
          const SizedBox(width: 4),
          Text(ratingWord5(_rating),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
        ]),
        TextField(
            controller: _comment,
            maxLines: 2,
            decoration:
                const InputDecoration(hintText: 'Comentario (opcional)…')),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const JayaloSpinner(size: 16)
                    : const Text('Enviar calificación'))),
      ]),
    );
  }
}

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
      if (!mounted) return;
      await showRatingThanks(context); // ⭐ estrella + "Gracias por tu calificación"
      if (mounted) widget.onDone();
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
            Text('Tu opinión ayuda a otros clientes.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
          Text(
              'Al calificar a este proveedor, reconoces que la transacción fue realizada de forma privada. Jayalo no interviene en disputas comerciales ni garantiza la veracidad de la información intercambiada. Tu calificación ayuda a la comunidad a identificar proveedores responsables.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
                              color: n <= _overall
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant)))),
          ]),
          // Etiqueta cualitativa de la nota elegida (pedido PO: que diga si es
          // malo/bueno/excelente, no solo el número).
          if (_overall > 0) ...[
            const SizedBox(height: 6),
            Text('${ratingWord10(_overall)} · $_overall/10',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
          ],
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
