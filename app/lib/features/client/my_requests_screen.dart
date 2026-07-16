import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

(Color, String) phaseBadge(BuildContext c, RequestPhase p) {
  final cs = Theme.of(c).colorScheme;
  return switch (p) {
    RequestPhase.waiting => (cs.outline, 'Esperando ofertas'),
    RequestPhase.withOffers => (cs.primary, 'Con ofertas'),
    RequestPhase.accepted => (Colors.amber.shade800, 'Oferta aceptada'),
    RequestPhase.unlocked => (Colors.green.shade700, 'Contacto desbloqueado'),
    RequestPhase.completed => (cs.outline, 'Completada'),
  };
}

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<(Map<String, dynamic>, RequestPhase)>> _load = _fetch();

  Future<List<(Map<String, dynamic>, RequestPhase)>> _fetch() async {
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
              offers: byReq[r['id']] ?? const [])
        )
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis solicitudes')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _load = _fetch()),
        child: FutureBuilder(
          future: _load,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.receipt_long_outlined, size: 56),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Aún no has pedido nada.\nToca "Crear" y dinos qué buscas.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final (r, phase) = items[i];
                final (color, label) = phaseBadge(context, phase);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    title: Text(r['title'] as String,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle:
                        Text(timeAgo(DateTime.parse(r['created_at'] as String))),
                    trailing: Chip(
                        label: Text(label,
                            style: TextStyle(color: color, fontSize: 12)),
                        side: BorderSide(color: color.withValues(alpha: .4))),
                    onTap: () => context.go('/client/request/${r['id']}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
