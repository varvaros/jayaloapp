import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import 'offer_actions.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

String fmtRD(num? v) => v == null
    ? ''
    : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

String offerPriceLabel(Map<String, dynamic> o) {
  if (o['price'] != null) return fmtRD(o['price'] as num);
  if (o['price_min'] != null && o['price_max'] != null) {
    return '${fmtRD(o['price_min'] as num)} – ${fmtRD(o['price_max'] as num)}';
  }
  if (o['pricing_mode'] == 'hourly' && o['hourly_rate'] != null) {
    return '${fmtRD(o['hourly_rate'] as num)}/hora';
  }
  return 'A evaluar';
}

const _phaseCopy = {
  RequestPhase.waiting:
      'Tu solicitud está publicada. Los proveedores la están viendo.',
  RequestPhase.withOffers:
      'Revisa las ofertas y acepta la que más te convenga.',
  RequestPhase.accepted: 'El proveedor te contactará pronto.',
  RequestPhase.unlocked: 'Ya puedes hablar con el proveedor.',
  RequestPhase.completed: 'Califica al proveedor para ayudar a la comunidad.',
};

/// Etiquetas cortas del "camino de píldoras" (variante D2 elegida por el PO).
const _phaseShort = {
  RequestPhase.waiting: 'Publicada',
  RequestPhase.withOffers: 'Con ofertas',
  RequestPhase.accepted: 'Aceptada',
  RequestPhase.unlocked: 'Desbloqueado',
  RequestPhase.completed: 'Completada',
};

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    supa
        .from('customer_requests')
        .select('id,title,status,kind,bullets,user_id,created_at')
        .eq('id', widget.requestId)
        .single()
        .then((r) => mounted ? setState(() => _request = r) : null);
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    if (req == null) {
      return Scaffold(appBar: AppBar(), body: const JayaloLoaderBlock());
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(req['title'] as String,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: offersStream(widget.requestId),
        builder: (context, snap) {
          final offers = snap.data ?? const <Map<String, dynamic>>[];
          final phase = phaseForRequest(
              requestStatus: req['status'] as String,
              offers: offers.map(offerLite).toList());
          final hasAccepted = offers
              .any((o) => o['status'] == 'accepted' || o['status'] == 'completed');
          return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _PhasePath(key: ValueKey(phase), phase: phase),
                ),
                SectionHeader(text: 'Ofertas (${offers.length})'),
                if (offers.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Todavía no hay ofertas. Te avisaremos con una notificación.')),
                for (final o in offers)
                  JayaloCard(
                    onTap: () => showOfferSheet(context, req, o,
                        hasAcceptedElsewhere:
                            hasAccepted && o['status'] == 'pending'),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(offerPriceLabel(o),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              if ((o['message'] as String?)?.isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 2),
                                Text(o['message'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _offerStatusChip(context, o, hasAccepted),
                      ],
                    ),
                  ),
              ]);
        },
      ),
    );
  }

  Widget _offerStatusChip(
      BuildContext context, Map<String, dynamic> o, bool hasAccepted) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final st = o['status'] as String;
    final (txt, tone) = switch (st) {
      'accepted' when o['unlocked_at'] != null => (
          'Desbloqueada',
          dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight
        ),
      'accepted' => (
          'Aceptada',
          dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight
        ),
      'completed' => (
          'Completada',
          dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
        ),
      'rejected' => (
          'Rechazada',
          dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
        ),
      _ => hasAccepted
          ? (
              'Otra aceptada',
              dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
            )
          : ('Pendiente', dark ? JayaloStatus.pendingDark : JayaloStatus.pendingLight),
    };
    return StatusChip(label: txt, tone: tone);
  }
}

/// D2 · Camino de píldoras: las fases pasadas en gris con check, la actual con
/// el color de su tono, las futuras huecas. Debajo, el copy de la fase.
class _PhasePath extends StatelessWidget {
  const _PhasePath({super.key, required this.phase});
  final RequestPhase phase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final doneTone =
        dark ? JayaloStatus.completedDark : JayaloStatus.completedLight;
    final idx = RequestPhase.values.indexOf(phase);
    return JayaloCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tu solicitud va así:',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < RequestPhase.values.length; i++)
                if (i < idx)
                  StatusChip(
                      label: _phaseShort[RequestPhase.values[i]]!,
                      tone: doneTone,
                      icon: Icons.check)
                else if (i == idx)
                  StatusChip(
                      label: _phaseShort[RequestPhase.values[i]]!,
                      tone: toneFor(context, phase))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(_phaseShort[RequestPhase.values[i]]!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant)),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_phaseCopy[phase]!),
        ],
      ),
    );
  }
}
