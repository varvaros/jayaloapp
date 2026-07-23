import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../../domain/recharge.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../shared/brand_kit.dart';
import '../shared/celebration.dart';
import '../shared/violet_header.dart';

/// Signature de las fuentes de datos del inbox: `providerInbox` (Para ti,
/// filtra por rubro del proveedor) y `allOpenRequests` (Todas, cualquier
/// rubro). Inyectada en [ProviderInboxView] para que la pantalla se pueda
/// probar sin red.
typedef InboxFetch =
    Future<List<Map<String, dynamic>>> Function({
      String? kind,
      required bool todas,
    });

/// Saldo del proveedor, inyectado (Task 9) por la misma razón que [InboxFetch]:
/// las tarjetas de interés necesitan saber si alcanza para desbloquear sin
/// tocar red en los tests de widget.
typedef BalanceFetch = Future<int?> Function();

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
    this.actions = const [HeaderBell()],
    this.balanceFetch = walletBalance,
  });

  final InboxFetch fetch;

  /// Inyectable (como [actions]): `HeaderAvatar` toca Supabase en su
  /// `initState`, así que los tests pasan un widget inerte.
  final Widget? leading;
  final List<Widget> actions;
  final BalanceFetch balanceFetch;

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

  /// Saldo para el desbloqueo de intereses de producto (Task 9). `null` =
  /// aún no cargó — tratado como "sin saldo" por `shouldOfferRecharge`.
  int? _balance;

  /// Estado de la oferta de este proveedor por solicitud (badge de la
  /// tarjeta): sin entrada = no ofertó; 'pending' = "Ya ofertaste";
  /// 'accepted'/'completed' = "Aceptada". Se recalcula en cada `_runFetch`.
  Map<String, String> _offeredStatuses = {};

  /// Cuántas ofertas ha recibido cada solicitud (FOMO, pedido PO 2026-07-21):
  /// solo el número, no las ofertas. Sin entrada = 0. Se recalcula en cada
  /// `_runFetch`.
  Map<String, int> _offerCounts = {};

  late Future<List<Map<String, dynamic>>> _load = _runFetch();

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  /// Envuelve `widget.fetch` para actualizar el badge de la pestaña
  /// "Solicitudes" (proveedor) con el conteo de la bandeja "Para ti" — las
  /// solicitudes abiertas de su rubro por atender. En "Todas" no se toca el
  /// badge (ese conteo no es una alerta accionable, es exploración).
  Future<List<Map<String, dynamic>>> _runFetch() async {
    var items = await widget.fetch(kind: _kind, todas: _todas);
    if (mounted && !_todas) {
      solicitudesBadge.value = items
          .where((r) => r['source'] != 'store')
          .length;
    }
    // "Para ti" también incluye las solicitudes de OTRO rubro a las que ya
    // ofertó (pedido PO: "si alguien ofertó en otro rubro, esa oferta pasa a
    // Para ti") — el proveedor les da seguimiento desde su bandeja. Best-effort
    // y DESPUÉS del badge: dar seguimiento no es una alerta pendiente.
    if (!_todas) {
      try {
        final have = {for (final r in items) r['id']};
        final offered = await myOfferedOpenRequests(kind: _kind);
        items = [...items, ...offered.where((r) => !have.contains(r['id']))]
          ..sort(
            (a, b) => (b['created_at'] as String? ?? '').compareTo(
              a['created_at'] as String? ?? '',
            ),
          );
      } catch (_) {}
    }
    // ¿A cuáles de estas solicitudes ya ofertó y en qué estado? (badge
    // "Ya ofertaste"/"Aceptada"). Y cuántas ofertas ha recibido CADA una
    // (FOMO): ambas por el mismo conjunto de ids de marketplace.
    final ids = [
      for (final r in items)
        if (r['source'] != 'store') r['id'] as String,
    ];
    try {
      _offeredStatuses = await myOfferedRequestStatuses(ids);
    } catch (_) {
      _offeredStatuses = {};
    }
    try {
      _offerCounts = await offerCountsForRequests(ids);
    } catch (_) {
      _offerCounts = {};
    }
    return items;
  }

  Future<void> _loadBalance() async {
    int? b;
    try {
      b = await widget.balanceFetch();
    } catch (_) {
      return; // best-effort: sin saldo confirmado, shouldOfferRecharge trata null como "sin saldo"
    }
    if (!mounted) return;
    setState(() {
      _balance = b;
    });
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
    _loadBalance();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
  );

  /// ADR-0031: el pago SIEMPRE ocurre fuera de la app (navegador del
  /// sistema). Mismo patrón que `MyOffersScreen._openWallet`.
  Future<void> _openWallet() async {
    Uri target = Uri.parse(AppConfig.walletUrl);
    try {
      target = Uri.parse(await createWalletLoginLink());
    } catch (_) {}
    var ok = false;
    try {
      ok = await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      _snack('No se pudo abrir el navegador. Visita jayalo.com para recargar.');
    }
  }

  Future<void> _onInterestAction(Map<String, dynamic> row) async {
    if (row['unlocked'] == true) {
      await _showInterestContactSheet(row);
      return;
    }
    if (shouldOfferRecharge(
      balance: _balance,
      cost: productInterestUnlockCost,
    )) {
      _offerRechargeSheet();
      return;
    }
    _showUnlockSheet(row);
  }

  /// Saldo insuficiente: SIEMPRE ofrecer recargar, nunca lanzar a un cobro
  /// que va a fallar (regla del proyecto).
  void _offerRechargeSheet() {
    showModalBottomSheet(
      context: context,
      // Por el navigator RAÍZ: si no, el sheet queda DEBAJO de la navbar
      // flotante del shell y tapa el botón (bug PO 2026-07-21).
      useRootNavigator: true,
      // Respeta el área segura: sin esto el sheet se mete bajo la barra de
      // navegación del sistema y el botón "Recargar" queda tapado (bug PO
      // 2026-07-22: "queda debajo de todo").
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 24 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saldo insuficiente',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Necesitas al menos 1 crédito para conversar con este comprador. '
              'Recarga para continuar — no se te cobrará nada ahora.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openWallet();
              },
              child: const Text('Recargar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnlockSheet(Map<String, dynamic> row) {
    showModalBottomSheet(
      context: context,
      // Por el navigator RAÍZ: si no, el sheet queda DEBAJO de la navbar
      // flotante del shell y tapa el botón (bug PO 2026-07-21).
      useRootNavigator: true,
      showDragHandle: true,
      // Sube la hoja ~30% de la pantalla (pedido PO 2026-07-22: quedaba muy
      // abajo) — el relleno inferior la despega del borde.
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.sizeOf(ctx).height * .30,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Conversar con el comprador',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Costo: $productInterestUnlockCost crédito · Tu saldo: ${_balance ?? 0}',
            ),
            const SizedBox(height: 16),
            HoldToConfirmButton(
              onConfirmed: () async {
                Navigator.pop(ctx);
                await _unlockInterest(row);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlockInterest(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    ({bool ok, bool already, int charged, int? newBalance}) res;
    try {
      res = await unlockProductInterest(id, productInterestUnlockCost);
    } catch (_) {
      if (mounted) _snack('No se pudo desbloquear. Intenta de nuevo.');
      return;
    }
    if (!res.ok) {
      if (mounted) _snack('No se pudo desbloquear. Intenta de nuevo.');
      return;
    }
    // `already` es un ÉXITO idempotente (ya pagado antes), no un error —
    // solo se avisa, nunca se bloquea el acceso al contacto.
    if (mounted) {
      if (res.newBalance != null) setState(() => _balance = res.newBalance);
      if (res.already) _snack('Ya tenías este contacto desbloqueado.');
    }
    // Celebrar solo el desbloqueo fresco (con `already` no hubo cobro nuevo).
    if (mounted && !res.already) {
      await showUnlockCelebration(context); // 🔓 candado abriéndose
      if (!mounted) return;
    }
    _refetch();
    await _showInterestContactSheet(row);
  }

  Future<void> _showInterestContactSheet(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    ({String? firstName, String? phone}) contact;
    try {
      contact = await productInterestContact(id);
    } catch (_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'No pudimos cargar el contacto',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tu desbloqueo está guardado — no se te volverá a cobrar. '
                'Revisa tu conexión e intenta de nuevo.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showInterestContactSheet(row);
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      // Por el navigator RAÍZ: si no, el sheet queda DEBAJO de la navbar
      // flotante del shell y tapa el botón (bug PO 2026-07-21).
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '✅ Contacto desbloqueado',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              contact.phone != null
                  ? '${contact.firstName ?? 'Cliente'} · ${contact.phone}'
                  : 'Este cliente todavía no tiene WhatsApp verificado; '
                        'conversa con él por el chat de Jayalo.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openInterestChat(row, peerName: contact.firstName);
              },
              icon: const Icon(Icons.chat),
              label: const Text('Abrir chat'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInterestChat(
    Map<String, dynamic> row, {
    String? peerName,
  }) async {
    String? convId;
    try {
      convId = await getOrCreateConversation(
        kind: 'product_interest',
        sourceId: row['id'] as String,
      );
    } catch (_) {}
    if (!mounted) return;
    if (convId == null) {
      _snack('No se pudo abrir el chat. Intenta de nuevo.');
      return;
    }
    await context.push('/messages/$convId', extra: {'peer_name': peerName});
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
              child: RefreshIndicator(
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
                        return _InboxCard(
                          title: r['title'] as String? ?? '',
                          description: r['description'] as String? ?? '',
                          kind: r['kind'] as String?,
                          imageUrl: r['image_url'] as String?,
                          wholesale: r['is_wholesale'] == true,
                          offerStatus: _offeredStatuses[r['id']],
                          offerCount: _offerCounts[r['id']] ?? 0,
                          createdAt: DateTime.parse(r['created_at'] as String),
                          // push (no go): apila el detalle para que el atrás
                          // vuelva a la bandeja (el go reemplazaba la pila y la
                          // flecha "no funcionaba"). Al volver se refresca por si
                          // acaba de ofertar/editar.
                          onTap: () async {
                            await context.push('/provider/request/${r['id']}');
                            if (context.mounted) _refetch();
                          },
                        ).cascadeIn(i);
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
class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.title,
    required this.description,
    required this.kind,
    required this.createdAt,
    required this.onTap,
    this.imageUrl,
    this.wholesale = false,
    this.offerStatus,
    this.offerCount = 0,
  });

  final String title;
  final String description;
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

  /// Miniatura de la foto del cliente (nunca ícono roto: cae al ícono si no
  /// hay foto o falla la URL). Antes la lista era solo-ícono — el PO reportó
  /// "todas las solicitudes salen sin imágenes" (2026-07-20).
  Widget _leading(ColorScheme cs) {
    Widget ph() => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        kind == 'producto'
            ? Icons.inventory_2_outlined
            : Icons.handyman_outlined,
        size: 20,
        color: cs.primary,
      ),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return ph();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: JayaloNetworkImage(
        url,
        width: 44,
        height: 44,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _leading(cs),
              if (wholesale) const WholesaleRibbon(radius: 12),
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
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
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
                    // FOMO (pedido PO 2026-07-21): cuántas ofertas ya recibió
                    // esta solicitud — solo el número, no se pueden ver. Chip
                    // ámbar con llama = competencia/urgencia. 0 → no se muestra.
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
                          // ofertaste" = ÁMBAR (esperando); "Aceptada" = VERDE (te
                          // eligieron); "Desbloqueado" = VIOLETA (ya pagaste el
                          // contacto).
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un interés de producto (Task 9): un comprador tocó "Me
/// interesa" en TU producto — otra cosa que una solicitud del marketplace,
/// así que se tiñe distinto (violeta mientras hay dinero esperando desbloqueo
/// — pedido PO 2026-07-22, antes ámbar; verde cuando ya se desbloqueó) y lleva
/// su propia acción: "Conversar · N crédito(s)" o
/// "Abrir chat" si ya se pagó.
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
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  timeAgo(createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            child: Text(
              unlocked
                  ? 'Abrir chat'
                  : 'Conversar · $productInterestUnlockCost crédito'
                        '${productInterestUnlockCost == 1 ? '' : 's'}',
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
