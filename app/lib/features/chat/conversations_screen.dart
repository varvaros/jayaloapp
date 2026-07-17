import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../client/request_status_screen.dart' show fmtRD;

const _tabs = [
  ('abierto', 'Abierto'),
  ('cerrado', 'Completado'),
  ('perdido', 'No concretado'),
];

Color _statusColor(BuildContext c, String s) => switch (s) {
      'abierto' => Theme.of(c).colorScheme.primary,
      'cerrado' => Colors.green,
      _ => Theme.of(c).colorScheme.outline,
    };

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, dynamic>>? _all;
  bool _error = false;
  String _tab = 'abierto';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final rows = await conversationsList();
      if (mounted) setState(() => _all = rows);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      body: _error
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('No pudimos cargar tus mensajes.'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ]))
          : all == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _body(all)),
    );
  }

  Widget _body(List<Map<String, dynamic>> all) {
    final counts = <String, int>{};
    for (final c in all) {
      counts[c['status'] as String] = (counts[c['status'] as String] ?? 0) + 1;
    }
    final term = _q.trim().toLowerCase();
    final filtered = all
        .where((c) => c['status'] == _tab)
        .where((c) =>
            term.isEmpty ||
            ((c['product_name'] as String?) ?? '').toLowerCase().contains(term) ||
            ((c['peer_name'] as String?) ?? '').toLowerCase().contains(term))
        .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SegmentedButton<String>(
          segments: [
            for (final (v, label) in _tabs)
              ButtonSegment(
                  value: v,
                  label: Text(counts[v] == null ? label : '$label ${counts[v]}',
                      style: const TextStyle(fontSize: 12))),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
          showSelectedIcon: false,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Buscar…', isDense: true),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? ListView(children: [
                const SizedBox(height: 64),
                const Icon(Icons.inbox_outlined, size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                Center(
                    child: Text(_tab == 'abierto'
                        ? 'Sin conversaciones abiertas.\nLas conversaciones empiezan cuando contactas a un proveedor.'
                        : _tab == 'cerrado'
                            ? 'Sin conversaciones completadas.'
                            : 'Sin conversaciones no concretadas.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey))),
              ])
            : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _row(filtered[i]),
              ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> c) {
    final unread = (c['unread_count'] as int?) ?? 0;
    final lastAt = c['last_created_at'] ?? c['updated_at'];
    final price = c['agreed_price'] != null
        ? ' · ${fmtRD(c['agreed_price'] as num)}'
        : c['agreed_hourly_rate'] != null
            ? ' · ${fmtRD(c['agreed_hourly_rate'] as num)}/h'
            : '';
    return ListTile(
      onTap: () async {
        await context.push('/messages/${c['id']}');
        _load(); // refresh al volver del chat (badges/último mensaje)
      },
      leading: CircleAvatar(
        backgroundImage:
            c['peer_avatar_url'] != null ? NetworkImage(c['peer_avatar_url'] as String) : null,
        child: c['peer_avatar_url'] == null ? const Icon(Icons.person_outline) : null,
      ),
      title: Row(children: [
        Container(
            width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(context, c['status'] as String))),
        Expanded(
            child: Text(c['peer_name'] as String? ?? '',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14))),
        Text(
            lastAt == null
                ? ''
                : formatListTime(DateTime.parse(lastAt as String).toLocal()),
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c['product_name'] ?? ''}$price',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(
              child: Text(
                  c['last_kind'] == null
                      ? 'Sin mensajes aún'
                      : messagePreview(c['last_kind'] as String, c['last_body'] as String? ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: unread > 0 ? null : Colors.grey,
                      fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal))),
          if (unread > 0)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 11))),
        ]),
      ]),
    );
  }
}
