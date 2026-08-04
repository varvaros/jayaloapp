import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

void main() {
  // Este test es sobre el toggle de filtro, no sobre onboarding. Las guías de
  // esta pantalla (`client.my_requests.v1` / `client.others_requests.v1`)
  // montan un velo a pantalla completa que intercepta los taps; marcarlas como
  // vistas evita que el velo se coma el tap al botón "Ver solicitudes de
  // usuarios".
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('client.my_requests.v1');
    await onboardingStore.markDone('client.others_requests.v1');
  });

  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  final others = [
    {
      'id': 'o1',
      'title': 'Busco 50 sillas plegables',
      'kind': 'producto',
      'is_wholesale': false,
      'image_url': null,
      'created_at': DateTime.now().toIso8601String(),
      'with_shipping': true,
      'requires_state_supplier': true,
    },
  ];

  testWidgets('el toggle De otros muestra el feed ajeno inyectado',
      (tester) async {
    await tester.pumpWidget(host(
      MyRequestsScreen(
        // `myFetch: []` evita que el tab inicial "Mías" toque la red en el test.
        myFetch: () async => [],
        othersFetch: () async => others,
        // `HeaderBell` (default) toca `notifCountStore`, que accede a `supa`
        // sin try/catch en su constructor y revienta sin Supabase
        // inicializado — mismo patrón usado en catalog_screen_test.dart.
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    // Cambiar al segmento de solicitudes ajenas (etiqueta actual del filtro).
    await tester.tap(find.text('Ver solicitudes de usuarios'));
    await tester.pumpAndSettle();

    expect(find.text('Busco 50 sillas plegables'), findsOneWidget);
  });

  testWidgets('la tarjeta "De otros" pinta los símbolos de los requisitos',
      (tester) async {
    await tester.pumpWidget(host(
      MyRequestsScreen(
        myFetch: () async => [],
        othersFetch: () async => others,
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver solicitudes de usuarios'));
    await tester.pumpAndSettle();

    expect(find.text('Busco 50 sillas plegables'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
  });

  testWidgets('la tarjeta de MI solicitud pinta sus propios requisitos',
      (tester) async {
    // 4° elemento (`ClosedReason?`, Task 11 ronda 2) en `null`: esta fila no
    // es la fase `closed`.
    final mia = <(Map<String, dynamic>, RequestPhase, int, ClosedReason?)>[
      (
        {
          'id': 'm1',
          'title': 'Necesito 10 laptops',
          'kind': 'producto',
          'status': 'open',
          'is_wholesale': false,
          'image_url': null,
          'image_urls': <String>[],
          'created_at': DateTime.now().toIso8601String(),
          'requires_fiscal_receipt': true,
        },
        RequestPhase.waiting,
        0,
        null,
      ),
    ];

    await tester.pumpWidget(host(
      MyRequestsScreen(
        myFetch: () async => mia,
        othersFetch: () async => [],
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Necesito 10 laptops'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });
}
