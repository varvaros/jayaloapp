import 'package:flutter/material.dart';
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
typedef InboxFetch = Future<List<Map<String, dynamic>>> Function(
    {String? kind, required bool todas});

/// Saldo del proveedor, inyectado (Task 9) por la misma razón que [InboxFetch]:
/// las tarjetas de interés necesitan saber si alcanza para desbloquear sin
/// tocar red en los tests de widget.
typedef BalanceFetch = Future<int?> Function();

class ProviderInboxScreen extends StatelessWidget {
  const ProviderInboxScreen({super.key});

  static Future<List<Map<String, dynamic>>> _fetch(
          {String? kind, required bool todas}) =>
      todas ? allOpenRequests(kind: kind) : providerInbox(kind: kind);

  @override
  Widget build(BuildContext context) =>
      const ProviderInboxView(fetch: _fetch);
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

  /// false = "Para ti" (su rubro), true = "Todas" (cualquier rubro).
  /// NO persiste entre sesiones: al entrar siempre arranca en "Para ti", que
  /// es la vista con solicitudes relevantes para ofertar.
  bool _todas = false;

  /// Saldo para el desbloqueo de intereses de producto (Task 9). `null` =
  /// aún no cargó — tratado como "sin saldo" por `shouldOfferRecharge`.
  int? _balance;

  late Future<List<Map<String, dynamic>>> _load =
      widget.fetch(kind: _kind, todas: _todas);

  @override
  void initState() {
    super.initState();
    _loadBalance();
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
    final next = widget.fetch(kind: _kind, todas: _todas);
    setState(() {
      _load = next;
    });
    _loadBalance();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

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
    if (shouldOfferRecharge(balance: _balance, cost: productInterestUnlockCost)) {
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
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saldo insuficiente', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                  'Necesitas al menos 1 crédito para conversar con este comprador. '
                  'Recarga para continuar — no se te cobrará nada ahora.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openWallet();
                },
                child: const Text('Recargar'),
              ),
            ]),
      ),
    );
  }

  void _showUnlockSheet(Map<String, dynamic> row) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Conversar con el comprador',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Costo: $productInterestUnlockCost crédito · Tu saldo: ${_balance ?? 0}'),
              const SizedBox(height: 16),
              HoldToConfirmButton(onConfirmed: () async {
                Navigator.pop(ctx);
                await _unlockInterest(row);
              }),
            ]),
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
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('No pudimos cargar el contacto',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Tu desbloqueo está guardado — no se te volverá a cobrar. '
                    'Revisa tu conexión e intenta de nuevo.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showInterestContactSheet(row);
                  },
                  child: const Text('Reintentar'),
                ),
              ]),
        ),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('✅ Contacto desbloqueado', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(contact.phone != null
                  ? '${contact.firstName ?? 'Cliente'} · ${contact.phone}'
                  : 'Este cliente todavía no tiene WhatsApp verificado; '
                      'conversa con él por el chat de Jayalo.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openInterestChat(row, peerName: contact.firstName);
                },
                icon: const Icon(Icons.chat),
                label: const Text('Abrir chat'),
              ),
            ]),
      ),
    );
  }

  Future<void> _openInterestChat(Map<String, dynamic> row, {String? peerName}) async {
    String? convId;
    try {
      convId = await getOrCreateConversation(
          kind: 'product_interest', sourceId: row['id'] as String);
    } catch (_) {}
    if (!mounted) return;
    if (convId == null) {
      _snack('No se pudo abrir el chat. Intenta de nuevo.');
      return;
    }
    await context.push('/messages/$convId', extra: {'peer_name': peerName});
    if (mounted) _refetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        // Header violeta con los dos toggles reales del inbox (doctrina: van
        // compactos, en una fila; las tarjetas son las protagonistas).
        VioletHeader(
          leading: widget.leading,
          title: _todas ? 'Todas las solicitudes' : 'Solicitudes para ti',
          actions: widget.actions,
          below: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
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
                index: _kind == null ? 0 : (_kind == 'producto' ? 1 : 2),
                onChanged: (i) {
                  _kind = i == 0 ? null : (i == 1 ? 'producto' : 'servicio');
                  _refetch();
                },
              ),
            ]),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refetch(),
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
                    message: _todas
                        ? 'Ahora mismo no hay solicitudes abiertas.\n'
                            'Vuelve más tarde: entran nuevas todos los días.'
                        : 'Aquí verás las solicitudes que coinciden con tu negocio.\n'
                            'Te avisaremos cuando llegue una nueva.',
                  );
                }
                return ListView.builder(
                  controller: homeScrollController,
                  padding: EdgeInsets.only(
                      top: 8, bottom: 8 + navBarReservedSpace(context)),
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
                      createdAt: DateTime.parse(r['created_at'] as String),
                      onTap: () => context.go('/provider/request/${r['id']}'),
                    ).cascadeIn(i);
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
  });

  final String title;
  final String description;
  final String? kind;
  final DateTime createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                kind == 'producto'
                    ? Icons.inventory_2_outlined
                    : Icons.handyman_outlined,
                size: 20,
                color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
/// así que se tiñe distinto (ámbar mientras hay dinero esperando desbloqueo,
/// verde cuando ya se desbloqueó — mismo lenguaje de color que
/// `MyOffersScreen`) y lleva su propia acción: "Conversar · N crédito(s)" o
/// "Abrir chat" si ya se pagó.
class _InterestCard extends StatelessWidget {
  const _InterestCard({required this.row, required this.onAction});

  final Map<String, dynamic> row;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unlocked = row['unlocked'] == true;
    final tone = unlocked
        ? (dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight)
        : (dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight);
    final title = (row['title'] as String?) ?? 'Producto';
    final message = (row['description'] as String?) ?? '';
    final imageUrl = row['image_url'] as String?;
    final createdAt = DateTime.parse(row['created_at'] as String);
    return JayaloCard(
      tint: tone.bg,
      onTap: onAction,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(imageUrl, tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.favorite, size: 13, color: tone.ink),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Interesado en tu producto',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tone.ink)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: tone.ink)),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tone.ink.withValues(alpha: .8))),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style: TextStyle(fontSize: 11, color: tone.ink.withValues(alpha: .7))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
                backgroundColor: tone.ink, foregroundColor: tone.bg),
            child: Text(unlocked
                ? 'Abrir chat'
                : 'Conversar · $productInterestUnlockCost crédito'
                    '${productInterestUnlockCost == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
  }

  /// Miniatura con placeholder/error builder (nunca un ícono roto si la
  /// URL falla o el producto no tiene fotos).
  Widget _thumb(String? url, StatusTone tone) {
    const box = 44.0;
    Widget placeholder() => Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
              color: tone.ink.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.inventory_2_outlined, size: 20, color: tone.ink),
        );
    if (url == null || url.isEmpty) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
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
