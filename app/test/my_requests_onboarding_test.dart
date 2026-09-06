import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Recorrido de la primera pantalla del cliente (PO 2026-09-05): siete pasos,
/// uno por elemento, empezando por el buscador. Las anclas del shell (el `+`,
/// la barra) no están montadas aquí: esos pasos salen centrados, sin perderse.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  Widget screen({bool embedded = false}) => MaterialApp(
        home: MyRequestsScreen(
          actions: const [],
          embedded: embedded,
          myFetch: () async => [],
          othersFetch: () async => [],
        ),
      );

  testWidgets(
      'arranca en el buscador con «PASO 1 DE 7» y avanza por las píldoras',
      (t) async {
    await t.pumpWidget(screen());
    await t.pumpAndSettle();
    expect(find.text('Ejemplo'), findsOneWidget);
    expect(find.text('PASO 1 DE 7'), findsOneWidget);
    expect(find.textContaining('Busca productos'), findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('PASO 2 DE 7'), findsOneWidget);
    expect(find.textContaining('tus solicitudes y en qué van'), findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.textContaining('qué están pidiendo otros usuarios'),
        findsOneWidget);
  });

  testWidgets('incrustada (Mis ofertas del proveedor) no lleva recorrido',
      (t) async {
    await t.pumpWidget(screen(embedded: true));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsNothing);
    expect(onboardingStore.isDone('client.home_tour.v1'), isFalse);
  });
}
