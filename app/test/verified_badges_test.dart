import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/verified_badges.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('VerifiedTick no pinta nada si no hay ningún sello', (tester) async {
    await tester.pumpWidget(wrap(
      const VerifiedTick(whatsappVerified: false, idVerified: false),
    ));
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('VerifiedTick pinta el ✓ con un solo sello', (tester) async {
    await tester.pumpWidget(wrap(
      const VerifiedTick(whatsappVerified: true, idVerified: false),
    ));
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets('VerifiedLabel dice WhatsApp verificado', (tester) async {
    await tester.pumpWidget(wrap(
      const VerifiedLabel(whatsappVerified: true, idVerified: false),
    ));
    expect(find.text('WhatsApp verificado'), findsOneWidget);
  });

  testWidgets('VerifiedLabel prioriza el sello de identidad', (tester) async {
    await tester.pumpWidget(wrap(
      const VerifiedLabel(whatsappVerified: true, idVerified: true),
    ));
    expect(find.text('Proveedor verificado'), findsOneWidget);
    expect(find.text('WhatsApp verificado'), findsNothing);
  });
}
