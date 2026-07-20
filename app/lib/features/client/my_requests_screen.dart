import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../shared/brand_kit.dart';
import '../shared/profile_avatar_button.dart';
import '../shared/violet_header.dart';

/// Aviso temporal mientras el buscador/filtro del header no está cableado.
///
/// ⚠️ HUECO DE LÓGICA DOCUMENTADO (no es un bug): el diseño aprobado pone un
/// buscador con "Filtrar" en el home, pero buscar/filtrar solicitudes propias
/// es funcionalidad NUEVA que hoy no existe en el backend ni en el estado de la
/// pantalla. Decisión pendiente del PO: implementarlo o retirarlo del diseño
/// (ver memoria `jayalo-mockups-app-handoff`). Se dibuja la barra (estética
/// primero) y se avisa al tocar, sin fingir resultados.
void _searchSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
        content: Text('Buscar y filtrar: próximamente.')));
}

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
  int _seenTick = requestsChanged.value;

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
    super.dispose();
  }

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
    _refetchIfStale();
    return Scaffold(
      body: Column(
        children: [
          // Header violeta: avatar → menú de perfil, "Jayalo" centrado, campana,
          // saludo grande y el buscador (envuelto por el header, doctrina).
          VioletHeader(
            leading: const HeaderAvatar(),
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
            below: WarmSearchField(
              hint: 'Buscar en Jayalo',
              onTap: () => _searchSoon(context),
              onFilter: () => _searchSoon(context),
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
                      message: 'Aún no has pedido nada.\n'
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
                              top: 2, bottom: 8 + navBarReservedSpace(context)),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final (r, phase, offerCount) = items[i];
                            return _RequestCard(
                              title: r['title'] as String,
                              createdAt:
                                  DateTime.parse(r['created_at'] as String),
                              phase: phase,
                              offerCount: offerCount,
                              imageUrl: _firstImage(r),
                              kind: r['kind'] as String?,
                              onTap: () =>
                                  context.go('/client/request/${r['id']}'),
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
          Text('Tus solicitudes',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
          const Spacer(),
          Text('$count activa${count == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant)),
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
  });

  final String title;
  final DateTime createdAt;
  final RequestPhase phase;
  final int offerCount;
  final String? imageUrl;
  final String? kind;
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
    final tinted = _live.contains(phase);
    // Tarjeta teñida en las fases vivas; blanca cuando espera/completa.
    final bg = tinted ? tone.bg : cs.surfaceContainerLowest;
    final fg = tinted ? tone.ink : cs.onSurface;
    final (_, label) = phaseChip(phase, offerCount);
    return JayaloCard(
      onTap: onTap,
      tint: bg,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
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
                      color: fg),
                ),
                const SizedBox(height: 3),
                Text(
                  timeAgo(createdAt),
                  style: TextStyle(
                      fontSize: 11.5, color: fg.withValues(alpha: .7)),
                ),
                const SizedBox(height: 8),
                _pill(label, tone, tinted),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              size: 20, color: fg.withValues(alpha: .4)),
        ],
      ),
    );
  }

  /// Miniatura: foto (cover) si la hay; si no, un ícono de tipo sobre relleno
  /// suave (nunca un ícono roto).
  Widget _thumb(BuildContext context, bool tinted, StatusTone tone) {
    final cs = Theme.of(context).colorScheme;
    final holderBg =
        tinted ? Colors.white.withValues(alpha: .65) : cs.surfaceContainerHighest;
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
              color: tone.ink.withValues(alpha: .8)),
        );
    final url = imageUrl;
    if (url == null) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(url,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder(),
          loadingBuilder: (_, child, p) => p == null ? child : placeholder()),
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
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: tone.ink)),
      );
}
