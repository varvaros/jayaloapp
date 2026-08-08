import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/credit_shop.dart';
import 'package:jayalo_app/features/provider/credit_shop_screen.dart';

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
