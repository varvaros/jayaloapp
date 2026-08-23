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
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/error_reporter.dart';
import '../../core/play_billing_service.dart';
import '../../core/sfx.dart';
import '../../data/repos.dart' show activeCreditPackages, walletBalance;
import '../../domain/credit_shop.dart';
import '../shared/moneda.dart';
import '../shared/recharge_celebration.dart';
import '../shell/floating_nav_bar.dart' show navBarReservedSpace;

/// Reparte [n] monedas en filas, de ABAJO ARRIBA, para apilarlas en la
/// tarjeta: pirámide con un tope de 4 por fila (más no cabe en una tarjeta de
/// media pantalla) y cada fila con una menos que la de debajo.
///
/// Nunca devuelve filas vacías y la suma es siempre [n]: si alguna de las dos
/// cosas fallara, la pila pintaría huecos o perdería monedas.
List<int> pilaDeMonedas(int n) {
  final filas = <int>[];
  var quedan = n;
  var fila = math.min(4, (n / 2).ceil());
  while (quedan > 0) {
    final k = math.min(fila, quedan);
    filas.add(k);
    quedan -= k;
    fila = math.max(1, k - 1);
  }
  return filas;
}

/// Parte PURA de la tienda: sin plugin, sin red, sin Supabase. Todo lo que
/// pinta llega por parámetro, que es lo que la hace testeable.
class CreditShopBody extends StatefulWidget {
  const CreditShopBody({
    super.key,
    required this.tiers,
    required this.playPrices,
    required this.onBuy,
    this.busyProductId,
    this.pilaKeys,
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

  /// playProductId -> llave de la PILA de monedas de su tarjeta. La pantalla
  /// las pasa para saber de dónde despega el vuelo de monedas al acreditarse
  /// la compra; `null` (los tests del body) deja el body igual de puro.
  final Map<String, GlobalKey>? pilaKeys;

  @override
  State<CreditShopBody> createState() => _CreditShopBodyState();
}

class _CreditShopBodyState extends State<CreditShopBody> {
  // En el estado y NO en `build`: al empezar una compra el padre cambia
  // `busyProductId` y reconstruye; con el controlador creado en `build`, el
  // carrusel se iría de golpe a la primera tarjeta con la hoja de Google
  // abriéndose encima.
  // UNA tarjeta por pantalla y la siguiente asomando. Se probó a .47 (dos por
  // pantalla, como el ejemplo de tienda de juego) y el PO lo descartó el
  // 2026-08-22: «se siente muy pesado» — dos tarjetas llenas de números a la
  // vez no dejan mirar ninguna.
  //
  // `keepPage: false`: con el `true` de fábrica el controlador restaura al
  // montarse el offset guardado en el `PageStorage` de la ruta, y aquí ningún
  // scrollable lleva `PageStorageKey` (todos comparten ranura). La tienda tiene
  // que abrir SIEMPRE en el mismo sitio, y ese sitio es el paquete más barato:
  // abrir en el de US$211 no sería un detalle de scroll, parecería un empujón.
  final _pages = PageController(viewportFraction: .82, keepPage: false);

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

    final dark = Theme.of(context).brightness == Brightness.dark;
    // Tinta del sello sobre el violeta: blanca atenuada, NO `onSurfaceVariant`
    // (ese gris se pierde sobre el fondo nuevo).
    final selloFg = Colors.white.withValues(alpha: .86);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: vitrinaCreditos(dark)),
      child: Column(
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
                  // La pila crece con el PUESTO en la escalera, no con los
                  // créditos: un paquete de 200 no puede pintar 200 monedas, y
                  // lo que tiene que leerse de un vistazo es "este trae más".
                  monedas: 3 + 2 * math.min(i, 3),
                  pilaKey: widget.pilaKeys?[t.playProductId],
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
                Icon(Icons.lock_outline, size: 15, color: selloFg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Pago seguro con Google Play',
                      style: TextStyle(fontSize: 12.5, color: selloFg)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo VIOLETA del área de compra (mockup aprobado PO 2026-08-22, a partir
/// del ejemplo de tienda de juego que trajo el PO).
///
/// Solo cubre la zona de los paquetes: la banda del Jayi que va encima sigue
/// BLANCA y su animación no se toca. En oscuro baja de tono para que la
/// tarjeta (que ahí es `dSurfaceHighest`, más clara que el fondo) siga
/// separándose del violeta.
LinearGradient vitrinaCreditos(bool dark) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0, .58, 1],
      colors: dark
          ? const [Color(0xFF3A1F86), Color(0xFF24115C), Color(0xFF17093B)]
          : const [Color(0xFF7A4CF5), Color(0xFF5A2ED8), Color(0xFF47189E)],
    );

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.playPrice,
    required this.onBuy,
    required this.busy,
    required this.monedas,
    this.pilaKey,
  });

  final ShopTier tier;
  final String playPrice;
  final VoidCallback onBuy;
  final bool busy;

  /// Cuántas monedas apila la tarjeta (3, 5, 7 o 9): el tamaño del paquete
  /// contado en oro, que es lo que se lee antes que ningún número.
  final int monedas;

  /// Ancla de la pila: el vuelo de monedas de la acreditación despega de aquí.
  final GlobalKey? pilaKey;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = tierName(tier.label);
    final mutedFg = Theme.of(context).colorScheme.onSurfaceVariant;
    // En oscuro la tarjeta sube a `dSurfaceHighest` y NO al `dCard` del resto
    // de la app: sobre el violeta de la vitrina, el `dCard` queda casi tan
    // oscuro como el fondo y la tarjeta se pierde.
    final cardColor = dark ? JayaloColors.dSurfaceHighest : JayaloColors.card;
    final ink = dark ? JayaloColors.dForeground : JayaloColors.head;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      // Clip.none: el sello de ahorro se sale del borde derecho a propósito
      // (como en el ejemplo que trajo el PO). Cabe en el aire de 8 px entre
      // tarjeta y tarjeta, así que no pisa a la vecina.
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          Card(
            color: cardColor,
            // Explícito: sin esto M3 tiñe la superficie con el `surfaceTint`
            // según la elevación y el blanco de la tarjeta se va a lila.
            surfaceTintColor: Colors.transparent,
            shadowColor: const Color(0xFF1E0850),
            elevation: tier.isBestValue ? 10 : 6,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: tier.isBestValue
                  ? const BorderSide(color: kOroMoneda, width: 2.5)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              // Center + scroll y NO un Column a secas: PageView da constraints
              // de alto EXACTAS, y con la fuente grande del sistema (ajuste de
              // accesibilidad) el contenido no cabe — sin esto, el CTA "Comprar",
              // último hijo, se recortaba en release sin franja amarilla.
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tier.isBestValue)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: _PildoraOro(texto: 'MEJOR PRECIO'),
                        ),
                      // El chip ES la marca de "más popular" (PO 2026-08-22:
                      // el chip decía «Popular» y justo debajo ponía «Más
                      // popular» — lo mismo dos veces). El paquete que el
                      // admin marca se lleva el chip en VIOLETA lleno; los
                      // demás, el lila de siempre.
                      if (name != null)
                        Chip(
                          label: Text(name),
                          labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: tier.isPopular
                                  ? (dark
                                      ? JayaloColors.dPrimaryFg
                                      : JayaloColors.primaryFg)
                                  : (dark
                                      ? JayaloColors.dForeground
                                      : JayaloColors.accentFg)),
                          backgroundColor: tier.isPopular
                              ? (dark
                                  ? JayaloColors.dPrimary
                                  : JayaloColors.primary)
                              : (dark
                                  ? JayaloColors.dAccent
                                  : JayaloColors.accent),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      const SizedBox(height: 6),
                      _PilaMonedas(key: pilaKey, monedas: monedas),
                      // Wrap y no Row: en línea normalmente («55 créditos»),
                      // pero con la fuente grande del sistema «200 créditos»
                      // no cabe de una y tiene que poder partirse.
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text('${tier.points}',
                              style: TextStyle(
                                  fontSize: 44,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  color: ink)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text('créditos',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: ink)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Hasta ${tier.maxUnlocks} clientes desbloqueados',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, height: 1.3, color: mutedFg)),
                      const SizedBox(height: 18),
                      // <- de Play, NUNCA tier.priceUSD.
                      Text(playPrice,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: ink)),
                      const SizedBox(height: 14),
                      FilledButton(
                        key: ValueKey('buy_${tier.playProductId}'),
                        onPressed: busy ? null : onBuy,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
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
          if (tier.savingsPct > 0)
            Positioned(
              top: 20,
              right: -8,
              child: _SelloAhorro(pct: tier.savingsPct),
            ),
        ],
      ),
    );
  }
}

/// Contador de saldo del AppBar (pedido PO 2026-08-22, del contador que trae
/// el ejemplo): moneda + número, para que quien viene a recargar vea con
/// cuánto llega sin volver atrás.
///
/// Solo el número al lado de la moneda: «Tienes 38 créditos» entero no cabe
/// junto al título en un teléfono estrecho. El texto completo va en la
/// semántica, que es quien lo lee en voz alta.
class _ContadorSaldo extends StatefulWidget {
  const _ContadorSaldo({required this.saldo, required this.dark});
  final int saldo;
  final bool dark;

  @override
  State<_ContadorSaldo> createState() => _ContadorSaldoState();
}

class _ContadorSaldoState extends State<_ContadorSaldo>
    with SingleTickerProviderStateMixin {
  /// Golpecito al recibir un número nuevo: durante el vuelo de monedas el
  /// saldo sube aterrizaje a aterrizaje y el contador «recibe» cada moneda.
  /// Un pulso seno (1 → 1.12 → 1) y no un Tween: no hay estado intermedio
  /// que limpiar y se reencadena solo si otro aterrizaje llega antes de
  /// terminar el pulso anterior.
  late final AnimationController _pulso = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 170));

  @override
  void didUpdateWidget(_ContadorSaldo old) {
    super.didUpdateWidget(old);
    if (old.saldo != widget.saldo && !JayaloMotion.reduced(context)) {
      _pulso.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return Semantics(
      label: 'Tienes ${widget.saldo} créditos',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _pulso,
          builder: (context, child) => Transform.scale(
            scale: 1 + .12 * math.sin(math.pi * _pulso.value),
            child: child,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
            decoration: BoxDecoration(
              color: dark ? JayaloColors.dAccent : JayaloColors.accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MonedaJayalo(size: 20),
                const SizedBox(width: 6),
                Text('${widget.saldo}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: dark
                            ? JayaloColors.dForeground
                            : JayaloColors.accentFg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sello dorado que cuelga del borde de la tarjeta con el % de ahorro
/// (sustituye a la línea verde de texto: era lo que menos se veía de la
/// tarjeta y es lo que más pesa al elegir paquete).
class _SelloAhorro extends StatelessWidget {
  const _SelloAhorro({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD75E), kOroMoneda],
          ),
          borderRadius: BorderRadius.horizontal(
              left: Radius.circular(8), right: Radius.circular(4)),
          boxShadow: [
            BoxShadow(
                color: Color(0x4D1E0850), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Text('Ahorras $pct%',
            style: const TextStyle(
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: kTintaOro)),
      );
}

/// Píldora dorada del «MEJOR PRECIO» (sustituye al texto violeta de antes:
/// sobre la tarjeta blanca de la vitrina el oro es lo que canta).
class _PildoraOro extends StatelessWidget {
  const _PildoraOro({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: kOroMoneda,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(texto,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
                color: kTintaOro)),
      );
}

/// Pila de monedas de la tarjeta: la MISMA moneda que llueve en la banda del
/// Jayi ([pintarMoneda]), apilada en filas. Tamaño fijo para las cuatro
/// tarjetas —aunque una apile 3 y otra 9— para que las pilas queden alineadas
/// entre tarjetas vecinas.
class _PilaMonedas extends StatelessWidget {
  const _PilaMonedas({super.key, required this.monedas});
  final int monedas;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(176, 100),
        painter: _PilaPainter(monedas: monedas),
      );
}

class _PilaPainter extends CustomPainter {
  _PilaPainter({required this.monedas});
  final int monedas;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 17.0;
    final filas = pilaDeMonedas(monedas);

    // Sombra de apoyo: sin ella la pila flota sobre la tarjeta.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.width / 2, size.height - 3),
          width: (filas.first * 2.3 * r).clamp(0, size.width),
          height: 11),
      Paint()..color = const Color(0x1A3E3560),
    );

    var y = size.height - r - 4;
    for (final n in filas) {
      final paso = 2.3 * r;
      final x0 = size.width / 2 - (n - 1) * paso / 2;
      for (var i = 0; i < n; i++) {
        pintarMoneda(canvas, Offset(x0 + i * paso, y), r);
      }
      y -= 1.55 * r;
    }
  }

  @override
  bool shouldRepaint(_PilaPainter old) => old.monedas != monedas;
}

/// Pantalla completa: carga paquetes + precios de Play y cablea las compras.
class CreditShopScreen extends StatefulWidget {
  const CreditShopScreen({
    super.key,
    this.loadPackages = activeCreditPackages,
    this.fetchBalance = walletBalance,
  });

  /// Inyectable solo para poder montar la pantalla completa en tests sin
  /// Supabase. En producción siempre es [activeCreditPackages].
  final Future<List<ShopPackage>> Function() loadPackages;

  /// Saldo para el contador del AppBar. Inyectable por lo mismo; en producción
  /// es [walletBalance] (cacheado 60 s, así que abrir la tienda no añade una
  /// query por visita).
  final Future<int?> Function() fetchBalance;

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

  /// Saldo del contador del AppBar. `null` = todavía no se sabe: el contador
  /// no se pinta hasta tener el número (un "0 créditos" falso en una pantalla
  /// de recarga es de lo peor que se puede enseñar).
  int? _saldo;

  /// Anclas del vuelo de monedas: de la pila de la tarjeta comprada
  /// ([_pilaKeys], una por producto) al contador del AppBar ([_keyContador]).
  final _pilaKeys = <String, GlobalKey>{};
  final _keyContador = GlobalKey();

  /// El vuelo vivo, si lo hay. Vive en un OverlayEntry (por ENCIMA del AppBar:
  /// las monedas tienen que aterrizar dentro de él) y hay que retirarlo a mano
  /// si la pantalla muere a mitad de vuelo.
  OverlayEntry? _vuelo;

  @override
  void initState() {
    super.initState();
    _events = _billing.events.listen(_onEvent);
    unawaited(_load());
    unawaited(_cargarSaldo());
  }

  @override
  void dispose() {
    // Solo la SUSCRIPCION. El servicio sobrevive a la pantalla a proposito.
    _events?.cancel();
    _vuelo?.remove();
    _vuelo = null;
    super.dispose();
  }

  /// Centro, en coordenadas globales, del widget anclado a [key].
  Offset? _centroDe(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// El vuelo de monedas de la acreditación (mockup «enjambre cometa»
  /// aprobado PO 2026-08-23): las cinco estallan sobre la tarjeta comprada y
  /// salen disparadas una a una al contador, que sube aterrizaje a aterrizaje.
  ///
  /// Cae al salto seco (número nuevo y ya) cuando falta cualquier pieza: sin
  /// saldo previo pintado no hay contador al que volar, sin la tarjeta a la
  /// vista no hay pila de la que despegar, y con «reducir animaciones» el
  /// movimiento (y su sonido) sobran por decisión del usuario.
  void _celebrarAcreditacion(CreditPurchaseEvent e) {
    final nuevo = e.balance;
    if (nuevo == null) return;
    final desde = _saldo;
    final pilaKey = e.productId == null ? null : _pilaKeys[e.productId];
    final origen = pilaKey == null ? null : _centroDe(pilaKey);
    final destino = _centroDe(_keyContador);
    if (desde == null ||
        desde == nuevo ||
        origen == null ||
        destino == null ||
        _vuelo != null ||
        JayaloMotion.reduced(context)) {
      setState(() => _saldo = nuevo);
      // Sin vuelo NO hay nada que esperar: la celebración es el acuse de la
      // compra, no el adorno del vuelo, así que entra igual.
      unawaited(_abrirCelebracion(desde, nuevo));
      return;
    }
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => VueloMonedas(
        origen: origen,
        destino: destino,
        // Cada aterrizaje empuja el contador un quinto del camino; el último
        // cae EXACTO en el saldo del servidor (división entera acumulada).
        onAterrizaje: (i) {
          if (!mounted) return;
          setState(() => _saldo = desde + (nuevo - desde) * (i + 1) ~/ 5);
        },
        // Si la pantalla murió a mitad de vuelo, `dispose` ya retiró la
        // entrada (y con ella este widget): solo se retira si sigue siendo
        // la vigente, o un remove doble reventaría.
        onFin: () {
          if (_vuelo == entry) {
            entry.remove();
            _vuelo = null;
          }
          // Y AHORA la celebración (pedido PO 2026-08-23: "después que pase
          // la animación de las monedas entra esta pantalla"). Nunca a la vez:
          // el panel taparía el contador justo mientras sube.
          unawaited(_abrirCelebracion(desde, nuevo));
        },
      ),
    );
    _vuelo = entry;
    Overlay.of(context).insert(entry);
  }

  /// El panel violeta de la recarga (mockup B aprobado PO 2026-08-23): el saldo
  /// nuevo de héroe, lluvia de monedas y Jayi asomando.
  ///
  /// No se auto-cierra. "Buscar clientes" lleva a las solicitudes; salir por
  /// atrás devuelve `null` y deja al proveedor EN la tienda, que sigue viva
  /// debajo — el que venía a comprar otro paquete no pierde el sitio.
  ///
  /// [desde] es el saldo ANTES de acreditar y puede ser `null` (la tienda
  /// abrió sin poder leer el saldo): entonces no se canta ningún "+N" en vez
  /// de inventar un delta.
  Future<void> _abrirCelebracion(int? desde, int nuevo) async {
    if (!mounted) return;
    final buscarClientes = await showRechargeCelebration(
      context,
      agregados: desde == null ? null : nuevo - desde,
      saldo: nuevo,
    );
    if (buscarClientes != true || !mounted) return;
    context.go('/provider');
  }

  /// Aparte de `_load` y con su propio try: que no se sepa el saldo no puede
  /// dejar sin tienda a quien viene a recargar.
  Future<void> _cargarSaldo() async {
    try {
      final saldo = await widget.fetchBalance();
      if (!mounted) return;
      setState(() => _saldo = saldo);
    } catch (_) {
      // Sin contador; la tienda funciona igual.
    }
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
        //
        // El contador SÍ es de esta pantalla: las monedas de la tarjeta
        // comprada vuelan al contador y el saldo sube aterrizaje a
        // aterrizaje. El número viene del servidor en el propio evento.
        _celebrarAcreditacion(e);
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
      appBar: AppBar(
        title: const Text('Recargar créditos'),
        actions: [
          if (_saldo != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: KeyedSubtree(
                key: _keyContador,
                child: _ContadorSaldo(saldo: _saldo!, dark: dark),
              ),
            ),
        ],
      ),
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
                        pilaKeys: {
                          for (final t in _tiers)
                            if (t.playProductId != null)
                              t.playProductId!: _pilaKeys.putIfAbsent(
                                  t.playProductId!, GlobalKey.new),
                        },
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
  static const _oro = kOroMoneda;

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

  void _moneda(Canvas canvas, Offset c, double rot, double alpha) =>
      pintarMoneda(canvas, c, 12, rot: rot, alpha: alpha);

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

/// El vuelo de monedas de la acreditación (mockup «enjambre cometa», PO
/// 2026-08-23): cinco monedas estallan a la vez sobre la pila de la tarjeta
/// comprada, flotan un instante y salen disparadas UNA A UNA, con estela
/// dorada y un arco propio cada una, hasta el contador del AppBar.
///
/// Como el Jayi de la banda: UN SOLO controller para toda la coreografía —
/// estallido, tirones, estelas, aterrizajes, destello y el sonido salen de la
/// misma línea de tiempo, que es lo que la mantiene articulada (feedback PO
/// sobre el mockup: «se ve desarticulada» — aquí nada corre por su cuenta).
/// Público solo para los widget tests de la pantalla.
class VueloMonedas extends StatefulWidget {
  const VueloMonedas({
    super.key,
    required this.origen,
    required this.destino,
    required this.onAterrizaje,
    required this.onFin,
  });

  /// Centro de la pila de la tarjeta comprada, en coordenadas globales.
  final Offset origen;

  /// Centro del contador del AppBar, en coordenadas globales.
  final Offset destino;

  /// Una llamada por moneda que llega (0..4), EN el instante del impacto: la
  /// pantalla sube el saldo con cada una y el contador pulsa al recibirla.
  final void Function(int moneda) onAterrizaje;

  /// El vuelo terminó: quien lo montó retira el overlay.
  final VoidCallback onFin;

  @override
  State<VueloMonedas> createState() => _VueloMonedasState();
}

class _VueloMonedasState extends State<VueloMonedas>
    with SingleTickerProviderStateMixin {
  /// 1 240 ms en total: estallido 322, respiro, y cinco tiros de 384 cada
  /// 90 ms. Duración propia (no un token de `motion.dart`): es la coreografía
  /// de UNA celebración, como el ciclo de 4,2 s del Jayi.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1240));

  int _aterrizadas = 0;
  bool _sono = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_avanza);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onFin();
    });
    _c.forward();
  }

  void _avanza() {
    final t = _c.value;
    // El ting-ting-ting arranca un pelín antes del primer impacto (.71) para
    // que los tintineos caigan sobre los aterrizajes, no detrás de ellos.
    if (!_sono && t >= .56) {
      _sono = true;
      unawaited(playSfx(Sfx.coinsCredited));
    }
    while (_aterrizadas < 5 &&
        t >= _VueloPainter.aterrizajes[_aterrizadas]) {
      widget.onAterrizaje(_aterrizadas);
      _aterrizadas++;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _VueloPainter(
              t: _c.value,
              origen: widget.origen,
              destino: widget.destino,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _VueloPainter extends CustomPainter {
  _VueloPainter({required this.t, required this.origen, required this.destino});

  final double t;
  final Offset origen;
  final Offset destino;

  // ── La línea de tiempo (fracciones de los 1 240 ms) ────────────────────────
  /// Fin del estallido conjunto.
  static const _finEstallido = .26;

  /// Salida del tiro de cada moneda (cada 90 ms desde los 496 ms)…
  static const _salidas = [.40, .4725, .545, .6175, .69];

  /// …y su impacto en el contador, 384 ms después. La última cierra el vuelo.
  static const aterrizajes = [.71, .7825, .855, .9275, 1.0];

  // ── La geometría (relativa a la pila) ─────────────────────────────────────
  /// De dónde despega cada moneda: las posiciones de la pila de 5.
  static const _cunas = [
    Offset(-40, 18), Offset(-20, -10), Offset(0, 18),
    Offset(20, -10), Offset(40, 18),
  ];

  /// Hasta dónde estalla cada una: un abanico sobre la tarjeta.
  static const _abanico = [
    Offset(-66, -64), Offset(-34, -88), Offset(6, -99),
    Offset(44, -85), Offset(74, -52),
  ];

  /// Comba del arco de cada tiro, alternando el lado: cinco trayectorias
  /// hermanas pero no clónicas, que es lo que se lee como "orgánico".
  static const _combas = [-30.0, 24.0, -18.0, 26.0, -22.0];

  /// El acelerón del tiro. El mockup usaba u³ y en los fotogramas se vio el
  /// defecto: la moneda pasa medio tiro pegada al enjambre (a mitad de tiempo
  /// solo lleva el 15 % del camino) y luego cruza la pantalla en un
  /// parpadeo — teletransporte, no vuelo. u² (easeInQuad) sigue llegando
  /// lanzada pero despega a tiempo de leerse.
  static const _acelera = Curves.easeInQuad;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 5; i++) {
      _moneda(canvas, i);
      _impacto(canvas, i);
    }
  }

  void _moneda(Canvas canvas, int i) {
    final cuna = origen + _cunas[i];
    final flote = origen + _abanico[i];

    if (t < _finEstallido) {
      // Estallido conjunto: de la pila al abanico con un puntito de rebote
      // (easeOutBack) y apareciendo en los primeros metros.
      final u = (t / _finEstallido).clamp(0.0, 1.0);
      final e = Curves.easeOutBack.transform(u);
      final pos = Offset.lerp(cuna, flote, e)!;
      final escala = .35 + .65 * Curves.easeOutCubic.transform(u);
      pintarMoneda(canvas, pos, 15 * escala,
          alpha: (u * 3.5).clamp(0.0, 1.0));
      return;
    }

    final salida = _salidas[i];
    // Flote: sube 7 px y respira 2 px, CONGELADO en el instante de la salida
    // para que el tiro arranque exactamente donde la moneda estaba — sin ese
    // empalme el tiro "teletransporta" y se ve desarticulado.
    final tf = math.min(t, salida);
    final flotePos = flote +
        Offset(
            0,
            -7 * Curves.easeOutCubic.transform(
                    ((tf - _finEstallido) / .10).clamp(0.0, 1.0)) -
                2 * math.sin(9 * (tf - _finEstallido) + i * 1.7));

    if (t < salida) {
      pintarMoneda(canvas, flotePos, 15);
      return;
    }

    final u = ((t - salida) / (aterrizajes[i] - salida)).clamp(0.0, 1.0);
    if (u >= 1) return; // ya aterrizó: la pinta el impacto, no la moneda.

    final e = _acelera.transform(u);
    // Arco cuadrático: el punto de control se sale de la recta hacia el lado
    // de su comba.
    final medio = Offset.lerp(flotePos, destino, .5)!;
    final dir = destino - flotePos;
    final largo = dir.distance;
    final perp = largo == 0
        ? Offset.zero
        : Offset(-dir.dy / largo, dir.dx / largo) * _combas[i];
    final control = medio + perp;
    Offset punto(double k) =>
        flotePos * (1 - k) * (1 - k) + control * 2 * k * (1 - k) + destino * k * k;

    // Estela: cuatro tramos por donde la moneda acaba de pasar, afinándose.
    // En el ORO de la moneda y no en crema: el vuelo cruza la tarjeta blanca
    // y una estela pálida desaparecía contra ella (visto en los fotogramas).
    for (var k = 4; k >= 1; k--) {
      final a = (e - .055 * k).clamp(0.0, 1.0);
      final b = (e - .055 * (k - 1)).clamp(0.0, 1.0);
      if (a >= b) continue;
      canvas.drawLine(
        punto(a),
        punto(b),
        Paint()
          ..color = kOroMoneda
              .withValues(alpha: (.58 - .12 * k) * (1 - u * .3))
          ..strokeWidth = 8.5 - 1.6 * k
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.save();
    final pos = punto(e);
    pintarMoneda(canvas, pos, 15 * (1 - .62 * e),
        rot: _combas[i].sign * 1.1 * e);
    canvas.restore();
  }

  /// El golpe en el contador: anillo que se abre + dos chispas; la última
  /// moneda trae además el halo grande del "ya está".
  void _impacto(Canvas canvas, int i) {
    final u = ((t - aterrizajes[i]) / .15).clamp(0.0, 1.0);
    if (t < aterrizajes[i] || u >= 1) return;
    final abre = Curves.easeOutCubic.transform(u);
    final ultimo = i == 4;

    if (ultimo) {
      canvas.drawCircle(
          destino,
          12 + 26 * abre,
          Paint()
            ..color = kOroMoneda.withValues(alpha: .35 * (1 - u))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawCircle(
        destino,
        (ultimo ? 10 : 8) + (ultimo ? 34 : 24) * abre,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - u)
          ..color = kOroMoneda.withValues(alpha: .55 * (1 - u)));

    final k = math.sin(math.pi * u);
    _estrella(canvas, destino + const Offset(-11, -7), 7 * k, k);
    _estrella(canvas, destino + const Offset(9, -4), 5 * k, k);
  }

  void _estrella(Canvas canvas, Offset c, double r, double alpha) {
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
    canvas.drawPath(p, Paint()..color = kOroMoneda.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_VueloPainter old) =>
      old.t != t || old.origen != origen || old.destino != destino;
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
