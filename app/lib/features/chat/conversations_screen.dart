import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shared/profile_avatar_button.dart';

const _tabs = [
  ('abierto', 'Abierto'),
  ('cerrado', 'Completado'),
  ('perdido', 'No concretado'),
];

Color _statusColor(BuildContext c, String s) => switch (s) {
      'abierto' => Theme.of(c).colorScheme.primary,
      'cerrado' => Theme.of(c).brightness == Brightness.dark
          ? JayaloColors.dSuccess
          : JayaloColors.success,
      _ => Theme.of(c).colorScheme.outline,
    };

class ConversationsScreen extends StatefulWidget {
  /// [actions] es inyectable (mismo patrón que `CatalogView`/
  /// `ProviderInboxView`) para poder probar el contrato del AppBar sin
  /// montar `NotificationBell`/`ProfileAvatarButton` de verdad — ambos
  /// tocan Supabase en su `initState`/constructor y esta app no inicializa
  /// Supabase en los tests de widgets.
  const ConversationsScreen({
    super.key,
    this.actions = const [NotificationBell(), ProfileAvatarButton()],
  });

  final List<Widget> actions;

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
      appBar: AppBar(
          title: const Text('Mensajes'),
          // I1 (revisión final de rama): Mensajes es el puesto 3 en ambas
          // barras (spec navbar-iteración 2) pero es la ÚNICA pestaña raíz
          // que se había quedado sin campana/avatar — sin esto, un usuario
          // parado aquí no tenía ninguna vía a Ajustes sin cambiar de
          // pestaña primero (ver docstring de `profile_avatar_button.dart`).
          actions: widget.actions),
      body: _error
          ? ErrorRetry(
              onRetry: _load, message: 'No pudimos cargar tus mensajes')
          : all == null
              ? const JayaloLoaderBlock()
              : RefreshIndicator(onRefresh: _load, child: _body(all)),
    );
  }

  Widget _body(List<Map<String, dynamic>> all) {
    final cs = Theme.of(context).colorScheme;
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
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar…',
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none)),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                message: _tab == 'abierto'
                    ? 'Sin conversaciones abiertas.\nLas conversaciones empiezan cuando contactas a un proveedor.'
                    : _tab == 'cerrado'
                        ? 'Sin conversaciones completadas.'
                        : 'Sin conversaciones no concretadas.',
              )
            : ListView.builder(
                padding: EdgeInsets.only(
                    top: 4, bottom: 4 + navBarReservedSpace(context)),
                itemCount: filtered.length,
                itemBuilder: (context, i) =>
                    _ConversationCard(c: filtered[i], onOpen: _open)
                        .cascadeIn(i),
              ),
      ),
    ]);
  }

  Future<void> _open(Map<String, dynamic> c) async {
    // Task I-2: pasa peer_name/avatar ya resueltos en esta lista para que
    // ChatScreen no tenga que llamar de nuevo al RPC agregado
    // `conversationsList()` solo para esos dos campos.
    await context.push('/messages/${c['id']}', extra: {
      'peer_name': c['peer_name'],
      'peer_avatar_url': c['peer_avatar_url'],
    });
    _load(); // refresh al volver del chat (badges/último mensaje)
  }
}

/// Tarjeta que respira para la conversación: con no-leídos se tiñe del verde
/// de "mensajes" (mismo tono que un contacto desbloqueado en la web); al día,
/// tarjeta neutra.
class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.c, required this.onOpen});
  final Map<String, dynamic> c;
  final Future<void> Function(Map<String, dynamic>) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unread = (c['unread_count'] as int?) ?? 0;
    final tone = dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight;
    final tinted = unread > 0;
    final fg = tinted ? tone.ink : cs.onSurface;
    final muted = tinted ? tone.ink.withValues(alpha: .75) : cs.onSurfaceVariant;
    final lastAt = c['last_created_at'] ?? c['updated_at'];
    final price = c['agreed_price'] != null
        ? ' · ${fmtRD(c['agreed_price'] as num)}'
        : c['agreed_hourly_rate'] != null
            ? ' · ${fmtRD(c['agreed_hourly_rate'] as num)}/h'
            : '';
    return JayaloCard(
      tint: tinted ? tone.bg : null,
      onTap: () => onOpen(c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundImage: c['peer_avatar_url'] != null
                ? NetworkImage(c['peer_avatar_url'] as String)
                : null,
            child: c['peer_avatar_url'] == null
                ? const Icon(Icons.person_outline)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor(context, c['status'] as String))),
                  Expanded(
                      child: Text(c['peer_name'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight:
                                  tinted ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 14,
                              color: fg))),
                  Text(
                      lastAt == null
                          ? ''
                          : formatListTime(
                              DateTime.parse(lastAt as String).toLocal()),
                      style: TextStyle(fontSize: 11, color: muted)),
                ]),
                const SizedBox(height: 2),
                Text('${c['product_name'] ?? ''}$price',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                      child: Text(
                          c['last_kind'] == null
                              ? 'Sin mensajes aún'
                              : messagePreview(c['last_kind'] as String,
                                  c['last_body'] as String? ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: tinted ? fg : cs.onSurfaceVariant,
                              fontWeight: tinted
                                  ? FontWeight.w600
                                  : FontWeight.normal))),
                  if (unread > 0)
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: tone.ink,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('$unread',
                            style: TextStyle(
                                color: tone.bg,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
