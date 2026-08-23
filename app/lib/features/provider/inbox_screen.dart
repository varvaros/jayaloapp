import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/inbox_load.dart';
import '../../domain/pricing.dart';
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../shared/brand_kit.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/swipe_to_actions.dart';
import '../shared/violet_header.dart';
import 'hidden_requests_store.dart';
import 'opened_requests.dart';
import '../shared/moneda.dart';

/// Signature de las fuentes de datos del inbox: `providerInbox` (Para ti,
/// filtra por rubro del proveedor) y `allOpenRequests` (Todas, cualquier
/// rubro). Inyectada en [ProviderInboxView] para que la pantalla se pueda
/// probar sin red.
typedef InboxFetch =
    Future<List<Map<String, dynamic>>> Function({
      String? kind,
      required bool todas,
    });

class ProviderInboxScreen extends StatelessWidget {
  const ProviderInboxScreen({super.key});

  static Future<List<Map<String, dynamic>>> _fetch({
    String? kind,
    required bool todas,
  }) => todas ? allOpenRequests(kind: kind) : providerInbox(kind: kind);

  @override
  Widget build(BuildContext context) => const ProviderInboxView(fetch: _fetch);
}

/// Dibuja el toggle "Para ti/Todas", el filtro de tipo y la lista.
///
/// StatefulWidget porque el toggle y el filtro son estado de UI que vive
/// junto al de carga (mismo espíritu que separar ReputationView/StatsView de
/// sus pantallas, extendido aquí: `fetch` se inyecta para poder montar este
/// widget en tests sin tocar la red). `actions` también es inyectable: por
/// defecto son la campana y el avatar reales, pero [NotificationBell] y
/// [ProfileAvatarButton] tocan `supa` en su `initState` (vía
/// `notifCountStore`/`profileStore`), que revienta si Supabase no está
/// inicializado — en los tests se pasa una lista vacía.
class ProviderInboxView extends StatefulWidget {
  const ProviderInboxView({
    super.key,
    required this.fetch,
    this.leading = const HeaderAvatar(),
    this.actions = const [HeaderSaldo(), HeaderBell()],
  });

  final InboxFetch fetch;

  /// Inyectable (como [actions]): `HeaderAvatar` toca Supabase en su
  /// `initState`, así que los tests pasan un widget inerte.
  final Widget? leading;
  final List<Widget> actions;

  @override
  State<ProviderInboxView> createState() => _ProviderInboxViewState();
}

class _ProviderInboxViewState extends State<ProviderInboxView> {
  String? _kind;

  /// Filtro de estado (pedido PO 2026-07-22): actúa EN CLIENTE sobre el feed ya
  /// cargado, según el estado de la oferta de ESTE proveedor por solicitud.
  /// 'todas' = todo (incluye tarjetas de interés); 'abiertas' = sin oferta o con
  /// oferta pendiente; 'aceptadas' = le aceptaron la oferta; 'desbloqueadas' =
  /// ya desbloqueó/completó el contacto.
  String _status = 'todas';
  static const _statusOptions = [
    'Todas',
    'Abiertas',
    'Aceptadas',
    'Desbloqueadas',
  ];
  static const _statusKeys = [
    'todas',
    'abiertas',
    'aceptadas',
    'desbloqueadas',
  ];

  /// El header violeta se pliega al bajar por la lista y reaparece al subir
  /// (paridad con la bandeja del cliente; pedido PO 2026-07-22: "el header no
  /// sube al hacer swipe" en la bandeja del proveedor).
  bool _headerHidden = false;

  /// false = "Para ti" (su rubro), true = "Todas" (cualquier rubro).
  /// NO persiste entre sesiones: al entrar siempre arranca en "Para ti", que
  /// es la vista con solicitudes relevantes para ofertar.
  bool _todas = false;

  /// Estado de la oferta de este proveedor por solicitud (badge de la
  /// tarjeta): sin entrada = no ofertó; 'pending' = "Ya ofertaste";
  /// 'accepted'/'completed' = "Aceptada". Se recalcula en cada `_runFetch`.
  Map<String, String> _offeredStatuses = {};

  /// Cuántas ofertas ha recibido cada solicitud (FOMO, pedido PO 2026-07-21):
  /// solo el número, no las ofertas. Sin entrada = 0. Se recalcula en cada
  /// `_runFetch`.
  Map<String, int> _offerCounts = {};

  /// Requisitos que el cliente exige por solicitud (símbolos de la tarjeta).
  /// Sin entrada = los de la propia fila. Se recalcula en cada `_runFetch`.
  Map<String, RequestRequirements> _requirements = {};

  late Future<List<Map<String, dynamic>>> _load = _runFetch();

  /// Coordina "un solo row de swipe abierto a la vez" (mismo patrón que
  /// Mis solicitudes y la lista de chats).
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);

  @override
  void initState() {
    super.initState();
    // Ocultas por swipe: cargar el set persistido y repintar cuando cambie
    // (el hide y el «Deshacer» del toast notifican al instante).
    hiddenRequestsStore.ensureLoaded();
    hiddenRequestsStore.addListener(_onHiddenChanged);
    // Abiertas: alimentan el badge de "Solicitudes". Se escucha para que al
    // volver del detalle el numero YA este bajado, sin esperar recarga.
    openedRequestsStore.ensureLoaded().then((_) => _syncBadge());
    openedRequestsStore.addListener(_onOpenedChanged);
  }

  /// Ids que pueden contar para el badge en la ultima carga. Se guarda para
  /// recalcular sin volver a la red cuando se abre una solicitud.
  Set<String> _badgeIds = const {};

  /// `updated_at` de esas solicitudes en la ultima carga: es contra esto que se
  /// compara lo ya visto.
  Map<String, DateTime> _updatedAt = const {};

  void _onOpenedChanged() {
    if (mounted) setState(_syncBadge);
  }

  /// El badge = lo que queda SIN ABRIR. En "Todas" no se toca: ese conteo no es
  /// una alerta accionable, es exploracion.
  void _syncBadge() {
    if (!mounted || _todas) return;
    solicitudesBadge.value = _badgeIds
        .where((id) => openedRequestsStore.hasUnseen(id, _updatedAt[id]))
        .length;
  }

  void _onHiddenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    hiddenRequestsStore.removeListener(_onHiddenChanged);
    openedRequestsStore.removeListener(_onOpenedChanged);
    _openRow.dispose();
    super.dispose();
  }

  /// Carga la bandeja en DOS OLEADAS concurrentes (antes eran 4 viajes a la red
  /// en serie). La orquestación y su porqué viven en `domain/inbox_load.dart`,
  /// que es donde están sus tests; aquí solo se conectan las fuentes reales y
  /// se vuelca el resultado en el estado del widget.
  ///
  /// "Para ti" incluye además las solicitudes de OTRO rubro a las que ya ofertó
  /// (pedido PO: "si alguien ofertó en otro rubro, esa oferta pasa a Para ti");
  /// en "Todas" ese merge no aplica → se pasa `null`.
  Future<List<Map<String, dynamic>>> _runFetch() async {
    final data = await loadInboxData(
      fetchItems: () => widget.fetch(kind: _kind, todas: _todas),
      fetchOfferedOpen: _todas
          ? null
          : () => myOfferedOpenRequests(kind: _kind),
      seen: openedRequestsStore.seen,
      fetchUpdatedAt: updatedAtForRequests,
      fetchStatuses: myOfferedRequestStatuses,
      fetchCounts: offerCountsForRequests,
      fetchRequirements: requirementsForRequests,
    );
    // En "Todas" no se toca el badge: ese conteo no es una alerta accionable,
    // es exploración.
    _badgeIds = data.badgeIds;
    _updatedAt = data.updatedAt;
    if (mounted && !_todas) solicitudesBadge.value = data.badgeCount;
    _offeredStatuses = data.statuses;
    _offerCounts = data.counts;
    _requirements = data.requirements;
    return data.items;
  }

  // Bloque, no expresión: `setState(() => _load = future)` hace que la
  // closure DEVUELVA ese future (una asignación se evalúa al valor asignado)
  // y Flutter revienta con "setState() callback argument returned a
  // Future." en cuanto se llama (lo descubrió el test del toggle). El mismo
  // patrón roto vive en my_requests_screen.dart, reputation_screen.dart y
  // stats_screen.dart, pero tocar esos archivos queda fuera de esta tarea.
  void _refetch() {
    final next = _runFetch();
    setState(() {
      _load = next;
    });
  }

  /// Abre el DETALLE del interés como PANTALLA (pedido PO 2026-08-01).
  ///
  /// Antes esto desplegaba una `showModalBottomSheet` al 70% de alto que,
  /// además, escribía el WhatsApp del cliente en texto plano en cuanto estaba
  /// desbloqueado. Ahora es `ProductInterestDetailScreen`, con la misma
  /// estructura que el detalle de solicitud y el teléfono detrás del gate con
  /// advertencia. La fila ya cargada viaja en `extra` para pintar sin esperar
  /// a la red.
  ///
  /// Al volver se refresca: el desbloqueo ocurre dentro y la tarjeta tiene que
  /// pasar a "Desbloqueado".
  Future<void> _onInterestAction(Map<String, dynamic> row) async {
    await context.push('/provider/interest/${row['id']}', extra: row);
    if (mounted) _refetch();
  }

  /// Pliega/despliega el header según la DIRECCIÓN del gesto (mismo patrón que
  /// my_requests_screen): arrastrar hacia arriba lo oculta; hacia abajo lo
  /// muestra. Solo reacciona a `UserScrollNotification`.
  bool _onListScroll(ScrollNotification n) {
    if (n is! UserScrollNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && !_headerHidden) {
      setState(() => _headerHidden = true);
    } else if (n.direction == ScrollDirection.forward && _headerHidden) {
      setState(() => _headerHidden = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header violeta con los dos toggles reales del inbox (doctrina: van
          // compactos, en una fila; las tarjetas son las protagonistas). Se
          // pliega al bajar por la lista (pedido PO 2026-07-22).
          CollapsibleHeader(
            hidden: _headerHidden,
            onReveal: () => setState(() => _headerHidden = false),
            child: VioletHeader(
              leading: widget.leading,
              title: _todas ? 'Todas las solicitudes' : 'Solicitudes para ti',
              actions: widget.actions,
              below: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        HeaderSegmented(
                          options: const ['Para ti', 'Todas'],
                          index: _todas ? 1 : 0,
                          onChanged: (i) {
                            _todas = i == 1;
                            _refetch();
                          },
                        ),
                        const SizedBox(width: 8),
                        HeaderSegmented(
                          options: const ['Todo', 'Productos', 'Servicios'],
                          index: _kind == null
                              ? 0
                              : (_kind == 'producto' ? 1 : 2),
                          onChanged: (i) {
                            _kind = i == 0
                                ? null
                                : (i == 1 ? 'producto' : 'servicio');
                            _refetch();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Filtro de estado (pedido PO 2026-07-22). Es client-side sobre el
                  // feed ya cargado → solo setState, sin refetch de red.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: HeaderSegmented(
                      options: _statusOptions,
                      index: _statusKeys.indexOf(_status),
                      onChanged: (i) =>
                          setState(() => _status = _statusKeys[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onListScroll,
              child: JayaloRefresh(
                onRefresh: () async => _refetch(),
                child: FutureBuilder(
                  future: _load,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const JayaloLoaderBlock();
                    }
                    // Filtro de estado EN CLIENTE (pedido PO 2026-07-22), según
                    // el estado de la oferta de ESTE proveedor por solicitud.
                    final items = (snap.data!).where((r) {
                      if (r['source'] == 'store') return _status == 'todas';
                      // Ocultas por swipe («no me interesa», PO 2026-08-10):
                      // fuera de la bandeja en ambas pestañas. Solo aplica a
                      // solicitudes del marketplace, no a los intereses de
                      // producto (esos son compradores de TU tienda).
                      if (hiddenRequestsStore.contains(r['id'] as String)) {
                        return false;
                      }
                      // null = no ofertó; 'pending' = ofertó; 'accepted' = le
                      // aceptaron; 'unlocked'/'completed' = desbloqueó contacto.
                      final st = _offeredStatuses[r['id']];
                      return switch (_status) {
                        'abiertas' => st == null || st == 'pending',
                        'aceptadas' => st == 'accepted',
                        'desbloqueadas' =>
                          st == 'unlocked' || st == 'completed',
                        _ => true, // todas
                      };
                    }).toList();
                    if (items.isEmpty) {
                      return EmptyState(
                        controller: homeScrollController,
                        message: switch (_status) {
                          'aceptadas' =>
                            'Todavía no tienes solicitudes aceptadas.\n'
                                'Cuando te acepten una oferta, aparecerá aquí.',
                          'desbloqueadas' =>
                            'Aún no has desbloqueado ningún contacto.\n'
                                'Los que desbloquees aparecerán aquí.',
                          _ =>
                            _todas
                                ? 'Ahora mismo no hay solicitudes abiertas.\n'
                                      'Vuelve más tarde: entran nuevas todos los días.'
                                : 'Aquí verás las solicitudes que coinciden con tu negocio.\n'
                                      'Te avisaremos cuando llegue una nueva.',
                        },
                      );
                    }
                    // Primera solicitud REGULAR (no _InterestCard) de la lista:
                    // ancla de la guía de onboarding. Las tarjetas 'store' son
                    // otra cosa (interés de producto), así que la guía —que
                    // habla de "personas buscando servicios"— no debe anclarse
                    // ahí.
                    final firstRegularIndex = items.indexWhere(
                      (r) => r['source'] != 'store',
                    );
                    return ListView.builder(
                      controller: homeScrollController,
                      padding: EdgeInsets.only(
                        top: 8,
                        bottom: 8 + navBarReservedSpace(context),
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final r = items[i];
                        // Los intereses de producto ('store') son otra cosa que
                        // una solicitud del marketplace: un comprador interesado
                        // en TU producto, no una solicitud abierta — tarjeta y
                        // acción propias (Task 9).
                        if (r['source'] == 'store') {
                          return _InterestCard(
                            row: r,
                            onAction: () => _onInterestAction(r),
                          ).cascadeIn(i);
                        }
                        final id = r['id'] as String;
                        final card = _InboxCard(
                          title: r['title'] as String? ?? '',
                          kind: r['kind'] as String?,
                          imageUrl: r['image_url'] as String?,
                          wholesale: r['is_wholesale'] == true,
                          offerStatus: _offeredStatuses[r['id']],
                          offerCount: _offerCounts[r['id']] ?? 0,
                          // La oleada B manda; si no trajo entrada (falló, o la
                          // fila ya venía completa desde `allOpenRequests`), se
                          // usan los de la propia fila. Las dos fuentes leen las
                          // mismas cinco columnas, así que no pueden discrepar.
                          requirements:
                              _requirements[r['id']] ?? requirementsFromRow(r),
                          createdAt: DateTime.parse(r['created_at'] as String),
                          // Sin margen propio: lo aplica el swipe.
                          margin: EdgeInsets.zero,
                          // push (no go): apila el detalle para que el atrás
                          // vuelva a la bandeja (el go reemplazaba la pila y la
                          // flecha "no funcionaba"). Al volver se refresca por si
                          // acaba de ofertar/editar.
                          onTap: () async {
                            await context.push('/provider/request/${r['id']}');
                            if (context.mounted) _refetch();
                          },
                        );
                        // Deslizar → «Descartar» (pedido PO 2026-08-10,
                        // «cuando no interesa una solicitud»; renombrado de
                        // «Ocultar» el 2026-08-18). Local al dispositivo, con
                        // Deshacer en el toast — el store se sigue llamando
                        // `hiddenRequestsStore` a proposito, decision del PO.
                        final row = SwipeToActions(
                          id: id,
                          group: _openRow,
                          actions: [
                            SwipeAction(
                              icon: Icons.visibility_off_outlined,
                              label: 'Descartar',
                              color: Theme.of(context).colorScheme.outline,
                              onTap: () async {
                                hiddenRequestsStore.hide(id);
                                showJayaloToast(
                                  context,
                                  'Solicitud descartada.',
                                  actionLabel: 'Deshacer',
                                  onAction: () =>
                                      hiddenRequestsStore.unhide(id),
                                );
                              },
                            ),
                          ],
                          child: card,
                        );
                        if (i == firstRegularIndex) {
                          // cascadeIn(i) va DENTRO del child (no envolviendo
                          // todo el OnboardingGuide): la guía mide su ancla con
                          // localToGlobal en un post-frame callback, y si el
                          // slide de entrada envuelve la guía, esa medición cae
                          // en la posición A MITAD de camino de la animación —
                          // el spotlight queda ~10% de una tarjeta desalineado.
                          // Con cascadeIn solo en la tarjeta, la guía mide la
                          // posición YA asentada mientras la tarjeta sigue
                          // animando visualmente.
                          return OnboardingGuide(
                            guideKey: 'provider.requests_list.v1',
                            steps: onboardingCopy['provider.requests_list.v1']!,
                            child: row.cascadeIn(i),
                          );
                        }
                        return row.cascadeIn(i);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Variante "I2 · Con ícono de tipo" (elegida por el PO): tarjeta neutra con
/// el ícono de producto/servicio en contenedor redondeado, como una
/// notificación. El acento usa el primario del tema (violeta claro / azul
/// oscuro).
///
/// SIN descripción (pedido PO 2026-08-09): la lista ya no la muestra —
/// se sigue viendo en el detalle de la solicitud, que ya la pinta. El
/// espacio que dejó libre pasó a la miniatura, ahora más grande.
class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.onTap,
    this.imageUrl,
    this.wholesale = false,
    this.offerStatus,
    this.offerCount = 0,
    this.requirements = RequestRequirements.none,
    this.margin,
  });

  final String title;
  final String? kind;
  final DateTime createdAt;
  final VoidCallback onTap;
  final String? imageUrl;

  /// La solicitud es "al por mayor" — se marca con un sticker en la esquina de
  /// la miniatura (pedido PO): el proveedor lo distingue de un vistazo.
  final bool wholesale;

  /// Estado de la oferta de ESTE proveedor a esta solicitud (`null` = aún no
  /// ofertó). Pinta el badge: 'pending' → "Ya ofertaste" (verde);
  /// 'accepted'/'completed' → "Aceptada" (ámbar, ¡hay dinero esperando!).
  final String? offerStatus;

  /// Cuántas ofertas ha recibido la solicitud EN TOTAL (FOMO, pedido PO
  /// 2026-07-21): solo el número, no se pueden ver. 0 = no se muestra chip.
  final int offerCount;

  /// Lo que el cliente EXIGE en esta solicitud (comprobante fiscal, suplidor
  /// del Estado, envío…). Se pintan como símbolos mudos junto a la hora; el
  /// texto completo vive en el detalle.
  final RequestRequirements requirements;

  /// Null = margen estándar de lista; se pasa cero cuando la tarjeta vive
  /// dentro de [SwipeToActions] (el swipe aplica el margen exterior).
  final EdgeInsetsGeometry? margin;

  /// Lado de la miniatura: sin descripción en la tarjeta (pedido PO
  /// 2026-08-09) la foto pasa a ser la protagonista — 76 desde el mockup
  /// aprobado 2026-08-10 (antes 64, y antes 44).
  static const _thumbSize = 76.0;
  static const _thumbRadius = 16.0;

  /// Miniatura de la foto del cliente (nunca ícono roto: cae al ícono si no
  /// hay foto o falla la URL). Antes la lista era solo-ícono — el PO reportó
  /// "todas las solicitudes salen sin imágenes" (2026-07-20).
  Widget _leading(ColorScheme cs) {
    Widget ph() => Container(
      width: _thumbSize,
      height: _thumbSize,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(_thumbRadius),
      ),
      child: Icon(
        kind == 'producto'
            ? Icons.inventory_2_outlined
            : Icons.handyman_outlined,
        size: 26,
        color: cs.primary,
      ),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return ph();
    return ClipRRect(
      borderRadius: BorderRadius.circular(_thumbRadius),
      child: JayaloNetworkImage(
        url,
        width: _thumbSize,
        height: _thumbSize,
        fit: BoxFit.cover,
        loadingBuilder: (c, child, p) => p == null ? child : ph(),
        errorBuilder: (c, e, s) => ph(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onTap,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _leading(cs),
              if (wholesale) const WholesaleRibbon(radius: _thumbRadius),
            ],
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
                  // +2pt sobre el cuerpo (pedido PO 2026-07-22: otro punto
                  // sobre el +1 anterior).
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                // Mockup aprobado 2026-08-10: la línea de META (hora +
                // símbolos de requisitos) va aparte, y los CHIPS de estado en
                // su propia fila debajo — antes todo compartía un solo Wrap.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeAgo(createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    // Guardado con `hasAnyRequirement`: un `SizedBox.shrink()`
                    // dentro de este `Wrap` igual consume su `spacing`.
                    if (hasAnyRequirement(requirements))
                      RequestRequirementBadges(
                        req: requirements,
                        variant: RequirementBadgeVariant.symbols,
                      ),
                  ],
                ),
                if (offerCount > 0 ||
                    (offerStatus != null && offerStatus != 'rejected')) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // FOMO (pedido PO 2026-07-21): cuántas ofertas ya
                      // recibió la solicitud — solo el número, no se pueden
                      // ver. Chip ámbar con llama = competencia/urgencia.
                      if (offerCount > 0)
                        StatusChip(
                          label: offerCount == 1
                              ? '1 oferta'
                              : '$offerCount ofertas',
                          icon: Icons.local_fire_department,
                          tone: Theme.of(context).brightness == Brightness.dark
                              ? JayaloStatus.pendingDark
                              : JayaloStatus.pendingLight,
                        ),
                      if (offerStatus != null && offerStatus != 'rejected')
                        Builder(
                          builder: (context) {
                            // Colores del badge (pedido PO 2026-07-21/22): "Ya
                            // ofertaste" = ÁMBAR (esperando); "Aceptada" =
                            // VERDE (te eligieron); "Desbloqueado" = VIOLETA
                            // (ya pagaste el contacto).
                            final unlocked =
                                offerStatus == 'unlocked' ||
                                offerStatus == 'completed';
                            final accepted = offerStatus == 'accepted';
                            final (label, icon, state) = unlocked
                                ? ('Desbloqueado', Icons.lock_open, 'unlocked')
                                : accepted
                                ? (
                                    'Aceptada',
                                    Icons.emoji_events_outlined,
                                    'accepted',
                                  )
                                : (
                                    'Ya ofertaste',
                                    Icons.check_circle_outline,
                                    'pending',
                                  );
                            return StatusChip(
                              label: label,
                              icon: icon,
                              tone: offerBadgeTone(context, state),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un interés de producto (Task 9): un comprador tocó "Me
/// interesa" en TU producto — otra cosa que una solicitud del marketplace, así
/// que se tiñe distinto (violeta mientras hay dinero esperando desbloqueo —
/// pedido PO 2026-07-22, antes ámbar; verde cuando ya se desbloqueó).
///
/// SIN botón (pedido PO 2026-08-01): antes traía un `FilledButton` con
/// "Conversar · N crédito(s)" / "Abrir chat", y era la única tarjeta del inbox
/// que lo hacía — las de solicitud se tocan y se entra. El PO lo señaló como
/// inconsistencia: "vamos a ponerlo igual que las demás solicitudes, que debes
/// entrar para abrir el chat". Ahora el estado se comunica con un [StatusChip]
/// junto a la hora, exactamente como "Ya ofertaste" / "Aceptada" /
/// "Desbloqueado" en [_RequestCard], y la acción vive dentro del detalle.
class _InterestCard extends StatelessWidget {
  const _InterestCard({required this.row, required this.onAction});

  final Map<String, dynamic> row;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final unlocked = row['unlocked'] == true;
    // Mismo diseño que la tarjeta de oferta aceptada (pedido PO 2026-07-22):
    // fondo BLANCO y botón VERDE de aceptar oferta (JayaloColors.success).
    final green = dark ? JayaloColors.dSuccess : JayaloColors.success;
    final title = (row['title'] as String?) ?? 'Producto';
    final message = (row['description'] as String?) ?? '';
    final imageUrl = row['image_url'] as String?;
    final createdAt = DateTime.parse(row['created_at'] as String);
    return JayaloCard(
      onTap: onAction,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(imageUrl, green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite, size: 13, color: green),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Interesado en tu producto',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
                // Misma fila que en `_RequestCard`: la hora y, al lado, el
                // chip de estado. Violeta "Desbloqueado" cuando ya se pagó;
                // ámbar con el costo mientras haya dinero pendiente (ámbar =
                // espera/dinero en todo el proyecto).
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeAgo(createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (unlocked)
                      StatusChip(
                        label: 'Desbloqueado',
                        icon: Icons.lock_open,
                        tone: offerBadgeTone(context, 'unlocked'),
                      )
                    else
                      StatusChip(
                        label: '$productInterestUnlockCost crédito'
                            '${productInterestUnlockCost == 1 ? '' : 's'}',
                        leading: const MonedaJayalo(size: 14),
                        tone: offerBadgeTone(context, 'pending'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Miniatura con placeholder/error builder (nunca un ícono roto si la
  /// URL falla o el producto no tiene fotos).
  Widget _thumb(String? url, Color accent) {
    const box = 44.0;
    Widget placeholder() => Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.inventory_2_outlined, size: 20, color: accent),
    );
    if (url == null || url.isEmpty) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: JayaloNetworkImage(
        url,
        width: box,
        height: box,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder(),
        errorBuilder: (context, error, stack) => placeholder(),
      ),
    );
  }
}
