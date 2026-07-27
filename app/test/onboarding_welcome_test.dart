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

  testWidgets('guia de creditos (anclada, tienda proveedor) se muestra y se marca',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnboardingGuide(
          guideKey: 'wallet.credits.v1',
          steps: onboardingCopy['wallet.credits.v1']!,
          child: const SizedBox(width: 300, height: 80, child: Text('Tu saldo')),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(onboardingStore.isDone('wallet.credits.v1'), isTrue);
  });

  testWidgets('guia de chat (bienvenida, sin ancla) se muestra centrada y se marca',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnboardingGuide(
          guideKey: 'client.chat_reveal.v1',
          mode: OnboardingMode.welcome,
          steps: onboardingCopy['client.chat_reveal.v1']!,
          child: const SizedBox(width: 300, height: 400, child: Text('chat')),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(onboardingStore.isDone('client.chat_reveal.v1'), isTrue);
  });
}
