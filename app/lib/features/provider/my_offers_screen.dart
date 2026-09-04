import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/router.dart' show openCreditShop;
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show MyRequestsScreen, timeAgo;
import '../client/request_status_screen.dart' show offerPriceLabel;
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';
import '../chat/widgets/rating_form.dart';
import 'unlock_flow.dart';
import '../shared/moneda.dart';

/// ¿Toca calificar al cliente por esta oferta? Completada + cliente conocido +
/// sin reseña previa.
///
/// ⚠️ DIVERGE A PROPÓSITO de la web (`ProviderOffersSection.tsx:705`), que
/// además exige `purchase_completed === true`. Copiar ese cuarto término dejó
/// el botón INVISIBLE PARA SIEMPRE en la app (hallazgo Critical de la revisión
/// final, 2026-08-01): en la app **nadie escribe esa columna** —
/// `markPurchaseCompleted` no tiene ningún llamador y
/// `mark_conversation_completed` no la toca—, así que una oferta cerrada desde
/// la app queda con `status='completed'` y `purchase_completed = NULL`.
///
/// La web tiene un flujo de DOS pasos (primero "¿se concretó la venta?", luego
/// el cierre); la app tiene uno solo: `status == 'completed'` YA significa que
/// el proveedor confirmó el cierre, porque es él quien pulsa "Marcar como
/// completado". Tres términos, no cuatro.
bool needsCustomerReview(
  Map<String, dynamic> offer,
  Set<String> reviewed,
) =>
    offer['status'] == 'completed' &&
    offer['customer_id'] != null &&
    !reviewed.contains(offer['id']);

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({
    super.key,
    this.fetchOffers = myOffers,
    this.fetchBalance = walletBalance,
    this.fetchReviewed = customerReviewsFor,
    this.fetchUnseen = unseenOfferIds,
    this.markSeen = markOfferSeen,
    this.leading = const HeaderAvatar(),
    this.actions = const [HeaderSaldo(), HeaderBell()],
  });

  /// Inyectables (mismo patrón que `MyBusinessView.pickImage`/`updateCover`):
  /// el default es la implementación real de `repos.dart`; los tests pasan
  /// dobles para no tocar Supabase.
  final Future<List<Map<String, dynamic>>> Function() fetchOffers;
  final Future<int?> Function() fetchBalance;
  final Future<Set<String>> Function(List<String> offerIds) fetchReviewed;

  /// Las ofertas que te aceptaron y aún no has abierto (= las que llevan
  /// borde), y cómo marcar una como vista. Ver [unseenOfferIds].
  final Future<Set<String>> Function() fetchUnseen;
  final Future<void> Function(String offerId) markSeen;

  /// Inyectables (mismo patrón que `ProviderInboxView.leading`/`.actions`):
  /// `HeaderAvatar`/`HeaderBell` tocan Supabase en su `initState` (vía
  /// `profileStore`/`notifCountStore`), que revienta si Supabase no está
  /// inicializado — los tests pasan widgets inertes.
  final Widget? leading;
  final List<Widget> actions;

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _offers = [];
  int? _balance;
  bool _loading = true;

  /// Ofertas de esta tanda que ya tienen reseña del cliente (una sola consulta).
  Set<String> _reviewed = {};

  /// Ofertas ACEPTADAS que todavía no has abierto (su `offer_accepted` sigue
  /// sin leer). Son las únicas que llevan borde: el borde marca lo NUEVO, no el
  /// estado (pedido PO 2026-08-21). Se vacía por oferta al tocarla.
  Set<String> _unseen = {};

  /// Las que YA marcaste vistas en esta sesión de pantalla. Existe por una
  /// carrera real: al tocar una oferta se navega al detalle y, al volver,
  /// `_refetch` vuelve a preguntarle al servidor quién sigue sin ver. Si el
  /// UPDATE de `read_at` todavía no había llegado —volver de inmediato es un
  /// gesto normal— el servidor la devolvía como no vista y **el borde
  /// reaparecía**, que es exactamente lo que el PO reportó. Restarlas hace la
  /// marca monótona: vista una vez, vista para siempre.
  final Set<String> _yaVistas = {};

  /// Segmento activo: 0 = Mis ofertas (lo que vendo), 1 = Mis pedidos (lo que
  /// compro). Arranca en ofertas — es el motivo principal por el que un
  /// proveedor entra acá.
  int _tab = 0;

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
    // Al volver al primer plano, refrescar el saldo (spec §6). Con Play
    // Billing la compra ocurre in-app, pero el saldo puede haber cambiado
    // igual (una compra pendiente que acreditó al reintentar).
    if (state == AppLifecycleState.resumed) _refetch();
  }

  Future<void> _refetch() async {
    final results =
        await Future.wait([widget.fetchOffers(), widget.fetchBalance()]);
    final offers = results[0] as List<Map<String, dynamic>>;
    // En lote, no por tarjeta, y las dos en paralelo: no dependen entre sí.
    // Best-effort las dos (`onError` por consulta y no un try/catch alrededor
    // del `.wait`): si falla una, la otra sigue valiendo. Sin la primera solo
    // se pierde el botón de calificar; sin la segunda, el borde de "nuevo".
    final (reviewed, unseen) = await (
      widget
          .fetchReviewed(offers.map((o) => o['id'] as String).toList())
          .onError((_, _) => <String>{}),
      widget.fetchUnseen().onError((_, _) => <String>{}),
    ).wait;
    if (!mounted) return;
    setState(() {
      _offers = offers;
      _balance = results[1] as int?;
      _reviewed = reviewed;
      _unseen = unseen.difference(_yaVistas);
      _loading = false;
    });
  }

  /// Al ABRIR una oferta queda vista: le quita el borde al instante (optimista)
  /// y marca su `offer_accepted` leída en el servidor. Gemela de
  /// `_markOfferSeen` del cliente — sin esto el borde no se quitaba NUNCA, que
  /// es justo lo que reportó el PO (2026-08-21).
  void _markSeen(String offerId) {
    if (!_unseen.contains(offerId)) return;
    _yaVistas.add(offerId);
    setState(() => _unseen = {..._unseen}..remove(offerId));
    // Sin await: la navegación no espera al servidor. `markSeen` ya se traga
    // sus propios errores, así que no hay futuro colgando sin dueño.
    widget.markSeen(offerId);
  }

  // Anclas de las tres secciones, para el salto rápido de abajo del
  // segmentado. Son `GlobalKey` porque `Scrollable.ensureVisible` necesita el
  // `BuildContext` YA MONTADO del encabezado al que se salta.
  final _kAceptadas = GlobalKey();
  final _kPendientes = GlobalKey();
  final _kHistorial = GlobalKey();

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
    // Las secciones que EXISTEN ahora mismo: no se ofrece saltar a un
    // encabezado que la lista no va a pintar. "Pendientes" siempre está.
    final saltos = <(String, GlobalKey)>[
      if (toUnlock.isNotEmpty) ('Aceptadas', _kAceptadas),
      ('Pendientes', _kPendientes),
      if (rest.isNotEmpty) ('Historial', _kHistorial),
    ];
    return Scaffold(
      body: Column(
        children: [
          VioletHeader(
            leading: widget.leading,
            title: 'Mis ofertas',
            actions: widget.actions,
          ),
          // Segmentado "Mis ofertas · Mis pedidos" (PO 2026-07-30).
          //
          // El eje NO es "¿oferta o solicitud?" sino "¿qué papel juego?": acá
          // vive TODO lo mío, lo que vendo y lo que compro. La pestaña
          // Solicitudes se queda intacta con la demanda AJENA — es la
          // superficie de ingresos del proveedor y meterla detrás de un
          // segmento le bajaría la mitad de la prominencia.
          //
          // Resuelve el agujero real: el proveedor podía crear una solicitud
          // desde el ＋ de la barra y después no tenía dónde encontrarla salvo
          // abriendo el menú lateral. Crear y consultar ahora están a la misma
          // profundidad.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PillSegmented(
              options: const ['Mis ofertas', 'Mis pedidos'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          // Salto rápido a cada sección (pedido PO 2026-08-22). La lista es
          // larga —cartera, aceptadas, pendientes e historial— y llegar al
          // final costaba varios dedos de scroll.
          //
          // Solo en "Mis ofertas": "Mis pedidos" es otra pantalla incrustada,
          // con sus propias secciones. Y solo si hay MÁS DE UNA a la que ir:
          // una píldora suelta que te lleva a donde ya estás es ruido.
          if (_tab == 0 && !_loading && saltos.length > 1)
            _SectionJump(items: saltos),
          Expanded(
            child: _tab == 1
                // La pantalla del cliente en modo incrustado: mismas tarjetas,
                // misma carga, mismo vacío, mismo pull-to-refresh. Cero
                // duplicación — ver `MyRequestsScreen.embedded`.
                ? const MyRequestsScreen(embedded: true)
                : _loading
                    ? const JayaloLoaderBlock()
                    : JayaloRefresh(
                        onRefresh: _refetch,
                        // `SingleChildScrollView` + `Column` y NO `ListView`:
                        // el salto a secciones lo exige. `ListView` monta solo
                        // lo visible, así que el ancla de "Historial" no
                        // existía todavía y `Scrollable.ensureVisible` no tenía
                        // a dónde ir — la tira fallaba EN SILENCIO justo con
                        // las listas largas, que son las que la necesitan (lo
                        // cazó su test, no el device).
                        //
                        // El coste es acotado: `_buildOfferList` ya construía
                        // TODAS las tarjetas en cada rebuild, así que lo único
                        // que se añade es montarlas. Son las ofertas de UN
                        // proveedor, y la cascada escalonada de entrada ya
                        // asume una lista de ese tamaño. Si algún día un
                        // proveedor acumula cientos, esto es lo primero que hay
                        // que volver perezoso (y entonces el salto necesita
                        // `scrollable_positioned_list`).
                        child: SingleChildScrollView(
                          // Sin esto el pull-to-refresh muere cuando el
                          // contenido no llena la pantalla.
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(
                            top: 12,
                            bottom: 12 + navBarReservedSpace(context),
                          ),
                          // Cascada de entrada (fade + slide) en cada tarjeta,
                          // igual que Solicitudes y Catálogo: `_ci` es el
                          // índice corrido para escalonar el stagger de arriba
                          // hacia abajo.
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _buildOfferList(toUnlock, pending, rest),
                          ),
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
      OnboardingGuide(
        guideKey: 'wallet.credits.v1',
        steps: onboardingCopy['wallet.credits.v1']!,
        child: _WalletCard(
          balance: _balance,
          tone: _balance == 0 ? _red : _green,
          onRecharge: _openWallet,
        ),
      ).cascadeIn(ci++),
    );
    if (toUnlock.isNotEmpty) {
      children.add(
        SectionHeader(
          key: _kAceptadas,
          text: '🏆 ¡Te aceptaron! Desbloquea el contacto',
        ),
      );
      for (final o in toUnlock) {
        children.add(_acceptedCard(o).cascadeIn(ci++));
      }
    }
    children.add(
      SectionHeader(key: _kPendientes, text: 'Pendientes (${pending.length})'),
    );
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
      children.add(SectionHeader(key: _kHistorial, text: 'Historial'));
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
    final price = offerPriceLabel(o);
    final nuevo = _unseen.contains(o['id']);
    return JayaloCard(
      // Fondo BLANCO (pedido PO 2026-07-22): antes la tarjeta iba teñida de
      // verde; ahora solo el botón lleva el verde.
      //
      // El BORDE verde no revive aquel tinte: marca que ESTO ES NUEVO. Solo
      // aparece mientras no hayas abierto la oferta y se va al tocarla (PO
      // 2026-08-21: "no se quita el borde que indica que es nuevo"). Antes iba
      // siempre puesto, porque marcaba el ESTADO "te aceptaron" (PO
      // 2026-08-19) — y un estado no se puede quitar de encima.
      //
      // 1 px y no 2: el PO lo quiso "50% más sutil". La marca tiene que
      // llamar la atención, no gritar.
      border: nuevo ? Border.all(color: tone.ink, width: 1) : null,
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
                  ? JayaloNetworkImage(
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
                //
                // Definición ÚNICA en `UnlockOfferButton` (unlock_flow.dart,
                // pedido PO 2026-09-04): la bandeja del proveedor reusa el
                // mismo widget para que ambas pantallas no puedan divergir. Se
                // pasa `onPressed: () => _openOffer(o)` (en vez de dejar que
                // el botón llame a `startUnlockFlow` por su cuenta) para
                // conservar el `_markSeen` que ya hacía `_openOffer` antes de
                // abrir el flujo.
                Align(
                  alignment: Alignment.centerLeft,
                  child: UnlockOfferButton(
                    offer: o,
                    onPressed: () => _openOffer(o),
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
    // `unlocked_at` GANA sobre el status (bug PO 2026-07-23: decía "Ya
    // ofertaste" con el contacto ya desbloqueado). Antes solo mostraba
    // "Desbloqueada" si el status era exactamente 'accepted'; si estaba
    // desbloqueada con otro status (p. ej. 'pending') caía al default. Misma
    // doctrina que `myOfferedRequestStatuses` y el inbox: desbloqueado manda.
    final (label, tone) = switch (st) {
      'completed' => ('Completada', offerBadgeTone(context, 'completed')),
      'rejected' => ('Rechazada', offerBadgeTone(context, 'rejected')),
      _ when unlocked => ('Desbloqueada', offerBadgeTone(context, 'unlocked')),
      'accepted' => ('Aceptada', offerBadgeTone(context, 'accepted')),
      _ => ('Ya ofertaste', offerBadgeTone(context, 'pending')),
    };
    final created = o['created_at'] as String?;
    final cs = Theme.of(context).colorScheme;
    // La oferta pendiente se puede editar/borrar.
    final pending = st == 'pending';
    // Borde verde de "te aceptaron y no lo has visto", igual que en
    // `_acceptedCard`. Aquí llegan las aceptadas que YA desbloqueaste (esas
    // salen de la sección "¡Te aceptaron!" y caen en Historial) y las
    // completadas; en la práctica casi todas llegan ya vistas, y por eso el
    // Historial se ve limpio.
    //
    // Antes la condición era `st == 'accepted' || st == 'completed'` a secas,
    // o sea el ESTADO: el borde no se quitaba nunca (PO 2026-08-21). Ahora
    // manda `_unseen`, igual que arriba. Nota: esto es una divergencia
    // DELIBERADA con la hoja del cliente, donde el verde sigue marcando la
    // oferta aceptada de forma permanente.
    final nuevo = _unseen.contains(o['id']);
    return JayaloCard(
      onTap: () => _openOffer(o),
      border: nuevo
          ? Border.all(
              color: offerBadgeTone(context, 'accepted').ink, width: 1)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  o['request_title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: 6),
          // Mockup aprobado 2026-08-10: el PRECIO en violeta (ya agrupado en
          // miles por fmtRD) · antigüedad tenue, y en las pendientes un
          // «Editar» explícito a la derecha — antes era prosa dentro del
          // subtítulo ("Toca para editar").
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  offerPriceLabel(o),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              if (created != null) ...[
                const SizedBox(width: 8),
                Text(
                  timeAgo(DateTime.parse(created)),
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
              if (pending) ...[
                const Spacer(),
                Text(
                  'Editar',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ],
          ),
          if (needsCustomerReview(o, _reviewed)) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _rateCustomer(o),
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('Calificar al cliente'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Abre el calificador bilateral en una hoja. No se toca
  /// `showOfferContactSheet`: el PO retiró de esa hoja el cierre de venta el
  /// 2026-07-23 y volver a meterle una acción de cierre iría contra eso.
  Future<void> _rateCustomer(Map<String, dynamic> o) async {
    final businessId = o['business_id'] as String?;
    final customerId = o['customer_id'] as String?;
    if (businessId == null || customerId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: CustomerRatingPanel(
          offerId: o['id'] as String,
          businessId: businessId,
          customerId: customerId,
          onDone: () => Navigator.pop(ctx),
        ),
      ),
    );
    if (mounted) await _refetch();
  }

  void _openOffer(Map<String, dynamic> o) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    // Abrirla = verla, vaya a donde vaya después. Va ANTES del reparto para
    // que los tres caminos (editar, desbloquear, historial) la marquen igual:
    // el borde dice "no lo has visto", no "no lo has desbloqueado".
    _markSeen(o['id'] as String);
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
    } else {
      // Historial (rechazada / completada / aceptada y desbloqueada, pedido PO
      // 2026-08-09): antes rechazada no hacía NADA y completada/desbloqueada
      // abría directo la hoja de contacto. Ahora todas llevan al DETALLE de
      // la solicitud (mismo push que usan las tarjetas de "Solicitudes para
      // ti" y las pendientes de arriba, sin `?edit=`): la pantalla ya sabe
      // mostrar "Ver mi oferta"/"Ver contacto" según el estado
      // (`_alreadyOfferedCard`), así que no hay que duplicar esa lógica aquí.
      context.push('/provider/request/${o['request_id']}').then((_) {
        if (mounted) _refetch();
      });
    }
  }

  Future<void> _openWallet() => openCreditShop(context);
}

/// Tarjeta de saldo (mockup aprobado PO 2026-08-10, sustituye a la "W1
/// ámbar" del 07): tarjeta BLANCA con la billetera en tesela verde y
/// "Recargar" en violeta — el violeta es LA acción, el verde solo acento del
/// dinero.
class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.balance,
    required this.tone,
    required this.onRecharge,
  });
  final int? balance;

  /// Ya no tiñe la TARJETA (mockup 08-10): con saldo 0 el NÚMERO hereda el
  /// tono de alerta del call-site (rojo); con saldo, la tinta de títulos.
  final StatusTone tone;
  final VoidCallback onRecharge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zero = (balance ?? 0) == 0;
    return JayaloCard(
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MonedaJayalo(size: 20),
                    const SizedBox(width: 6),
                    Text(
                      '${balance ?? '—'} crédito${balance == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: zero ? tone.ink : jayaloHead(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  'Tu saldo para desbloquear contactos',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: onRecharge,
                  child: const Text('Recargar'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Jayi con su moneda gigante (mockup aprobado 2026-08-10).
          const _JayiCoin(),
        ],
      ),
    );
  }
}

/// Jayi sosteniendo su moneda gigante (mockup aprobado PO 2026-08-10, «ponlo
/// que pestañe y listo»): painter propio, cero assets nuevos. Cuatro
/// movimientos suaves en bucle — Jayi flota, la moneda respira brillo dorado,
/// un destello la barre con chispas titilando, y el ojo PESTAÑEA. Con
/// «reducir movimiento» del sistema queda un frame fijo.
class _JayiCoin extends StatefulWidget {
  const _JayiCoin();

  @override
  State<_JayiCoin> createState() => _JayiCoinState();
}

class _JayiCoinState extends State<_JayiCoin> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  /// En widget-tests el bucle infinito rompe TODO `pumpAndSettle` de las
  /// pantallas que montan la tarjeta de saldo (nunca "asienta"): frame fijo.
  /// `Platform.environment` (no `bool.fromEnvironment`: ese dart-define NO
  /// está definido bajo `flutter test` y el gate no gateaba).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _bob.stop();
      _fx.stop();
    } else {
      if (!_bob.isAnimating) _bob.repeat(reverse: true);
      if (!_fx.isAnimating) _fx.repeat();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_bob, _fx]),
        builder: (_, _) => CustomPaint(
          size: const Size(118, 112),
          painter: _JayiCoinPainter(bob: _bob.value, fx: _fx.value),
        ),
      );
}

class _JayiCoinPainter extends CustomPainter {
  _JayiCoinPainter({required this.bob, required this.fx});

  /// 0..1 con repeat(reverse): el flote (0 = abajo, 1 = arriba).
  final double bob;

  /// 0..1 en bucle: brillo de la moneda, destello, chispas y pestañeo.
  final double fx;

  static const _violetaTubo = Color(0xFF6B40EE);
  static const _cuerpoA = Color(0xFF7E56F5);
  static const _cuerpoB = Color(0xFF6438E8);
  static const _oro = Color(0xFFF2B705);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(0, -5 * bob);
    final tubo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _violetaTubo;

    // Antenas.
    tubo.strokeWidth = 5;
    canvas.drawPath(
        Path()
          ..moveTo(47, 16)
          ..cubicTo(43, 8, 35, 5, 30, 8),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(65, 15)
          ..cubicTo(69, 7, 77, 4, 82, 7),
        tubo);

    // Cuerpo "tele".
    const bodyRect = Rect.fromLTWH(22, 14, 70, 66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cuerpoA, _cuerpoB],
        ).createShader(bodyRect),
    );

    // Ojo con PESTAÑEO: el párpado baja y sube en el último tramo del ciclo
    // (fx ∈ [.90, 1]) — un parpadeo de ~260 ms cada 2,6 s.
    var eyeScale = 1.0;
    if (fx >= .90) {
      eyeScale = 1 - .88 * math.sin(math.pi * (fx - .90) / .10);
    }
    canvas.save();
    canvas.translate(45, 38);
    canvas.scale(1, eyeScale.clamp(.12, 1.0));
    canvas.drawCircle(Offset.zero, 14, Paint()..color = Colors.white);
    canvas.drawCircle(
        const Offset(5, 3), 5.2, Paint()..color = _cuerpoB);
    canvas.restore();

    // Bracitos hacia la moneda.
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(27, 62)
          ..cubicTo(18, 70, 18, 80, 26, 86),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(88, 62)
          ..cubicTo(97, 70, 97, 80, 89, 86),
        tubo);

    // Moneda: halo que respira + oro + anillo + J + destello que la barre.
    const cCoin = Offset(58, 84);
    final glow = .5 + .5 * math.sin(2 * math.pi * fx);
    canvas.drawCircle(
        cCoin,
        26,
        Paint()
          ..color = _oro.withValues(alpha: .25 + .35 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(
        cCoin,
        26,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.24, -.36),
            colors: [Color(0xFFFFEDB0), _oro, Color(0xFFC98A00)],
            stops: [0, .55, 1],
          ).createShader(Rect.fromCircle(center: cCoin, radius: 26)));
    canvas.drawCircle(
        cCoin,
        19.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFFFE9A8));
    final j = TextPainter(
      text: const TextSpan(
          text: 'J',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A5E00))),
      textDirection: TextDirection.ltr,
    )..layout();
    j.paint(canvas, cCoin - Offset(j.width / 2, j.height / 2 + 1));
    if (fx < .6) {
      final t = fx / .6;
      canvas.save();
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: cCoin, radius: 26)));
      canvas.translate(32 + 52 * t, 84);
      canvas.rotate(.31);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 9, height: 64),
          Paint()
            ..color = const Color(0xFFFFF6DC)
                .withValues(alpha: .85 * math.sin(math.pi * t)));
      canvas.restore();
    }

    // Manitas por DELANTE de la moneda (la están sosteniendo).
    final mano = Paint()..color = _cuerpoA;
    canvas.drawCircle(const Offset(30, 86), 5.5, mano);
    canvas.drawCircle(const Offset(86, 86), 5.5, mano);

    // Chispas desfasadas alrededor.
    _chispa(canvas, const Offset(97, 58), 7, 0);
    _chispa(canvas, const Offset(20, 46), 5.5, .35);
    _chispa(canvas, const Offset(99, 30), 4.8, .65);
  }

  void _chispa(Canvas canvas, Offset c, double r, double phase) {
    final k = math.max(0.0, math.sin(2 * math.pi * (fx - phase)));
    if (k <= .01) return;
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * .28, c.dy - r * .28)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + r * .28, c.dy + r * .28)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * .28, c.dy + r * .28)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - r * .28, c.dy - r * .28)
      ..close();
    canvas.drawPath(p, Paint()..color = _oro.withValues(alpha: k));
  }

  @override
  bool shouldRepaint(_JayiCoinPainter old) =>
      old.bob != bob || old.fx != fx;
}

/// Tira de salto a las secciones de Mis ofertas.
///
/// NO es un filtro y no tiene estado seleccionado: no esconde nada, solo lleva
/// la vista al encabezado. Por eso son píldoras sueltas y no un
/// [PillSegmented], que promete "estás en esta pestaña" — prometer eso y no
/// cumplirlo es peor que no tener la tira.
class _SectionJump extends StatelessWidget {
  const _SectionJump({required this.items});

  /// Etiqueta y ancla de cada sección, en el orden en que aparecen abajo.
  final List<(String, GlobalKey)> items;

  void _jump(BuildContext context, GlobalKey key) {
    // Si la sección se fue entre el pintado y el toque (una recarga a
    // destiempo), no hay a dónde ir: mejor no hacer nada que reventar.
    final target = key.currentContext;
    if (target == null) return;
    JayaloHaptics.tabChange();
    Scrollable.ensureVisible(
      target,
      // Con "reducir animaciones" el salto es seco: el movimiento aquí es
      // cortesía, y la orden del usuario es llegar.
      duration: JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.page,
      curve: Curves.easeOut,
      // 0 = el encabezado queda pegado arriba del área visible.
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final (label, key) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: cs.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _jump(context, key),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        // Pesos ligeros, doctrina estética: nada de 700+.
                        fontWeight: FontWeight.w600,
                        // Gris, no violeta (pedido PO 2026-08-22). Y el MISMO
                        // gris que `SectionHeader` (`onSurfaceVariant`): la
                        // tira y los títulos a los que lleva hablan igual. El
                        // violeta se reserva para la acción, y esto es
                        // navegación.
                        color: cs.onSurfaceVariant,
                      ),
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
