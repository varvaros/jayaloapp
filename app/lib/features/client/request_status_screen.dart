import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../../domain/phase.dart';
import 'my_requests_screen.dart' show phaseChip;
import 'offer_actions.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';

/// Tono ámbar del panel del detalle (la doctrina lo pide cálido, NO lila —
/// así el detalle no se confunde con el chat). Claro sale del mockup
/// (`#F0C48C`); oscuro cae a un ámbar apagado.
({Color panel, Color ink, Color sheet}) _amber(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (
          panel: const Color(0xFF3A2C12),
          ink: const Color(0xFFF0C48C),
          sheet: Theme.of(context).colorScheme.surfaceContainerLowest,
        )
      : (
          panel: const Color(0xFFF0C48C),
          ink: const Color(0xFF6B4514),
          sheet: Theme.of(context).colorScheme.surfaceContainerLowest,
        );
}

String offerPriceLabel(Map<String, dynamic> o) {
  if (o['price'] != null) return fmtRD(o['price'] as num);
  if (o['price_min'] != null && o['price_max'] != null) {
    return '${fmtRD(o['price_min'] as num)} – ${fmtRD(o['price_max'] as num)}';
  }
  if (o['pricing_mode'] == 'hourly' && o['hourly_rate'] != null) {
    return '${fmtRD(o['hourly_rate'] as num)}/hora';
  }
  return 'A evaluar';
}

const _phaseCopy = {
  RequestPhase.waiting:
      'Tu solicitud está publicada. Los proveedores la están viendo.',
  RequestPhase.withOffers:
      'Revisa las ofertas y acepta la que más te convenga.',
  RequestPhase.accepted: 'El proveedor te contactará pronto.',
  RequestPhase.unlocked: 'Ya puedes hablar con el proveedor.',
  RequestPhase.completed: 'Califica al proveedor para ayudar a la comunidad.',
};

/// Títulos del héroe de fase (variante D1 elegida por el PO).
const _phaseTitle = {
  RequestPhase.waiting: 'Esperando ofertas',
  RequestPhase.withOffers: 'Con ofertas',
  RequestPhase.accepted: 'Oferta aceptada',
  RequestPhase.unlocked: 'Contacto desbloqueado',
  RequestPhase.completed: 'Completada',
};

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    supa
        .from('customer_requests')
        .select('id,title,status,kind,bullets,user_id,created_at,image_urls')
        .eq('id', widget.requestId)
        .single()
        .then((r) => mounted ? setState(() => _request = r) : null);
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    if (req == null) {
      return Scaffold(
        body: Stack(children: [
          const Padding(
              padding: EdgeInsets.only(top: 80), child: SkeletonList()),
          SafeArea(child: _BackFab(onTap: () => context.pop())),
        ]),
      );
    }
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: offersStream(widget.requestId),
        builder: (context, snap) {
          final offers = snap.data ?? const <Map<String, dynamic>>[];
          final phase = phaseForRequest(
              requestStatus: req['status'] as String,
              offers: offers.map(offerLite).toList());
          return Column(children: [
            _AmberPanel(
                request: req, phase: phase, onBack: () => context.pop()),
            Expanded(
              child: _DetailSheet(
                request: req,
                phase: phase,
                offers: offers,
                onSeeOffers: () => _showOffers(context, req, offers),
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// Hoja de ofertas que sube sobre el detalle: cada oferta es una tarjeta;
  /// tocarla abre la MISMA `showOfferSheet` de siempre (aceptar/rechazar), sin
  /// tocar el flujo de aceptación.
  ///
  /// SUBE con la MISMA configuración que el modal de crear-solicitud (subida
  /// lenta y fluida: `modalRise` con la curva enfatizada; cierre en `page`).
  Future<void> _showOffers(BuildContext context, Map<String, dynamic> req,
      List<Map<String, dynamic>> offers) async {
    final hasAccepted = offers
        .any((o) => o['status'] == 'accepted' || o['status'] == 'completed');
    final cheapest = _cheapestOfferId(offers);
    final riseController = BottomSheet.createAnimationController(this)
      ..duration =
          JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.modalRise
      ..reverseDuration =
          JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.page;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      transitionAnimationController: riseController,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        minChildSize: .4,
        builder: (ctx, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Ofertas',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(ctx))),
                  const Spacer(),
                  Text('Acepta la que más te convenga',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ]),
          ),
          Expanded(
            child: offers.isEmpty
                ? const Center(
                    child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Todavía no hay ofertas.\nTe avisaremos con una notificación.',
                        textAlign: TextAlign.center),
                  ))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: offers.length,
                    itemBuilder: (_, i) {
                      final o = offers[i];
                      return _OfferCard(
                        offer: o,
                        cheapest: o['id'] == cheapest,
                        statusChip: offerStatusChip(ctx, o, hasAccepted),
                        onTap: () => showOfferSheet(ctx, req, o,
                            hasAcceptedElsewhere:
                                hasAccepted && o['status'] == 'pending'),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
    riseController.dispose();
  }
}

/// Id de la oferta más barata (numérica) — la que lleva el chip verde "Más
/// económica" como orientación (sin decidir por el cliente).
String? _cheapestOfferId(List<Map<String, dynamic>> offers) {
  String? id;
  num? best;
  for (final o in offers) {
    final p = (o['price'] ?? o['price_min'] ?? o['hourly_rate']) as num?;
    if (p == null) continue;
    if (best == null || p < best) {
      best = p;
      id = o['id'] as String?;
    }
  }
  return id;
}

Widget offerStatusChip(
    BuildContext context, Map<String, dynamic> o, bool hasAccepted) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final st = o['status'] as String;
  final (txt, tone) = switch (st) {
    'accepted' when o['unlocked_at'] != null => (
        'Desbloqueada',
        dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight
      ),
    'accepted' => (
        'Aceptada',
        dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight
      ),
    'completed' => (
        'Completada',
        dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
      ),
    'rejected' => (
        'Rechazada',
        dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
      ),
    _ => hasAccepted
        ? (
            'Otra aceptada',
            dark ? JayaloStatus.completedDark : JayaloStatus.completedLight
          )
        : ('Pendiente',
            dark ? JayaloStatus.pendingDark : JayaloStatus.pendingLight),
  };
  return StatusChip(label: txt, tone: tone);
}

/// Botón de atrás flotante sobre el panel ámbar (la doctrina: en el detalle la
/// FOTO manda; no lleva header violeta, solo el atrás flotando).
class _BackFab extends StatelessWidget {
  const _BackFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 16),
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: 1,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(Icons.arrow_back_ios_new,
                    size: 18, color: jayaloHead(context)),
              ),
            ),
          ),
        ),
      );
}

/// Panel ámbar con la foto grande (cover) + miniaturas al borde derecho, o un
/// ícono de fase si la solicitud no trae fotos.
class _AmberPanel extends StatelessWidget {
  const _AmberPanel(
      {required this.request, required this.phase, required this.onBack});
  final Map<String, dynamic> request;
  final RequestPhase phase;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final am = _amber(context);
    final images = ((request['image_urls'] as List?)?.cast<String>() ??
            const <String>[])
        .where((u) => u.isNotEmpty)
        .toList();
    final (icon, _) = phaseChip(phase, 0);
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: 300 + topInset,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: am.panel,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          // La foto LLENA todo el panel ámbar (cover) — el ámbar solo asoma si
          // no hay foto (ícono de fase centrado). Sin cuadro interno.
          Positioned.fill(
            child: images.isEmpty
                ? Center(child: Icon(icon, size: 120, color: am.ink))
                : Image.network(images.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Center(child: Icon(icon, size: 120, color: am.ink))),
          ),
          // Miniatura de la 2ª foto pegada al borde derecho (máx. 2 fotos).
          if (images.length > 1)
            Positioned(
              top: topInset + 30,
              right: 0,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Image.network(images[1],
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(width: 76, height: 76, color: am.panel)),
              ),
            ),
          SafeArea(child: _BackFab(onTap: onBack)),
        ],
      ),
    );
  }
}

/// Hoja blanca del detalle: título + chip de fase, "Desde", avatares anónimos
/// de proveedores, chips de Detalles (los bullets de la IA), meta de publicación
/// y el CTA "Ver N ofertas".
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.request,
    required this.phase,
    required this.offers,
    required this.onSeeOffers,
  });

  final Map<String, dynamic> request;
  final RequestPhase phase;
  final List<Map<String, dynamic>> offers;
  final VoidCallback onSeeOffers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bullets =
        ((request['bullets'] as List?)?.cast<String>() ?? const <String>[])
            .where((b) => b.trim().isNotEmpty)
            .toList();
    final createdAt = DateTime.parse(request['created_at'] as String);
    final tone = toneFor(context, phase);
    final cheapest = offers
        .map((o) => (o['price'] ?? o['price_min'] ?? o['hourly_rate']) as num?)
        .whereType<num>()
        .fold<num?>(null, (a, b) => a == null ? b : (b < a ? b : a));

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(request['title'] as String,
                        style: TextStyle(
                            fontSize: 21,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: jayaloHead(context))),
                  ),
                  const SizedBox(width: 12),
                  StatusChip(label: _phaseTitle[phase]!, tone: tone),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                Text(
                    cheapest != null
                        ? 'Desde: '
                        : 'Aún sin ofertas',
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
                if (cheapest != null)
                  Text(fmtRD(cheapest),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                const Spacer(),
                _ProviderDots(count: offers.length),
              ]),
              if (bullets.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Detalles',
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in bullets)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(b,
                          style: TextStyle(fontSize: 12, color: cs.onSurface)),
                    ),
                ]),
              ],
              const SizedBox(height: 18),
              Text(
                  'Publicada: ${formatDayLabel(createdAt)} · ${formatTimeHM(createdAt)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(_phaseCopy[phase]!,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        // CTA: "Ver N ofertas" (violeta, solo navega — aceptar vive por oferta
        // en la hoja). Reserva el alto de la barra flotante para no quedar tapado.
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 12 + navBarReservedSpace(context)),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999))),
                child: const Text('Volver'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onSeeOffers,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999))),
                child: Text(offers.isEmpty
                    ? 'Ver ofertas'
                    : 'Ver ${offers.length} oferta${offers.length == 1 ? '' : 's'}'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Círculos anónimos apilados = proveedores que ofertaron (las ofertas son
/// anónimas; solo se insinúa cuántas hay).
class _ProviderDots extends StatelessWidget {
  const _ProviderDots({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final shown = count > 3 ? 3 : count;
    return SizedBox(
      width: 28.0 + (shown - 1) * 18,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer,
                  border: Border.all(color: cs.surfaceContainerLowest, width: 2),
                ),
                child: Icon(Icons.person, size: 15, color: cs.onPrimaryContainer),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de oferta dentro de la hoja: precio grande, chip verde "Más
/// económica" en la más barata, mensaje a 2 líneas y su estado. Tocarla abre
/// `showOfferSheet` (aceptar/rechazar), sin cambiar ese flujo.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.cheapest,
    required this.statusChip,
    required this.onTap,
  });

  final Map<String, dynamic> offer;
  final bool cheapest;
  final Widget statusChip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final message = offer['message'] as String? ?? '';
    return JayaloCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(offerPriceLabel(offer),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context))),
            const SizedBox(width: 8),
            if (cheapest)
              StatusChip(
                  label: 'Más económica',
                  tone: Theme.of(context).brightness == Brightness.dark
                      ? JayaloStatus.unlockedDark
                      : JayaloStatus.unlockedLight),
            const Spacer(),
            statusChip,
          ]),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
