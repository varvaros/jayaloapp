import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/client/offer_requirement_coverage.dart';

void main() {
  Future<void> montar(
    WidgetTester tester,
    RequestRequirements req,
    OfferCapabilities cap, {
    Brightness brillo = Brightness.light,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(brillo),
      home: Scaffold(
        body: OfferRequirementCoverage(coverage: requirementCoverage(req, cap)),
      ),
    ));
  }

  testWidgets('sin condiciones cotejables no pinta nada', (tester) async {
    await montar(tester, RequestRequirements.none, OfferCapabilities.none);
    expect(find.text('Tus condiciones'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('solo evaluación tampoco pinta nada', (tester) async {
    await montar(
      tester,
      const RequestRequirements(requiresEvaluation: true),
      OfferCapabilities.none,
    );
    expect(find.text('Tus condiciones'), findsNothing);
  });

  testWidgets('la lista sale completa aunque la oferta lo cubra todo',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresFiscalReceipt: true,
      ),
      const OfferCapabilities(offersShipping: true, hasFiscalReceipt: true),
    );
    expect(find.text('Tus condiciones'), findsOneWidget);
    expect(find.text('Envío'), findsOneWidget);
    expect(find.text('Comprobante fiscal'), findsOneWidget);
  });

  testWidgets('lo no declarado lo dice, y no afirma un negativo', (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresStateSupplier: true,
      ),
      const OfferCapabilities(offersShipping: true),
    );
    expect(find.text('Envío'), findsOneWidget);
    expect(find.text('Suplidor del Estado — no lo declaró'), findsOneWidget);
    expect(find.textContaining('no cumple'), findsNothing);
    expect(find.textContaining('no emite'), findsNothing);
  });

  testWidgets('las filas salen en orden canónico', (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        requiresStateSupplier: true,
        withShipping: true,
        requiresFiscalReceipt: true,
      ),
      OfferCapabilities.none,
    );
    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final iEnvio = textos.indexWhere((t) => t.startsWith('Envío'));
    final iFiscal = textos.indexWhere((t) => t.startsWith('Comprobante fiscal'));
    final iEstado = textos.indexWhere((t) => t.startsWith('Suplidor del Estado'));
    expect(iEnvio < iFiscal, isTrue);
    expect(iFiscal < iEstado, isTrue);
  });

  testWidgets('en oscuro pinta sin reventar y con el mismo texto',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(requiresFiscalReceipt: true),
      OfferCapabilities.none,
      brillo: Brightness.dark,
    );
    expect(find.text('Comprobante fiscal — no lo declaró'), findsOneWidget);
  });

  Color colorDeIcono(WidgetTester tester, IconData icono) =>
      tester.widget<Icon>(find.byIcon(icono)).color!;

  testWidgets('lo cumplido va en verde y lo no cumplido en gris (claro)',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresStateSupplier: true,
      ),
      const OfferCapabilities(offersShipping: true),
    );
    expect(colorDeIcono(tester, Icons.check_circle_outline),
        JayaloColors.success);
    expect(colorDeIcono(tester, Icons.remove_circle_outline),
        JayaloColors.mutedFg);
  });

  testWidgets('en oscuro el verde es el del tema oscuro', (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresStateSupplier: true,
      ),
      const OfferCapabilities(offersShipping: true),
      brillo: Brightness.dark,
    );
    expect(colorDeIcono(tester, Icons.check_circle_outline),
        JayaloColors.dSuccess);
    expect(colorDeIcono(tester, Icons.remove_circle_outline),
        JayaloColors.dMutedFg);
  });
}
