import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/provider/inbox_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Recorrido de la primera pantalla del proveedor (PO 2026-09-05): ocho pasos,
/// uno por elemento. Con la bandeja vacía el paso 1 (primera tarjeta) no tiene
/// ancla y sale centrado; los segmentados del encabezado sí están y se
/// señalan. Las anclas del shell (el `+`, la barra, la monedita) no están
/// montadas aquí: esos pasos salen centrados, sin perderse.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  Future<List<Map<String, dynamic>>> vacio(
          {String? kind, required bool todas}) async =>
      [];

  Widget host() => MaterialApp(
        home: ProviderInboxView(
          fetch: vacio,
          leading: const SizedBox.shrink(),
          actions: const [],
        ),
      );

  testWidgets('arranca con «PASO 1 DE 8» y avanza por Para ti/Todas y el tipo',
      (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('PASO 1 DE 8'), findsOneWidget);
    expect(find.textContaining('llegan las solicitudes'), findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('PASO 2 DE 8'), findsOneWidget);
    expect(find.textContaining('Para ti: solicitudes de tu rubro'),
        findsOneWidget);

    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('PASO 3 DE 8'), findsOneWidget);
    expect(find.textContaining('productos o servicios'), findsOneWidget);
  });

  testWidgets('Saltar marca el recorrido del proveedor como visto', (t) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsNothing);
    expect(onboardingStore.isDone('provider.inbox_tour.v1'), isTrue);
  });
}
