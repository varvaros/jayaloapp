import 'dart:async';

import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/money.dart';
import '../shared/brand_kit.dart';
import '../shared/celebration.dart';
import '../shared/onboarding_store.dart';
import 'request_status_screen.dart' show offerPriceLabel;

void showOfferSheet(BuildContext context, Map<String, dynamic> request,
    Map<String, dynamic> offer,
    {required bool hasAcceptedElsewhere}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Sube por encima de TODO, incluida la barra flotante del shell: así el
    // botón "Aceptar" nunca queda detrás del navbar (pedido PO). Sin esto el
    // sheet se apila en el navigator interno del shell y el navbar (que es un
    // bottomNavigationBar) lo tapa por abajo.
    useRootNavigator: true,
    // "Que suba más lenta y desacelere al llegar al final" (pedido PO):
    // easeOutCubic arranca rápido y frena suave; 520 ms lo hace notable sin
    // sentirse pesado. Se logra sin un controller propio (que rompía el
    // arrastre-para-cerrar en versiones anteriores) — `sheetAnimationStyle`
    // solo ajusta la curva/duración de la transición estándar.
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    // Altura FIJA casi al tope (92%, pedido PO: "los detalles de la oferta
    // deben subir casi al tope de la ventana") — misma técnica del sheet de la
    // lista (altura fija, sin DraggableScrollableSheet: el DSS anidado se
    // atascaba y no cerraba — gotcha documentado en request_status_screen).
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * .92,
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            // Despeja el teclado + el inset del sistema (la barra flotante ya no
            // tapa porque este sheet va por el navigator raíz).
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.paddingOf(ctx).bottom +
                24),
        child: _OfferSheetBody(
            offer: offer,
            request: request,
            hasAcceptedElsewhere: hasAcceptedElsewhere),
      ),
    ),
  );
}

/// Marquesina de las fotos que el proveedor subió en la oferta: una tira
/// horizontal que se desliza sola y en bucle (pedido PO). Tocar una foto abre
/// el visor a pantalla completa. Si no hay fotos, no se dibuja nada.
class _OfferPhotoMarquee extends StatefulWidget {
  const _OfferPhotoMarquee({required this.urls});
  final List<String> urls;

  @override
  State<_OfferPhotoMarquee> createState() => _OfferPhotoMarqueeState();
}

class _OfferPhotoMarqueeState extends State<_OfferPhotoMarquee> {
  final _ctrl = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Arranca el auto-desplazamiento tras el primer layout (cuando ya hay
    // maxScrollExtent). ~50 px/s: lento, tipo escaparate.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_ctrl.hasClients) return;
      final max = _ctrl.position.maxScrollExtent;
      if (max <= 0) return; // una sola foto o cabe sin desbordar: sin marquesina
      var next = _ctrl.offset + 1.5;
      if (next >= max) next = 0; // vuelta al inicio
      _ctrl.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => showPhotoViewer(context, widget.urls, initialIndex: i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: JayaloNetworkImage(
              widget.urls[i],
              width: 240,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 240,
                height: 150,
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferSheetBody extends StatefulWidget {
  const _OfferSheetBody({
    required this.offer,
    required this.request,
    required this.hasAcceptedElsewhere,
  });
  final Map<String, dynamic> offer;
  final Map<String, dynamic> request;
  final bool hasAcceptedElsewhere;
  @override
  State<_OfferSheetBody> createState() => _OfferSheetBodyState();
}

class _OfferSheetBodyState extends State<_OfferSheetBody> {
  bool _busy = false;

  /// Espejo del progreso del hold "Mantener para aceptar" → la mascota que se
  /// infla + ¡PUM! (pedido PO 2026-07-23: la MISMA animación del desbloqueo,
  /// también al aceptar). Cero timers propios; lo escribe el propio botón.
  final ValueNotifier<double> _acceptProgress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _acceptProgress.dispose();
    super.dispose();
  }

  // Info pública ANÓNIMA del proveedor (pedido PO 2026-07-22, paridad web):
  // reputación, verificado y tiempo de respuesta. `null` mientras carga.
  BusinessRating? _rep;
  bool? _verified;

  /// Alias estable durante la vida de la hoja (derivado del id de la oferta,
  /// no aleatorio por frame como la web) — es la etiqueta "Proveedor 2820".
  late final String _alias =
      'Proveedor ${1000 + (widget.offer['id'].hashCode.abs() % 9000)}';

  @override
  void initState() {
    super.initState();
    _loadProvider();
    unawaited(onboardingStore.ensureLoaded());
  }

  Future<void> _loadProvider() async {
    final bid = widget.offer['business_id'] as String?;
    if (bid == null) return;
    try {
      final res = await Future.wait([
        businessRatings([bid]),
        businessesVerified([bid]),
      ]);
      if (!mounted) return;
      setState(() {
        _rep = (res[0] as Map<String, BusinessRating>)[bid];
        _verified = (res[1] as Map<String, bool>)[bid];
      });
    } catch (_) {/* best-effort: si falla, se omite el bloque */}
  }

  /// "Respondió en ~Xh": del `created_at` de la solicitud al de la oferta.
  String? get _responseLabel {
    final ra = widget.request['created_at'] as String?;
    final oa = widget.offer['created_at'] as String?;
    if (ra == null || oa == null) return null;
    final diff = DateTime.tryParse(oa)?.difference(DateTime.tryParse(ra) ??
        DateTime.now());
    if (diff == null || diff.isNegative) return null;
    if (diff.inMinutes < 60) return 'Respondió en ~${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Respondió en ~${diff.inHours} h';
    return 'Respondió en ~${diff.inDays} d';
  }

  void _openStore() {
    final bid = widget.offer['business_id'] as String?;
    if (bid == null) return;
    context.push('/store/$bid?alias=${Uri.encodeComponent(_alias)}');
  }

  /// Bloque de encabezado del proveedor: alias tocable (→ tienda) + reputación
  /// + verificado + tiempo de respuesta.
  Widget _providerHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rep = _rep;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(kCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openStore,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.storefront_outlined, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(_alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: jayaloHead(context))),
                    ),
                    if (_verified == true) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified,
                          size: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? JayaloColors.dSuccess
                              : JayaloColors.success),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Wrap(spacing: 10, runSpacing: 2, children: [
                    if (rep != null && rep.count > 0)
                      _metaChip(Icons.star_rounded,
                          '${rep.avg.toStringAsFixed(1)} (${rep.count})',
                          color: const Color(0xFFF2B705))
                    else
                      _metaChip(Icons.star_border_rounded, 'Sin reseñas'),
                    if (_responseLabel != null)
                      _metaChip(Icons.schedule_outlined, _responseLabel!),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? cs.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(text,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }

  /// Bloque de detalle estructurado de la oferta (pedido PO 2026-07-21: los
  /// detalles se veían diminutos → distribuirlos como opciones bien diagramadas
  /// aprovechando el espacio del sheet). Cada campo presente = una FILA ancha:
  /// ícono en pastilla + etiqueta + valor. Solo se muestran los que existen.
  List<Widget> _detailBlock(BuildContext context) {
    final o = widget.offer;
    String? s(String k) {
      final v = o[k] as String?;
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    }

    num? n(String k) => o[k] as num?;
    final colors = ((o['product_colors'] as List?)?.cast<String>() ?? const [])
        .where((c) => c.trim().isNotEmpty)
        .toList();

    // (ícono, etiqueta, valor)
    final rows = <(IconData, String, String)>[
      if (s('product_brand') != null)
        (Icons.sell_outlined, 'Marca', s('product_brand')!),
      if (colors.isNotEmpty) (Icons.palette_outlined, 'Color', colors.join(', ')),
      if (s('product_warranty') != null)
        (Icons.verified_outlined, 'Garantía', s('product_warranty')!),
      if (s('delivery_time') != null)
        (Icons.local_shipping_outlined, 'Entrega', s('delivery_time')!),
      if (o['offers_shipping'] == true)
        (
          Icons.local_shipping_outlined,
          'Envío',
          n('shipping_price') != null ? fmtRD(n('shipping_price')!) : 'Gratis'
        ),
      if (o['offers_installation'] == true)
        (
          Icons.build_outlined,
          'Instalación',
          n('installation_price') != null
              ? fmtRD(n('installation_price')!)
              : 'Gratis'
        ),
      if (o['requires_evaluation'] == true)
        (
          Icons.content_paste_search_outlined,
          'Evaluación',
          n('evaluation_price') != null ? fmtRD(n('evaluation_price')!) : 'Gratis'
        ),
      if (s('availability_note') != null)
        (Icons.event_available_outlined, 'Disponibilidad', s('availability_note')!),
      if (s('estimated_duration') != null)
        (Icons.timelapse_outlined, 'Duración', s('estimated_duration')!),
    ];
    if (rows.isEmpty) return const [];
    final cs = Theme.of(context).colorScheme;

    // Cada dato = un TILE (ícono arriba, etiqueta tenue, valor fuerte) en una
    // rejilla de 2 columnas (pedido PO 2026-07-22: desglosar la info de forma
    // estética aprovechando el espacio, no una fila corrida).
    Widget tile(IconData icon, String label, String value) => Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: cs.primary),
              ),
              const SizedBox(height: 10),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .3,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.2,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );

    final tiles = [for (final r in rows) tile(r.$1, r.$2, r.$3)];
    final grid = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      grid.add(Padding(
        padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 10 : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ],
          ),
        ),
      ));
    }
    return [const SizedBox(height: 18), ...grid];
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    final cs = Theme.of(context).colorScheme;
    final photos = ((o['image_urls'] as List?)?.cast<String>() ?? const <String>[])
        .where((u) => u.isNotEmpty)
        .toList();
    // ¿Se muestra el hold de aceptar? Si sí, se pinta la mascota que se infla
    // por encima (IgnorePointer: nunca roba el toque del botón).
    final showAccept = st == 'pending' && !widget.hasAcceptedElsewhere;
    // Detalles scrolleables arriba + acciones FIJAS abajo: con el sheet casi a
    // pantalla completa, el botón de aceptar queda siempre a mano.
    return Stack(
      children: [
        Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _providerHeader(context),
                  const SizedBox(height: 16),
                  if (photos.isNotEmpty) ...[
                    _OfferPhotoMarquee(urls: photos),
                    const SizedBox(height: 16),
                  ],
                  Text(offerPriceLabel(o),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: jayaloHead(context))),
                  ..._detailBlock(context),
                  if ((o['message'] as String? ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(o['message'] as String,
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 20),
                ]),
          ),
        ),
        if (st == 'pending' && !widget.hasAcceptedElsewhere) ...[
          // El hold ES el botón de aceptar (pedido PO): un solo gesto, sin
          // hoja de confirmación intermedia; el helper explica la regla.
          Text(
              'Puedes aceptar hasta 3 ofertas por solicitud. Es gratis; cada '
              'proveedor que elijas podrá desbloquear tu contacto.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          HoldCoachMark(
            gesture: 'accept',
            message: 'Mantén presionado para aceptar',
            tone: HoldToConfirmTone.free,
            progress: _acceptProgress,
            child: HoldToConfirmButton(
              tone: HoldToConfirmTone.free,
              // "Mantener para aceptar" (pedido PO 2026-07-21): el label enseña
              // el gesto — antes decía "Aceptar esta oferta" y parecía un tap.
              label: 'Mantener para aceptar',
              progress: _acceptProgress, // alimenta la mascota que se infla
              onConfirmed: _accept,
            ),
          ),
          TextButton(
              onPressed: _busy ? null : _reject, child: const Text('Rechazar')),
        ] else if (st == 'pending')
          const Text('Ya elegiste 3 finalistas para esta solicitud.',
              textAlign: TextAlign.center)
        else if (st == 'accepted' && !unlocked) ...[
          const Text('Oferta aceptada. El proveedor te contactará pronto.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          // Descartar un finalista aún no desbloqueado: libera el cupo y reabre
          // (server-side). Solo cuando NO está desbloqueado (paridad con la web).
          OutlinedButton.icon(
            onPressed: _busy ? null : _discard,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: .4)),
            ),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Descartar oferta'),
          ),
        ] else if (unlocked) ...[
          // Contacto desbloqueado: el siguiente paso es CONVERSAR, no calificar
          // (la calificación llega al cerrarse el chat, pedido PO 2026-07-21).
          const Text('Contacto desbloqueado. Ya pueden coordinar por el chat.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _openChat,
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Hablar con el proveedor'),
          ),
        ],
      ],
        ),
        if (showAccept)
          Positioned.fill(
            child: IgnorePointer(
              child: HoldMascotLayer(
                progress: _acceptProgress,
                // Baja: el detalle de la oferta ocupa arriba; la mascota vive
                // sobre el botón de aceptar, en el tercio inferior.
                alignment: const Alignment(0, .34),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _accept() async {
    // El hold del botón YA es la confirmación deliberada (pedido PO: sin hoja
    // intermedia). `_busy` evita el doble disparo si mantiene dos veces.
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    // El RPC arranca YA (en paralelo) mientras la mascota hace su "¡PUM!" en la
    // hoja — la animación no retrasa la aceptación. Handler inmediato para no
    // dejar el future sin oyente durante el PUM.
    final accepting = acceptOffer(offerId: widget.offer['id'] as String)
        .catchError((_) => false);
    if (!JayaloMotion.reduced(context)) {
      await Future<void>.delayed(JayaloMotion.mascotPum);
    }
    final accepted = await accepting;
    if (!mounted) return;
    if (accepted) {
      // 🎉 violeta + cotejo + confeti, con el aviso de reputación DENTRO de la
      // misma ventana violeta (pedido PO 2026-07-22): al terminar la animación
      // aparece el texto + "Lo entiendo", que cierra la celebración.
      await showAcceptCelebration(context, footer: _reputationFooter);
      if (!mounted) return;
      Navigator.pop(context); // cierra la hoja de la oferta
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta oferta ya no está disponible.')));
    }
  }

  /// Aviso de buen trato tras aceptar (pedido PO 2026-07-22): va DENTRO de la
  /// ventana violeta de la celebración, debajo de la animación. Blanco sobre
  /// violeta; `dismiss` cierra la celebración.
  Widget _reputationFooter(VoidCallback dismiss) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Cuida tu reputación',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 10),
                Text(
                  'Los proveedores son personas ocupadas que hacen un esfuerzo '
                  'por atenderte. Trátalos con respeto y responde a tiempo: al '
                  'finalizar, ellos también te valorarán.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: .92)),
                ),
                const SizedBox(height: 22),
                // Botón blanco (contraste sobre el violeta), texto violeta.
                FilledButton(
                  onPressed: dismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _brandViolet(context),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Lo entiendo',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
        ),
      );

  Color _brandViolet(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? JayaloColors.dPrimary
          : JayaloColors.primary;

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Rechazar oferta'),
              // El campo con la receta única de la app (relleno gris + radius):
              // antes iba "desnudo" y no se distinguía del fondo del diálogo.
              content: TextField(
                  controller: ctrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration:
                      filledField(d, '¿Por qué?', hint: 'Opcional')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Rechazar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await rejectOffer(
        offerId: widget.offer['id'] as String, reason: ctrl.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Descartar un finalista ACEPTADO aún no desbloqueado: pone la oferta en
  /// 'rejected' → la BD (trigger de conteo + reapertura) libera el cupo y
  /// reabre la solicitud. Solo se ofrece si NO está desbloqueado (paridad web).
  Future<void> _discard() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Descartar oferta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Se liberará un cupo y podrás elegir otra oferta.'),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration:
                          filledField(d, '¿Por qué?', hint: 'Opcional')),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Descartar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await rejectOffer(
        offerId: widget.offer['id'] as String, reason: ctrl.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Abre (o crea) la conversación de la oferta y navega al chat — la vía para
  /// coordinar tras desbloquear (reemplaza la calificación inline prematura).
  Future<void> _openChat() async {
    setState(() => _busy = true);
    String? convId;
    try {
      convId = await getOrCreateConversation(
          kind: 'offer', sourceId: widget.offer['id'] as String);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (convId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir el chat. Intenta de nuevo.')));
      return;
    }
    Navigator.pop(context); // cierra la hoja de la oferta
    context.push('/messages/$convId');
  }
}
