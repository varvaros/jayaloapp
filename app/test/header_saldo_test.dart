import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/features/provider/inbox_screen.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';
import 'package:jayalo_app/features/shared/moneda.dart';
import 'package:jayalo_app/features/shared/saldo_store.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// Contador de créditos de las cabeceras (pedido PO 2026-08-22: «que se vea en
/// todas las pantallas relevantes»).
void main() {
  // El store es un singleton: cada test deja el saldo como lo encontró.
  tearDown(() => saldoStore.saldo = null);

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          // Fondo violeta como el de las cabeceras reales: la píldora es
          // blanca traslúcida y sobre blanco no se vería.
          backgroundColor: const Color(0xFF7147F2),
          body: child,
        ),
      );

  testWidgets('mientras no se sabe el saldo NO pinta nada', (t) async {
    saldoStore.saldo = null;
    await t.pumpWidget(host(const HeaderSaldo()));

    expect(find.byType(MonedaJayalo), findsNothing,
        reason: 'un «0 créditos» falso en la cabecera es peor que no enseñar '
            'nada, y una píldora vacía es lo mismo');
  });

  testWidgets('con saldo pinta la moneda y el número', (t) async {
    await t.pumpWidget(host(const HeaderSaldo()));
    saldoStore.set(38);
    await t.pump();

    expect(find.text('38'), findsOneWidget);
    expect(find.byType(MonedaJayalo), findsOneWidget,
        reason: 'la misma moneda de la tienda: es lo que une el número con lo '
            'que compras');
  });

  testWidgets('el número lo lee en voz alta entero, no suelto', (t) async {
    final semantica = t.ensureSemantics();
    await t.pumpWidget(host(const HeaderSaldo()));
    saldoStore.set(38);
    await t.pump();

    expect(find.bySemanticsLabel('Tienes 38 créditos. Recargar.'),
        findsOneWidget);
    semantica.dispose();
  });

  testWidgets('tocarlo lleva a recargar', (t) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HeaderSaldo())),
      GoRoute(
          path: '/tienda-creditos',
          builder: (_, _) => const Scaffold(body: Text('RECARGA'))),
    ]);
    addTearDown(router.dispose);

    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    saldoStore.set(38);
    await t.pump();

    await t.tap(find.byType(HeaderSaldo));
    await t.pumpAndSettle();

    expect(find.text('RECARGA'), findsOneWidget,
        reason: 'un contador que no lleva a ninguna parte es una burla: si te '
            'dice que te quedan 3 créditos, tiene que dejarte recargar');
  });

  // El contador es de las pantallas del PROVEEDOR: el cliente no gasta
  // créditos. Se comprueba en los defaults y no montando las pantallas (que
  // tocan Supabase al montar).
  test('las pantallas del proveedor lo traen de fábrica', () {
    expect(const MyOffersScreen().actions.whereType<HeaderSaldo>(), hasLength(1));
    expect(
        ProviderInboxView(fetch: ({String? kind, required bool todas}) async => const []).actions
            .whereType<HeaderSaldo>(),
        hasLength(1));
  });
}
