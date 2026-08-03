import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-08-03: una solicitud COMPLETADA salía sobre tarjeta blanca,
/// igual que una `waiting`, y parecía activa. Debe verse apagada —teñida con su
/// gris— y llevar una banda violeta centrada que diga "Completado".
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    // Las guías de esta pantalla montan un velo a pantalla completa; sin esto
    // tapa la tarjeta (mismo patrón que `my_requests_others_test.dart`).
    await onboardingStore.markDone('client.my_requests.v1');
    await onboardingStore.markDone('client.others_requests.v1');
  });

  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  /// `myFetch` sustituye a `_fetch` entero, así que las filas se inyectan ya
  /// con su fase: no hace falta Supabase.
  Future<List<(Map<String, dynamic>, RequestPhase, int)>> rowsWith(
    RequestPhase phase,
  ) async =>
      [
        (
          {
            'id': 'r1',
            'title': 'Mesa de caoba',
            'kind': 'producto',
            'is_wholesale': false,
            'image_url': null,
            'status': 'completed',
            'created_at': DateTime.now().toIso8601String(),
          },
          phase,
          2,
        ),
      ];

  JayaloCard cardOf(WidgetTester tester) => tester.widget<JayaloCard>(
        find
            .ancestor(
              of: find.text('Mesa de caoba'),
              matching: find.byType(JayaloCard),
            )
            .first,
      );

  testWidgets('completada: tarjeta teñida con el gris de su fase, no blanca',
      (tester) async {
    await tester.pumpWidget(host(MyRequestsScreen(
      myFetch: () => rowsWith(RequestPhase.completed),
      othersFetch: () async => [],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(cardOf(tester).tint, JayaloStatus.completedLight.bg);
  });

  testWidgets('completada: banda violeta centrada que dice "Completado"',
      (tester) async {
    await tester.pumpWidget(host(MyRequestsScreen(
      myFetch: () => rowsWith(RequestPhase.completed),
      othersFetch: () async => [],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Completado'), findsOneWidget);
    // La banda SUSTITUYE a la píldora de estado: dos etiquetas diciendo lo
    // mismo en la misma tarjeta sería ruido.
    expect(find.text('Completada'), findsNothing);
  });

  testWidgets('esperando: sigue sobre tarjeta blanca y SIN banda',
      (tester) async {
    // La regresión que importa: `waiting` es la fase más viva de todas (acaba
    // de publicarse) y tiene que seguir sin teñir, o el arreglo habría movido
    // el problema en vez de resolverlo.
    await tester.pumpWidget(host(MyRequestsScreen(
      myFetch: () => rowsWith(RequestPhase.waiting),
      othersFetch: () async => [],
      actions: const [],
    )));
    await tester.pumpAndSettle();

    expect(cardOf(tester).tint, isNot(JayaloStatus.completedLight.bg));
    expect(find.text('Completado'), findsNothing);
  });
}
