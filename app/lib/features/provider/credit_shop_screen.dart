/// Tienda de créditos IN-APP (Play Billing v1).
///
/// Sustituye al link-out al wallet web de ADR-0031: Play prohíbe llevar
/// al usuario a otro método de pago, así que la recarga ocurre aquí dentro.
///
/// Dos piezas a propósito:
/// - [CreditShopBody] es PURA (sin plugin, sin red, sin Supabase): todo lo que
///   pinta llega por parámetro. Es lo que testean los widget tests.
/// - [CreditShopScreen] carga los paquetes, arranca el servicio de Play y le
///   pasa los datos ya resueltos.
///
/// ⚠️ El precio que se pinta es SIEMPRE `ProductDetails.price` de Play
/// (localizado, y con impuesto donde Google lo recauda), nunca el `priceUSD`
/// de la BD. Y el «Ahorras X%» sale de `ProductDetails.rawPrice` (decisión PO
/// 2026-08-08): con el USD de la BD el % no cuadraba con los RD$ pintados al
/// lado — decía 9% donde el ahorro real era 10,5%.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/error_reporter.dart';
import '../../core/play_billing_service.dart';
import '../../data/repos.dart' show activeCreditPackages;
import '../../domain/credit_shop.dart';
import '../shell/floating_nav_bar.dart' show navBarReservedSpace;

/// Parte PURA de la tienda: sin plugin, sin red, sin Supabase. Todo lo que
/// pinta llega por parámetro, que es lo que la hace testeable.
class CreditShopBody extends StatefulWidget {
  const CreditShopBody({
    super.key,
    required this.tiers,
    required this.playPrices,
    required this.onBuy,
    this.busyProductId,
  });

  final List<ShopTier> tiers;

  /// playProductId -> precio YA formateado por Play (localizado, con impuesto
  /// donde Google lo recauda). Es el único precio que se muestra.
  final Map<String, String> playPrices;

  /// Recibe el id de producto de Play del paquete elegido.
  final void Function(String playProductId) onBuy;

  /// Paquete con una compra en curso: su CTA queda deshabilitado para no
  /// abrir dos hojas de Google encima.
  final String? busyProductId;

  @override
  State<CreditShopBody> createState() => _CreditShopBodyState();
}

class _CreditShopBodyState extends State<CreditShopBody> {
  // En el estado y NO en `build`: al empezar una compra el padre cambia
  // `busyProductId` y reconstruye; con el controlador creado en `build`, el
  // carrusel se iría de golpe a la primera tarjeta con la hoja de Google
  // abriéndose encima.
  final _pages = PageController(viewportFraction: .82);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiers = widget.tiers;
    final playPrices = widget.playPrices;
    // Una tarjeta sin precio de Play NO se pinta: significa que el id no está
    // dado de alta en la consola y el botón llevaría a un callejón sin salida.
    final visibles = tiers
        .where((t) => t.playProductId != null && playPrices.containsKey(t.playProductId))
        .toList();

    if (visibles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay paquetes disponibles ahora mismo.',
              textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          // PageView y no ListView: el diseño aprobado pide carrusel CON SNAP, y
          // `PageScrollPhysics` sobre un ListView solo engancha si cada ítem
          // mide justo el viewport. `viewportFraction` < 1 deja asomar la
          // siguiente tarjeta, que es lo que invita a deslizar.
          child: PageView.builder(
            controller: _pages,
            padEnds: false,
            itemCount: visibles.length,
            itemBuilder: (context, i) {
              final t = visibles[i];
              return _TierCard(
                tier: t,
                playPrice: playPrices[t.playProductId]!,
                busy: widget.busyProductId == t.playProductId,
                onBuy: () => widget.onBuy(t.playProductId!),
              );
            },
          ),
        ),
        Padding(
          // La ruta vive en el shell y la barra FLOTA sobre el cuerpo
          // (extendBody): sin esta reserva, el sello queda siempre debajo de
          // la píldora y en un 360×640 la píldora tapa el CTA "Comprar".
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + navBarReservedSpace(context)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Pago seguro con Google Play',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.playPrice,
    required this.onBuy,
    required this.busy,
  });

  final ShopTier tier;
  final String playPrice;
  final VoidCallback onBuy;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = tierName(tier.label);
    final success = dark ? JayaloColors.dSuccess : JayaloColors.success;
    final mutedFg = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Card(
        color: dark ? JayaloColors.dCard : JayaloColors.card,
        elevation: tier.isBestValue ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: tier.isBestValue
              ? BorderSide(color: dark ? JayaloColors.dPrimary : JayaloColors.primary, width: 2)
              : BorderSide(color: dark ? JayaloColors.dBorder : JayaloColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          // Center + scroll y NO un Column a secas: PageView da constraints
          // de alto EXACTAS, y con la fuente grande del sistema (ajuste de
          // accesibilidad) el contenido no cabe — sin esto, el CTA "Comprar",
          // último hijo, se recortaba en release sin franja amarilla.
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              if (name != null)
                Chip(
                  label: Text(name),
                  labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: dark ? JayaloColors.dForeground : JayaloColors.accentFg),
                  backgroundColor: dark ? JayaloColors.dAccent : JayaloColors.accent,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              if (tier.isPopular)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Más popular',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              if (tier.isBestValue)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Mejor precio',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: dark ? JayaloColors.dPrimary : JayaloColors.primary)),
                ),
              const SizedBox(height: 10),
              Text('${tier.points}',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Text('créditos'),
              const SizedBox(height: 6),
              Text('Hasta ${tier.maxUnlocks} clientes desbloqueados',
                  style: TextStyle(fontSize: 13, color: mutedFg)),
              if (tier.savingsPct > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ahorras ${tier.savingsPct}%',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: success)),
                ),
              const SizedBox(height: 14),
              // <- de Play, NUNCA tier.priceUSD.
              Text(playPrice,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              FilledButton(
                key: ValueKey('buy_${tier.playProductId}'),
                onPressed: busy ? null : onBuy,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Text('Comprar'),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla completa: carga paquetes + precios de Play y cablea las compras.
class CreditShopScreen extends StatefulWidget {
  const CreditShopScreen({super.key, this.loadPackages = activeCreditPackages});

  /// Inyectable solo para poder montar la pantalla completa en tests sin
  /// Supabase. En producción siempre es [activeCreditPackages].
  final Future<List<ShopPackage>> Function() loadPackages;

  @override
  State<CreditShopScreen> createState() => _CreditShopScreenState();
}

class _CreditShopScreenState extends State<CreditShopScreen> {
  // El servicio es GLOBAL y no se destruye con la pantalla: una compra pagada
  // puede llegar despues de que el usuario salga de aqui, y con un servicio
  // por pantalla ese evento moria con ella.
  final PlayBillingService _billing = playBilling;
  StreamSubscription<CreditPurchaseEvent>? _events;

  List<ShopTier> _tiers = const [];
  Map<String, String> _playPrices = const {};
  Map<String, ProductDetails> _products = const {};
  String? _busy;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _events = _billing.events.listen(_onEvent);
    unawaited(_load());
  }

  @override
  void dispose() {
    // Solo la SUSCRIPCION. El servicio sobrevive a la pantalla a proposito.
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // El stream y la recuperacion ANTES de nada: `start()` engancha
      // `purchaseStream` y ademas pide a Play las compras que quedaron a
      // medias, que en Android NO se re-entregan solas.
      await _billing.start();

      final packages = await widget.loadPackages();
      final ids = packages
          .map((p) => p.playProductId)
          .whereType<String>()
          .toSet();
      final resp = ids.isEmpty
          ? null
          : await _billing.loadProducts(ids);

      // ⚠️ El plugin calcula notFoundIDs = pedidos − devueltos SIN importar
      // la causa: un device sin Play o un BillingClient caído meten TODOS los
      // ids ahí (con o sin `error`). Eso NO es "producto sin dar de alta":
      // es un fallo de carga — estado de error con Reintentar, y sin falsa
      // alarma de configuración al tracker (cada device sin Play sería una).
      if (resp != null && (resp.error != null || resp.productDetails.isEmpty)) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No pudimos conectar con Google Play. Intenta de nuevo.';
        });
        return;
      }

      if (resp != null && resp.notFoundIDs.isNotEmpty) {
        // Play SÍ respondió con productos: lo que falta aquí es un alta
        // pendiente en la consola. La tarjeta no se pinta (el body filtra por
        // precio), pero es un fallo de configuración que nadie vería si no
        // se reporta.
        unawaited(reportError(
          StateError(
              'Play no conoce estos productos: ${resp.notFoundIDs.join(", ")}'),
          StackTrace.current,
        ));
      }

      final products = {
        for (final p in resp?.productDetails ?? const <ProductDetails>[])
          p.id: p,
      };
      if (!mounted) return;
      setState(() {
        // Los `rawPrice` de Play alimentan el "Ahorras X%" y la insignia:
        // el % tiene que salir de la misma moneda que el precio pintado al
        // lado, no del USD de la BD (decía 9% donde el ahorro real era 10,5%).
        _tiers = buildShopTiers(packages, rawPrices: {
          for (final e in products.entries) e.key: e.value.rawPrice,
        });
        _products = products;
        _playPrices = {
          for (final e in products.entries) e.key: e.value.price,
        };
        _loading = false;
      });
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar los paquetes. Revisa tu conexión.';
      });
    }
  }

  void _onEvent(CreditPurchaseEvent e) {
    if (!mounted) return;
    // Una compra RESTAURADA no es la compra en curso: llega por
    // `restorePurchases()` y puede aterrizar con la hoja de Google abierta
    // para OTRA compra. Si soltara el spinner o pintara avisos, el usuario
    // creería que su compra ya terminó y cancelaría un pago real. Su
    // desenlace feliz lo anuncia el listener global de `app.dart`.
    if (e.fromRestore) return;
    // Un evento de OTRO producto tampoco es el desenlace de la compra en
    // curso: un pago DIFERIDO de otra sesión que Google confirma en segundo
    // plano llega como `purchased` (no restaurada) y soltaría este spinner.
    // Los eventos sin producto (sintéticos: cancelar la hoja, error previo
    // al cobro) sí son del flujo vivo y deben soltar.
    final deOtraCompra =
        e.productId != null && _busy != null && e.productId != _busy;
    if (!deOtraCompra) setState(() => _busy = null);
    switch (e.kind) {
      case CreditPurchaseKind.credited:
        // El "Listo. Tienes N créditos." lo pinta SOLO el listener global de
        // `app.dart` (que además siembra el cache del saldo): pintarlo aquí
        // también encolaba dos snackbars de ~9 s por la misma compra.
        break;
      case CreditPurchaseKind.pending:
        // ⚠️ NUNCA decir que el pago falló: el usuario ya pagó y el dinero
        // está en Google. Solo falta que podamos confirmarlo.
        _snack('Estamos confirmando tu pago. Te avisamos en un momento.');
        break;
      case CreditPurchaseKind.canceled:
        // Sin ruido: el usuario cerró la hoja a propósito.
        break;
      case CreditPurchaseKind.failed:
        _snack('No se pudo completar la compra.');
        break;
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));

  Future<void> _buy(String playProductId) async {
    final product = _products[playProductId];
    if (product == null) return;
    setState(() => _busy = playProductId);
    try {
      // `false` = la hoja de Google NO se abrió (el plugin no lanza en ese
      // caso). El stream no va a emitir nada, así que nadie más soltaría el
      // spinner: hay que deshacer aquí.
      final opened = await _billing.buy(product);
      if (!opened) {
        if (!mounted) return;
        setState(() => _busy = null);
        _snack('No se pudo abrir el pago. Intenta de nuevo.');
      }
    } catch (e, s) {
      unawaited(reportError(e, s));
      if (!mounted) return;
      setState(() => _busy = null);
      _snack('No se pudo abrir el pago. Intenta de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? JayaloColors.dBackground : JayaloColors.background,
      appBar: AppBar(title: const Text('Recargar créditos')),
      body: Column(
        children: [
          _MascotBand(dark: dark),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(message: _error!, onRetry: _load)
                    : CreditShopBody(
                        tiers: _tiers,
                        playPrices: _playPrices,
                        busyProductId: _busy,
                        onBuy: _buy,
                      ),
          ),
        ],
      ),
    );
  }
}

/// Banda BLANCA con el Jayi dibujado bajo una lluvia de monedas (mockup
/// aprobado PO 2026-08-10, «fondo blanco, no violeta»): sustituye al
/// `mascot.png` estático de la banda violeta original.
class _MascotBand extends StatelessWidget {
  const _MascotBand({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dark ? JayaloColors.dCard : JayaloColors.card,
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x125D4826),
                      blurRadius: 18,
                      offset: Offset(0, 6)),
                ],
              ),
            ),
          ),
          const Positioned(right: 8, bottom: -2, child: _JayiMonedas()),
          Positioned(
            left: 20,
            bottom: 16,
            right: 150,
            child: Text(
              // «clientes», no «contactos»: el vocabulario de la tienda
              // (decisión PO 08-08, «Hasta N clientes desbloqueados»).
              'Recarga y sigue desbloqueando clientes',
              // Tope de líneas: anclado abajo en un Stack con Clip.none, sin
              // esto el texto crecía hacia ARRIBA con fuente grande en
              // pantallas estrechas y pintaba encima del AppBar.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: jayaloHead(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jayi bajo la lluvia de monedas (mockup aprobado PO 2026-08-10): monedas
/// doradas que caen con gravedad, REBOTAN en su cabeza con un chispazo y salen
/// girando alternando el lado; Jayi se agacha un pelín y pestañea con cada
/// impacto. Mismo patrón que el Jayi de Mis ofertas: painter propio, cero
/// assets nuevos, y frame fijo en tests y con «reducir movimiento».
class _JayiMonedas extends StatefulWidget {
  const _JayiMonedas();

  @override
  State<_JayiMonedas> createState() => _JayiMonedasState();
}

class _JayiMonedasState extends State<_JayiMonedas>
    with SingleTickerProviderStateMixin {
  /// Un SOLO controller: los tres impactos, el agacharse, el pestañeo y las
  /// chispas viven en la misma línea de tiempo (como el mockup CSS) y quedan
  /// sincronizados gratis.
  late final AnimationController _t = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4200));

  /// En widget-tests el bucle infinito rompe TODO `pumpAndSettle` de la
  /// pantalla (nunca "asienta"): frame fijo. `Platform.environment` y no
  /// `bool.fromEnvironment` (ese dart-define NO está definido bajo
  /// `flutter test` y el gate no gateaba).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estatico = _enTest || JayaloMotion.reduced(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (_, _) => CustomPaint(
        key: const ValueKey('jayi_monedas'),
        size: const Size(150, 196),
        painter: _JayiMonedasPainter(t: _t.value, estatico: estatico),
      ),
    );
  }
}

class _JayiMonedasPainter extends CustomPainter {
  _JayiMonedasPainter({required this.t, required this.estatico});

  /// 0..1: el ciclo completo (4,2 s) con impactos en .15, .45 y .75.
  final double t;

  /// Frame fijo (tests / «reducir movimiento»): Jayi quieto con una moneda
  /// posada en la cabeza y una chispa tenue.
  final bool estatico;

  static const _violetaTubo = Color(0xFF6B40EE);
  static const _cuerpoA = Color(0xFF7E56F5);
  static const _cuerpoB = Color(0xFF6438E8);
  static const _oro = Color(0xFFF2B705);

  /// Escala de Jayi dentro de la banda. NO es capricho: la banda mide 108 y
  /// el cuerpo de la escena (150×196) desborda hacia arriba POR DETRÁS del
  /// AppBar (el Scaffold pinta el AppBar encima del body) — el rebote entero
  /// tiene que caber por debajo de y≈88 o la moneda desaparecería en el aire
  /// a mitad de arco.
  static const _s = .82;

  /// Traslación del sistema local de Jayi (118×100, mismas coordenadas que el
  /// painter de Mis ofertas) dentro de la escena.
  static const _jayiX = 75 - 59 * _s;
  static const _jayiY = 196.0 - 100 * _s;

  /// Centro de la moneda posada en la cabeza (el punto de impacto).
  static const _reposo = Offset(_jayiX + 57 * _s, _jayiY + 20 * _s - 12);

  /// Instantes de impacto y hacia qué lado sale cada rebote.
  static const _impactos = [.15, .45, .75];
  static const _lados = [1.0, -1.0, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    _jayi(canvas);
    if (estatico) {
      _moneda(canvas, _reposo, 0, 1);
      _chispa(canvas, _reposo + const Offset(16, -4), 5.5, .8);
      return;
    }
    for (var i = 0; i < _impactos.length; i++) {
      _monedaEnCaida(canvas, _impactos[i], _lados[i]);
      _chispazo(canvas, _impactos[i], _lados[i]);
    }
  }

  /// Cuánto se agacha Jayi ahora mismo (0..1): un pulso seno de ~380 ms
  /// arrancando en cada impacto.
  double get _agacho {
    if (estatico) return 0;
    for (final ti in _impactos) {
      final u = (t - ti) / .09;
      if (u >= 0 && u <= 1) return math.sin(math.pi * u);
    }
    return 0;
  }

  /// Párpado (1 = ojo abierto): pestañeo de ~210 ms con cada impacto.
  double get _ojo {
    if (estatico) return 1;
    for (final ti in _impactos) {
      final u = (t - ti) / .05;
      if (u >= 0 && u <= 1) return 1 - .88 * math.sin(math.pi * u);
    }
    return 1;
  }

  void _jayi(Canvas canvas) {
    canvas.save();
    // El agacharse comprime desde los pies (pivote abajo): la cabeza es la
    // que absorbe el golpe.
    final k = _agacho;
    final pies = Offset(_jayiX + 59 * _s, _jayiY + 86 * _s);
    canvas.translate(pies.dx, pies.dy);
    canvas.scale(1 + .05 * k, 1 - .07 * k);
    canvas.translate(-pies.dx, -pies.dy);

    canvas.translate(_jayiX, _jayiY);
    canvas.scale(_s);

    final tubo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _violetaTubo;

    // Antenas.
    tubo.strokeWidth = 5;
    canvas.drawPath(
        Path()
          ..moveTo(47, 22)
          ..cubicTo(43, 14, 35, 11, 30, 14),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(65, 21)
          ..cubicTo(69, 13, 77, 10, 82, 13),
        tubo);

    // Cuerpo "tele".
    const bodyRect = Rect.fromLTWH(22, 20, 70, 66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cuerpoA, _cuerpoB],
        ).createShader(bodyRect),
    );

    // Ojo con pestañeo por impacto.
    canvas.save();
    canvas.translate(45, 44);
    canvas.scale(1, _ojo.clamp(.12, 1.0));
    canvas.drawCircle(Offset.zero, 14, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(5, 3), 5.2, Paint()..color = _cuerpoB);
    canvas.restore();

    // Bracitos relajados (aquí no sostienen nada).
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(24, 60)
          ..cubicTo(16, 66, 15, 75, 21, 80),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(94, 60)
          ..cubicTo(102, 66, 103, 75, 97, 80),
        tubo);
    canvas.drawCircle(const Offset(21, 81), 5.5, Paint()..color = _cuerpoA);
    canvas.drawCircle(const Offset(97, 81), 5.5, Paint()..color = _cuerpoA);

    canvas.restore();
  }

  /// Trayectoria de una moneda: cae con gravedad (ease-in), rebota en la
  /// cabeza (ease-out hacia arriba), recae acelerando y se desvanece.
  void _monedaEnCaida(Canvas canvas, double ti, double lado) {
    Offset pos;
    double rot, alpha = 1;
    final caidaIni = ti - .15;
    if (t >= caidaIni && t < ti) {
      final u = (t - caidaIni) / .15;
      pos = _reposo + Offset(0, -110 * (1 - u * u));
      rot = 2.6 * u;
    } else if (t >= ti && t < ti + .07) {
      final u = (t - ti) / .07;
      final e = 1 - (1 - u) * (1 - u);
      pos = _reposo + Offset(lado * 24 * e, -30 * e);
      rot = 2.6 + 2.1 * u;
    } else if (t >= ti + .07 && t < ti + .15) {
      final u = (t - (ti + .07)) / .08;
      pos = _reposo + Offset(lado * (24 + 20 * u), -30 + 60 * u * u);
      rot = 4.7 + 2.3 * u;
      if (u > .7) alpha = 1 - (u - .7) / .3;
    } else {
      return;
    }
    _moneda(canvas, pos, rot, alpha);
  }

  void _moneda(Canvas canvas, Offset c, double rot, double alpha) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    canvas.drawCircle(
        Offset.zero,
        14,
        Paint()
          ..color = _oro.withValues(alpha: .38 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(
        Offset.zero,
        12,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.24, -.36),
            colors: [
              const Color(0xFFFFEDB0).withValues(alpha: alpha),
              _oro.withValues(alpha: alpha),
              const Color(0xFFC98A00).withValues(alpha: alpha),
            ],
            stops: const [0, .55, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: 12)));
    canvas.drawCircle(
        Offset.zero,
        8.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFFFE9A8).withValues(alpha: alpha));
    final j = TextPainter(
      text: TextSpan(
          text: 'J',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8A5E00).withValues(alpha: alpha))),
      textDirection: TextDirection.ltr,
    )..layout();
    j.paint(canvas, -Offset(j.width / 2, j.height / 2 + .5));
    canvas.restore();
  }

  /// Chispazo dorado del golpe: dos estrellitas que crecen y se apagan.
  void _chispazo(Canvas canvas, double ti, double lado) {
    final u = (t - ti) / .085;
    if (u < 0 || u > 1) return;
    final k = math.sin(math.pi * u);
    _chispa(canvas, _reposo + Offset(lado * 16, -4), 6 * k, k);
    _chispa(canvas, _reposo + Offset(lado * 7, -13), 4.2 * k, k);
  }

  void _chispa(Canvas canvas, Offset c, double r, double alpha) {
    if (r <= .1 || alpha <= .01) return;
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
    canvas.drawPath(p, Paint()..color = _oro.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_JayiMonedasPainter old) =>
      old.t != t || old.estatico != estatico;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}
