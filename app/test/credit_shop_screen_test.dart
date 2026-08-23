import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jayalo_app/core/error_reporter.dart';
import 'package:jayalo_app/core/play_billing_service.dart';
import 'package:jayalo_app/core/play_verify_client.dart';
import 'package:jayalo_app/domain/credit_shop.dart';
import 'package:jayalo_app/features/provider/credit_shop_screen.dart';

/// Doble mínimo para montar la PANTALLA completa sin canal de plataforma.
/// `notFoundIDs` se calcula como el plugin real: pedidos − devueltos, SIN
/// importar la causa (verificado en `in_app_purchase_android_platform.dart`).
class _ScreenIap implements InAppPurchase {
  _ScreenIap({required this.buyResult, required this.products, this.productsError});
  final bool buyResult;
  final List<ProductDetails> products;

  /// Simula la PlatformException del BillingClient (sin Play, sin conexión).
  final IAPError? productsError;

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
      ProductDetailsResponse(
        productDetails: products,
        notFoundIDs: identifiers
            .where((id) => !products.any((p) => p.id == id))
            .toList(),
        error: productsError,
      );

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

class _OkVerify implements PlayVerifyClient {
  @override
  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async =>
      const PlayVerifyResult(balance: 65, points: 55, credited: true);
}

/// Compra viva tal como la entrega el plugin tras un cobro real.
PurchaseDetails _compra(String token, PurchaseStatus status,
        {String productID = 'creditos_10usd'}) =>
    PurchaseDetails(
      productID: productID,
      purchaseID: 'p1',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = true;

ProductDetails _producto(String id) => ProductDetails(
      id: id,
      title: id,
      description: '',
      price: 'RD\$650.00',
      rawPrice: 650,
      currencyCode: 'DOP',
    );

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

  // El chip ES la marca de "más popular" desde el 08-22: antes el chip decía
  // «Popular» y justo debajo un texto repetía «Más popular». Lo que este test
  // cuida sigue siendo lo mismo: que la distinción salga del label del admin y
  // no se la invente la pantalla.
  testWidgets('distingue el paquete popular solo donde el label lo dice',
      (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00', 'creditos_50usd': 'RD\$3,200.00'},
      onBuy: (_) {},
    )));

    Color? fondo(String nombre) => t
        .widget<Chip>(find.ancestor(
            of: find.text(nombre), matching: find.byType(Chip)))
        .backgroundColor;

    expect(fondo('Popular'), isNot(fondo('Inicial')),
        reason: 'el paquete que el admin marca como popular tiene que '
            'distinguirse del resto');
    expect(find.text('Más popular'), findsNothing,
        reason: 'decirlo en el chip y otra vez debajo era la misma cosa dos '
            'veces (decisión PO 08-22)');
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

  // Decisión PO 2026-08-08: el desbloqueo más barato cuesta 1 crédito, así
  // que el tope honesto es "hasta N clientes" con N = créditos del paquete.
  testWidgets('promete "Hasta N clientes desbloqueados"', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (_) {},
    )));

    expect(find.text('Hasta 10 clientes desbloqueados'), findsOneWidget);
    expect(find.textContaining('contactos'), findsNothing);
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

  // Monta la pantalla completa con un servicio real sobre dobles y devuelve
  // el servicio, para poder inyectarle lotes de compras como hace Play.
  Future<PlayBillingService> montarTienda(
    WidgetTester t, {
    List<ProductDetails>? products,
    List<ShopPackage>? packages,
    IAPError? productsError,
    MediaQueryData? mediaQuery,
    int? saldo = 38,
  }) async {
    final svc = PlayBillingService(
      verifyClient: _OkVerify(),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: _ScreenIap(
        buyResult: true,
        products: products ?? [_producto('creditos_10usd')],
        productsError: productsError,
      ),
    );
    debugPlayBilling = svc;
    addTearDown(() => debugPlayBilling = null);

    final screen = CreditShopScreen(
      loadPackages: () async =>
          packages ??
          const [
            ShopPackage(
                id: 'a',
                points: 10,
                priceUSD: 10,
                label: 'Inicial — 10 puntos',
                playProductId: 'creditos_10usd'),
          ],
      fetchBalance: () async => saldo,
    );
    await t.pumpWidget(MaterialApp(
      home: mediaQuery == null
          ? screen
          : MediaQuery(data: mediaQuery, child: screen),
    ));
    await t.pumpAndSettle();
    return svc;
  }

  // ── I-1 de la revisión de la tarea 10 ──────────────────────────────────
  // El plugin calcula notFoundIDs = pedidos − devueltos SIN importar la
  // causa: un device sin Play (o una caída) mete TODOS los ids ahí. Eso no
  // es "producto sin dar de alta": es un fallo de carga, con Reintentar y
  // sin falsa alarma de configuración al tracker.

  testWidgets('Play caído es estado de error con Reintentar, no vacío ni alarma',
      (t) async {
    final reportes = <Object>[];
    debugOnReport = reportes.add;
    addTearDown(() => debugOnReport = null);

    await montarTienda(t,
        products: const [],
        productsError: IAPError(
            source: 'google_play', code: 'SERVICE_UNAVAILABLE', message: ''));

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('No hay paquetes'), findsNothing,
        reason: 'el vacío no tiene salida; el error sí (Reintentar)');
    expect(reportes.where((e) => '$e'.contains('Play no conoce')), isEmpty,
        reason: 'cada device sin Play sería una falsa alarma de configuración');
  });

  testWidgets('todos los ids sin devolver y sin error también es fallo de carga',
      (t) async {
    // BILLING_UNAVAILABLE sin excepción: lista vacía y error == null.
    final reportes = <Object>[];
    debugOnReport = reportes.add;
    addTearDown(() => debugOnReport = null);

    await montarTienda(t, products: const []);

    expect(find.text('Reintentar'), findsOneWidget);
    expect(reportes.where((e) => '$e'.contains('Play no conoce')), isEmpty);
  });

  testWidgets('el alta faltante en consola SÍ se reporta cuando Play respondió',
      (t) async {
    final reportes = <Object>[];
    debugOnReport = reportes.add;
    addTearDown(() => debugOnReport = null);

    await montarTienda(
      t,
      products: [_producto('creditos_10usd')], // creditos_50usd no está
      packages: const [
        ShopPackage(
            id: 'a',
            points: 10,
            priceUSD: 10,
            label: 'Inicial — 10 puntos',
            playProductId: 'creditos_10usd'),
        ShopPackage(
            id: 'b',
            points: 55,
            priceUSD: 50,
            label: 'Popular — 55 puntos',
            playProductId: 'creditos_50usd'),
      ],
    );

    expect(find.text('Inicial'), findsOneWidget,
        reason: 'lo que Play sí conoce se vende igual');
    expect(find.text('Reintentar'), findsNothing);
    expect(reportes.where((e) => '$e'.contains('Play no conoce')), hasLength(1),
        reason: 'un paquete activo sin alta en consola es un fallo de '
            'configuración que nadie vería sin el reporte');
  });

  // I-2 de la revisión: PageView da constraints de alto EXACTAS y la tarjeta
  // era un Column sin scroll — con la fuente grande del sistema (ajuste de
  // accesibilidad común) el CTA "Comprar", último hijo, se recortaba en
  // release sin franja amarilla. El overflow revienta este test si vuelve.
  testWidgets('con fuente grande la tarjeta no desborda y el CTA existe',
      (t) async {
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;

    await montarTienda(t,
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.3),
          padding: EdgeInsets.only(bottom: 132), // la barra flotante del shell
        ));

    expect(find.byKey(const ValueKey('buy_creditos_10usd')), findsOneWidget);
  });

  // ── I-3 de la revisión: el copy "delicado" del brief, por fin con test ──

  testWidgets('pending dice "estamos confirmando", JAMÁS que falló', (t) async {
    final svc = await montarTienda(t);

    await svc.handlePurchases([_compra('TOK', PurchaseStatus.pending)]);
    await t.pumpAndSettle();

    expect(find.text('Estamos confirmando tu pago. Te avisamos en un momento.'),
        findsOneWidget);
    expect(find.textContaining('No se pudo'), findsNothing,
        reason: 'el usuario YA pagó y el dinero está en Google: anunciar un '
            'fallo aquí es la peor mentira posible');
    expect(find.textContaining('falló'), findsNothing);
  });

  testWidgets('el fallo previo al cobro (sintético) sí avisa que no se pudo',
      (t) async {
    final svc = await montarTienda(t);

    // Error SIN token ni producto: la única forma de "error" sin dinero detrás.
    await svc.handlePurchases([
      _compra('', PurchaseStatus.error, productID: ''),
    ]);
    await t.pumpAndSettle();

    expect(find.text('No se pudo completar la compra.'), findsOneWidget);
  });

  // Minor de la revisión: un pago DIFERIDO de otra compra, confirmado por
  // Google en segundo plano, llega como `purchased` (no restaurada). Sin el
  // productId en el evento soltaba el spinner de la compra en curso.
  testWidgets('el desenlace de OTRO producto no suelta el spinner', (t) async {
    final svc = await montarTienda(
      t,
      products: [_producto('creditos_10usd'), _producto('creditos_50usd')],
      packages: const [
        ShopPackage(
            id: 'a',
            points: 10,
            priceUSD: 10,
            label: 'Inicial — 10 puntos',
            playProductId: 'creditos_10usd'),
        ShopPackage(
            id: 'b',
            points: 55,
            priceUSD: 50,
            label: 'Popular — 55 puntos',
            playProductId: 'creditos_50usd'),
      ],
    );

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    await t.pump(); // hoja de Google "abierta" para creditos_10usd

    await svc.handlePurchases(
        [_compra('TOK-OTRO', PurchaseStatus.purchased, productID: 'creditos_50usd')]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    var btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNull,
        reason: 'el pago diferido de otra compra no es el desenlace de esta');

    await svc.handlePurchases(
        [_compra('TOK-ESTA', PurchaseStatus.purchased, productID: 'creditos_10usd')]);
    await t.pumpAndSettle();

    btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNotNull);
  });

  // Minor de la revisión: la banda decía «contactos» cuando el PO cambió el
  // vocabulario a «clientes desbloqueados» (08-08). A nivel PANTALLA, no
  // solo del body (el test del body no ve la banda).
  testWidgets('la pantalla entera no dice «contactos»', (t) async {
    await montarTienda(t);
    expect(find.textContaining('contactos'), findsNothing);
  });

  // La banda dejó el `mascot.png` estático: ahora es el Jayi dibujado con la
  // lluvia de monedas (mockup aprobado PO 08-10). Si el gate de FLUTTER_TEST
  // no gateara el bucle infinito, TODOS los `pumpAndSettle` de este archivo
  // colgarían — que este test pase ya prueba el frame fijo.
  testWidgets('la banda pinta al Jayi con monedas, sin mascot.png', (t) async {
    await montarTienda(t);
    expect(find.byKey(const ValueKey('jayi_monedas')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  // Minor de la revisión: el texto de la banda (Positioned sin top, en un
  // Stack con Clip.none) crecía hacia ARRIBA con fuente grande en pantallas
  // estrechas e invadía el AppBar. La banda empieza justo bajo el AppBar
  // (56 px sin status bar): el texto nunca puede pintar por encima de eso.
  testWidgets('el texto de la banda no invade el AppBar con fuente grande',
      (t) async {
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;

    await montarTienda(t,
        mediaQuery: const MediaQueryData(textScaler: TextScaler.linear(2.0)));

    final texto = find.textContaining('Recarga y sigue');
    expect(texto, findsOneWidget);
    expect(t.getTopLeft(texto).dy, greaterThanOrEqualTo(56),
        reason: 'sin tope de líneas, el texto anclado abajo crece hacia '
            'arriba y pinta encima del AppBar');
  });

  // El eslabón que une la decisión del PO con la pantalla: `_load` tiene que
  // pasar los `rawPrice` de Play al dominio. Con el USD de la BD estos dos
  // paquetes dirían "Ahorras 9%"; en RD\$ el ahorro real es 10%.
  testWidgets('el ahorro pintado sale del precio de Play', (t) async {
    debugPlayBilling = PlayBillingService(
      verifyClient: _NoVerify(),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: _ScreenIap(
        buyResult: true,
        products: [
          ProductDetails(
            id: 'creditos_10usd',
            title: 'Inicial',
            description: '',
            price: 'RD\$650.00',
            rawPrice: 650,
            currencyCode: 'DOP',
          ),
          ProductDetails(
            id: 'creditos_50usd',
            title: 'Popular',
            description: '',
            price: 'RD\$3,200.00',
            rawPrice: 3200,
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
          ShopPackage(
              id: 'b',
              points: 55,
              priceUSD: 50,
              label: 'Popular — 55 puntos',
              playProductId: 'creditos_50usd'),
        ],
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Ahorras 10%'), findsOneWidget,
        reason: 'el % debe salir de los RD\$ que el usuario tiene delante, '
            'no del USD de la BD (que diría 9%)');
  });

  // Important de la revisión: el listener global de `app.dart` y el de esta
  // pantalla oían el mismo evento y encolaban DOS snackbars de ~9 s por la
  // misma compra (con dos ortografías distintas). El aviso de crédito tiene
  // UN dueño: el global, que funciona aunque la tienda no esté montada.
  testWidgets('la pantalla no duplica el aviso de crédito, pero sí suelta el CTA',
      (t) async {
    final svc = await montarTienda(t);

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    await t.pump();

    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    expect(find.textContaining('Listo'), findsNothing,
        reason: 'el "Listo. Tienes N créditos." lo pinta SOLO el listener '
            'global de app.dart; aquí duplicaba el aviso');
    final btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNotNull,
        reason: 'la compra en curso terminó: el CTA debe volver');
  });

  // Important de la revisión: una compra VIEJA recuperada por
  // `restorePurchases` podía aterrizar con la hoja de Google abierta; su
  // evento soltaba el spinner y pintaba el éxito detrás de la hoja, y el
  // usuario cancelaba un pago real creyendo que ya compró.
  testWidgets('un evento de compra restaurada no toca la compra en curso',
      (t) async {
    final svc = await montarTienda(t);

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    await t.pump(); // hoja de Google "abierta": _busy puesto

    await svc.handlePurchases([_compra('TOK-VIEJO', PurchaseStatus.restored)]);
    // Sin pumpAndSettle: el spinner del CTA (que DEBE seguir vivo) anima sin
    // fin y no dejaría asentar nunca. Pumps finitos: microtask + un frame.
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    var btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNull,
        reason: 'la compra restaurada no es la compra en curso: el CTA debe '
            'seguir bloqueado mientras la hoja de Google está abierta');
    expect(find.byType(SnackBar), findsNothing,
        reason: 'nada que pintar detrás de la hoja de pago');

    // El desenlace de la compra EN CURSO sí libera.
    await svc.handlePurchases([_compra('TOK-NUEVO', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(btn.onPressed, isNotNull);
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

  // ── Contador de saldo del AppBar (pedido PO 2026-08-22) ───────────────────

  /// El contador del AppBar, y no «cualquier 65 en pantalla»: desde que la
  /// acreditación termina en la celebración de recarga, el saldo nuevo se pinta
  /// DOS veces (el contador y el número héroe del panel).
  Finder contador(String saldo) => find.descendant(
        of: find.byType(AppBar),
        matching: find.text(saldo),
      );

  testWidgets('el AppBar dice con cuántos créditos llegas', (t) async {
    final semantica = t.ensureSemantics();
    await montarTienda(t, saldo: 38);

    expect(find.text('38'), findsOneWidget);
    expect(find.bySemanticsLabel('Tienes 38 créditos'), findsOneWidget,
        reason: 'el número solo no se lee en voz alta: el texto entero vive '
            'en la semántica');
    semantica.dispose();
  });

  testWidgets('sin saber el saldo NO se inventa un cero', (t) async {
    await montarTienda(t, saldo: null);

    expect(find.text('0'), findsNothing,
        reason: 'un "0 créditos" falso en la pantalla de recarga es de lo '
            'peor que se puede enseñar');
    expect(find.byKey(const ValueKey('buy_creditos_10usd')), findsOneWidget,
        reason: 'y la tienda tiene que funcionar igual');
  });

  testWidgets('tras acreditar, el contador sube sin salir de la pantalla',
      (t) async {
    final svc = await montarTienda(t, saldo: 10);
    expect(find.text('10'), findsWidgets);

    // `_OkVerify` devuelve balance 65: es el saldo que manda el servidor.
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    expect(contador('65'), findsOneWidget,
        reason: 'quedarse viendo el saldo viejo después de pagar parece que '
            'no te acreditaron');
  });

  // ── Vuelo de monedas al acreditar (mockup «enjambre cometa», PO 08-23) ───

  testWidgets('al acreditar, las monedas vuelan y el saldo sube por aterrizajes',
      (t) async {
    final svc = await montarTienda(t, saldo: 10);
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pump();

    expect(find.byType(VueloMonedas), findsOneWidget,
        reason: 'la acreditación con la tarjeta a la vista dispara el vuelo');
    expect(find.text('10'), findsWidgets,
        reason: 'el saldo NO salta de golpe: sube moneda a moneda');

    // A los 600 ms ninguna moneda aterrizó todavía (la primera cae a los 880).
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('65'), findsNothing);

    // A los 950 ms aterrizó exactamente UNA: 10 + 55·1/5 = 21.
    await t.pump(const Duration(milliseconds: 350));
    expect(find.text('21'), findsOneWidget,
        reason: 'cada aterrizaje empuja el contador un quinto del camino');

    await t.pumpAndSettle();
    expect(contador('65'), findsOneWidget,
        reason: 'el último aterrizaje cae EXACTO en el saldo del servidor');
    expect(find.byType(VueloMonedas), findsNothing,
        reason: 'el vuelo se retira solo al terminar');
  });

  testWidgets('con «reducir animaciones» el saldo salta y nada vuela',
      (t) async {
    final svc = await montarTienda(t,
        saldo: 10,
        mediaQuery: const MediaQueryData(disableAnimations: true));
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pump();

    expect(find.byType(VueloMonedas), findsNothing,
        reason: 'el usuario pidió sin movimiento: número nuevo y ya');
    expect(contador('65'), findsOneWidget);

    // Detrás ya viene la celebración: hay que dejarla asentar o el test muere
    // con timers vivos. Que entra sin vuelo lo comprueba su propio test.
    await t.pumpAndSettle();
  });

  // ── Celebración de la recarga (mockup B, PO 2026-08-23) ──────────────────
  // El orden es el pedido: primero vuelan las monedas al contador, y CUANDO
  // ESE VUELO TERMINA baja el panel violeta. Nunca los dos a la vez.

  testWidgets('mientras las monedas vuelan, la celebración NO ha entrado',
      (t) async {
    final svc = await montarTienda(t, saldo: 10);
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(find.byType(VueloMonedas), findsOneWidget);
    expect(find.byKey(const ValueKey('celebration-recharge')), findsNothing,
        reason: 'el panel taparía el contador justo cuando está subiendo');
  });

  testWidgets('terminado el vuelo, entra la celebración con el saldo nuevo',
      (t) async {
    final svc = await montarTienda(t, saldo: 10);
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    expect(find.byType(VueloMonedas), findsNothing);
    expect(find.byKey(const ValueKey('celebration-recharge')), findsOneWidget);
    expect(find.text('¡Ya estás listo!'), findsOneWidget);
    expect(find.text('+55 CRÉDITOS'), findsOneWidget,
        reason: 'el delta sale del saldo previo (10) al del servidor (65)');
  });

  testWidgets('«Buscar clientes» lleva a las solicitudes', (t) async {
    // La única pieza de la celebración que la tienda decide: a dónde va el
    // botón. Va con un router de verdad porque `context.go` con una ruta que
    // no existe no falla en el análisis, falla en la mano del proveedor.
    final svc = PlayBillingService(
      verifyClient: _OkVerify(),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: _ScreenIap(
          buyResult: true, products: [_producto('creditos_10usd')]),
    );
    debugPlayBilling = svc;
    addTearDown(() => debugPlayBilling = null);

    final router = GoRouter(
      initialLocation: '/tienda-creditos',
      routes: [
        GoRoute(
          path: '/tienda-creditos',
          builder: (_, _) => CreditShopScreen(
            loadPackages: () async => const [
              ShopPackage(
                  id: 'a',
                  points: 10,
                  priceUSD: 10,
                  label: 'Inicial — 10 puntos',
                  playProductId: 'creditos_10usd'),
            ],
            fetchBalance: () async => 10,
          ),
        ),
        GoRoute(
            path: '/provider',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('SOLICITUDES')))),
      ],
    );
    addTearDown(router.dispose);

    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    await t.tap(find.text('Buscar clientes'));
    await t.pumpAndSettle();

    expect(find.text('SOLICITUDES'), findsOneWidget);
    expect(find.byKey(const ValueKey('celebration-recharge')), findsNothing,
        reason: 'el panel se va con el proveedor, no se queda encima');
  });

  testWidgets('sin vuelo posible la celebración entra igual', (t) async {
    // «Reducir animaciones» salta el vuelo: el saldo pega el salto seco. La
    // celebración NO se salta — es el acuse de la compra, no un adorno.
    final svc = await montarTienda(t,
        saldo: 10,
        mediaQuery: const MediaQueryData(disableAnimations: true));
    await svc.handlePurchases([_compra('TOK', PurchaseStatus.purchased)]);
    await t.pumpAndSettle();

    expect(find.byType(VueloMonedas), findsNothing);
    expect(find.byKey(const ValueKey('celebration-recharge')), findsOneWidget);
    expect(find.text('65'), findsWidgets);
  });

  // ── Vitrina violeta, mockup aprobado PO 2026-08-22 ────────────────────────

  final cuatro = buildShopTiers(const [
    ShopPackage(id: 'a', points: 10, priceUSD: 10, label: 'Inicial — 10 puntos',
        playProductId: 'creditos_10usd'),
    ShopPackage(id: 'b', points: 55, priceUSD: 50, label: 'Popular — 55 puntos',
        playProductId: 'creditos_50usd'),
    ShopPackage(id: 'c', points: 110, priceUSD: 100, label: 'Pro — 110 puntos',
        playProductId: 'creditos_100usd'),
    ShopPackage(id: 'd', points: 200, priceUSD: 180, label: 'Max — 200 puntos',
        playProductId: 'creditos_180usd'),
  ]);
  const preciosCuatro = {
    'creditos_10usd': 'RD\$650.00',
    'creditos_50usd': 'RD\$3,200.00',
    'creditos_100usd': 'RD\$6,300.00',
    'creditos_180usd': 'RD\$11,200.00',
  };

  // UNA tarjeta por pantalla (decisión PO 2026-08-22: dos «se siente muy
  // pesado») y la siguiente asomando. Se mide con geometría y no con
  // `findsNWidgets`: el PageView CONSTRUYE tarjetas que no se ven, así que
  // encontrarlas no prueba nada.
  testWidgets('cabe UNA tarjeta entera y la siguiente solo asoma', (t) async {
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;

    await t.pumpWidget(host(CreditShopBody(
      tiers: cuatro,
      playPrices: preciosCuatro,
      onBuy: (_) {},
    )));

    Rect cta(String id) => t.getRect(find.byKey(ValueKey('buy_$id')));

    expect(cta('creditos_10usd').left, greaterThan(0));
    expect(cta('creditos_10usd').right, lessThanOrEqualTo(360),
        reason: 'la tarjeta enfocada tiene que caber entera');
    expect(cta('creditos_50usd').left, lessThan(360),
        reason: 'la siguiente debe ASOMAR o nada invita a deslizar');
    expect(cta('creditos_50usd').right, greaterThan(360),
        reason: 'si la segunda cupiera entera volveríamos a las dos por '
            'pantalla que el PO descartó');
  });

  testWidgets('el sello dorado solo aparece donde hay ahorro de verdad',
      (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: cuatro,
      playPrices: preciosCuatro,
      onBuy: (_) {},
    )));

    // El paquete base ahorra 0%: pintarle un sello sería vender humo.
    expect(find.text('Ahorras 0%'), findsNothing);
    expect(find.textContaining('Ahorras'), findsWidgets);

    // La insignia de mejor precio vive en el ÚLTIMO paquete, que el PageView
    // ni siquiera construye hasta que se desliza hasta él.
    expect(find.text('MEJOR PRECIO'), findsNothing);
    await t.drag(find.byType(PageView), const Offset(-1200, 0));
    await t.pumpAndSettle();
    expect(find.text('MEJOR PRECIO'), findsOneWidget,
        reason: 'la insignia de mejor precio es UNA, la del mejor por crédito');
  });

  test('la pila reparte las monedas sin huecos ni pérdidas', () {
    for (final n in [3, 5, 7, 9]) {
      final filas = pilaDeMonedas(n);
      expect(filas.reduce((a, b) => a + b), n,
          reason: 'la pila de $n perdió o inventó monedas');
      expect(filas.every((k) => k > 0 && k <= 4), isTrue,
          reason: 'fila vacía o más ancha que la tarjeta en la pila de $n');
      for (var i = 1; i < filas.length; i++) {
        expect(filas[i], lessThanOrEqualTo(filas[i - 1]),
            reason: 'una fila más ancha que la de debajo no es una pila');
      }
    }
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
