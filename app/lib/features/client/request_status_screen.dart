import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
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

/// Precio "efectivo" con el que se comparan las ofertas: precio base + costo
/// de envío cuando el proveedor lo cobra (pedido PO: sumar el envío al precio
/// para el badge "Más económica"). `null` si la oferta no tiene un precio
/// numérico (a evaluar) — esas no entran a la comparación.
num? offerEffectivePrice(Map<String, dynamic> o) {
  final base = (o['price'] ?? o['price_min'] ?? o['hourly_rate']) as num?;
  if (base == null) return null;
  final ship =
      o['offers_shipping'] == true ? (o['shipping_price'] as num?) : null;
  return base + (ship ?? 0);
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
  // "En contacto", no "desbloqueado" (pedido PO 2026-07-23): el CLIENTE nunca
  // desbloquea nada — quien paga es el proveedor; para el cliente la fase es
  // simplemente que ya están en contacto.
  RequestPhase.unlocked: 'En contacto',
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

  /// Ids de las ofertas de esta solicitud cuya notificación `offer_new` sigue
  /// SIN LEER (= "sin abrir"). Alimentan el número del botón "Ver N ofertas" y
  /// el borde de cada oferta en la hoja. Se marca leída al abrir cada oferta.
  Set<String> _unreadOfferIds = {};

  @override
  void initState() {
    super.initState();
    supa
        .from('customer_requests')
        .select(
            'id,title,status,kind,bullets,user_id,created_at,image_urls,budget_min,budget_max,is_wholesale')
        .eq('id', widget.requestId)
        .single()
        .then((r) => mounted ? setState(() => _request = r) : null);
    _loadUnreadOffers();
  }

  /// Ofertas sin leer del usuario (best-effort). Solo importan las de esta
  /// solicitud; se filtran al cruzarlas con las ofertas mostradas.
  Future<void> _loadUnreadOffers() async {
    try {
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      final notifs = List<Map<String, dynamic>>.from(
        await supa
            .from('notifications')
            .select('entity_id')
            .eq('user_id', uid)
            .eq('kind', 'offer_new')
            .isFilter('read_at', null),
      );
      if (!mounted) return;
      setState(() => _unreadOfferIds = notifs
          .map((n) => n['entity_id'] as String?)
          .whereType<String>()
          .toSet());
    } catch (_) {}
  }

  /// Al ABRIR una oferta queda vista: marca su `offer_new` leída (best-effort) y
  /// quita el borde/número al instante. Cuando la solicitud se queda sin ofertas
  /// sin leer, su "Nuevas ofertas" desaparece de la lista.
  Future<void> _markOfferSeen(String offerId) async {
    if (!_unreadOfferIds.contains(offerId)) return;
    setState(() => _unreadOfferIds = {..._unreadOfferIds}..remove(offerId));
    try {
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      await supa
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .eq('kind', 'offer_new')
          .eq('entity_id', offerId)
          .isFilter('read_at', null);
      // Avisa a la LISTA de solicitudes que recompute su "Nuevas ofertas": vive
      // montada como pestaña del shell y escucha `requestsChanged`. Sin esto,
      // volver a la lista mostraba el estado viejo (bug PO 2026-07-23: "entré a
      // las ofertas y no se quita Nuevas ofertas") — el `.then` de la lista solo
      // recargaba al hacer pop, y no siempre disparaba.
      requestsChanged.value++;
    } catch (_) {}
  }

  /// Atrás robusto: si hay pila (se llegó con push desde la lista), vuelve;
  /// si no (deep-link de una notificación abre el detalle con go y no hay pila),
  /// cae al home en vez de quedarse muerto.
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/client');
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    if (req == null) {
      return Scaffold(
        body: Stack(
          children: [
            const JayaloLoaderBlock(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _CornerFab(
                    icon: Icons.arrow_back_ios_new,
                    onTap: _goBack,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: offersStream(widget.requestId),
        builder: (context, snap) {
          final offers = snap.data ?? const <Map<String, dynamic>>[];
          final phase = phaseForRequest(
            requestStatus: req['status'] as String,
            offers: offers.map(offerLite).toList(),
          );
          // Cuántas de las ofertas mostradas siguen sin abrir (número del CTA).
          final unreadCount =
              offers.where((o) => _unreadOfferIds.contains(o['id'])).length;
          return Column(
            children: [
              _AmberPanel(request: req, phase: phase, onBack: _goBack),
              Expanded(
                child: _DetailSheet(
                  request: req,
                  phase: phase,
                  offers: offers,
                  unreadCount: unreadCount,
                  onSeeOffers: () => _showOffers(context, req, offers),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Hoja de ofertas que sube sobre el detalle: cada oferta es una tarjeta;
  /// tocarla abre la MISMA `showOfferSheet` de siempre (aceptar/rechazar), sin
  /// tocar el flujo de aceptación.
  ///
  /// SIN `transitionAnimationController` custom: pasarle el controller de 2s
  /// del modal de crear (que es una transición de PÁGINA, no un sheet
  /// arrastrable) rompía el gesto de cerrar — al soltar el arrastre el sheet
  /// quedaba VARADO a media altura y nunca bajaba (bug conocido de Flutter con
  /// controllers custom + drag; reproducido en el Redmi). Con la animación
  /// estándar del sheet, arrastrar/tap fuera/atrás cierran como en el resto
  /// de la app.
  Future<void> _showOffers(
    BuildContext context,
    Map<String, dynamic> req,
    List<Map<String, dynamic>> offers,
  ) async {
    // Re-fetch fresco al abrir: con realtime el stream ya trae live, pero pedir
    // la lista actual garantiza que "ver ofertas" nunca salga vacío por un
    // desfase del stream (bug PO 2026-07-20).
    var list = offers;
    try {
      list = await offersForRequest(req['id'] as String);
    } catch (_) {
      // Sin red: se usa lo que trajo el stream.
    }
    if (!context.mounted) return;
    final hasAccepted = list.any(
      (o) => o['status'] == 'accepted' || o['status'] == 'completed',
    );
    final cheapest = cheapestOfferId(list);
    // Estado de verificación de los negocios que ofertaron (para el badge rojo
    // "Negocio sin verificar"). Best-effort: si falla, no se muestra el badge.
    Map<String, bool> verified = {};
    try {
      verified = await businessesVerified([
        for (final o in list)
          if (o['business_id'] != null) o['business_id'] as String,
      ]);
    } catch (_) {
      verified = {};
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // "Ver ofertas debe subir más lento" (pedido PO 2026-07-21): la misma
      // subida suave de la hoja de la oferta (arranca rápido, frena al llegar).
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 520),
        reverseDuration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      // Altura FIJA (70%), sin DraggableScrollableSheet: el DSS anidado en un
      // showModalBottomSheet se atascaba en su minChildSize al arrastrar hacia
      // abajo y el sheet NUNCA se cerraba (reproducido en el Redmi — "sube
      // pero no baja"). Con altura fija, el arrastre nativo del BottomSheet
      // (asa/encabezado), el tap fuera y el atrás cierran como siempre.
      builder: (ctx) => _OffersSheet(
        request: req,
        offers: list,
        cheapestId: cheapest,
        verified: verified,
        hasAccepted: hasAccepted,
        initialUnread: _unreadOfferIds,
        onSeen: _markOfferSeen,
      ),
    );
  }
}

/// Hoja de ofertas (nivel 3): lista de tarjetas; las que siguen SIN ABRIR
/// llevan borde. Con estado propio para quitar el borde al instante al tocar
/// una oferta; avisa al detalle (`onSeen`) para bajar el número del botón y, en
/// cascada, el punto rojo de la lista de solicitudes.
class _OffersSheet extends StatefulWidget {
  const _OffersSheet({
    required this.request,
    required this.offers,
    required this.cheapestId,
    required this.verified,
    required this.hasAccepted,
    required this.initialUnread,
    required this.onSeen,
  });

  final Map<String, dynamic> request;
  final List<Map<String, dynamic>> offers;
  final String? cheapestId;
  final Map<String, bool> verified;
  final bool hasAccepted;
  final Set<String> initialUnread;
  final ValueChanged<String> onSeen;

  @override
  State<_OffersSheet> createState() => _OffersSheetState();
}

class _OffersSheetState extends State<_OffersSheet> {
  late Set<String> _unread = {...widget.initialUnread};

  void _open(Map<String, dynamic> o) {
    final id = o['id'] as String?;
    if (id != null && _unread.contains(id)) {
      setState(() => _unread = {..._unread}..remove(id)); // quita el borde ya
      widget.onSeen(id); // marca leída + baja el número del botón
    }
    showOfferSheet(
      context,
      widget.request,
      o,
      hasAcceptedElsewhere: widget.hasAccepted && o['status'] == 'pending',
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.offers;
    return SizedBox(
      height: MediaQuery.of(context).size.height * .7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Ofertas',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
                const Spacer(),
                Text(
                  'Acepta la que más te convenga',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Todavía no hay ofertas.\nTe avisaremos con una notificación.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final o = list[i];
                      return _OfferCard(
                        offer: o,
                        cheapest: o['id'] == widget.cheapestId,
                        unverified: widget.verified[o['business_id']] == false,
                        unread: _unread.contains(o['id']),
                        statusChip: offerStatusChip(context, o, widget.hasAccepted),
                        onTap: () => _open(o),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Id de la oferta más barata (numérica) — la que lleva el chip verde "Más
/// económica" como orientación (sin decidir por el cliente).
String? cheapestOfferId(List<Map<String, dynamic>> offers) {
  String? id;
  num? best;
  var tied = false;
  var priced = 0; // ofertas vivas con un precio comparable
  for (final o in offers) {
    // Solo compiten por "Más económica" las ofertas vivas (una rechazada no
    // debería ganar el badge). Ordena por precio efectivo (precio + envío).
    final st = o['status'] as String?;
    if (st == 'rejected') continue;
    final p = offerEffectivePrice(o);
    if (p == null) continue;
    priced++;
    if (best == null || p < best) {
      best = p;
      id = o['id'] as String?;
      tied = false;
    } else if (p == best) {
      tied = true; // otra oferta iguala el precio más bajo
    }
  }
  // El badge SOLO orienta si hay con qué comparar: se necesita más de una
  // oferta con precio Y un ganador único (PO 2026-07-21: "si solo hay una
  // oferta no debe decir Más económica"; tampoco si el mínimo empata).
  if (priced < 2 || tied) return null;
  return id;
}

Widget offerStatusChip(
  BuildContext context,
  Map<String, dynamic> o,
  bool hasAccepted,
) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final st = o['status'] as String;
  final (txt, tone) = switch (st) {
    // "En contacto", no "Desbloqueada" (pedido PO 2026-07-23): vista del
    // CLIENTE — él nunca desbloquea, el proveedor ya lo contactó.
    'accepted' when o['unlocked_at'] != null => (
      'En contacto',
      dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight,
    ),
    'accepted' => (
      'Aceptada',
      // Azul claro (pedido PO 2026-07-21): el ámbar ya no marca "aceptada".
      dark ? JayaloStatus.offerAcceptedDark : JayaloStatus.offerAcceptedLight,
    ),
    'completed' => (
      'Completada',
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    ),
    'rejected' => (
      'Rechazada',
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    ),
    _ =>
      hasAccepted
          ? (
              'Otra aceptada',
              dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
            )
          : (
              'Pendiente',
              dark ? JayaloStatus.pendingDark : JayaloStatus.pendingLight,
            ),
  };
  return StatusChip(label: txt, tone: tone);
}

/// Botón circular flotante sobre el panel ámbar (la doctrina: en el detalle la
/// FOTO manda; no lleva header violeta, solo los controles flotando). El atrás
/// va a la izquierda; el ⋮ (menú) a la derecha.
class _CornerFab extends StatelessWidget {
  const _CornerFab({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    elevation: 1,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Tooltip(
          message: tooltip ?? '',
          child: Icon(icon, size: 18, color: jayaloHead(context)),
        ),
      ),
    ),
  );
}

/// Panel ámbar con la foto grande (cover) + miniaturas al borde derecho, o un
/// ícono de fase si la solicitud no trae fotos.
class _AmberPanel extends StatelessWidget {
  const _AmberPanel({
    required this.request,
    required this.phase,
    required this.onBack,
  });
  final Map<String, dynamic> request;
  final RequestPhase phase;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final am = _amber(context);
    final images =
        ((request['image_urls'] as List?)?.cast<String>() ?? const <String>[])
            .where((u) => u.isNotEmpty)
            .toList();
    // Sin foto, el panel se pinta LILA CLARO con el ícono violeta (pedido PO
    // 2026-07-19: "color lila claro al fondo que se ve debajo del
    // placeholder"); con foto sigue el ámbar de siempre detrás del cover.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ph = dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight;
    final (icon, _) = phaseChip(phase, 0);
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: 300 + topInset,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: images.isEmpty ? ph.bg : am.panel,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          // La foto LLENA todo el panel ámbar (cover) — si no hay foto queda
          // el placeholder (ícono de fase centrado sobre lila claro). Sin
          // cuadro interno. Tocarla abre el visor a pantalla completa.
          Positioned.fill(
            child: images.isEmpty
                ? Center(child: Icon(icon, size: 120, color: ph.ink))
                : GestureDetector(
                    onTap: () => showPhotoViewer(context, images),
                    child: JayaloNetworkImage(
                      images.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Center(child: Icon(icon, size: 120, color: am.ink)),
                    ),
                  ),
          ),
          // Miniatura de la 2ª foto pegada al borde derecho (máx. 2 fotos).
          if (images.length > 1)
            Positioned(
              top: topInset + 30,
              right: 0,
              child: GestureDetector(
                onTap: () => showPhotoViewer(context, images, initialIndex: 1),
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  child: JayaloNetworkImage(
                    images[1],
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(width: 76, height: 76, color: am.panel),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: Align(
                alignment: Alignment.topLeft,
                child: _CornerFab(
                  icon: Icons.arrow_back_ios_new,
                  tooltip: 'Atrás',
                  onTap: onBack,
                ),
              ),
            ),
          ),
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
    required this.unreadCount,
    required this.onSeeOffers,
  });

  final Map<String, dynamic> request;
  final RequestPhase phase;
  final List<Map<String, dynamic>> offers;

  /// Ofertas sin abrir: número del badge rojo sobre el botón "Ver N ofertas".
  final int unreadCount;
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
    // "Desde": el total efectivo (precio + envío) más bajo entre las ofertas.
    final cheapest = offers
        .map(offerEffectivePrice)
        .whereType<num>()
        .fold<num?>(null, (a, b) => a == null ? b : (b < a ? b : a));

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        request['title'] as String,
                        style: TextStyle(
                          // +1pt (pedido PO).
                          fontSize: 22,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusChip(label: _phaseTitle[phase]!, tone: tone),
                  ],
                ),
                // Pill "Al por mayor" dentro de la solicitud (pedido PO
                // 2026-07-22): chip violeta debajo del estado, no toca la
                // etiqueta de la lista. Solo en productos mayoristas.
                if (request['is_wholesale'] == true) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: StatusChip(
                      label: 'Al por mayor',
                      icon: Icons.inventory_2_outlined,
                      tone: Theme.of(context).brightness == Brightness.dark
                          ? JayaloStatus.respondedDark
                          : JayaloStatus.respondedLight,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      cheapest != null ? 'Desde: ' : 'Aún sin ofertas',
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (cheapest != null)
                      Text(
                        fmtRD(cheapest),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context),
                        ),
                      ),
                    const Spacer(),
                    _ProviderDots(count: offers.length),
                  ],
                ),
                if (bullets.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Detalles',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in bullets)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            b,
                            style: TextStyle(fontSize: 12, color: cs.onSurface),
                          ),
                        ),
                    ],
                  ),
                ],
                if (requestBudgetLabel(request['budget_min'] as num?,
                        request['budget_max'] as num?) !=
                    null) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.payments_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                          'Presupuesto estimado: ${requestBudgetLabel(request['budget_min'] as num?, request['budget_max'] as num?)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: jayaloHead(context))),
                    ),
                  ]),
                ],
                const SizedBox(height: 18),
                Text(
                  'Publicada: ${formatDayLabel(createdAt)} · ${formatTimeHM(createdAt)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  _phaseCopy[phase]!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // CTA único: "Ver N ofertas" (violeta, solo navega — aceptar vive por
          // oferta en la hoja). El "Volver" se quitó: duplicaba la flecha de
          // atrás flotante del panel (ambos hacían context.pop()). Reserva el
          // alto de la barra flotante para no quedar tapado.
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + navBarReservedSpace(context),
            ),
            // Badge rojo con el número de ofertas SIN ABRIR (pedido PO
            // 2026-07-23), en la esquina del botón — la "notificación" que dice
            // cuántas faltan por revisar.
            child: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              offset: const Offset(-6, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onSeeOffers,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    offers.isEmpty
                        ? 'Ver ofertas'
                        : 'Ver ${offers.length} oferta${offers.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
                  border: Border.all(
                    color: cs.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.person,
                  size: 15,
                  color: cs.onPrimaryContainer,
                ),
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
    this.unverified = false,
    this.unread = false,
  });

  final Map<String, dynamic> offer;
  final bool cheapest;
  final Widget statusChip;
  final VoidCallback onTap;

  /// La oferta aún no se ha abierto: borde grueso oscuro que lo indica (pedido
  /// PO 2026-07-23). Se quita al tocarla.
  final bool unread;

  /// El negocio del proveedor aún no está verificado por Jayalo — se avisa al
  /// cliente con un badge rojo (decisión PO 2026-07-20: ofertar ya no exige
  /// verificación, la transparencia pasa a este aviso).
  final bool unverified;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final message = offer['message'] as String? ?? '';
    return JayaloCard(
      onTap: onTap,
      // Sin abrir: borde grueso oscuro (violeta de marca) para destacarla.
      border: unread ? Border.all(color: cs.primary, width: 2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                offerPriceLabel(offer),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context),
                ),
              ),
              const SizedBox(width: 8),
              if (cheapest)
                StatusChip(
                  label: 'Más económica',
                  tone: Theme.of(context).brightness == Brightness.dark
                      ? JayaloStatus.unlockedDark
                      : JayaloStatus.unlockedLight,
                ),
              const Spacer(),
              statusChip,
            ],
          ),
          if (unverified) ...[
            const SizedBox(height: 6),
            StatusChip(
              label: 'Negocio sin verificar',
              icon: Icons.gpp_maybe_outlined,
              tone: dark
                  ? (bg: const Color(0x33F14E46), ink: const Color(0xFFF6A7A2))
                  : (bg: const Color(0xFFFDE8E8), ink: const Color(0xFFC0261C)),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
