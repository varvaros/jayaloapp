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
        .where(
          (o) =>
              o['status'] == 'rejected' ||
              o['status'] == 'completed' ||
              (o['status'] == 'accepted' && o['unlocked_at'] != null),
        )
        .toList();
    return Scaffold(
      body: Column(
        children: [
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
                        top: 12,
                        bottom: 12 + navBarReservedSpace(context),
                      ),
                      // Cascada de entrada (fade + slide) en cada tarjeta, igual
                      // que Solicitudes y Catálogo: `_ci` es el índice corrido
                      // para escalonar el stagger de arriba hacia abajo.
                      children: _buildOfferList(toUnlock, pending, rest),
                    ),
                  ),
          ),
        ],
      ),
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
    children.add(
      _WalletCard(
        balance: _balance,
        tone: _balance == 0 ? _red : _green,
        onRecharge: _openWallet,
      ).cascadeIn(ci++),
    );
    if (toUnlock.isNotEmpty) {
      children.add(
        const SectionHeader(text: '🏆 ¡Te aceptaron! Desbloquea el contacto'),
      );
      for (final o in toUnlock) {
        children.add(_acceptedCard(o).cascadeIn(ci++));
      }
    }
    children.add(SectionHeader(text: 'Pendientes (${pending.length})'));
    if (pending.isEmpty && toUnlock.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            'Oferta desde "Solicitudes" — es gratis y te avisamos si te aceptan.',
          ),
        ),
      );
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

  /// Tarjeta de oferta ACEPTADA, con el mismo patrón que "Interesado en tu
  /// producto" (pedido PO 2026-07-22): título de la solicitud, botón
  /// "Conversar · N créditos" (el desbloqueo cuesta lo mismo que conversar) y,
  /// debajo, el estado "Aceptada". La foto de la oferta identifica de cuál se
  /// trata. Violeta = el tono de "desbloquear" (el momento de dinero).
  Widget _acceptedCard(Map<String, dynamic> o) {
    // Verde de "Aceptada" (el mismo de las solicitudes); el violeta queda
    // reservado para las desbloqueadas (pedido PO 2026-07-22).
    final tone = offerBadgeTone(context, 'accepted');
    final imgs =
        ((o['image_urls'] as List?)?.cast<String>() ?? const <String>[])
            .where((u) => u.isNotEmpty)
            .toList();
    final title = (o['request_title'] as String? ?? '').trim();
    final cost = estimatedUnlockCost(o);
    final price = offerPriceLabel(o);
    return JayaloCard(
      // Fondo BLANCO (pedido PO 2026-07-22): antes la tarjeta iba teñida de
      // verde; ahora solo el botón lleva el verde.
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
                  ? Image.network(
                      imgs.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _acceptedThumbFallback(tone),
                    )
                  : _acceptedThumbFallback(tone),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: jayaloHead(context),
                    ),
                  ),
                const SizedBox(height: 8),
                // Botón "Conversar · N créditos": desbloquea el contacto (mismo
                // flujo que toca la tarjeta). Igual estilo que la interest card.
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _openOffer(o),
                    style: FilledButton.styleFrom(
                      // Mismo verde del botón de ACEPTAR oferta
                      // (HoldToConfirmTone.free → JayaloColors.success), texto
                      // blanco; destaca sobre el fondo blanco de la tarjeta.
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? JayaloColors.dSuccess
                              : JayaloColors.success,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: Text(
                      'Conversar · $cost crédito${cost == 1 ? '' : 's'}',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // "Aceptada" + el PRECIO OFERTADO al lado (pedido PO
                // 2026-07-22): ver la cifra aceptada motiva a desbloquear. El
                // precio va más grande — es el protagonista de la fila.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Aceptada',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tone.ink,
                      ),
                    ),
                    if (price.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          price,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: jayaloHead(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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
      'accepted' when unlocked => (
        'Desbloqueada',
        offerBadgeTone(context, 'unlocked'),
      ),
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
                Text(
                  o['request_title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  pending ? '$base · Toca para editar' : base,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
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
      context.push('/provider/request/${o['request_id']}?edit=${o['id']}').then(
        (_) {
          if (mounted) _refetch();
        },
      );
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
  const _WalletCard({
    required this.balance,
    required this.tone,
    required this.onRecharge,
  });
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
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: tone.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${balance ?? '—'} crédito${balance == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: tone.ink,
                  ),
                ),
                Text(
                  'Tu saldo para desbloquear contactos',
                  style: TextStyle(
                    fontSize: 11,
                    color: tone.ink.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onRecharge,
            style: FilledButton.styleFrom(
              backgroundColor: tone.ink,
              foregroundColor: tone.bg,
            ),
            child: const Text('Recargar'),
          ),
        ],
      ),
    );
  }
}
