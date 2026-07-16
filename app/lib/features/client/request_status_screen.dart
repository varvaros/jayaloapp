import 'package:flutter/material.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import 'my_requests_screen.dart' show phaseBadge;
import 'offer_actions.dart';

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
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
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
          final (color, label) = phaseBadge(context, phase);
          final hasAccepted = offers
              .any((o) => o['status'] == 'accepted' || o['status'] == 'completed');
          return ListView(padding: const EdgeInsets.all(16), children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Card(
                key: ValueKey(phase),
                color: color.withValues(alpha: .08),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(_phaseCopy[phase]!),
                    const SizedBox(height: 16),
                    _PhaseStepper(phase: phase, color: color),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Ofertas (${offers.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (offers.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Todavía no hay ofertas. Te avisaremos con una notificación.')),
            for (final o in offers)
              Card(
                child: ListTile(
                  title: Text(offerPriceLabel(o),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(o['message'] as String? ?? '',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: _offerStatusChip(context, o, hasAccepted),
                  onTap: () => showOfferSheet(context, req, o,
                      hasAcceptedElsewhere:
                          hasAccepted && o['status'] == 'pending'),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _offerStatusChip(
      BuildContext context, Map<String, dynamic> o, bool hasAccepted) {
    final st = o['status'] as String;
    final txt = switch (st) {
      'accepted' => o['unlocked_at'] != null ? 'Desbloqueada' : 'Aceptada',
      'completed' => 'Completada',
      'rejected' => 'Rechazada',
      _ => hasAccepted ? 'Otra aceptada' : 'Pendiente',
    };
    return Chip(label: Text(txt, style: const TextStyle(fontSize: 11)));
  }
}

class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.phase, required this.color});
  final RequestPhase phase;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final idx = RequestPhase.values.indexOf(phase);
    final muted = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Row(children: [
      for (var i = 0; i < RequestPhase.values.length; i++) ...[
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: i <= idx ? color : muted),
        ),
        if (i < RequestPhase.values.length - 1)
          Expanded(child: Container(height: 3, color: i < idx ? color : muted)),
      ],
    ]);
  }
}
