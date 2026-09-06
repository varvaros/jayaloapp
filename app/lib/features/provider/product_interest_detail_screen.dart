import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/router.dart' show openCreditShop;
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../../domain/recharge.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shared/brand_kit.dart';
import '../shared/celebration.dart';
import '../shared/collapsing_photo_panel.dart';
import '../shared/customer_rep_card.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/moneda.dart';
import 'unlock_flow.dart' show StartChatButton, WhatsappReveal;

/// Detalle de un interés de producto: alguien tocó "Me interesa" en el
/// catálogo del proveedor.
///
/// Antes era una `showModalBottomSheet` al 70% de alto dentro de
/// `inbox_screen.dart`. El PO pidió (2026-08-01) "ponerlo igual que las demás
/// solicitudes, pero con badge que indique que eso fue desde la tienda", así
/// que ahora es una pantalla con la misma estructura que
/// `ProviderRequestDetailScreen`: panel de foto plegable, y debajo datos del
/// cliente → información → acción.
///
/// El otro motivo del cambio: la hoja escribía el WhatsApp del cliente EN
/// TEXTO PLANO en cuanto se abría desbloqueada. Aquí el teléfono vive detrás
/// de [WhatsappReveal], el mismo gate con advertencia que usan las ofertas.
class ProductInterestDetailScreen extends StatefulWidget {
  const ProductInterestDetailScreen({
    super.key,
    required this.interestId,
    this.initial,
  });

  final String interestId;

  /// Fila que el inbox ya tiene cargada (título, mensaje, foto, fecha,
  /// `unlocked`). Se pinta de inmediato mientras el resto llega; si falta, la
  /// pantalla se aguanta con los valores por defecto sin romperse.
  final Map<String, dynamic>? initial;

  @override
  State<ProductInterestDetailScreen> createState() =>
      _ProductInterestDetailScreenState();
}

class _ProductInterestDetailScreenState
    extends State<ProductInterestDetailScreen> {
  late bool _unlocked = widget.initial?['unlocked'] == true;
  int? _balance;
  String? _customerId;
  Map<String, dynamic>? _rep;
  PeerBadges? _badges;
  String? _contactName;
  String? _contactPhone;

  /// Identidad real del cliente, gateada server-side (PO 2026-08-11).
  ({bool unlocked, String? firstName, String? lastName, String? avatarUrl})?
      _custProfile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Saldo: sin él `shouldOfferRecharge` trata null como "sin saldo", que es
    // el lado seguro (ofrece recargar en vez de cobrar a ciegas).
    walletBalance()
        .then((b) => mounted ? setState(() => _balance = b) : null)
        .catchError((_) => null);

    // El cliente: la RPC del inbox no devuelve `customer_id`, pero el
    // proveedor SÍ puede leerlo de `product_interests` (RLS por
    // `provider_user_id`, y la columna está en el grant). Con él se dibuja la
    // misma ficha que en el detalle de solicitud.
    String? cid;
    try {
      cid = await productInterestCustomerId(widget.interestId);
    } catch (_) {}
    if (!mounted || cid == null) return;
    setState(() => _customerId = cid);

    final id = cid;
    customerReputation(id)
        .then((r) => mounted ? setState(() => _rep = r) : null)
        .catchError((_) => null);
    peerVerificationBadges([id])
        .then((m) => mounted ? setState(() => _badges = m[id]) : null)
        .catchError((_) => null);
    // Identidad real, gateada server-side por desbloqueo DE ESTE interés
    // (PO 2026-08-11: por solicitud, no por cliente).
    customerPublicProfile(id, interestId: widget.interestId)
        .then((p) => mounted ? setState(() => _custProfile = p) : null)
        .catchError((_) => null);

    if (_unlocked) await _loadContact();
  }

  Future<void> _loadContact() async {
    try {
      final c = await productInterestContact(widget.interestId);
      if (!mounted) return;
      setState(() {
        _contactName = c.firstName;
        _contactPhone = c.phone;
      });
    } catch (_) {
      // Sin contacto la pantalla sigue sirviendo: el chat es la vía principal.
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.initial ?? const <String, dynamic>{};
    return ProductInterestDetailView(
      title: (row['title'] as String?) ?? 'Producto',
      message: (row['description'] as String?) ?? '',
      imageUrl: row['image_url'] as String?,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      unlocked: _unlocked,
      cost: productInterestUnlockCost,
      balance: _balance,
      customerId: _customerId,
      reputation: _rep,
      badges: _badges,
      customerRealName: _custProfile?.unlocked == true
          ? [_custProfile?.firstName, _custProfile?.lastName]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(' ')
          : null,
      customerRealAvatarUrl:
          _custProfile?.unlocked == true ? _custProfile?.avatarUrl : null,
      onOpenCustomerProfile: _customerId == null
          ? null
          : () => context.push('/provider/customer/$_customerId'
              '?interest=${widget.interestId}'),
      contactName: _contactName,
      contactPhone: _contactPhone,
      onBack: () => context.pop(),
      onUnlock: _unlock,
      onRecharge: _openWallet,
      onOpenChat: _openChat,
    );
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  /// Mismo guion que el desbloqueo de ofertas y que la hoja que esto sustituye:
  /// el cobro arranca YA, en paralelo al "¡PUM!" de la mascota, y al terminar
  /// viene la celebración con "¡Iniciar conversación!".
  Future<void> _unlock() async {
    final unlocking =
        unlockProductInterest(widget.interestId, productInterestUnlockCost)
            .then((r) => (ok: r.ok, newBalance: r.newBalance))
            .catchError((_) => (ok: false, newBalance: null as int?));
    if (!JayaloMotion.reduced(context)) {
      await Future<void>.delayed(JayaloMotion.mascotPum);
    }
    final res = await unlocking;
    if (!mounted) return;
    if (!res.ok) {
      // Acción PAGADA que no se consumó: el pulso pesado la separa del acierto
      // sin que haya que leer el aviso.
      JayaloHaptics.error();
      _snack('No se pudo desbloquear. Intenta de nuevo.');
      return;
    }
    setState(() {
      _unlocked = true;
      if (res.newBalance != null) _balance = res.newBalance;
    });
    // La ficha pasa de anónima a identidad real sin salir de la pantalla.
    final cid = _customerId;
    if (cid != null) {
      customerPublicProfile(cid, interestId: widget.interestId)
          .then((p) => mounted ? setState(() => _custProfile = p) : null)
          .catchError((_) => null);
    }
    await _loadContact();
    if (!mounted) return;
    await showUnlockCelebration(
      context,
      footer: (dismiss) => StartChatButton(
        conversationKind: 'product_interest',
        sourceId: widget.interestId,
        dismiss: dismiss,
        onOpen: (convId) async {
          if (!mounted) return;
          await context.push('/messages/$convId',
              extra: {'peer_name': _contactName});
        },
      ),
    );
  }

  /// Play Billing: la recarga ocurre DENTRO de la app (sustituye al link-out
  /// de ADR-0031, que Play prohíbe).
  Future<void> _openWallet() => openCreditShop(context);

  Future<void> _openChat() async {
    String? convId;
    try {
      convId = await getOrCreateConversation(
          kind: 'product_interest', sourceId: widget.interestId);
    } catch (_) {}
    if (!mounted) return;
    if (convId == null) {
      _snack('No se pudo abrir el chat. Intenta de nuevo.');
      return;
    }
    context.push('/messages/$convId', extra: {'peer_name': _contactName});
  }
}

/// Solo dibuja — todo entra por parámetro para poder montarla en tests sin
/// red, igual que `ProviderInboxView` o `MyBusinessView`.
class ProductInterestDetailView extends StatefulWidget {
  const ProductInterestDetailView({
    super.key,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.createdAt,
    required this.unlocked,
    required this.cost,
    required this.balance,
    this.customerId,
    this.reputation,
    this.badges,
    this.customerRealName,
    this.customerRealAvatarUrl,
    this.onOpenCustomerProfile,
    this.contactName,
    this.contactPhone,
    this.onUnlock,
    this.onRecharge,
    this.onOpenChat,
    this.onBack,
    this.onOpenViewer,
  });

  final String title;
  final String message;
  final String? imageUrl;
  final DateTime? createdAt;
  final bool unlocked;
  final int cost;

  /// `null` = aún no cargó. `shouldOfferRecharge` lo trata como "sin saldo".
  final int? balance;

  final String? customerId;
  final Map<String, dynamic>? reputation;
  final PeerBadges? badges;

  /// Identidad real del cliente cuando el contacto ya se pagó (gateada por la
  /// RPC `get_customer_public_profile`, decisión PO 2026-08-11). `null` =
  /// ficha anónima.
  final String? customerRealName;
  final String? customerRealAvatarUrl;

  /// Abre el perfil del cliente (la ficha es una puerta, mockup 2026-08-11).
  final VoidCallback? onOpenCustomerProfile;

  /// Solo tras desbloquear. El teléfono NUNCA se escribe en pantalla: alimenta
  /// el [WhatsappReveal], que exige un hold y avisa de que por WhatsApp no hay
  /// devolución de créditos.
  final String? contactName;
  final String? contactPhone;

  final VoidCallback? onUnlock;
  final VoidCallback? onRecharge;
  final VoidCallback? onOpenChat;
  final VoidCallback? onBack;
  final void Function(int index)? onOpenViewer;

  @override
  State<ProductInterestDetailView> createState() =>
      _ProductInterestDetailViewState();
}

class _ProductInterestDetailViewState extends State<ProductInterestDetailView> {
  /// Espejo del progreso del hold para la mascota que se infla y hace ¡PUM!
  /// (mismo patrón que el desbloqueo de ofertas).
  final _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? JayaloColors.dSuccess : JayaloColors.success;
    final url = widget.imageUrl;
    final images = (url == null || url.isEmpty) ? const <String>[] : [url];
    final needsRecharge =
        shouldOfferRecharge(balance: widget.balance, cost: widget.cost);
    final showMascot = !widget.unlocked && !needsRecharge;

    return Scaffold(
      body: Stack(children: [
        CustomScrollView(slivers: [
          CollapsingPhotoPanel(
            images: images,
            fallbackIcon: Icons.inventory_2_outlined,
            leading: widget.onBack == null
                ? null
                : Center(
                    child: Material(
                      color: cs.surfaceContainerLowest,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      elevation: 1,
                      child: InkWell(
                        onTap: widget.onBack,
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(Icons.arrow_back_ios_new,
                              size: 18, color: jayaloHead(context)),
                        ),
                      ),
                    ),
                  ),
            onOpenViewer: widget.onOpenViewer,
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                  22, 22, 22, 16 + navBarReservedSpace(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 23,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  const SizedBox(height: 8),
                  // El badge que pidió el PO: esto no salió del marketplace,
                  // salió del catálogo de este proveedor.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(
                      label: 'Desde tu tienda',
                      icon: Icons.storefront_outlined,
                      tone: dark
                          ? JayaloStatus.respondedDark
                          : JayaloStatus.respondedLight,
                    ),
                  ),
                  if (widget.createdAt != null) ...[
                    const SizedBox(height: 8),
                    Text(timeAgo(widget.createdAt!),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],

                  // ── 1) DATOS DEL CLIENTE ──
                  _heading('Datos del cliente'),
                  CustomerRepCard(
                    customerId: widget.customerId,
                    reputation: widget.reputation,
                    badges: widget.badges,
                    realName: widget.customerRealName,
                    realAvatarUrl: widget.customerRealAvatarUrl,
                    onTap: widget.onOpenCustomerProfile,
                  ),

                  // ── 2) INFORMACIÓN ──
                  _heading('Información'),
                  if (widget.message.isEmpty)
                    Text('Sin mensaje: solo marcó interés en el producto.',
                        style:
                            TextStyle(fontSize: 13, color: cs.onSurfaceVariant))
                  else
                    Text(widget.message,
                        style: TextStyle(
                            fontSize: 14, height: 1.4, color: cs.onSurface)),

                  // ── 3) DESBLOQUEO O ABRIR CHAT ──
                  const Divider(height: 32),
                  if (widget.unlocked) ...[
                    Text(
                      'Conversa con ${widget.contactName ?? 'tu cliente'} por '
                      'el chat de Jayalo.',
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: widget.onOpenChat,
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Abrir chat'),
                    ),
                    // El teléfono, detrás del gate con la advertencia de que
                    // por WhatsApp no hay devolución. Nunca escrito en claro.
                    if (widget.contactPhone != null) ...[
                      const SizedBox(height: 14),
                      WhatsappReveal(
                          // Su RPC (`get_unlocked_product_interest_contact`)
                          // es STABLE y no marca nada, así que el teléfono ya
                          // está en mano: el cargador solo lo entrega.
                          loadPhone: () async => widget.contactPhone,
                          firstName: widget.contactName),
                    ],
                  ] else ...[
                    // Jayi va DENTRO del flujo y en este orden exacto —
                    // Jayi, Costo, boton— por pedido del PO 2026-08-30. Antes
                    // era una capa fija sobre TODA la pantalla, asi que caia
                    // donde tocara segun el scroll y la orientacion: en
                    // horizontal aterrizaba sobre la barra de abajo, detras
                    // del boton «+». Mover el porcentaje no arreglaba eso, solo
                    // cambiaba de sitio el problema.
                    //
                    // El alto es FIJO: `Transform.scale` pinta pero no ocupa,
                    // asi que la mascota se infla hasta 1.8x sin empujar ni el
                    // «Costo» ni el boton.
                    if (showMascot)
                      SizedBox(
                        height: 132,
                        child: IgnorePointer(
                          child: HoldMascotLayer(progress: _progress),
                        ),
                      ),
                    Row(
                      children: [
                        const MonedaJayalo(size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Costo: ${widget.cost} crédito${widget.cost == 1 ? '' : 's'}'
                            ' · Tu saldo: ${widget.balance ?? 0}',
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (needsRecharge)
                      FilledButton(
                        onPressed: widget.onRecharge,
                        child: const Text('Saldo insuficiente — Recargar'),
                      )
                    else
                      HoldToConfirmButton(
                        label: 'Mantener para desbloquear · ${widget.cost} '
                            'crédito${widget.cost == 1 ? '' : 's'}',
                        progress: _progress,
                        onConfirmed: () async => widget.onUnlock?.call(),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
