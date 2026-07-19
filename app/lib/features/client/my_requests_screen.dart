import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shared/profile_avatar_button.dart';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

/// Ícono y copy corto por fase. Con ofertas muestra el conteo real — es el
/// dato que hace abrir la app.
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
          actions: const [NotificationBell(), ProfileAvatarButton()]),
      body: RefreshIndicator(
        // onRefresh espera Future<void>; bloque de setState para no devolver Future.
        onRefresh: () async {
          setState(() {
            _load = _fetch();
          });
        },
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
              padding: EdgeInsets.only(
                  top: 8, bottom: 8 + navBarReservedSpace(context)),
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

/// Variante "A · Respiración plena" (elegida por el PO): la tarjeta entera se
/// tiñe del tono de su fase, igual que una notificación sin leer. Las fases
/// vivas (con ofertas, aceptada, desbloqueado) llevan color; esperando y
/// completada van apagadas como una notificación leída.
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

  static const _live = {
    RequestPhase.withOffers,
    RequestPhase.accepted,
    RequestPhase.unlocked,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = toneFor(context, phase);
    final alive = _live.contains(phase);
    final bg =
        alive ? tone.bg : cs.surfaceContainerHighest.withValues(alpha: .55);
    final fg = alive ? tone.ink : cs.onSurfaceVariant;
    final ic = alive ? tone.ink : cs.outline;
    final (icon, label) = phaseChip(phase, offerCount);
    return JayaloCard(
      onTap: onTap,
      tint: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ic.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: ic),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label · ${timeAgo(createdAt)}',
                  style: TextStyle(
                      fontSize: 12, color: fg.withValues(alpha: .75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
