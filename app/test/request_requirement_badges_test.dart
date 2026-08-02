import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/shared/request_requirement_badges.dart';

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: jayaloTheme(brightness),
        home: Scaffold(body: child),
      );

  const todos = RequestRequirements(
    withShipping: true,
    withInstallation: true,
    requiresEvaluation: true,
    requiresFiscalReceipt: true,
    requiresStateSupplier: true,
  );

  testWidgets('sin requisitos no dibuja nada', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    expect(find.textContaining('Requiere'), findsNothing);
  });

  testWidgets('el padding NO se aplica cuando no hay nada que pintar',
      (tester) async {
    // Si el padding se aplicara igual, cada detalle sin requisitos quedaría con
    // un hueco vertical fantasma bajo el título.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
      padding: EdgeInsets.only(top: 40),
    )));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(RequestRequirementBadges)).height,
      0,
      reason: 'sin requisitos el widget debe ocupar cero',
    );
  });

  testWidgets('chips: los cinco textos, en orden canónico', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    final textos = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(RequestRequirementBadges),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .toList();
    expect(textos, [
      'Requiere envío',
      'Requiere instalación',
      'Requiere evaluación previa',
      'Requiere comprobante fiscal',
      'Requiere suplidor del Estado',
    ]);
  });

  testWidgets('chips: la evaluación SÍ aparece (divergencia con la web)',
      (tester) async {
    // La web la excluye del detalle porque allí ya tiene su chip ámbar propio.
    // La app no lo tiene: si se copiara la exclusión, el requisito quedaría
    // invisible en los tres detalles.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresEvaluation: true),
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Requiere evaluación previa'), findsOneWidget);
  });

  testWidgets('symbols: cinco íconos y ningún texto', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RequestRequirementBadges),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: 'en el listado los símbolos son mudos: el texto vive en el detalle',
    );
  });

  testWidgets('symbols: solo pinta los activos', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });

  testWidgets('el tono cambia entre claro y oscuro', (tester) async {
    Color colorDelIcono() => tester
        .widget<Icon>(find.byIcon(Icons.receipt_long_outlined))
        .color!;

    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoLight.ink);

    await tester.pumpWidget(host(
      const RequestRequirementBadges(
        req: RequestRequirements(requiresFiscalReceipt: true),
        variant: RequirementBadgeVariant.symbols,
      ),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoDark.ink);
  });
}
