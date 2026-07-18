import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../../domain/phase.dart';
import 'my_requests_screen.dart' show phaseChip;
import 'offer_actions.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

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

/// Títulos del héroe de fase (variante D1 elegida por el PO).
const _phaseTitle = {
  RequestPhase.waiting: 'Esperando ofertas',
  RequestPhase.withOffers: 'Con ofertas',
  RequestPhase.accepted: 'Oferta aceptada',
  RequestPhase.unlocked: 'Contacto desbloqueado',
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
              padding: EdgeInsets.only(
                  top: 12, bottom: 12 + navBarReservedSpace(context)),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _PhaseHero(
                      key: ValueKey(phase),
                      phase: phase,
                      offerCount: offers.length,
                      createdAt:
                          DateTime.parse(req['created_at'] as String)),
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

/// D1 · Héroe teñido (elegido por el PO): tarjeta grande del color de la fase
/// con ícono, título, copy, la referencia de día y hora de publicación, y el
/// stepper de puntos del avance.
class _PhaseHero extends StatelessWidget {
  const _PhaseHero({
    super.key,
    required this.phase,
    required this.offerCount,
    required this.createdAt,
  });

  final RequestPhase phase;
  final int offerCount;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(context, phase);
    final idx = RequestPhase.values.indexOf(phase);
    final (icon, _) = phaseChip(phase, offerCount);
    return JayaloCard(
      tint: tone.bg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.ink.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: tone.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_phaseTitle[phase]!,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: tone.ink)),
                    const SizedBox(height: 2),
                    Text(
                      'Publicada: ${formatDayLabel(createdAt)} · ${formatTimeHM(createdAt)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: tone.ink.withValues(alpha: .65)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_phaseCopy[phase]!,
              style: TextStyle(
                  fontSize: 13, color: tone.ink.withValues(alpha: .85))),
          const SizedBox(height: 14),
          Row(children: [
            for (var i = 0; i < RequestPhase.values.length; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: i == idx ? 14 : 12,
                height: i == idx ? 14 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= idx
                      ? tone.ink
                      : tone.ink.withValues(alpha: .2),
                ),
              ),
              if (i < RequestPhase.values.length - 1)
                Expanded(
                  child: Container(
                      height: 3,
                      color: i < idx
                          ? tone.ink
                          : tone.ink.withValues(alpha: .2)),
                ),
            ],
          ]),
        ],
      ),
    );
  }
}
