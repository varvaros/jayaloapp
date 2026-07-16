import 'package:flutter/material.dart';
import '../../data/repos.dart';
import 'request_status_screen.dart' show offerPriceLabel;

void showOfferSheet(BuildContext context, Map<String, dynamic> request,
    Map<String, dynamic> offer,
    {required bool hasAcceptedElsewhere}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: _OfferSheetBody(offer: offer, hasAcceptedElsewhere: hasAcceptedElsewhere),
    ),
  );
}

class _OfferSheetBody extends StatefulWidget {
  const _OfferSheetBody({required this.offer, required this.hasAcceptedElsewhere});
  final Map<String, dynamic> offer;
  final bool hasAcceptedElsewhere;
  @override
  State<_OfferSheetBody> createState() => _OfferSheetBodyState();
}

class _OfferSheetBodyState extends State<_OfferSheetBody> {
  bool _busy = false;
  int _rating = 8;

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(offerPriceLabel(o),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(o['message'] as String? ?? ''),
          const SizedBox(height: 20),
          if (st == 'pending' && !widget.hasAcceptedElsewhere) ...[
            FilledButton(
              onPressed: _busy ? null : _accept,
              child: const Text('Aceptar esta oferta'),
            ),
            TextButton(
                onPressed: _busy ? null : _reject, child: const Text('Rechazar')),
          ] else if (st == 'pending')
            const Text('Ya aceptaste otra oferta para esta solicitud.',
                textAlign: TextAlign.center)
          else if (st == 'accepted' && !unlocked)
            const Text('Oferta aceptada. El proveedor te contactará pronto.',
                textAlign: TextAlign.center)
          else if (unlocked) ...[
            const Text('Contacto desbloqueado. Ya pueden hablar.'),
            const SizedBox(height: 12),
            Text('Califica al vendedor: $_rating/10'),
            Slider(
                value: _rating.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_rating',
                onChanged: (v) => setState(() => _rating = v.round())),
            FilledButton(
              onPressed: _busy ? null : _review,
              child: const Text('Enviar calificación'),
            ),
          ],
        ]);
  }

  Future<void> _accept() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('¿Aceptar esta oferta?'),
              content: const Text('Solo puedes aceptar UNA oferta por solicitud.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Sí, aceptar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final accepted = await acceptOffer(offerId: widget.offer['id'] as String);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accepted
            ? '¡Oferta aceptada! El proveedor será notificado. 🏆'
            : 'Esta oferta ya no está disponible.')));
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Rechazar oferta'),
              content: TextField(
                  controller: ctrl,
                  decoration:
                      const InputDecoration(hintText: '¿Por qué? (opcional)')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Rechazar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await rejectOffer(
        offerId: widget.offer['id'] as String, reason: ctrl.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _review() async {
    setState(() => _busy = true);
    try {
      await submitReview(
          businessId: widget.offer['business_id'] as String, rating: _rating);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Gracias por calificar al vendedor!')));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }
}
