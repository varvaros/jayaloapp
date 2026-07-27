import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('estado vacio: tarjeta de ejemplo + guia "mis solicitudes"',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: MyRequestsScreen(
        actions: const [],
        myFetch: () async => [],
        othersFetch: () async => [],
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Ejemplo'), findsOneWidget);
    // La guia de menor order presente en esta pantalla (2 = mis solicitudes)
    // gana el turno primero.
    expect(find.textContaining('se verán tus solicitudes'), findsOneWidget);
  });
}
