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
/// (localizado, y con impuesto donde Google lo recauda), nunca el `priceUSD` de
/// la BD. `priceUSD` solo alimenta el cálculo del ahorro.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/brand.dart';
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
              Text('~${tier.contactsEstimate} contactos',
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

      if (resp != null && resp.notFoundIDs.isNotEmpty) {
        // La tarjeta no se pinta (el body filtra por precio), pero que un
        // paquete activo no exista en la consola es un fallo de configuración
        // que nadie vería si no se reporta.
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
        _tiers = buildShopTiers(packages);
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
    setState(() => _busy = null);
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

/// Banda violeta con la mascota asomando por detrás del panel de tarjetas.
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [JayaloColors.primary, Color(0xFF5B2EE0)],
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: -18,
            child: Image.asset('assets/images/mascot.png',
                width: 120, excludeFromSemantics: true),
          ),
          const Positioned(
            left: 20,
            bottom: 16,
            right: 150,
            child: Text(
              'Recarga y sigue desbloqueando contactos',
              style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
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
