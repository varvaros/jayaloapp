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

  testWidgets('guia hacer oferta se muestra y se marca', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnboardingGuide(
          guideKey: 'provider.make_offer.v1',
          steps: onboardingCopy['provider.make_offer.v1']!,
          child: const SizedBox(width: 160, height: 48, child: Text('Hacer oferta')),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(onboardingStore.isDone('provider.make_offer.v1'), isTrue);
  });
}
