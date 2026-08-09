import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-08-09: tocar una oferta del HISTORIAL (rechazada, completada
/// o aceptada-y-desbloqueada) debe abrir el DETALLE de la solicitud
/// (`/provider/request/:id`), igual que ya hacían las tarjetas PENDIENTES
/// ("Toca para editar"). Antes rechazada no navegaba a ningún lado y
/// completada/desbloqueada abría directo la hoja de contacto sin pasar por el
/// detalle.
void main() {
  // Este test es sobre navegación, no sobre onboarding. La guía
  // 'wallet.credits.v1' (sobre la tarjeta de saldo, primera de la lista)
  // monta un velo a pantalla completa que intercepta los taps — mismo
  // patrón que `my_requests_others_test.dart`.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('wallet.credits.v1');
  });

  Map<String, dynamic> offer({
    required String id,
    required String requestId,
    required String status,
    DateTime? unlockedAt,
  }) => {
    'id': id,
    'request_id': requestId,
    'request_title': 'Necesito un plomero',
    'status': status,
    'unlocked_at': unlockedAt?.toIso8601String(),
    'created_at': DateTime.now().toIso8601String(),
  };

  /// Router real con una ruta señuelo para `/provider/request/:id` que
  /// registra el id recibido — mismo patrón que
  /// `inbox_screen_test.dart` para probar navegación sin depender del árbol
  /// completo de rutas de la app.
  ({GoRouter router, List<String> idsVisitados}) buildRouter(Widget home) {
    final idsVisitados = <String>[];
    final router = GoRouter(
      initialLocation: '/offers',
      routes: [
        GoRoute(path: '/offers', builder: (_, _) => home),
        GoRoute(
          path: '/provider/request/:id',
          builder: (_, s) {
            idsVisitados.add(s.pathParameters['id']!);
            return Scaffold(body: Text('detalle ${s.pathParameters['id']}'));
          },
        ),
      ],
    );
    return (router: router, idsVisitados: idsVisitados);
  }

  Future<void> pump(
    WidgetTester tester,
    GoRouter router,
  ) async {
    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'tocar una oferta RECHAZADA del historial navega al detalle con el requestId correcto',
      (tester) async {
    final offers = [
      offer(id: 'o-rej', requestId: 'req-rej', status: 'rejected'),
    ];
    final built = buildRouter(MyOffersScreen(
      fetchOffers: () async => offers,
      fetchBalance: () async => 10,
      fetchReviewed: (_) async => {},
      leading: const SizedBox.shrink(),
      actions: const [],
    ));
    await pump(tester, built.router);

    expect(find.text('Necesito un plomero'), findsOneWidget);
    await tester.tap(find.text('Necesito un plomero'));
    await tester.pumpAndSettle();

    expect(find.text('detalle req-rej'), findsOneWidget);
    expect(built.idsVisitados, ['req-rej']);
  });

  testWidgets(
      'tocar una oferta COMPLETADA del historial navega al detalle con el requestId correcto',
      (tester) async {
    final offers = [
      offer(id: 'o-comp', requestId: 'req-comp', status: 'completed'),
    ];
    final built = buildRouter(MyOffersScreen(
      fetchOffers: () async => offers,
      fetchBalance: () async => 10,
      fetchReviewed: (_) async => {},
      leading: const SizedBox.shrink(),
      actions: const [],
    ));
    await pump(tester, built.router);

    await tester.tap(find.text('Necesito un plomero'));
    await tester.pumpAndSettle();

    expect(find.text('detalle req-comp'), findsOneWidget);
    expect(built.idsVisitados, ['req-comp']);
  });

  testWidgets(
      'tocar una oferta ACEPTADA y DESBLOQUEADA del historial navega al detalle',
      (tester) async {
    final offers = [
      offer(
        id: 'o-unl',
        requestId: 'req-unl',
        status: 'accepted',
        unlockedAt: DateTime(2026, 8, 1),
      ),
    ];
    final built = buildRouter(MyOffersScreen(
      fetchOffers: () async => offers,
      fetchBalance: () async => 10,
      fetchReviewed: (_) async => {},
      leading: const SizedBox.shrink(),
      actions: const [],
    ));
    await pump(tester, built.router);

    await tester.tap(find.text('Necesito un plomero'));
    await tester.pumpAndSettle();

    expect(find.text('detalle req-unl'), findsOneWidget);
    expect(built.idsVisitados, ['req-unl']);
  });

  testWidgets(
      'tocar una oferta PENDIENTE sigue yendo al detalle con `?edit=` (sin regresión)',
      (tester) async {
    final offers = [
      offer(id: 'o-pend', requestId: 'req-pend', status: 'pending'),
    ];
    final idsVisitados = <String>[];
    final router = GoRouter(
      initialLocation: '/offers',
      routes: [
        GoRoute(
          path: '/offers',
          builder: (_, _) => MyOffersScreen(
            fetchOffers: () async => offers,
            fetchBalance: () async => 10,
            fetchReviewed: (_) async => {},
            leading: const SizedBox.shrink(),
            actions: const [],
          ),
        ),
        GoRoute(
          path: '/provider/request/:id',
          builder: (_, s) {
            idsVisitados.add(
              '${s.pathParameters['id']}?${s.uri.query}',
            );
            return Scaffold(body: Text('detalle ${s.pathParameters['id']}'));
          },
        ),
      ],
    );
    await pump(tester, router);

    await tester.tap(find.text('Necesito un plomero'));
    await tester.pumpAndSettle();

    expect(find.text('detalle req-pend'), findsOneWidget);
    expect(idsVisitados, ['req-pend?edit=o-pend']);
  });
}
