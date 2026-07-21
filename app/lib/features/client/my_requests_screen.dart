import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../shared/brand_kit.dart';
import '../shared/profile_avatar_button.dart';
import '../shared/swipe_to_actions.dart';
import '../shared/violet_header.dart';

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
    '$offerCount oferta${offerCount == 1 ? '' : 's'}',
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
  int _seenTick = requestsChanged.value;
  // Coordina "un solo row de swipe abierto a la vez".
  final ValueNotifier<Object?> _openRow = ValueNotifier(null);

  // La pantalla vive montada como pestaña del shell: sin esto, publicar una
  // solicitud no se reflejaba hasta el pull-to-refresh (bug PO 2026-07-19).
  // Doble cinturón: el listener refresca en vivo si la pantalla está activa,
  // y el chequeo de tick en build() cubre el caso en que el aviso llegó
  // mientras el estado estaba desactivado por el shell (visto en device:
  // el listener solo no bastó al volver de crear-solicitud).
  @override
  void initState() {
    super.initState();
    requestsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    requestsChanged.removeListener(_reload);
    _openRow.dispose();
    super.dispose();
  }

  /// Eliminar una solicitud. SIEMPRE doble confirmación (pedido PO): el swipe
  /// destapa el botón, luego dos diálogos. La RPC `cancel_customer_request`
  /// pone la fila en `cancelled` (soft-delete: nunca borra un lead que un
  /// proveedor ya pagó — en ese caso lanza `unlocked_offer_exists`); al
  /// filtrarse las canceladas del listado, para el cliente "desaparece".
  Future<void> _deleteRequest(String id, int offerCount) async {
    final first = await _confirm(
      title: '¿Eliminar esta solicitud?',
      body: offerCount > 0
          ? 'Ya tienes ${offerCount == 1 ? 'una oferta' : '$offerCount ofertas'}. '
                'Si la eliminas, se retira del marketplace y esos proveedores se '
                'quedan sin respuesta — baja tu reputación como comprador.'
          : 'Se retira del marketplace y ningún proveedor podrá ofertarte.',
      confirmLabel: 'Sí, eliminar',
    );
    if (first != true || !mounted) return;
    final second = await _confirm(
      title: '¿Seguro?',
      body: 'Esta acción es definitiva: no podrás reabrir la solicitud.',
      confirmLabel: 'Eliminar definitivamente',
    );
    if (second != true || !mounted) return;
    try {
      await cancelCustomerRequest(id); // bump requestsChanged → refetch
      if (mounted) showJayaloToast(context, 'Solicitud eliminada.');
    } catch (e) {
      if (!mounted) return;
      showJayaloToast(
        context,
        e.toString().contains('unlocked_offer_exists')
            ? 'No puedes eliminarla: un proveedor ya pagó por contactarte. '
                  'Responde a sus ofertas — si no aceptas ninguna, queda '
                  'desierta y baja tu reputación.'
            : 'No se pudo eliminar la solicitud.',
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  void _reload() {
    if (mounted) {
      setState(() {
        _seenTick = requestsChanged.value;
        _load = _fetch();
      });
    }
  }

  void _refetchIfStale() {
    if (_seenTick != requestsChanged.value) {
      _seenTick = requestsChanged.value;
      _load = _fetch();
    }
  }

  Future<List<(Map<String, dynamic>, RequestPhase, int)>> _fetch() async {
    final reqs = await myRequests();
    if (reqs.isEmpty) return [];
    final ids = reqs.map((r) => r['id'] as String).toList();
    final offers = List<Map<String, dynamic>>.from(
      await supa
          .from('provider_offers')
          .select('request_id,status,unlocked_at')
          .inFilter('request_id', ids),
    );
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
            offers: byReq[r['id']] ?? const [],
          ),
          byReq[r['id']]?.length ?? 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _refetchIfStale();
    return Scaffold(
      body: Column(
        children: [
          // Header violeta: avatar → menú de perfil, "Jayalo" centrado, campana,
          // saludo grande y el buscador (envuelto por el header, doctrina).
          VioletHeader(
            leading: const HeaderLeading(),
            title: 'Jayalo',
            titleAlign: HeaderTitleAlign.center,
            actions: const [HeaderBell()],
            greeting: ListenableBuilder(
              listenable: profileStore,
              builder: (context, _) => HeaderGreeting(
                title: profileStore.firstName != null
                    ? 'Hola, ${profileStore.firstName}'
                    : 'Hola',
                subtitle: 'Tú pides y los proveedores te ofertan.',
              ),
            ),
            // El buscador "en Jayalo" no busca solicitudes propias (no tiene
            // sentido) sino el CATÁLOGO del marketplace, que es donde vive la
            // búsqueda real + los filtros. `?focus=1` abre con el foco puesto;
            // "Filtrar" abre el catálogo (su hoja de filtros llega con la
            // feature de filtros del catálogo).
            below: WarmSearchField(
              hint: 'Buscar en Jayalo',
              onTap: () => context.push('/catalog?focus=1'),
              onFilter: () => context.push('/catalog'),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              // onRefresh espera Future<void>; setState para no devolver Future.
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
                      message:
                          'Aún no has pedido nada.\n'
                          'Cuéntanos qué buscas y los proveedores te harán ofertas.',
                      ctaLabel: 'Crear solicitud',
                      // push, no go: crear-solicitud es MODAL (sube por encima
                      // con su CustomTransitionPage); un go la trataría como
                      // pestaña más — swap instantáneo (gotcha ShellRoute).
                      onCta: () => context.push('/client/create'),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SecRow(count: items.length),
                      Expanded(
                        child: ListView.builder(
                          controller: homeScrollController,
                          padding: EdgeInsets.only(
                            top: 2,
                            bottom: 8 + navBarReservedSpace(context),
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final (r, phase, offerCount) = items[i];
                            final id = r['id'] as String;
                            // push (no go): apila el detalle SOBRE la lista para
                            // que su atrás pueda volver. Con go() la pila se
                            // reemplazaba y el `context.pop()` del detalle
                            // (flecha) no tenía nada que popear — la flecha "no
                            // funcionaba". El resto de detalles (chat/catálogo)
                            // ya usa push por esto mismo.
                            void open() => context.push('/client/request/$id');
                            // El swipe (eliminar/editar) solo tiene sentido
                            // mientras la solicitud está ABIERTA: la RPC de
                            // borrar solo permite `open`, y editar una ya
                            // aceptada/completada no aplica. En esas fases el
                            // card va sin swipe.
                            final canManage =
                                phase == RequestPhase.waiting ||
                                phase == RequestPhase.withOffers;
                            if (!canManage) {
                              return _RequestCard(
                                title: r['title'] as String,
                                createdAt: DateTime.parse(
                                  r['created_at'] as String,
                                ),
                                phase: phase,
                                offerCount: offerCount,
                                imageUrl: _firstImage(r),
                                kind: r['kind'] as String?,
                                onTap: open,
                              ).cascadeIn(i);
                            }
                            final card = _RequestCard(
                              title: r['title'] as String,
                              createdAt: DateTime.parse(
                                r['created_at'] as String,
                              ),
                              phase: phase,
                              offerCount: offerCount,
                              imageUrl: _firstImage(r),
                              kind: r['kind'] as String?,
                              onTap: open,
                              // Sin margen propio: lo aplica el swipe.
                              margin: EdgeInsets.zero,
                            );
                            return SwipeToActions(
                              id: id,
                              group: _openRow,
                              actions: [
                                SwipeAction(
                                  icon: Icons.delete_outline,
                                  label: 'Eliminar',
                                  color: Theme.of(context).colorScheme.error,
                                  onTap: () => _deleteRequest(id, offerCount),
                                ),
                                SwipeAction(
                                  icon: Icons.edit_outlined,
                                  label: 'Editar',
                                  color: const Color(0xFF378ADD),
                                  // Editar llega en una sesión próxima
                                  // (decisión PO); por ahora avisa.
                                  onTap: () async => showJayaloToast(
                                    context,
                                    'Editar solicitud: próximamente.',
                                  ),
                                ),
                              ],
                              child: card,
                            ).cascadeIn(i);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila "Tus solicitudes · N activas" (el `.secrow` del mockup): título fuerte
/// a la izquierda, conteo tenue a la derecha.
class _SecRow extends StatelessWidget {
  const _SecRow({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 26, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'Tus solicitudes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: jayaloHead(context),
            ),
          ),
          const Spacer(),
          Text(
            '$count activa${count == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primera foto de la solicitud (paridad con la web: `image_url` primaria,
/// `image_urls` como respaldo). `null` si no tiene foto.
String? _firstImage(Map<String, dynamic> r) {
  final primary = r['image_url'] as String?;
  if (primary != null && primary.isNotEmpty) return primary;
  final list = (r['image_urls'] as List?)?.cast<String>() ?? const [];
  final first = list.where((u) => u.isNotEmpty);
  return first.isEmpty ? null : first.first;
}

/// Tarjeta de solicitud del home (mockup Tanda 1): tarjeta redondeada teñida
/// por fase, con FOTO (miniatura), tema, tiempo y un CHIP de estado — el de
/// "N ofertas" en lila/morado. Fases vivas (con ofertas/aceptada/desbloqueado)
/// llevan color; esperando/completada van sobre tarjeta blanca.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.title,
    required this.createdAt,
    required this.phase,
    required this.offerCount,
    required this.imageUrl,
    required this.kind,
    required this.onTap,
    this.margin,
  });

  final String title;
  final DateTime createdAt;
  final RequestPhase phase;
  final int offerCount;
  final String? imageUrl;
  final String? kind;
  final VoidCallback onTap;

  /// Null = margen estándar de lista; se pasa cero cuando el card vive dentro
  /// de [SwipeToActions] (el swipe aplica el margen exterior).
  final EdgeInsetsGeometry? margin;

  static const _live = {
    RequestPhase.withOffers,
    RequestPhase.accepted,
    RequestPhase.unlocked,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = toneFor(context, phase);
    final tinted = _live.contains(phase);
    // Tarjeta teñida en las fases vivas; blanca cuando espera/completa.
    final bg = tinted ? tone.bg : cs.surfaceContainerLowest;
    final fg = tinted ? tone.ink : cs.onSurface;
    final (_, label) = phaseChip(phase, offerCount);
    return JayaloCard(
      onTap: onTap,
      tint: bg,
      padding: const EdgeInsets.all(11),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
          _thumb(context, tinted, tone),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  timeAgo(createdAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: fg.withValues(alpha: .7),
                  ),
                ),
                const SizedBox(height: 8),
                _pill(label, tone, tinted),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: fg.withValues(alpha: .4)),
          ]),
          const SizedBox(height: 10),
          _phaseTimeline(context, tone, tinted),
        ],
      ),
    );
  }

  /// Timeline horizontal de 5 pasos (Esperando → Ofertas → Aceptada → Contacto
  /// → Completa) bajo cada solicitud (pedido PO 2026-07-20). El tramo alcanzado
  /// se colorea con la tinta de la FASE actual (ámbar/lila/naranja/verde/gris),
  /// así "cambia de color según el estado"; lo pendiente queda tenue.
  Widget _phaseTimeline(BuildContext context, StatusTone tone, bool tinted) {
    final cs = Theme.of(context).colorScheme;
    final active = tone.ink;
    final muted = tinted
        ? tone.ink.withValues(alpha: .28)
        : cs.onSurfaceVariant.withValues(alpha: .35);
    const labels = ['Esperando', 'Ofertas', 'Aceptada', 'Contacto', 'Completa'];
    final current = phase.index;

    Widget seg(bool show, bool done) => Expanded(
          child: show
              ? Container(height: 2, color: done ? active : muted)
              : const SizedBox(),
        );
    Widget dot(bool done, bool isCurrent) => Container(
          width: isCurrent ? 13 : 10,
          height: isCurrent ? 13 : 10,
          decoration: BoxDecoration(
            color: done ? active : Colors.transparent,
            border: Border.all(color: done ? active : muted, width: 2),
            shape: BoxShape.circle,
          ),
        );

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                seg(i > 0, i <= current),
                dot(i <= current, i == current),
                seg(i < labels.length - 1, i < current),
              ]),
              const SizedBox(height: 4),
              Text(
                labels[i],
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1.1,
                  color: i <= current ? active : muted,
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ]),
          ),
      ],
    );
  }

  /// Miniatura: foto (cover) si la hay; si no, un ícono de tipo sobre relleno
  /// suave (nunca un ícono roto).
  Widget _thumb(BuildContext context, bool tinted, StatusTone tone) {
    final cs = Theme.of(context).colorScheme;
    final holderBg = tinted
        ? Colors.white.withValues(alpha: .65)
        : cs.surfaceContainerHighest;
    Widget placeholder() => Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: holderBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        kind == 'servicio'
            ? Icons.handyman_outlined
            : Icons.inventory_2_outlined,
        size: 24,
        color: tone.ink.withValues(alpha: .8),
      ),
    );
    final url = imageUrl;
    if (url == null) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
        loadingBuilder: (_, child, p) => p == null ? child : placeholder(),
      ),
    );
  }

  /// Chip de estado: sobre tarjeta teñida va en píldora blanca translúcida con
  /// la tinta de la fase; sobre tarjeta blanca va en la píldora teñida.
  Widget _pill(String label, StatusTone tone, bool tinted) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
    decoration: BoxDecoration(
      color: tinted ? Colors.white.withValues(alpha: .85) : tone.bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: tone.ink,
      ),
    ),
  );
}
