import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_state.dart';
import '../../data/notifications_repository.dart';
import '../../domain/notifications.dart';
import 'notification_bell.dart';

/// Colores por familia (spec §3): tinte de fondo + texto + icono, en light y
/// dark. Ofertas usa el contenedor primario del seed #7C3AED; el resto son
/// tonos fijos ajustados a contraste.
({Color bg, Color fg, Color icon}) familyColors(
    BuildContext context, NotifFamily f) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (f) {
    NotifFamily.messages => dark
        ? (bg: const Color(0xFF16302E), fg: const Color(0xFFB2DFDB), icon: const Color(0xFF4DB6AC))
        : (bg: const Color(0xFFE0F2F1), fg: const Color(0xFF00504A), icon: const Color(0xFF00796B)),
    NotifFamily.offers => (bg: cs.primaryContainer, fg: cs.onPrimaryContainer, icon: cs.primary),
    NotifFamily.wallet => dark
        ? (bg: const Color(0xFF3A2E12), fg: const Color(0xFFFFE082), icon: const Color(0xFFFFB300))
        : (bg: const Color(0xFFFFF8E1), fg: const Color(0xFF6D4C00), icon: const Color(0xFFB28704)),
    NotifFamily.reviews => dark
        ? (bg: const Color(0xFF3A1F2B), fg: const Color(0xFFF8BBD0), icon: const Color(0xFFF06292))
        : (bg: const Color(0xFFFCE4EC), fg: const Color(0xFF880E4F), icon: const Color(0xFFC2185B)),
    NotifFamily.system => (bg: cs.surfaceContainerHighest, fg: cs.onSurface, icon: cs.onSurfaceVariant),
  };
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _items = [];
  bool _loading = true;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 0;

  int get _unread => _items.where((n) => n.unread).length;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await notificationsPage(0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows.map(AppNotification.fromMap));
        _page = 0;
        _hasMore = rows.length == notifPageSize;
        _loading = false;
      });
      // Revalida el badge compartido con la verdad recién cargada.
      notifCountStore.refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await notificationsPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(rows.map(AppNotification.fromMap));
        _hasMore = rows.length == notifPageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _markReadOptimistic(AppNotification n) {
    if (!n.unread) return;
    setState(() => n.readAt = DateTime.now());
    notifCountStore.add(-1);
    markNotificationRead(n.id).catchError((_) {});
  }

  void _open(AppNotification n) {
    // Optimista: si el update falla igual se navega (spec §3).
    _markReadOptimistic(n);
    context.push(mapLinkToRoute(n.link,
        provider: roleStore.value == RoleState.provider));
  }

  void _markAll() {
    final unread = _items.where((n) => n.unread).toList();
    if (unread.isEmpty) return;
    markAllNotificationsRead().catchError((_) {});
    notifCountStore.zero();
    // Cascada suave: las tarjetas se apagan escalonadas (el AnimatedContainer
    // de cada tarjeta hace el fade de color al cambiar readAt).
    for (var i = 0; i < unread.length; i++) {
      Future.delayed(Duration(milliseconds: 60 * i), () {
        if (!mounted) return;
        setState(() => unread[i].readAt = DateTime.now());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          // Píldora "N nuevas": se encoge hasta desaparecer al llegar a 0.
          AnimatedScale(
            scale: _unread > 0 ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$_unread nueva${_unread == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer),
              ),
            ),
          ),
          if (_unread > 0)
            IconButton(
              tooltip: 'Marcar todas como leídas',
              icon: const Icon(Icons.done_all),
              onPressed: _markAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const _Skeletons();
    if (_error) return _ErrorRetry(onRetry: _loadFirst);
    if (_items.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final groups = groupByDay(_items);
    final children = <Widget>[];
    for (final g in groups) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          g.label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: cs.onSurfaceVariant),
        ),
      ));
      for (final n in g.items) {
        children.add(_buildCard(n));
      }
    }
    if (_hasMore) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: _loadingMore
              ? const CircularProgressIndicator()
              : OutlinedButton(
                  onPressed: _loadMore, child: const Text('Cargar más')),
        ),
      ));
    }
    children.add(const SizedBox(height: 24));
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView(children: children),
    );
  }

  Widget _buildCard(AppNotification n) =>
      _NotifCard(key: ValueKey(n.id), n: n, onTap: () => _open(n));
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({super.key, required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fam = familyColors(context, familyFor(n.kind));
    final read = !n.unread;
    // Leída: fondo neutro, textos apagados, icono gris (spec §3). El
    // AnimatedContainer hace el desvanecido de color (~300ms) al marcar leída.
    final bg = read ? cs.surfaceContainerHighest.withValues(alpha: .55) : fam.bg;
    final fg = read ? cs.onSurfaceVariant : fam.fg;
    final ic = read ? cs.outline : fam.icon;
    final body = cleanBody(n.body);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
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
                  child: Icon(iconFor(n.kind), size: 20, color: ic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight:
                                read ? FontWeight.w500 : FontWeight.w700,
                            color: fg),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: fg.withValues(alpha: .8)),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        relativeTimeEs(n.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: fg.withValues(alpha: .65)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeletons extends StatelessWidget {
  const _Skeletons();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 84,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(children: const [
        SizedBox(height: 120),
        Icon(Icons.notifications_none, size: 56),
        Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no tienes notificaciones.\n'
            'Aquí verás tus ofertas, mensajes,\nreseñas y avisos de tu cuenta.',
            textAlign: TextAlign.center,
          ),
        ),
      ]);
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text('No se pudieron cargar las notificaciones'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}
