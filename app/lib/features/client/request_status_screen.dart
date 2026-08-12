import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/money.dart';
import '../../domain/phase.dart';
import '../../domain/finalist_slots.dart';
import '../../domain/request_requirements.dart';
import 'my_requests_screen.dart' show phaseChip;
import 'offer_actions.dart';
import 'offer_requirement_coverage.dart';
import 'request_detail_sheet.dart';
import '../shared/brand_kit.dart';
import '../shared/collapsing_photo_panel.dart';
import '../shared/network_image.dart' show jayaloAvatarImage;
import '../shared/verified_badges.dart';
import '../../core/motion.dart';

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

/// `business_id` de cada negocio con el que la solicitud REALMENTE cerró, en
/// el detalle de una solicitud completada.
///
/// Filtra estrictamente por `status == 'completed'` — no por `'accepted'`: el
/// modelo de hasta 3 finalistas permite varias ofertas `accepted` a la vez
/// (`clientSlotsMessage`), y calificar a alguien con quien el cliente no
/// cerró de verdad sería incorrecto. Mismo criterio "por oferta, no un
/// ganador elegido" que `needsCustomerReview` en `my_offers_screen.dart` usa
/// del lado del proveedor.
///
/// Un panel por NEGOCIO distinto (deduplicado: el mismo negocio puede tener
/// más de una oferta completada en la misma solicitud) y en orden estable —
/// el de aparición en `offers`, no el de un `Set` sin garantías de orden.
List<String> completedReviewBusinessIds(List<Map<String, dynamic>> offers) {
  final seen = <String>{};
  final ids = <String>[];
  for (final o in offers) {
    if (o['status'] != 'completed') continue;
    final bizId = o['business_id'] as String?;
    if (bizId == null) continue;
    if (seen.add(bizId)) ids.add(bizId);
  }
  return ids;
}

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

  /// Razón de cierre por id de oferta, para las ofertas cuya CONVERSACIÓN ya
  /// está cerrada (ver `closedConversationReasons`): alimenta
  /// `OfferLite.closedReason` para que este detalle pueda mostrar la fase
  /// "Cerrada" (y POR QUÉ), igual que la lista. `offersStream` es realtime,
  /// así que las ofertas pueden cambiar bajo los pies;
  /// `_closedOfferIdsChecked` evita volver a consultar una oferta ya resuelta
  /// en cada emisión del stream.
  Map<String, ClosedReason> _closedOfferReasons = {};
  final Set<String> _closedOfferIdsChecked = {};

  /// Best-effort, como `_loadUnreadOffers`: si falla, el detalle se pinta sin
  /// la fase "Cerrada" en vez de romperse. Solo consulta ofertas
  /// aceptadas/completadas (las únicas con conversación) que todavía no se
  /// han revisado.
  Future<void> _refreshClosedOfferIds(List<Map<String, dynamic>> offers) async {
    final dealIds = [
      for (final o in offers)
        if ((o['status'] == 'accepted' || o['status'] == 'completed') &&
            !_closedOfferIdsChecked.contains(o['id'] as String))
          o['id'] as String,
    ];
    if (dealIds.isEmpty) return;
    _closedOfferIdsChecked.addAll(dealIds);
    final closed = await closedConversationReasons(dealIds);
    if (!mounted || closed.isEmpty) return;
    setState(() => _closedOfferReasons = {..._closedOfferReasons, ...closed});
  }

  @override
  void initState() {
    super.initState();
    supa
        .from('customer_requests')
        .select(
            'id,title,status,kind,bullets,user_id,created_at,image_urls,budget_min,budget_max,is_wholesale,$requestRequirementCols')
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
          // Fire-and-forget: no bloquea el build. Guardado por
          // `_closedOfferIdsChecked`, así que no repite consulta por cada
          // emisión del stream una vez resuelta una oferta.
          _refreshClosedOfferIds(offers);
          final offerLites = offers
              .map((o) => offerLite(o,
                  closedReason: _closedOfferReasons[o['id'] as String]))
              .toList();
          final phase = phaseForRequest(
            requestStatus: req['status'] as String,
            offers: offerLites,
          );
          // Solo tiene sentido cuando `phase` es `closed`, pero calcularla
          // siempre es barato (lista corta, ya en memoria) y no complica el
          // llamador con un `if`.
          final closedReason = closedReasonFor(offerLites);
          // Cuántas de las ofertas mostradas siguen sin abrir (número del CTA).
          final unreadCount =
              offers.where((o) => _unreadOfferIds.contains(o['id'])).length;
          final images =
              ((req['image_urls'] as List?)?.cast<String>() ?? const <String>[])
                  .where((u) => u.isNotEmpty)
                  .toList();
          // El layout vive en `RequestDetailBody` (público y testeable); acá
          // solo se arman los datos y los callbacks.
          return RequestDetailBody(
            request: req,
            phase: phase,
            closedReason: closedReason,
            offers: offers,
            images: images,
            unreadCount: unreadCount,
            leading: _CornerFab(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              onTap: _goBack,
            ),
            onOpenViewer: (i) =>
                showPhotoViewer(context, images, initialIndex: i),
            onSeeOffers: () => _showOffers(context, req, offers),
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
    final acceptedCount = list
        .where((o) => o['status'] == 'accepted' || o['status'] == 'completed')
        .length;
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
    // Identidad pública (avatar/nombre/sellos) de los negocios que ofertaron
    // (PO 2026-07-29): UN solo viaje para toda la hoja, no una consulta por
    // tarjeta. Best-effort: si falla, cada tarjeta se pinta sin cabecera de
    // identidad — nunca deja la hoja en blanco ni rota.
    Map<String, BusinessCardInfo> identities = {};
    try {
      identities = await businessesCardInfo([
        for (final o in list)
          if (o['business_id'] != null) o['business_id'] as String,
      ]);
    } catch (_) {
      identities = {};
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      sheetAnimationStyle: JayaloMotion.sheetRise,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // El frenado de la subida ("ver ofertas debe subir más lento", PO
      // 2026-07-21) ya no vive acá: subió a `JayaloMotion.sheetRise`, que es
      // lo que ahora usan TODAS las hojas de la app.
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
        identities: identities,
        acceptedCount: acceptedCount,
        closedReasons: _closedOfferReasons,
        initialUnread: _unreadOfferIds,
        onSeen: _markOfferSeen,
      ),
    );
  }
}

/// Cuerpo del detalle de la solicitud del cliente: panel de foto plegable +
/// hoja SIN scroll propio dentro del mismo `CustomScrollView`, y el CTA
/// anclado abajo, FUERA de ese scroll.
///
/// Público, sin estado y sin tocar Supabase **a propósito**. Este layout vivía
/// inline en el `build` de `RequestStatusScreen`, que sí necesita Supabase y
/// por eso ningún test de widget lo podía montar: los tests de regresión del
/// plegado montaban una RÉPLICA a mano de esta composición. Con esa réplica,
/// devolver `hasScrollBody` a su default AQUÍ —en el fichero que la gente
/// edita— dejaba la suite entera en verde y reintroducía el bug exacto que
/// costó un `BLOCKED`. Ahora los tests montan ESTE widget, no una copia.
///
/// La pantalla sigue armando los datos y los callbacks (`_goBack`,
/// `showPhotoViewer`, `_showOffers`); acá solo vive el layout.
class RequestDetailBody extends StatelessWidget {
  const RequestDetailBody({
    super.key,
    required this.request,
    required this.phase,
    required this.offers,
    required this.images,
    required this.unreadCount,
    required this.onSeeOffers,
    this.closedReason,
    this.leading,
    this.onOpenViewer,
  });

  final Map<String, dynamic> request;
  final RequestPhase phase;
  final List<Map<String, dynamic>> offers;

  /// Solo aplica cuando `phase` es `closed`; `null` en cualquier otra fase o
  /// cuando las conversaciones aceptadas no coinciden en la razón (ver
  /// `closedReasonFor`). Opcional para no romper a quien construya este
  /// widget sin ese dato — el chip cae al genérico "Cerrada".
  final ClosedReason? closedReason;

  /// URLs de foto ya filtradas (sin vacías). Vacía = panel con el ícono de fase.
  final List<String> images;

  /// Ofertas sin abrir: número del badge rojo del CTA.
  final int unreadCount;
  final VoidCallback onSeeOffers;

  /// Control flotante arriba a la izquierda del panel (el atrás de la
  /// pantalla). Va como `leading` de la barra, así que sobrevive al plegado.
  final Widget? leading;

  /// Abre el visor a pantalla completa en la foto `index`.
  final void Function(int index)? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    // La foto se PLIEGA al bajar (pedido PO 2026-08-01, portado del detalle
    // del proveedor): `CollapsingPhotoPanel` reemplaza al antiguo
    // `_AmberPanel` de alto fijo. La hoja va en un
    // `SliverFillRemaining(hasScrollBody: false)` — `true` (el default) se
    // probó y falló: con la hoja teniendo su propio `ListView` los dos
    // scrolls quedaban aislados (panel fijo en 300.0 mientras el título
    // scrolleaba solo por dentro). `false` deja que el `Column` sin scroll de
    // la hoja participe del scroll EXTERNO junto con el panel.
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              CollapsingPhotoPanel(
                images: images,
                fallbackIcon: phaseChip(phase, 0).$1,
                leading: leading,
                onOpenViewer: onOpenViewer,
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: RequestDetailSheet(
                  request: request,
                  phase: phase,
                  offers: offers,
                  closedReason: closedReason,
                ),
              ),
            ],
          ),
        ),
        // El CTA vive FUERA del scroll, anclado abajo por este Column: si
        // estuviera dentro se iría de pantalla justo cuando hace falta.
        RequestDetailCta(
          offers: offers,
          unreadCount: unreadCount,
          onSeeOffers: onSeeOffers,
        ),
      ],
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
    required this.identities,
    required this.acceptedCount,
    this.closedReasons = const {},
    required this.initialUnread,
    required this.onSeen,
  });

  final Map<String, dynamic> request;
  final List<Map<String, dynamic>> offers;
  final String? cheapestId;
  final Map<String, bool> verified;

  /// Razón de cierre por id de oferta (chat muerto), cargada best-effort por
  /// la pantalla (`_closedOfferReasons`): el chip de esa oferta dice "Chat
  /// cerrado"/"No concretada" en vez de un "En contacto" que ya no es verdad
  /// (pedido PO 2026-08-10). Ausente del mapa = conversación viva.
  final Map<String, ClosedReason> closedReasons;

  /// Avatar/nombre/sellos por `business_id`, cargados en un solo viaje por
  /// `_showOffers` (PO 2026-07-29). Un negocio ausente del mapa = tarjeta sin
  /// cabecera de identidad.
  final Map<String, BusinessCardInfo> identities;
  final int acceptedCount;
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
      hasAcceptedElsewhere:
          isClosedToOffers(widget.acceptedCount) && o['status'] == 'pending',
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.offers;
    // Los requisitos son de la SOLICITUD: se calculan una vez, no por oferta.
    final reqs = requirementsFromRow(widget.request);
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
                  'Puedes aceptar hasta 3 ofertas',
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
                        providerInfo: widget.identities[o['business_id']],
                        unread: _unread.contains(o['id']),
                        statusChip: offerStatusChip(
                            context, o, isClosedToOffers(widget.acceptedCount),
                            closedReason:
                                widget.closedReasons[o['id'] as String]),
                        coverage: requirementCoverage(
                          reqs,
                          OfferCapabilities(
                            offersShipping: o['offers_shipping'] == true,
                            offersInstallation: o['offers_installation'] == true,
                            hasFiscalReceipt: o['has_fiscal_receipt'] == true,
                            isStateSupplier: o['is_state_supplier'] == true,
                          ),
                        ),
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
  bool noSlotsLeft, {
  ClosedReason? closedReason,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final st = o['status'] as String;
  final (txt, tone) = switch (st) {
    // La conversación de esta oferta murió (pedido PO 2026-08-10): decir "En
    // contacto" sobre un chat cerrado es mentira — la solicitud ahora sigue
    // viva con las demás ofertas y este chip cuenta qué pasó con ESTA.
    'accepted' when closedReason == ClosedReason.notAgreed => (
      'No concretada',
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    ),
    'accepted' when closedReason != null => (
      'Chat cerrado',
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    ),
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
      noSlotsLeft
          ? (
              'Cupos llenos',
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

/// Cabecera de identidad del proveedor dentro de una `_OfferCard` (PO
/// 2026-07-29): avatar redondo (logo o el mismo ícono de tienda que usa la
/// hoja de detalle, `offer_actions.dart`), nombre y sellos. Público y sin
/// estado a propósito — `_OfferCard` es privado a este archivo, así que un
/// test de widget no puede montarlo desde afuera; este widget sí es
/// importable y testeable aislado.
///
/// `info == null` no pinta NADA (`SizedBox.shrink`): ni un "Proveedor"
/// fantasma ni un avatar vacío. Pasa eso cuando la consulta por lote falló o
/// el negocio no resolvió (borrado, suspendido).
class OfferCardProviderHeader extends StatelessWidget {
  const OfferCardProviderHeader({super.key, required this.info});

  final BusinessCardInfo? info;

  @override
  Widget build(BuildContext context) {
    final info = this.info;
    if (info == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                info.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: jayaloHead(context),
                ),
              ),
            ),
            const SizedBox(width: 5),
            VerifiedTick(
              whatsappVerified: info.whatsappVerified,
              idVerified: info.identityVerified || info.businessVerified,
              size: 14,
            ),
          ],
        ),
        // Sello "Tienda física" (PO 2026-08-12) — AUTODECLARADO, así que va en
        // su propia fila, debajo del nombre, y con la píldora teal `requisito`
        // en vez del ✓ verde de `VerifiedTick`: mezclarlos afirmaría una
        // verificación que Jayalo nunca hizo.
        if (info.hasPhysicalLocation) ...[
          const SizedBox(height: 3),
          StatusChip(
            label: 'Tienda física',
            icon: Icons.storefront_outlined,
            tone: Theme.of(context).brightness == Brightness.dark
                ? JayaloStatus.requisitoDark
                : JayaloStatus.requisitoLight,
          ),
        ],
      ],
    );
  }

  /// Avatar grande (64px, rounded 14) para el layout horizontal de la card.
  static Widget avatar(BusinessCardInfo? info, BuildContext context) {
    if (info == null) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.storefront_outlined,
            color: Theme.of(context).colorScheme.primary),
      );
    }
    final logoUrl = info.logoUrl;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        image: logoUrl != null
            ? DecorationImage(
                image: jayaloAvatarImage(logoUrl, 64, context),
                fit: BoxFit.cover)
            : null,
      ),
      child: logoUrl == null
          ? Icon(Icons.storefront_outlined,
              color: Theme.of(context).colorScheme.primary)
          : null,
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
    required this.coverage,
    this.unverified = false,
    this.unread = false,
    this.providerInfo,
  });

  final Map<String, dynamic> offer;
  final bool cheapest;
  final Widget statusChip;
  final VoidCallback onTap;

  /// Lo que el cliente exigió en la solicitud y si esta oferta lo cubre, ya
  /// cotejado por `requirementCoverage`. Vacío = no exigió nada cotejable, y
  /// entonces el bloque no se pinta.
  final List<({Requirement key, bool covered, String label})> coverage;

  /// La oferta aún no se ha abierto: borde grueso oscuro que lo indica (pedido
  /// PO 2026-07-23). Se quita al tocarla.
  final bool unread;

  /// El negocio del proveedor aún no está verificado por Jayalo — se avisa al
  /// cliente con un badge rojo (decisión PO 2026-07-20: ofertar ya no exige
  /// verificación, la transparencia pasa a este aviso). NO se fusiona con los
  /// sellos nuevos de `providerInfo`: este badge avisa de un riesgo, aquellos
  /// premian una virtud — son señales opuestas.
  final bool unverified;

  /// Avatar/nombre/sellos del negocio (PO 2026-07-29). `null` = no se pinta
  /// cabecera (best-effort: la consulta por lote falló, o el negocio no
  /// resolvió — borrado o suspendido). Nunca un "Proveedor" fantasma.
  final BusinessCardInfo? providerInfo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final message = offer['message'] as String? ?? '';
    return JayaloCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      border: unread ? Border.all(color: cs.primary, width: 2) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OfferCardProviderHeader.avatar(providerInfo, context),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OfferCardProviderHeader(info: providerInfo),
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
                        tone: dark
                            ? JayaloStatus.unlockedDark
                            : JayaloStatus.unlockedLight,
                      ),
                    const Spacer(),
                    statusChip,
                  ],
                ),
                if (unverified) ...[
                  const SizedBox(height: 4),
                  StatusChip(
                    label: 'Negocio sin verificar',
                    icon: Icons.gpp_maybe_outlined,
                    tone: dark
                        ? (bg: const Color(0x33F14E46), ink: const Color(0xFFF6A7A2))
                        : (bg: const Color(0xFFFDE8E8), ink: const Color(0xFFC0261C)),
                  ),
                ],
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
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
                OfferRequirementCoverage(coverage: coverage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
