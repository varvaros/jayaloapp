import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand.dart';
import '../../core/session_state.dart';
import '../../data/notifications_repository.dart';
import '../../domain/notifications.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shell/floating_nav_bar.dart';
import 'notification_bell.dart';

/// Colores por familia (spec §3), tomados de los tokens `--status-*` de la web
/// (ver `core/brand.dart`): un "mensaje nuevo" se pinta con el mismo verde que
/// un contacto desbloqueado en jayalo.com, las ofertas con el violeta de
/// "respondida", el wallet con el ámbar de "aceptada" y el sistema con el gris
/// de "completada". El rosa de reseñas es el único derivado (la web no tiene
/// token propio) y usa la misma receta.
({Color bg, Color fg, Color icon}) familyColors(
    BuildContext context, NotifFamily f) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final tone = switch (f) {
    NotifFamily.messages =>
      dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight,
    NotifFamily.offers =>
      dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight,
    NotifFamily.wallet =>
      dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
    NotifFamily.reviews =>
      dark ? JayaloStatus.reviewDark : JayaloStatus.reviewLight,
    NotifFamily.system =>
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
  };
  return (bg: tone.bg, fg: tone.ink, icon: tone.ink);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final List<AppNotification> _items = [];
  bool _loading = true;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 0;
  RealtimeChannel? _channel;
  // Id de la tarjeta recién llegada por realtime (dispara su animación).
  String? _justArrivedId;
  // Ids que YA jugaron la animación de llegada: evita que se repita cuando
  // _justArrivedId se limpia (spec: la tarjeta no debe re-animar al toque).
  final Set<String> _arrivedIds = {};

  /// La píldora y "marcar todas" se alimentan del store COMPARTIDO (verdad
  /// del servidor tras [_loadFirst], optimista en tap/marcar-todas): el conteo
  /// local de `_items` subcontaría cuando hay más no-leídas que las páginas
  /// cargadas en memoria.
  int get _unread => notifCountStore.count;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifCountStore.addListener(_onStoreChanged);
    _loadFirst();
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notifCountStore.removeListener(_onStoreChanged);
    _unsubscribe();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// Realtime SOLO en foreground (spec §1, patrón del chat): al background se
  /// suelta el socket; al volver se re-carga la página 1 EN SILENCIO (cubre
  /// el gap sin flash de esqueleto ni perder las páginas ya cargadas) y se
  /// re-suscribe.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _unsubscribe();
    if (state == AppLifecycleState.resumed) {
      // Desde la pantalla de error el resume recarga completo: el merge
      // silencioso no limpia `_error` y dejaría los datos frescos ocultos.
      _loadFirst(silent: !_error);
      _subscribe();
    }
  }

  void _subscribe() {
    _unsubscribe();
    _channel = subscribeNotifications((row) {
      if (!mounted) return;
      final n = AppNotification.fromMap(row);
      if (_items.any((x) => x.id == n.id)) return;
      setState(() {
        _items.insert(0, n);
        _justArrivedId = n.id;
        _arrivedIds.add(n.id);
      });
      notifCountStore.add(1);
      // La animación de llegada dura ~1s (slide+fade+shimmer); pasado ese
      // tiempo se limpia _justArrivedId para que una segunda llegada no
      // reanime esta tarjeta. _arrivedIds recuerda que ya animó para que
      // _buildCard NO la vuelva a envolver en la cascada de entrada.
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _justArrivedId == n.id) {
          setState(() => _justArrivedId = null);
        }
      });
    });
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) unsubscribeNotifications(ch);
  }

  /// [silent]: usado en el resume desde background (spec §1). No debe verse
  /// como una carga: sin esqueleto y sin vaciar `_items` (perdería las
  /// páginas ya traídas con "Cargar más"). En vez de reemplazar la lista,
  /// fusiona la página 0 fresca por id: actualiza `readAt` de lo que ya
  /// estaba y antepone lo nuevo, dejando `_page`/`_hasMore` intactos.
  Future<void> _loadFirst({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final rows = await notificationsPage(0);
      if (!mounted) return;
      final fresh = rows.map(AppNotification.fromMap).toList();
      setState(() {
        if (silent) {
          final byId = {for (final n in _items) n.id: n};
          final newOnes = <AppNotification>[];
          for (final n in fresh) {
            final existing = byId[n.id];
            if (existing != null) {
              existing.readAt = n.readAt;
            } else {
              newOnes.add(n);
            }
          }
          _items.insertAll(0, newOnes);
        } else {
          _items
            ..clear()
            ..addAll(fresh);
          _page = 0;
          _hasMore = rows.length == notifPageSize;
          _loading = false;
        }
      });
      // Revalida el badge compartido con la verdad recién cargada.
      notifCountStore.refresh();
    } catch (_) {
      if (!mounted) return;
      // Resume silencioso: si falla, no se muestra la pantalla de error
      // sobre contenido válido — simplemente se reintenta en el próximo
      // resume/pull-to-refresh (best-effort, igual que el badge).
      if (silent) return;
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
        // Dedupe: el offset de `range` puede correrse si un INSERT realtime
        // llegó entre páginas, repitiendo una fila ya presente (mismo
        // ValueKey dos veces = crash de ListView en debug).
        final existing = _items.map((x) => x.id).toSet();
        _items.addAll(rows
            .map(AppNotification.fromMap)
            .where((n) => !existing.contains(n.id)));
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

  // Raíces de pestaña del shell: empujarlas con push() apilaría un duplicado
  // del home encima del que ya vive en el ShellRoute y confunde a BackGuard
  // (ver gotcha PopScope/predictive-back). context.go() reemplaza en vez de
  // apilar; el resto de rutas (detalle) sí usa push() para poder volver.
  static const _tabRoots = {
    '/client',
    '/provider',
    '/provider/offers',
    '/messages',
  };

  void _open(AppNotification n) {
    // Optimista: si el update falla igual se navega (spec §3).
    _markReadOptimistic(n);
    final route = mapLinkToRoute(n.link,
        provider: roleStore.value == RoleState.provider);
    if (_tabRoots.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  void _markAll() {
    if (_unread == 0) return;
    markAllNotificationsRead().catchError((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudieron marcar. Intenta de nuevo.')),
      );
      // Reconcilia el badge con el servidor: el zero() optimista de abajo
      // pudo quedar desalineado si el update realmente falló.
      notifCountStore.refresh();
    });
    notifCountStore.zero();
    // Cascada solo sobre lo cargado; las páginas no cargadas ya quedaron
    // marcadas por el update de arriba.
    final unread = _items.where((n) => n.unread).toList();
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
          // Sin píldora ni "marcar todas" sobre el esqueleto o el error: en
          // esos estados el conteo no corresponde a lo que se ve.
          if (!_loading && !_error) ...[
            // Píldora "N nuevas": se encoge hasta desaparecer al llegar a 0.
            AnimatedScale(
              scale: _unread > 0 ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    // Skeletons con forma de tarjeta (spec §Estados; único sitio con skeleton
    // por decisión PO — el resto de la app carga con la mascota).
    if (_loading) return const SkeletonList(count: 7);
    if (_error) return _ErrorRetry(onRetry: _loadFirst);
    // El vacío también entra al RefreshIndicator: sin datos igual se puede
    // deslizar para reintentar (spec: no dejar el estado vacío sin salida).
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: _items.isEmpty ? const _Empty() : _list(context),
    );
  }

  /// Aplana los grupos por día en una sola lista de filas (String = título de
  /// día, AppNotification = tarjeta) y la renderiza con ListView.builder:
  /// con 120+ tarjetas tras varios "Cargar más", construir todo el árbol de
  /// golpe (ListView(children:)) es el costo que se evita.
  Widget _list(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = groupByDay(_items);
    final rows = <Object>[];
    // Índice de tarjeta por fila (-1 en los encabezados): la cascada de
    // entrada solo cuenta tarjetas, nunca los títulos de día.
    final cardIndexOf = <int>[];
    var cardIndex = 0;
    for (final g in groups) {
      rows.add(g.label);
      cardIndexOf.add(-1);
      for (final n in g.items) {
        rows.add(n);
        cardIndexOf.add(cardIndex++);
      }
    }
    final footerCount = (_hasMore ? 1 : 0) + 1; // "Cargar más" + espaciador
    return ListView.builder(
      padding: EdgeInsets.only(bottom: navBarReservedSpace(context)),
      itemCount: rows.length + footerCount,
      itemBuilder: (context, i) {
        if (i < rows.length) {
          final row = rows[i];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                row,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                    color: cs.onSurfaceVariant),
              ),
            );
          }
          return _buildCard(row as AppNotification, cardIndexOf[i]);
        }
        final footerIndex = i - rows.length;
        if (_hasMore && footerIndex == 0) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const JayaloSpinner(size: 24)
                  : OutlinedButton(
                      onPressed: _loadMore, child: const Text('Cargar más')),
            ),
          );
        }
        return const SizedBox(height: 24);
      },
    );
  }

  Widget _buildCard(AppNotification n, int index) {
    // Swipe horizontal = marcar leída; la tarjeta NUNCA se elimina:
    // confirmDismiss siempre devuelve false → Dismissible la regresa a su
    // sitio con rebote y el AnimatedContainer desvanece el color (~300ms).
    // Sobre una leída el mismo gesto es no-op y solo rebota (spec §3).
    Widget card = Dismissible(
      key: ValueKey('sw-${n.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: .35,
        DismissDirection.endToStart: .35,
      },
      movementDuration: const Duration(milliseconds: 250),
      confirmDismiss: (_) async {
        _markReadOptimistic(n);
        return false;
      },
      child: _NotifCard(key: ValueKey(n.id), n: n, onTap: () => _open(n)),
    );
    if (n.id == _justArrivedId) {
      // Llegada realtime: entra deslizándose desde arriba con un destello
      // breve del color de su familia (spec §3).
      final fam = familyColors(context, familyFor(n.kind));
      card = card
          .animate(key: ValueKey('new-${n.id}'))
          .slideY(begin: -.35, end: 0, duration: 300.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 250.ms)
          .then()
          .shimmer(duration: 700.ms, color: fam.icon.withValues(alpha: .35));
    } else if (_arrivedIds.contains(n.id)) {
      // Ya jugó la animación de llegada: al limpiarse _justArrivedId esta
      // tarjeta pasaría de key 'new-' a 'in-' y replay-earía la cascada de
      // entrada. Se devuelve sin envoltorio de Animate para que no reanime.
    } else {
      // Cascada de entrada: fade + slide 12px hacia arriba, ~40ms de stagger
      // (tope en los primeros ~14 items para no eternizar listas largas).
      card = card
          .animate(key: ValueKey('in-${n.id}'))
          .fadeIn(duration: 250.ms, delay: (40 * min(index, 14)).ms)
          .slideY(
              begin: .10,
              end: 0,
              duration: 250.ms,
              delay: (40 * min(index, 14)).ms,
              curve: Curves.easeOutCubic);
    }
    return card;
  }
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.only(bottom: navBarReservedSpace(context)),
        children: [
          const SizedBox(height: 100),
          // La mascota mirando abajo-izquierda, igual que el vacío de la web.
          const Center(child: JayaloMascot(size: 76)),
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aún no tienes notificaciones.\n'
              'Aquí verás tus ofertas, mensajes,\nreseñas y avisos de tu cuenta.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
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
