import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../core/create_request_nav.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../shared/brand_kit.dart';
import '../shared/profile_avatar_button.dart';
import '../shared/swipe_to_actions.dart';
import '../shared/violet_header.dart';
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

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
  // Modelo de hasta 3 finalistas: aunque ya aceptaste, el cliente sigue viendo
  // cuántas ofertas recibió (antes se ocultaba al pasar a 'accepted').
  RequestPhase.accepted => (
    Icons.handshake,
    'Aceptada · $offerCount oferta${offerCount == 1 ? '' : 's'}',
  ),
  // "En contacto", no "Desbloqueado" (pedido PO 2026-07-23): el cliente nunca
  // desbloquea — el ícono de chat refuerza que ya están conversando.
  RequestPhase.unlocked => (
    Icons.forum_outlined,
    'En contacto · $offerCount oferta${offerCount == 1 ? '' : 's'}',
  ),
  RequestPhase.completed => (Icons.done_all, 'Completada'),
  // Sin el conteo de ofertas que llevan las fases vivas: el trato ya se
  // decidió, cuántas llegaron dejó de ser accionable.
  RequestPhase.closed => (Icons.lock_outline, 'Cerrada'),
};

/// Motivo por el que una solicitud NO se puede EDITAR, o null si sí.
///
/// Editar y borrar dejaron de ir juntos el 2026-08-03: sobre una "Cerrada" el
/// cliente puede limpiar la lista, pero editar no aplica — hubo trato.
String? blockedEditReasonForPhase(RequestPhase p) => switch (p) {
  RequestPhase.waiting || RequestPhase.withOffers => null,
  RequestPhase.accepted => 'Ya aceptaste una oferta: no puede editarse',
  RequestPhase.unlocked => 'Ya están en contacto: no puede editarse',
  RequestPhase.completed => 'Solicitud completada',
  RequestPhase.closed => 'El trato se cerró: no puede editarse',
};

/// Motivo por el que una solicitud NO se puede ELIMINAR, o null si sí.
///
/// La RPC `cancel_customer_request` solo acepta solicitudes `open`, y desde el
/// 2026-08-03 también las de trato cerrado aunque el proveedor haya pagado el
/// desbloqueo (el lead ya se consumió y el chat no puede reabrirse).
String? blockedDeleteReasonForPhase(RequestPhase p) => switch (p) {
  RequestPhase.waiting || RequestPhase.withOffers || RequestPhase.closed => null,
  RequestPhase.accepted => 'Ya aceptaste una oferta: no puede eliminarse',
  RequestPhase.unlocked => 'Ya están en contacto: no puede eliminarse',
  RequestPhase.completed => 'Solicitud completada',
};

/// Ordena las filas de la lista de solicitudes: las NO VISTAS primero y, dentro
/// de cada grupo, la más reciente arriba (pedido PO 2026-07-23). Función pura
/// (público para poder probar el orden sin Supabase).
void sortRequestRows(
  List<(Map<String, dynamic>, RequestPhase, int)> rows,
  Set<String> unseenReqIds,
) {
  rows.sort((a, b) {
    final ua = unseenReqIds.contains(a.$1['id']);
    final ub = unseenReqIds.contains(b.$1['id']);
    if (ua != ub) return ua ? -1 : 1;
    final ca = DateTime.parse(a.$1['created_at'] as String);
    final cb = DateTime.parse(b.$1['created_at'] as String);
    return cb.compareTo(ca);
  });
}

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({
    super.key,
    this.myFetch,
    this.othersFetch,
    this.actions = const [HeaderBell()],
    this.embedded = false,
  });

  /// Modo INCRUSTADO: solo la lista de "mis solicitudes", sin `Scaffold`, sin
  /// header violeta y sin los botones de filtro.
  ///
  /// Lo usa el segmento "Mis pedidos" de Mis ofertas (PO 2026-07-30): el
  /// proveedor puede CREAR una solicitud desde el ＋ de la barra pero no tenía
  /// dónde encontrarla salvo entrando al menú lateral — crear y consultar
  /// tienen que estar a la misma profundidad.
  ///
  /// Se incrusta la pantalla entera en vez de extraer la lista a un widget
  /// aparte para no duplicar NADA: carga, estado vacío con la tarjeta de
  /// ejemplo, onboarding, pull-to-refresh y las tarjetas siguen siendo los
  /// mismos de la pestaña del cliente, y cualquier arreglo futuro cae en los
  /// dos sitios solo.
  ///
  /// El toggle "Ver solicitudes de usuarios" NO viaja al modo incrustado: para
  /// un proveedor eso es literalmente su pestaña Solicitudes.
  final bool embedded;

  /// Inyectables para tests (por defecto los fetch reales).
  final Future<List<(Map<String, dynamic>, RequestPhase, int)>> Function()?
  myFetch;
  final Future<List<Map<String, dynamic>>> Function()? othersFetch;

  /// Igual patrón que `CatalogView`/`ProviderInboxView`: `HeaderBell` toca
  /// `notifCountStore`, cuyo constructor accede a `supa` SIN try/catch (a
  /// diferencia de `profileStore`, escrito a propósito para no tocar Supabase
  /// en su constructor) — revienta en widget-tests si Supabase no está
  /// inicializado. Inyectable para poder pasar `const []` en tests.
  final List<Widget> actions;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<(Map<String, dynamic>, RequestPhase, int)>> _load =
      _startLoad();
  int _seenTick = requestsChanged.value;

  /// True mientras NO hay una carga de "mis solicitudes" en vuelo (la última
  /// resolvió). Gatea la guía `client.others_requests.v1`: si esa guía pudiera
  /// pedir turno de inmediato (su botón siempre está visible) mientras la de
  /// `client.my_requests.v1` recién aparece al resolver `_load` (estado vacío,
  /// su ancla es la tarjeta de ejemplo), la de MAYOR `order` ganaba la carrera
  /// por llegar primero al coordinador — el de MENOR order (2, mis solicitudes)
  /// dejaba de "ganar el turno primero" pese a la doctrina. `_startLoad` lo
  /// pone en false en CADA recarga y en true al resolver, así ambas guías
  /// compiten por `order` y no por quién carga antes — no sólo en la 1ª carga.
  bool _myLoadSettled = false;

  /// Solicitudes con al menos una oferta NUEVA sin leer (= con notificación
  /// `offer_new` sin leer). Van PRIMERO en la lista, con punto rojo + borde
  /// grueso oscuro (pedido PO 2026-07-23). El "leído" es por OFERTA (se marca al
  /// abrir cada oferta en el detalle): esta solicitud deja de estar sin ver
  /// cuando ya no le quedan ofertas sin leer.
  Set<String> _unseenReqIds = {};
  // Coordina "un solo row de swipe abierto a la vez".
  final ValueNotifier<Object?> _openRow = ValueNotifier(null);

  bool _others = false; // false = Mías, true = De otros
  Future<List<Map<String, dynamic>>>? _othersLoad;

  Future<List<Map<String, dynamic>>> _fetchOthers() =>
      (widget.othersFetch ?? allOpenRequests)();

  Future<List<(Map<String, dynamic>, RequestPhase, int)>> _fetchMine() =>
      (widget.myFetch ?? _fetch)();

  /// Arranca (o rearranca) la carga de "mis solicitudes" sincronizando
  /// [_myLoadSettled]: vuelve a false mientras la nueva carga está en vuelo y
  /// se pone en true al resolver. Se usa en TODAS las rutas de carga (inicial,
  /// listener `_reload`, staleness y pull-to-refresh) para que el gate de la
  /// guía de "otros" valga en cada recarga, no sólo en la primera.
  Future<List<(Map<String, dynamic>, RequestPhase, int)>> _startLoad() {
    _myLoadSettled = false;
    final f = _fetchMine();
    f.whenComplete(() {
      if (mounted) setState(() => _myLoadSettled = true);
    });
    return f;
  }

  /// El buscador del header se esconde al bajar por la lista y reaparece al
  /// volver al tope (pedido PO). Mientras está escondido, una flecha permite
  /// sacarlo a mano.
  bool _searchHidden = false;

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

  /// Esconde/muestra el header COMPLETO según la DIRECCIÓN del gesto: al
  /// arrastrar hacia arriba (leer más) se pliega; al arrastrar hacia abajo se
  /// baja. Solo reacciona a `UserScrollNotification` — ignora los avisos de
  /// relayout que dispara el propio colapso del header (al plegarse crece la
  /// lista, el `maxScrollExtent` puede caer a 0 y antes eso reabría el header
  /// solo: el bug de "no se oculta", 2026-07-21).
  bool _onListScroll(ScrollNotification n) {
    if (n is! UserScrollNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && !_searchHidden) {
      setState(() => _searchHidden = true);
    } else if (n.direction == ScrollDirection.forward && _searchHidden) {
      setState(() => _searchHidden = false);
    }
    return false;
  }

  /// Botón de filtro (Mías / De otros): violeta con letra blanca. El activo va
  /// en violeta pleno; el inactivo en violeta translúcido (pedido PO 2026-07-22:
  /// botones violeta a la izquierda, letras blancas).
  Widget _filterButton(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.primary.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _seenTick = requestsChanged.value;
        _load = _startLoad();
      });
    }
  }

  void _refetchIfStale() {
    if (_seenTick != requestsChanged.value) {
      _seenTick = requestsChanged.value;
      _load = _startLoad();
    }
  }

  Future<List<(Map<String, dynamic>, RequestPhase, int)>> _fetch() async {
    final reqs = await myRequests();
    if (reqs.isEmpty) {
      _unseenReqIds = {};
      return [];
    }
    final ids = reqs.map((r) => r['id'] as String).toList();
    final offers = List<Map<String, dynamic>>.from(
      await supa
          .from('provider_offers')
          // `id` (nuevo): para mapear qué oferta tiene su `offer_new` sin leer.
          .select('id,request_id,status,unlocked_at')
          .inFilter('request_id', ids),
    );
    // Solo las ofertas aceptadas/completadas tienen conversación (verificado
    // contra producción 2026-08-03: cero conversaciones para pending/rejected/
    // cancelled). Si no hay ninguna, no se consulta nada: esta pantalla ya pasó
    // por auditoría de rendimiento y una ida y vuelta de más se nota.
    final dealIds = [
      for (final o in offers)
        if (o['status'] == 'accepted' || o['status'] == 'completed')
          o['id'] as String,
    ];
    final closedOfferIds = await closedConversationOfferIds(dealIds);
    final byReq = <String, List<OfferLite>>{};
    for (final o in offers) {
      byReq.putIfAbsent(o['request_id'] as String, () => []).add(
            offerLite(o,
                conversationClosed: closedOfferIds.contains(o['id'] as String)),
          );
    }
    // "No vistas": solicitudes con al menos una oferta cuya notificación
    // `offer_new` sigue sin leer, mapeadas vía las ofertas ya traídas.
    _unseenReqIds = await _fetchUnseenRequests(offers);
    final rows = [
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
    // Orden (pedido PO 2026-07-23): las NO VISTAS primero; dentro de cada grupo,
    // la más reciente arriba. `myRequests` ya viene por created_at desc, pero lo
    // dejamos explícito para no depender de ese detalle.
    sortRequestRows(rows, _unseenReqIds);
    // Badge de la pestaña "Solicitudes" (cliente): cuántas solicitudes tienen
    // ofertas SIN VER (pedido PO 2026-07-23: antes contaba TODA solicitud con
    // ofertas sin aceptar — se quedaba encendido aunque ya las hubieras
    // revisado). `_unseenReqIds` se vacía al abrir cada solicitud (marca su
    // `offer_new` leída + bump de `requestsChanged` → recarga), así el badge se
    // limpia cuando ya no queda nada por revisar.
    solicitudesBadge.value = _unseenReqIds.length;
    return rows;
  }

  /// Conjunto de request_ids con al menos una oferta cuya `offer_new` sigue SIN
  /// LEER (best-effort: nunca rompe la lista). El "leído" se marca por oferta en
  /// el detalle; aquí solo necesitamos si a la solicitud le queda ≥1 sin leer.
  Future<Set<String>> _fetchUnseenRequests(
    List<Map<String, dynamic>> offers,
  ) async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return {};
    try {
      final notifs = List<Map<String, dynamic>>.from(
        await supa
            .from('notifications')
            .select('entity_id')
            .eq('user_id', uid)
            .eq('kind', 'offer_new')
            .isFilter('read_at', null),
      );
      final unread = notifs
          .map((n) => n['entity_id'] as String?)
          .whereType<String>()
          .toSet();
      if (unread.isEmpty) return {};
      final reqIds = <String>{};
      for (final o in offers) {
        final oid = o['id'] as String?;
        final rid = o['request_id'] as String?;
        if (oid != null && rid != null && unread.contains(oid)) reqIds.add(rid);
      }
      return reqIds;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    _refetchIfStale();
    final body = Column(
        children: [
          // Header violeta: avatar → menú de perfil, "Jayalo" centrado, campana,
          // saludo grande y el buscador (envuelto por el header, doctrina).
          // Al navegar la lista se pliega COMPLETO (avatar y campana incluidos,
          // pedido PO 2026-07-21) y queda solo la flecha para bajarlo.
          //
          // Incrustada no lleva header: el de la pantalla anfitriona ya está
          // arriba, y dos headers violeta apilados serían absurdos.
          if (!widget.embedded)
          CollapsibleHeader(
            hidden: _searchHidden,
            onReveal: () => setState(() => _searchHidden = false),
            child: VioletHeader(
              leading: const HeaderLeading(),
              title: 'Jayalo',
              titleAlign: HeaderTitleAlign.center,
              actions: widget.actions,
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
          ),
          // Incrustada tampoco lleva los botones de filtro: el segmentado de la
          // pantalla anfitriona ya cumple ese papel, y "Ver solicitudes de
          // usuarios" para un proveedor es su propia pestaña Solicitudes.
          if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            // Botones violeta alineados a la izquierda (Wrap: si no caben en un
            // teléfono angosto, bajan a la segunda línea en vez de desbordar).
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterButton('Mis solicitudes', !_others, () {
                  if (_others) setState(() => _others = false);
                }),
                OnboardingGuide(
                  guideKey: 'client.others_requests.v1',
                  steps: onboardingCopy['client.others_requests.v1']!,
                  order: 3,
                  enabled: _myLoadSettled,
                  child: _filterButton('Ver solicitudes de usuarios', _others, () {
                    setState(() {
                      _others = true;
                      _othersLoad ??= _fetchOthers();
                    });
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            // El colapso del header (esconder buscador) escucha el scroll de
            // CUALQUIERA de las dos pestañas: antes solo envolvía "Mías", por eso
            // en "De otros" el header no subía con el scroll (bug PO 2026-07-22).
            child: NotificationListener<ScrollNotification>(
              onNotification: _onListScroll,
              child: _others
                  ? FutureBuilder<List<Map<String, dynamic>>>(
                      future: _othersLoad,
                      builder: (context, snap) {
                        if (!snap.hasData) return const JayaloLoaderBlock();
                        final list = snap.data!;
                        if (list.isEmpty) {
                          return const EmptyState(
                            message:
                                'Todavía no hay solicitudes de otros usuarios.',
                          );
                        }
                        return ListView.builder(
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: 8 + navBarReservedSpace(context),
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final r = list[i];
                            return _OtherRequestCard(
                              title: r['title'] as String? ?? 'Solicitud',
                              createdAt: DateTime.parse(
                                r['created_at'] as String,
                              ),
                              imageUrl: _firstImage(r),
                              kind: r['kind'] as String?,
                              wholesale: r['is_wholesale'] == true,
                              requirements: requirementsFromRow(r),
                              onTap: () => context.push(
                                '/client/other-request/${r['id']}',
                              ),
                            ).cascadeIn(i);
                          },
                        );
                      },
                    )
                  : JayaloRefresh(
                      // onRefresh espera Future<void>; setState para no devolver Future.
                      onRefresh: () async {
                        setState(() {
                          _load = _startLoad();
                        });
                      },
                      child: FutureBuilder(
                        future: _load,
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const JayaloLoaderBlock();
                          }
                          final items = snap.data!;
                          // La pista de swipe se enseña en la PRIMERA tarjeta
                          // que de verdad se puede deslizar: hacerlo en una
                          // bloqueada enseñaría el gesto donde no funciona.
                          // Calculado una sola vez por construcción de la
                          // lista (no dentro del itemBuilder, que corre por
                          // cada fila en cada scroll: sería O(n²)).
                          final firstOpen = items.indexWhere(
                            (r) => blockedDeleteReasonForPhase(r.$2) == null,
                          );
                          if (items.isEmpty) {
                            return ListView(
                              controller: homeScrollController,
                              padding: EdgeInsets.only(
                                top: 12,
                                bottom: navBarReservedSpace(context),
                              ),
                              children: [
                                OnboardingGuide(
                                  guideKey: 'client.my_requests.v1',
                                  steps:
                                      onboardingCopy['client.my_requests.v1']!,
                                  order: 2,
                                  child: const _ExampleRequestCard(),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(
                                    'Aún no has pedido nada.\n'
                                    'Cuéntanos qué buscas y los proveedores te '
                                    'harán ofertas.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Center(
                                  child: FilledButton(
                                    onPressed: () =>
                                        pushCreateRequestOnce(context),
                                    child: const Text('Crear solicitud'),
                                  ),
                                ),
                              ],
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
                                    final unseen = _unseenReqIds.contains(id);
                                    // El "leído" se marca por oferta DENTRO del
                                    // detalle; al volver, re-fetch para reflejar
                                    // el punto/orden si ya no quedan sin leer.
                                    void open() {
                                      context
                                          .push('/client/request/$id')
                                          .then((_) {
                                        if (mounted && unseen) _reload();
                                      });
                                    }
                                    // El swipe (eliminar/editar) solo aplica
                                    // mientras la solicitud está viva. En el
                                    // resto de fases la tarjeta YA NO queda
                                    // inerte: cede con goma y dice por qué (la
                                    // RPC de borrar solo permite `open`, y
                                    // editar una aceptada no aplica).
                                    final blockedEdit =
                                        blockedEditReasonForPhase(phase);
                                    final blockedDelete =
                                        blockedDeleteReasonForPhase(phase);
                                    // El row queda "bloqueado" (franja gris que
                                    // explica) solo si NINGUNA acción aplica.
                                    // Se muestra el motivo de EDICIÓN: es la
                                    // cadena que ya veían accepted/unlocked, y
                                    // debía quedar exacta.
                                    final blocked =
                                        blockedDelete != null && blockedEdit != null
                                            ? blockedEdit
                                            : null;
                                    final card = _RequestCard(
                                      title: r['title'] as String,
                                      createdAt: DateTime.parse(
                                        r['created_at'] as String,
                                      ),
                                      phase: phase,
                                      offerCount: offerCount,
                                      imageUrl: _firstImage(r),
                                      kind: r['kind'] as String?,
                                      wholesale: r['is_wholesale'] == true,
                                      unseen: unseen,
                                      requirements: requirementsFromRow(r),
                                      onTap: open,
                                      // Sin margen propio: lo aplica el swipe.
                                      margin: EdgeInsets.zero,
                                    );
                                    return SwipeToActions(
                                      id: id,
                                      group: _openRow,
                                      blockedReason: blocked,
                                      peekKey: (blocked == null && i == firstOpen)
                                          ? 'requests.swipe.v1'
                                          : null,
                                      actions: [
                                        if (blockedDelete == null)
                                          SwipeAction(
                                            icon: Icons.delete_outline,
                                            label: 'Eliminar',
                                            color:
                                                Theme.of(context).colorScheme.error,
                                            onTap: () =>
                                                _deleteRequest(id, offerCount),
                                          ),
                                        if (blockedEdit == null)
                                          SwipeAction(
                                            icon: Icons.edit_outlined,
                                            label: 'Editar',
                                            color: const Color(0xFF378ADD),
                                            // Editar llega en una sesión
                                            // próxima (decisión PO).
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
          ),
        ],
      );
    // Incrustada NO abre su propio Scaffold: iría uno dentro de otro y el de
    // adentro se comería el `extendBody` del shell (el hueco que la barra
    // flotante necesita para flotar sobre el contenido).
    return widget.embedded ? body : Scaffold(body: body);
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

/// Saturación 0 con los coeficientes de luminancia Rec. 709: pasa a gris sin
/// alterar el brillo percibido, que es lo que hace que una foto apagada siga
/// siendo legible en vez de convertirse en una mancha.
const _grayscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

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
    this.wholesale = false,
    this.unseen = false,
    this.requirements = RequestRequirements.none,
    this.margin,
  });

  final String title;
  final DateTime createdAt;
  final RequestPhase phase;
  final int offerCount;
  final String? imageUrl;
  final String? kind;
  final VoidCallback onTap;

  /// Solicitud "al por mayor": sticker en la esquina de la miniatura.
  final bool wholesale;

  /// Tiene ofertas NUEVAS sin ver: muestra la etiqueta "Nuevas ofertas" y va
  /// primero en la lista (pedido PO 2026-07-23). El borde quedó SOLO para las
  /// ofertas sin abrir dentro del detalle, no acá.
  final bool unseen;

  /// Lo que el cliente exigió en esta solicitud: símbolos mudos junto a la
  /// hora. El texto completo vive en el detalle.
  final RequestRequirements requirements;

  /// Null = margen estándar de lista; se pasa cero cuando el card vive dentro
  /// de [SwipeToActions] (el swipe aplica el margen exterior).
  final EdgeInsetsGeometry? margin;


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = toneFor(context, phase);
    // Teñida en todas las fases MENOS `waiting`: una solicitud recién puesta,
    // aún sin ofertas, es la más viva de todas y va sobre blanco.
    // `completed` también se tiñe (pedido PO 2026-08-03), con su gris: antes
    // caía en el mismo blanco que `waiting` y una solicitud ya cerrada se leía
    // como activa.
    final tinted = phase != RequestPhase.waiting;
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
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _thumb(context, tinted, tone),
                  if (wholesale) const WholesaleRibbon(radius: 16),
                ],
              ),
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
                        // +2pt (pedido PO 2026-07-22: otro punto sobre el +1).
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeAgo(createdAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: fg.withValues(alpha: .7),
                          ),
                        ),
                        // Guardado con `hasAnyRequirement`: un
                        // `SizedBox.shrink()` dentro de este `Wrap` igual
                        // consume su `spacing`.
                        if (hasAnyRequirement(requirements))
                          RequestRequirementBadges(
                            req: requirements,
                            variant: RequirementBadgeVariant.symbols,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Completada: banda violeta CENTRADA (pedido PO
                    // 2026-08-03). Sustituye a la píldora de estado, no la
                    // acompaña: dos etiquetas diciendo lo mismo en la misma
                    // tarjeta es ruido. El violeta pleno sobre el gris apagado
                    // es lo que hace legible el cierre de un vistazo.
                    if (phase == RequestPhase.completed)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Completado',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else
                      _pill(label, tone, tinted, dark),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // "Nuevas ofertas" a la DERECHA (pedido PO 2026-07-23): la
                  // izquierda ya está cargada (foto, título, fecha, chips). Rojo
                  // PASTEL (mismo tono suave que "Negocio sin verificar"), no
                  // chillón.
                  if (unseen) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      // Fondo BLANCO (pedido PO 2026-07-23): el rosado no jugaba
                      // bien sobre el lila ni el verde de las tarjetas. Blanco +
                      // texto rojo lee sobre cualquier tinte.
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Nuevas ofertas',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFC0261C),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: fg.withValues(alpha: .4),
                  ),
                ],
              ),
            ],
          ),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    seg(i > 0, i <= current),
                    dot(i <= current, i == current),
                    seg(i < labels.length - 1, i < current),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    height: 1.1,
                    color: i <= current ? active : muted,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Miniatura: foto (cover) si la hay; si no, un ícono de tipo sobre relleno
  /// suave (nunca un ícono roto).
  Widget _thumb(BuildContext context, bool tinted, StatusTone tone) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Mismo fix que la píldora: en oscuro el placeholder blanco con ícono claro
    // (tone.ink) era ilegible; se usa el tinte claro del status de fondo y el
    // oscuro para el ícono.
    final holderBg = tinted
        ? (dark ? tone.ink : Colors.white.withValues(alpha: .65))
        : cs.surfaceContainerHighest;
    final holderIcon =
        (tinted && dark ? tone.bg : tone.ink).withValues(alpha: .8);
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
        color: holderIcon,
      ),
    );
    // Completada: la miniatura en GRIS (pedido PO 2026-08-03). Teñir solo el
    // fondo no bastaba: la foto a todo color es lo primero que mira el ojo y
    // seguía leyéndose como una solicitud viva. Cerrada también está
    // terminada y corre el mismo riesgo de leerse como viva a todo color.
    Widget muted(Widget child) => phase == RequestPhase.completed ||
            phase == RequestPhase.closed
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
            child: child,
          )
        : child;
    final url = imageUrl;
    if (url == null) return muted(placeholder());
    return muted(ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: JayaloNetworkImage(
        url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
        loadingBuilder: (_, child, p) => p == null ? child : placeholder(),
      ),
    ));
  }

  /// Chip de estado: sobre tarjeta teñida va en píldora blanca translúcida con
  /// la tinta de la fase; sobre tarjeta blanca va en la píldora teñida.
  Widget _pill(String label, StatusTone tone, bool tinted, bool dark) {
    // En CLARO la píldora teñida es blanca con tinta oscura (tone.ink). En
    // OSCURO esa misma receta deja tinta CLARA (tone.ink es claro en oscuro)
    // sobre blanco → ilegible (bug PO 2026-07-23). Fix: en oscuro se invierte a
    // píldora con el tinte CLARO del status (tone.ink) y texto OSCURO (tone.bg),
    // que contrasta y resalta sobre la tarjeta teñida oscura.
    final Color pillBg;
    final Color pillInk;
    if (!tinted) {
      pillBg = tone.bg;
      pillInk = tone.ink;
    } else if (dark) {
      pillBg = tone.ink;
      pillInk = tone.bg;
    } else {
      pillBg = Colors.white.withValues(alpha: .85);
      pillInk = tone.ink;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: pillInk,
        ),
      ),
    );
  }
}

/// Card de una solicitud AJENA (pestaña "De otros"): foto + título + "hace X"
/// + cinta POR MAYOR. SIN timeline de fase ni swipe (eso es de las propias).
class _OtherRequestCard extends StatelessWidget {
  const _OtherRequestCard({
    required this.title,
    required this.createdAt,
    required this.imageUrl,
    required this.kind,
    required this.wholesale,
    required this.onTap,
    this.requirements = RequestRequirements.none,
  });

  final String title;
  final DateTime createdAt;
  final String? imageUrl;
  final String? kind;
  final bool wholesale;
  final VoidCallback onTap;

  /// Igual que en [_RequestCard]: símbolos mudos junto a la hora.
  final RequestRequirements requirements;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget thumb() {
      const box = 56.0;
      final holder = Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          kind == 'servicio'
              ? Icons.handyman_outlined
              : Icons.inventory_2_outlined,
          color: cs.onSurfaceVariant,
        ),
      );
      if (imageUrl == null || imageUrl!.isEmpty) return holder;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: JayaloNetworkImage(
          imageUrl!,
          width: box,
          height: box,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => holder,
        ),
      );
    }

    return JayaloCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              thumb(),
              if (wholesale) const WholesaleRibbon(radius: 14),
            ],
          ),
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
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeAgo(createdAt),
                      style:
                          TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
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
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: .4),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de solicitud de EJEMPLO (estado vacío): mismo lenguaje visual que
/// `_RequestCard` pero atenuada, con etiqueta "Ejemplo" y SIN `onTap`. Sirve de
/// ancla a la guía `client.my_requests.v1` y da sustancia al "aquí se verán tus
/// solicitudes". Desaparece en cuanto el cliente tiene una solicitud real.
class _ExampleRequestCard extends StatelessWidget {
  const _ExampleRequestCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: .9,
      child: JayaloCard(
        tint: cs.surfaceContainerLowest,
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.inventory_2_outlined,
                  size: 24, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Nevera 11 pies, poco uso',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Ejemplo',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('hace 2 h',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '3 ofertas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
