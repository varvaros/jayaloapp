import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;

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
      appBar: AppBar(title: const Text('Solicitudes para ti')),
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
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 120),
                    Icon(Icons.inbox_outlined, size: 56),
                    Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Aquí verás las solicitudes que coinciden con tu negocio.',
                            textAlign: TextAlign.center)),
                  ]);
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return Card(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text(r['title'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${r['description'] ?? ''}\n${timeAgo(DateTime.parse(r['created_at'] as String))}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        onTap: () => context.go('/provider/request/${r['id']}'),
                      ),
                    );
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
