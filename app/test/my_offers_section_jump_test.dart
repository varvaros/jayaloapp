import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-08-22: debajo de "Mis ofertas · Mis pedidos" va una tira con
/// Aceptadas / Pendientes / Historial, y al tocarla la vista SALTA a esa
/// sección. La lista es larga y llegar al historial costaba varios dedos.
///
/// La tira NO es un filtro: no esconde nada. Solo mueve el scroll.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    // La guía de créditos monta un velo que intercepta los toques.
    await onboardingStore.markDone('wallet.credits.v1');
  });

  Map<String, dynamic> offer({
    required String id,
    required String status,
    DateTime? unlockedAt,
  }) => {
    'id': id,
    'request_id': 'req-$id',
    'request_title': 'Solicitud $id',
    'status': status,
    'unlocked_at': unlockedAt?.toIso8601String(),
    'created_at': DateTime(2026, 8, 1).toIso8601String(),
  };

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> offers,
  ) async {
    final router = GoRouter(
      initialLocation: '/offers',
      routes: [
        GoRoute(
          path: '/offers',
          builder: (_, _) => MyOffersScreen(
            fetchOffers: () async => offers,
            fetchBalance: () async => 10,
            fetchReviewed: (_) async => {},
            fetchUnseen: () async => <String>{},
            markSeen: (_) async {},
            leading: const SizedBox.shrink(),
            actions: const [],
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
  }

  /// El encabezado de sección, no la píldora: `SectionHeader` pinta en
  /// VERSALITAS, así que 'Historial' es la píldora y 'HISTORIAL' la sección.
  /// Se ancla igual por tipo para no depender solo de las mayúsculas.
  Finder seccion(String texto) => find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text(texto.toUpperCase()),
      );

  /// Una lista con las TRES secciones y suficientes pendientes para que el
  /// historial nazca fuera de la pantalla.
  List<Map<String, dynamic>> listaLarga() => [
        offer(id: 'a1', status: 'accepted'), // Aceptadas
        for (var i = 0; i < 12; i++) offer(id: 'p$i', status: 'pending'),
        offer(id: 'h1', status: 'completed'), // Historial
      ];

  testWidgets('salen las tres píldoras, en el orden de las secciones',
      (tester) async {
    await pump(tester, listaLarga());

    expect(find.text('Aceptadas'), findsOneWidget);
    expect(find.text('Pendientes'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);

    final x = [
      tester.getTopLeft(find.text('Aceptadas')).dx,
      tester.getTopLeft(find.text('Pendientes')).dx,
      tester.getTopLeft(find.text('Historial')).dx,
    ];
    expect(x[0], lessThan(x[1]));
    expect(x[1], lessThan(x[2]));
    expect(
      {tester.getTopLeft(find.text('Aceptadas')).dy,
       tester.getTopLeft(find.text('Historial')).dy}.length,
      1,
      reason: 'una sola fila, como los filtros discretos de la doctrina',
    );
  });

  testWidgets('tocar Historial lo TRAE a la pantalla', (tester) async {
    await pump(tester, listaLarga());

    final alto = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final antes = tester.getTopLeft(seccion('Historial')).dy;
    expect(antes, greaterThan(alto),
        reason: 'el historial arranca fuera de la pantalla; si no, el test '
            'no prueba nada');

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    final despues = tester.getTopLeft(seccion('Historial')).dy;
    expect(despues, lessThan(antes), reason: 'la vista se movió hacia él');
    expect(despues, lessThan(alto), reason: 'y ahora se ve');
  });

  testWidgets('la tira NO filtra: las tres secciones siguen ahí tras saltar',
      (tester) async {
    await pump(tester, listaLarga());
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    expect(seccion('Historial'), findsOneWidget);
    expect(find.textContaining('PENDIENTES'), findsOneWidget);
  });

  testWidgets('sin aceptadas no se ofrece saltar a Aceptadas', (tester) async {
    await pump(tester, [
      for (var i = 0; i < 3; i++) offer(id: 'p$i', status: 'pending'),
      offer(id: 'h1', status: 'completed'),
    ]);

    expect(find.text('Aceptadas'), findsNothing,
        reason: 'no se ofrece ir a una sección que la lista no pinta');
    expect(find.text('Pendientes'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
  });

  testWidgets('con una sola sección la tira no aparece', (tester) async {
    await pump(tester, [offer(id: 'p1', status: 'pending')]);

    // Solo habría "Pendientes", y llevarte a donde ya estás es ruido.
    expect(find.text('Pendientes'), findsNothing);
    expect(find.text('Historial'), findsNothing);
  });

  // NO CUBIERTO: que la tira desaparezca en "Mis pedidos". Esa pestaña
  // incrusta `MyRequestsScreen(embedded: true)`, que se va a la red nada más
  // montarse y no admite fuentes inyectadas, así que en widget-test revienta
  // con "You must initialize the supabase instance". Drenar la excepción no
  // basta: la carga reintenta y deja más. El gate vive en el `if (_tab == 0)`
  // del build y se verificó a ojo en el device; hacerlo testeable exige
  // inyectarle las fuentes a la pantalla del cliente, que es otra tanda.
}
