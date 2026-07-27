import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('catalogo: guia welcome la primera vez', (t) async {
    await t.pumpWidget(MaterialApp(
      home: CatalogView(
        actions: const [],
        fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async => [],
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('ofrecen en sus tiendas'), findsOneWidget);
  });
}
