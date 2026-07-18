import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import '../shell/home_scroll.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

/// Copy e ícono del chip de fase (variante "C · Chip y pasos" elegida por el
/// PO). Con ofertas muestra el conteo real — es el dato que hace abrir la app.
(IconData, String) phaseChip(RequestPhase p, int offerCount) => switch (p) {
      RequestPhase.waiting => (Icons.schedule, 'Esperando ofertas'),
      RequestPhase.withOffers => (
          Icons.local_offer_outlined,
          '$offerCount oferta${offerCount == 1 ? '' : 's'}'
        ),
      RequestPhase.accepted => (Icons.handshake, 'Aceptada'),
      RequestPhase.unlocked => (Icons.lock_open, 'Desbloqueado'),
      RequestPhase.completed => (Icons.done_all, 'Completada'),
    };

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<(Map<String, dynamic>, RequestPhase, int)>> _load = _fetch();

  Future<List<(Map<String, dynamic>, RequestPhase, int)>> _fetch() async {
    final reqs = await myRequests();
    if (reqs.isEmpty) return [];
    final ids = reqs.map((r) => r['id'] as String).toList();
    final offers = List<Map<String, dynamic>>.from(await supa
        .from('provider_offers')
        .select('request_id,status,unlocked_at')
        .inFilter('request_id', ids));
    final byReq = <String, List<OfferLite>>{};
    for (final o in offers) {
      byReq.putIfAbsent(o['request_id'] as String, () => []).add(offerLite(o));
    }
    return [
      for (final r in reqs)
        (
          r,
          phaseForRequest(
              requestStatus: r['status'] as String,
              offers: byReq[r['id']] ?? const []),
          byReq[r['id']]?.length ?? 0,
        )
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Mis solicitudes'),
          actions: const [NotificationBell()]),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _load = _fetch()),
        child: FutureBuilder(
          future: _load,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const JayaloLoaderBlock();
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return EmptyState(
                controller: homeScrollController,
                message: 'Aún no has pedido nada.\n'
                    'Cuéntanos qué buscas y los proveedores te harán ofertas.',
                ctaLabel: 'Crear solicitud',
                onCta: () => context.go('/client/create'),
              );
            }
            return ListView.builder(
              controller: homeScrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final (r, phase, offerCount) = items[i];
                return _RequestCard(
                  title: r['title'] as String,
                  createdAt: DateTime.parse(r['created_at'] as String),
                  phase: phase,
                  offerCount: offerCount,
                  onTap: () => context.go('/client/request/${r['id']}'),
                ).cascadeIn(i);
              },
            );
          },
        ),
      ),
    );
  }
}

/// Variante "C · Chip y pasos": tarjeta neutra con chip de estado arriba a la
/// derecha y una mini-barra de progreso de 5 segmentos (una por fase) que
/// muestra el avance de un vistazo sin abrir el detalle.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.title,
    required this.createdAt,
    required this.phase,
    required this.offerCount,
    required this.onTap,
  });

  final String title;
  final DateTime createdAt;
  final RequestPhase phase;
  final int offerCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = toneFor(context, phase);
    final idx = RequestPhase.values.indexOf(phase);
    final (icon, label) = phaseChip(phase, offerCount);
    return JayaloCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: label, tone: tone, icon: icon),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < RequestPhase.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= idx ? tone.ink : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            timeAgo(createdAt),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
