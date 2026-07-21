import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../client/request_status_screen.dart' show offerPriceLabel;
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import 'unlock_flow.dart';

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});
  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _offers = [];
  int? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver del navegador (recarga PayPal), refrescar el saldo (spec §6).
    if (state == AppLifecycleState.resumed) _refetch();
  }

  Future<void> _refetch() async {
    final results = await Future.wait([myOffers(), walletBalance()]);
    if (!mounted) return;
    setState(() {
      _offers = results[0] as List<Map<String, dynamic>>;
      _balance = results[1] as int?;
      _loading = false;
    });
  }

  /// Verde para el SALDO de créditos: el crédito disponible es algo positivo,
  /// no una advertencia (pedido PO: "los créditos en verde; amarillo/naranja =
  /// advertencia"). El ámbar se reserva para "te aceptaron, desbloquea".
  StatusTone get _green => Theme.of(context).brightness == Brightness.dark
      ? JayaloStatus.unlockedDark
      : JayaloStatus.unlockedLight;

  /// Rojo cuando el saldo llegó a 0 (pedido PO 2026-07-22): sin créditos no se
  /// puede desbloquear — es una advertencia.
  StatusTone get _red => Theme.of(context).brightness == Brightness.dark
      ? (bg: const Color(0x33F14E46), ink: const Color(0xFFF6A7A2))
      : (bg: const Color(0xFFFDE8E8), ink: const Color(0xFFC0261C));

  @override
  Widget build(BuildContext context) {
    final toUnlock = _offers
        .where((o) => o['status'] == 'accepted' && o['unlocked_at'] == null)
        .toList();
    final pending = _offers.where((o) => o['status'] == 'pending').toList();
    final rest = _offers
        .where((o) =>
            o['status'] == 'rejected' ||
            o['status'] == 'completed' ||
            (o['status'] == 'accepted' && o['unlocked_at'] != null))
        .toList();
    return Scaffold(
      body: Column(children: [
        const VioletHeader(
          leading: HeaderAvatar(),
          title: 'Mis ofertas',
          actions: [HeaderBell()],
        ),
        Expanded(
          child: _loading
              ? const JayaloLoaderBlock()
              : RefreshIndicator(
                  onRefresh: _refetch,
                  child: ListView(
                      padding: EdgeInsets.only(
                          top: 12, bottom: 12 + navBarReservedSpace(context)),
                      // Cascada de entrada (fade + slide) en cada tarjeta, igual
                      // que Solicitudes y Catálogo: `_ci` es el índice corrido
                      // para escalonar el stagger de arriba hacia abajo.
                      children: _buildOfferList(toUnlock, pending, rest)),
                ),
        ),
      ]),
    );
  }

  /// Arma la lista de Mis ofertas con la cascada de entrada por tarjeta. Los
  /// encabezados de sección aparecen quietos; solo las tarjetas escalonan su
  /// fundido+deslizado ([CascadeIn]) con un índice corrido.
  List<Widget> _buildOfferList(
    List<Map<String, dynamic>> toUnlock,
    List<Map<String, dynamic>> pending,
    List<Map<String, dynamic>> rest,
  ) {
    final children = <Widget>[];
    var ci = 0;
    children.add(_WalletCard(
            balance: _balance,
            tone: _balance == 0 ? _red : _green,
            onRecharge: _openWallet)
        .cascadeIn(ci++));
    if (toUnlock.isNotEmpty) {
      children.add(
          const SectionHeader(text: '🏆 ¡Te aceptaron! Desbloquea el contacto'));
      for (final o in toUnlock) {
        children.add(_acceptedCard(o).cascadeIn(ci++));
      }
    }
    children.add(SectionHeader(text: 'Pendientes (${pending.length})'));
    if (pending.isEmpty && toUnlock.isEmpty) {
      children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
              'Oferta desde "Solicitudes" — es gratis y te avisamos si te aceptan.')));
    }
    for (final o in pending) {
      children.add(_offerCard(o).cascadeIn(ci++));
    }
    if (rest.isNotEmpty) {
      children.add(const SectionHeader(text: 'Historial'));
    }
    for (final o in rest) {
      children.add(_offerCard(o).cascadeIn(ci++));
    }
    children.add(const SizedBox(height: 16));
    return children;
  }

  /// "O1 · Tarjeta teñida" (elegida por el PO): el momento de dinero del
  /// proveedor no puede pasar desapercibido. PO 2026-07-21: todas se veían
  /// IGUALES ("¡Te aceptaron!" sin más) → ahora lleva el TÍTULO de la solicitud
  /// y una FOTO (la de la propia oferta) para saber de cuál se trata.
  Widget _acceptedCard(Map<String, dynamic> o) {
    // Violeta (el color de "desbloquear"): el momento de dinero del proveedor,
    // en el tono de la acción.
    final tone = Theme.of(context).brightness == Brightness.dark
        ? JayaloStatus.respondedDark
        : JayaloStatus.respondedLight;
    final imgs =
        ((o['image_urls'] as List?)?.cast<String>() ?? const <String>[])
            .where((u) => u.isNotEmpty)
            .toList();
    final title = (o['request_title'] as String? ?? '').trim();
    return JayaloCard(
      tint: tone.bg,
      onTap: () => _openOffer(o),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Foto de la oferta (o un candado tintado si no hay) — identifica de
          // un vistazo qué oferta fue aceptada.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imgs.isNotEmpty
                  ? Image.network(imgs.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _acceptedThumbFallback(tone))
                  : _acceptedThumbFallback(tone),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.emoji_events, size: 14, color: tone.ink),
                  const SizedBox(width: 4),
                  Text('¡Te aceptaron!',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: tone.ink)),
                ]),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: jayaloHead(context))),
                ],
                const SizedBox(height: 3),
                Text('${offerPriceLabel(o)} · Toca para desbloquear',
                    style: TextStyle(
                        fontSize: 13, color: tone.ink.withValues(alpha: .85))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock_open, size: 22, color: tone.ink),
        ],
      ),
    );
  }

  /// Miniatura de reemplazo del `_acceptedCard` cuando la oferta no trae foto.
  Widget _acceptedThumbFallback(StatusTone tone) => Container(
        color: tone.ink.withValues(alpha: .14),
        child: Icon(Icons.lock_open, size: 24, color: tone.ink),
      );

  Widget _offerCard(Map<String, dynamic> o) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    // Tonos del badge unificados (pedido PO 2026-07-21): desbloqueada = VIOLETA,
    // aceptada = VERDE, pendiente = ÁMBAR. Ver [offerBadgeTone].
    final (label, tone) = switch (st) {
      'accepted' when unlocked => ('Desbloqueada', offerBadgeTone(context, 'unlocked')),
      'accepted' => ('Aceptada', offerBadgeTone(context, 'accepted')),
      'completed' => ('Completada', offerBadgeTone(context, 'completed')),
      'rejected' => ('Rechazada', offerBadgeTone(context, 'rejected')),
      _ => ('Ya ofertaste', offerBadgeTone(context, 'pending')),
    };
    final created = o['created_at'] as String?;
    final cs = Theme.of(context).colorScheme;
    // La oferta pendiente se puede editar/borrar: se anuncia en el subtítulo.
    final pending = st == 'pending';
    final base = created == null
        ? offerPriceLabel(o)
        : '${offerPriceLabel(o)} · ${timeAgo(DateTime.parse(created))}';
    return JayaloCard(
      onTap: () => _openOffer(o),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o['request_title'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(pending ? '$base · Toca para editar' : base,
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: label, tone: tone),
        ],
      ),
    );
  }

  void _openOffer(Map<String, dynamic> o) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    if (st == 'pending') {
      // Aún sin aceptar: abrir el formulario para editar o borrar la oferta.
      // push (no go): apila el detalle para que el ATRÁS vuelva aquí (el go
      // reemplazaba la pila y la flecha no funcionaba); al volver se recarga.
      context
          .push('/provider/request/${o['request_id']}?edit=${o['id']}')
          .then((_) {
        if (mounted) _refetch();
      });
    } else if (st == 'accepted' && !unlocked) {
      // Flujo compartido (unlock_flow.dart): revelable → hold + costo →
      // celebración → contacto.
      startUnlockFlow(context, o, onChanged: _refetch);
    } else if (unlocked || st == 'completed') {
      showOfferContactSheet(context, o, onChanged: _refetch);
    }
  }

  Future<void> _openWallet() => openProviderWallet(context);
}

/// "W1 · Tarjeta ámbar" (elegida por el PO): el saldo en el tono del dinero,
/// con el número grande y Recargar a mano.
class _WalletCard extends StatelessWidget {
  const _WalletCard(
      {required this.balance, required this.tone, required this.onRecharge});
  final int? balance;
  final StatusTone tone;
  final VoidCallback onRecharge;

  @override
  Widget build(BuildContext context) {
    return JayaloCard(
      tint: tone.bg,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.ink.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.account_balance_wallet_outlined,
                size: 20, color: tone.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${balance ?? '—'} crédito${balance == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: tone.ink)),
                Text('Tu saldo para desbloquear contactos',
                    style: TextStyle(
                        fontSize: 11,
                        color: tone.ink.withValues(alpha: .8))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onRecharge,
            style: FilledButton.styleFrom(
                backgroundColor: tone.ink, foregroundColor: tone.bg),
            child: const Text('Recargar'),
          ),
        ],
      ),
    );
  }
}
