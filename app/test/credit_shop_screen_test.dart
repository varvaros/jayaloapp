import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jayalo_app/core/play_billing_service.dart';
import 'package:jayalo_app/core/play_verify_client.dart';
import 'package:jayalo_app/domain/credit_shop.dart';
import 'package:jayalo_app/features/provider/credit_shop_screen.dart';

/// Doble mínimo para montar la PANTALLA completa sin canal de plataforma.
class _ScreenIap implements InAppPurchase {
  _ScreenIap({required this.buyResult, required this.products});
  final bool buyResult;
  final List<ProductDetails> products;

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async =>
      buyResult;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async =>
      ProductDetailsResponse(productDetails: products, notFoundIDs: const []);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoVerify implements PlayVerifyClient {
  @override
  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async =>
      throw StateError('la pantalla no debe verificar nada en este test');
}

void main() {
  final tiers = buildShopTiers(const [
    ShopPackage(id: 'a', points: 10, priceUSD: 10, label: 'Inicial — 10 puntos',
        playProductId: 'creditos_10usd'),
    ShopPackage(id: 'b', points: 55, priceUSD: 50, label: 'Popular — 55 puntos',
        playProductId: 'creditos_50usd'),
  ]);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('pinta el precio de PLAY, no el USD de la base de datos', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      // Precio tal como lo devuelve Play: localizado y con impuesto.
      playPrices: const {'creditos_10usd': 'RD\$650.00', 'creditos_50usd': 'RD\$3,200.00'},
      onBuy: (_) {},
    )));

    expect(find.text('RD\$650.00'), findsOneWidget);
    expect(find.textContaining('\$10.00'), findsNothing);
  });

  testWidgets('no pinta la tarjeta de un producto que Play no conoce', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (_) {},
    )));

    expect(find.text('Inicial'), findsOneWidget);
    expect(find.text('Popular'), findsNothing);
  });

  testWidgets('marca "Más popular" solo donde el label del admin lo dice', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00', 'creditos_50usd': 'RD\$3,200.00'},
      onBuy: (_) {},
    )));

    expect(find.text('Más popular'), findsOneWidget);
  });

  testWidgets('el sello dice Google Play y no menciona la web ni PayPal', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (_) {},
    )));

    expect(find.textContaining('Google Play'), findsWidgets);
    // Anti-steering: ni PayPal ni jayalo.com pueden aparecer en esta pantalla.
    expect(find.textContaining('PayPal'), findsNothing);
    expect(find.textContaining('jayalo.com'), findsNothing);
  });

  testWidgets('el CTA entrega el id de producto de Play', (t) async {
    String? bought;
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (id) => bought = id,
    )));

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(bought, 'creditos_10usd');
  });

  testWidgets('sin productos disponibles muestra un vacío, no una lista rota',
      (t) async {
    await t.pumpWidget(host(const CreditShopBody(
      tiers: [], playPrices: {}, onBuy: _noop)));

    expect(find.textContaining('No hay paquetes disponibles'), findsOneWidget);
  });

  // C-3 de la revisión: la ruta vive dentro del ShellRoute y `showsNavBar`
  // da true para `/tienda-creditos`, así que la píldora flotante se pinta
  // ENCIMA del cuerpo (extendBody). Con `extendBody`, el alto real de la
  // barra llega como `MediaQuery.padding.bottom` (ver el doc-comment de
  // `navBarReservedSpace`); si la pantalla no lo reserva, el sello de Google
  // Play queda siempre tapado y en un 360×640 la barra tapa el CTA "Comprar".
  testWidgets('reserva el espacio de la barra flotante al fondo', (t) async {
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    const barra = 132.0; // ~kNavBarReservedSpace: la píldora + su margen

    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: barra)),
        child: Scaffold(
          body: CreditShopBody(
            tiers: tiers,
            playPrices: const {'creditos_10usd': 'RD\$650.00'},
            onBuy: (_) {},
          ),
        ),
      ),
    ));

    final selloBottom =
        t.getBottomLeft(find.textContaining('Pago seguro')).dy;
    expect(selloBottom, lessThanOrEqualTo(844 - barra),
        reason: 'el sello (y el CTA por encima de él) debe quedar por encima '
            'de la barra flotante, no debajo');
  });

  // C-2 de la revisión: `buyConsumable` devuelve `false` cuando la hoja de
  // Google no se abre (ITEM_ALREADY_OWNED, típicamente). El stream no emite
  // nada en ese caso, así que si la pantalla ignora el `false`, el spinner
  // del CTA no se suelta nunca: sin mensaje y sin salida.
  testWidgets('si la hoja de pago no se abre, el CTA vuelve y se avisa', (t) async {
    debugPlayBilling = PlayBillingService(
      verifyClient: _NoVerify(),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: _ScreenIap(
        buyResult: false,
        products: [
          ProductDetails(
            id: 'creditos_10usd',
            title: 'Inicial',
            description: '',
            price: 'RD\$650.00',
            rawPrice: 650,
            currencyCode: 'DOP',
          ),
        ],
      ),
    );
    addTearDown(() => debugPlayBilling = null);

    await t.pumpWidget(MaterialApp(
      home: CreditShopScreen(
        loadPackages: () async => const [
          ShopPackage(
              id: 'a',
              points: 10,
              priceUSD: 10,
              label: 'Inicial — 10 puntos',
              playProductId: 'creditos_10usd'),
        ],
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    await t.pumpAndSettle();

    expect(find.text('No se pudo abrir el pago. Intenta de nuevo.'),
        findsOneWidget);
    final btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNotNull,
        reason: 'el spinner debe soltarse: sin evento del stream, nadie más '
            'va a limpiar el estado de compra en curso');
  });

  testWidgets('en oscuro pinta sin reventar', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: CreditShopBody(
          tiers: tiers,
          playPrices: const {'creditos_10usd': 'RD\$650.00'},
          onBuy: (_) {},
        ),
      ),
    ));

    // Que el pump no lance ya es media aserción; la otra mitad es que el
    // contenido siga ahí y no se haya perdido contra el fondo.
    expect(find.text('RD\$650.00'), findsOneWidget);
    expect(find.text('Inicial'), findsOneWidget);
  });
}

void _noop(String _) {}
