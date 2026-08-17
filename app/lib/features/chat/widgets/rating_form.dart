import 'package:flutter/material.dart';
import '../../../data/repos.dart';
import '../../shared/celebration.dart';
import '../../shared/jayalo_loader.dart';

/// Palabra cualitativa de una calificación en escala de 10.
/// Vale para las DOS direcciones: `customer_reviews` (proveedor→cliente) y
/// `business_reviews`/`conversation_ratings` (cliente→proveedor) son todas 1-10.
/// (Existió un `ratingWord5` para el formulario del proveedor al cliente; murió
/// el 2026-08-17 con el arreglo de escala — esa tabla nunca fue de 5.)
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

/// Calificación del PROVEEDOR al CLIENTE (bilateral, pedido PO): **1-10** +
/// comentario opcional, en paridad con la web (`ProviderOffersSection`). Se
/// muestra cuando el chat de una oferta queda cerrado (por "completado" o por el
/// cierre automático a las 72h).
///
/// ⚠️ ESTO ERAN 5 ESTRELLAS Y ERA UN BUG (arreglado 2026-08-17). `customer_reviews.rating`
/// tiene `CHECK (1..10)` desde la migración `20260619014535` y la reputación se
/// pinta como "X / 10": un cliente impecable calificado con 5 estrellas salía
/// **5.0/10**, que parece mediocre. No volver a bajarlo a 5 sin cambiar la columna.
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
  // Default 8, igual que la web (`ProviderOffersSection.tsx`): el proveedor que
  // envía sin tocar nada no debería calificar con un aprobado raspado.
  int _rating = 8;
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
    // Calificador INMEDIATO (sin el paso previo "Calificar ahora") + respiro
    // inferior para no quedar bajo la barra de gestos del sistema (pedido PO
    // 2026-07-27: "que aparezca de inmediato" y "no tan abajo").
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¡Califica a este cliente!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Text('Tu opinión ayuda a otros proveedores.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        const Text('Califica al cliente',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        Text('Escala de 1 a 10.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        // Misma rejilla numerada que `RatingPanel` y `BusinessReviewPanel` de este
        // fichero: 10 botones, no estrellas. Ver el aviso de la clase.
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var n = 1; n <= 10; n++)
            InkWell(
                onTap: () => setState(() => _rating = n),
                child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: n <= _rating ? cs.primary : cs.outlineVariant),
                        color: n <= _rating ? cs.primary : null),
                    child: Text('$n',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: n <= _rating
                                ? cs.onPrimary
                                : cs.onSurfaceVariant)))),
        ]),
        const SizedBox(height: 6),
        Text('${ratingWord10(_rating)} · $_rating/10',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
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
  const RatingPanel({
    super.key,
    required this.convId,
    required this.customerId,
    required this.providerUserId,
    required this.onDone,
    this.businessId,
    this.submitConversation,
    this.submitBusinessReview,
  });
  final String convId;
  final String customerId;
  final String providerUserId;
  final VoidCallback onDone;

  /// Negocio al que pertenece esta conversación. Si viene, la nota se escribe
  /// TAMBIÉN en `business_reviews` — la tabla que de verdad alimenta la
  /// reputación pública. Sin ella la nota solo vive en `conversation_ratings`,
  /// que nadie promedia.
  final String? businessId;

  /// Inyectables para los tests (los reales tocan Supabase).
  final Future<void> Function(int overall)? submitConversation;
  final Future<void> Function(String businessId, int rating, String comment)?
      submitBusinessReview;

  @override
  State<RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends State<RatingPanel> {
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
      final saveConv = widget.submitConversation ??
          (int overall) => submitConversationRating(
              convId: widget.convId,
              customerId: widget.customerId,
              providerUserId: widget.providerUserId,
              overall: overall,
              quality: _quality,
              fulfillment: _fulfillment,
              service: _service,
              condition: _condition,
              comment: _comment.text);
      await saveConv(_overall);

      // Segunda escritura: la que MUEVE las estrellas. Best-effort a
      // propósito — la nota ya quedó guardada arriba, así que un fallo aquí no
      // puede tumbar el flujo ni hacer que el usuario recalifique.
      //
      // Escala: `_overall` y `business_reviews.rating` son ambos 1-10
      // (migración 20260619014535). NO convertir.
      final bizId = widget.businessId;
      if (bizId != null) {
        final saveBiz = widget.submitBusinessReview ??
            (String b, int r, String c) =>
                submitReview(businessId: b, rating: r, comment: c);
        try {
          await saveBiz(bizId, _overall, _comment.text);
        } catch (_) {
          // Silencioso: ver arriba.
        }
      }

      if (!mounted) return;
      await showRatingThanks(context); // ⭐ estrella + "Gracias por tu calificación"
      if (!mounted) return;
      // El llamador normalmente saca este panel del árbol al recibir
      // `onDone` (deja de haber algo que calificar), pero si por lo que sea
      // sigue montado no debe quedar con el spinner girando para siempre:
      // `JayaloSpinner` corre un ticker en `repeat()`.
      setState(() => _submitting = false);
      widget.onDone();
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
    // Calificador INMEDIATO (sin el paso previo "Calificar ahora") + respiro
    // inferior para no quedar bajo la barra de gestos del sistema (pedido PO
    // 2026-07-27: "que aparezca de inmediato" y "no tan abajo").
    return Container(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        // Material transparente: sin él, los `CheckboxListTile` de abajo
        // buscan el Material más cercano saltándose este `Container` con
        // color y Flutter lo marca como "background/ink splashes may be
        // invisible" (hallado 2026-08-01 al testear el envío end-to-end).
        child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¡Califica este proveedor!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('Tu opinión ayuda a otros clientes.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
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
        ]))));
  }
}

/// Calificación del CLIENTE al PROVEEDOR fuera del chat (detalle de solicitud
/// completada). Escribe SOLO `business_reviews` — que es la tabla de la que
/// salen las estrellas — porque `conversation_ratings` exige una conversación
/// cerrada y aquí no hay garantía de que exista.
///
/// Escala 1-10, igual que la web (`$requestId.tsx`) y que
/// `business_reviews.rating` desde la migración 20260619014535.
class BusinessReviewPanel extends StatefulWidget {
  const BusinessReviewPanel({
    super.key,
    required this.businessId,
    this.onSaved,
    this.loadExisting,
    this.submit,
  });
  final String businessId;

  /// Aviso opcional al padre de que se guardó (para refrescar lo suyo).
  final VoidCallback? onSaved;

  /// Inyectables para los tests (los reales tocan Supabase).
  final Future<({int rating, String? comment})?> Function(String businessId)?
      loadExisting;
  final Future<void> Function(String businessId, int rating, String comment)?
      submit;

  @override
  State<BusinessReviewPanel> createState() => _BusinessReviewPanelState();
}

class _BusinessReviewPanelState extends State<BusinessReviewPanel> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _submitting = false;

  /// Mi reseña vigente, si ya califiqué. El panel se carga A SÍ MISMO: así el
  /// detalle de solicitud solo lo monta, sin estado nuevo ni efectos durante
  /// su `build`.
  ({int rating, String? comment})? _existing;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Best-effort: si falla, se muestra el formulario. Reseñar de nuevo hace
  /// upsert (`uq_business_reviews_one_per_reviewer`), así que no duplica.
  Future<void> _load() async {
    final loader = widget.loadExisting ?? myBusinessReview;
    ({int rating, String? comment})? r;
    try {
      r = await loader(widget.businessId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _existing = r;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una calificación.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final save = widget.submit ??
          (String b, int r, String c) =>
              submitReview(businessId: b, rating: r, comment: c);
      await save(widget.businessId, _rating, _comment.text);
      if (!mounted) return;
      await showRatingThanks(context);
      if (!mounted) return;
      final c = _comment.text.trim();
      setState(() => _existing =
          (rating: _rating, comment: c.isEmpty ? null : c));
      widget.onSaved?.call();
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
    // Hasta saber si ya califiqué, no se pinta nada: mostrar el formulario y
    // reemplazarlo un instante después por "ya calificaste" es un parpadeo.
    if (!_loaded) return const SizedBox.shrink();
    final existing = _existing;
    if (existing != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.star, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text('Calificaste al proveedor: ${existing.rating}/10',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          if (existing.comment != null) ...[
            const SizedBox(height: 4),
            Text(existing.comment!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Califica al proveedor',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text('Tu opinión ayuda a la comunidad. Escala de 1 a 10.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var n = 1; n <= 10; n++)
            InkWell(
                onTap: () => setState(() => _rating = n),
                child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color:
                                n <= _rating ? cs.primary : cs.outlineVariant),
                        color: n <= _rating ? cs.primary : null),
                    child: Text('$n',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: n <= _rating
                                ? cs.onPrimary
                                : cs.onSurfaceVariant)))),
        ]),
        if (_rating > 0) ...[
          const SizedBox(height: 6),
          Text('${ratingWord10(_rating)} · $_rating/10',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
        ],
        const SizedBox(height: 8),
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
