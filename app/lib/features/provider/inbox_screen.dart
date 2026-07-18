import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shell/home_scroll.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

class ProviderInboxScreen extends StatefulWidget {
  const ProviderInboxScreen({super.key});
  @override
  State<ProviderInboxScreen> createState() => _ProviderInboxScreenState();
}

class _ProviderInboxScreenState extends State<ProviderInboxScreen> {
  String? _kind;
  late Future<List<Map<String, dynamic>>> _load = providerInbox();

  void _refetch() => setState(() => _load = providerInbox(kind: _kind));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Solicitudes para ti'),
          actions: const [NotificationBell()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('Todo')),
              ButtonSegment(value: 'producto', label: Text('Productos')),
              ButtonSegment(value: 'servicio', label: Text('Servicios')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              _kind = s.first;
              _refetch();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refetch(),
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
                    message:
                        'Aquí verás las solicitudes que coinciden con tu negocio.\n'
                        'Te avisaremos cuando llegue una nueva.',
                  );
                }
                return ListView.builder(
                  controller: homeScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return _InboxCard(
                      title: r['title'] as String? ?? '',
                      description: r['description'] as String? ?? '',
                      kind: r['kind'] as String?,
                      createdAt: DateTime.parse(r['created_at'] as String),
                      onTap: () => context.go('/provider/request/${r['id']}'),
                    ).cascadeIn(i);
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Variante "I2 · Con ícono de tipo" (elegida por el PO): tarjeta neutra con
/// el ícono de producto/servicio en contenedor redondeado, como una
/// notificación. El acento usa el primario del tema (violeta claro / azul
/// oscuro).
class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.title,
    required this.description,
    required this.kind,
    required this.createdAt,
    required this.onTap,
  });

  final String title;
  final String description;
  final String? kind;
  final DateTime createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                kind == 'producto'
                    ? Icons.inventory_2_outlined
                    : Icons.handyman_outlined,
                size: 20,
                color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
