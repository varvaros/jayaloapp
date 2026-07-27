import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('la guia de ofertas no sale con lista vacia y si con >=1', (t) async {
    Widget build(bool hasOffers) => MaterialApp(
          home: Scaffold(
            body: OnboardingGuide(
              guideKey: 'client.view_offers.v1',
              enabled: hasOffers,
              steps: onboardingCopy['client.view_offers.v1']!,
              child: const SizedBox(width: 200, height: 60, child: Text('oferta')),
            ),
          ),
        );

    await t.pumpWidget(build(false));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsNothing);

    await t.pumpWidget(build(true));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
  });
}
