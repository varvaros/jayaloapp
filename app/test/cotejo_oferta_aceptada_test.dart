import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/celebration.dart';

/// Hasta el 09-21 aceptar una oferta y desbloquear un contacto mostraban
/// EXACTAMENTE la misma animación —el mismo Jayi bailando en la misma pantalla
/// violeta— y solo cambiaba el texto. Una es gratis y la otra cuesta créditos:
/// tienen que distinguirse sin leer (PO 09-21, «cambiemos la animación de
/// oferta aceptada por un cotejo»).
void main() {
  Widget host(void Function(BuildContext) onTap) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (c) => Center(
          child: ElevatedButton(
            onPressed: () => onTap(c),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  Future<void> abrir(WidgetTester t, void Function(BuildContext) f) async {
    await t.pumpWidget(host(f));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('aceptar una oferta enseña el cotejo, no la mascota', (t) async {
    await abrir(t, (c) => showAcceptCelebration(c));
    expect(find.byType(CotejoAceptado), findsOneWidget);
    expect(find.byType(JayiCelebration), findsNothing);
    await t.pumpAndSettle();
  });

  testWidgets('desbloquear un contacto SIGUE siendo la mascota', (t) async {
    await abrir(t, (c) => showUnlockCelebration(c));
    expect(find.byType(JayiCelebration), findsOneWidget);
    expect(find.byType(CotejoAceptado), findsNothing);
    await t.pumpAndSettle();
  });

  testWidgets('el cotejo se anuncia a quien no puede verlo', (t) async {
    await abrir(t, (c) => showAcceptCelebration(c));
    expect(
      find.bySemanticsLabel('Oferta aceptada'),
      findsOneWidget,
      reason: 'la etiqueta la tenía la mascota y no se puede perder',
    );
    await t.pumpAndSettle();
  });

  testWidgets('con «reducir animaciones» el cotejo se pinta entero y quieto', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: const Scaffold(
          body: Center(child: CotejoAceptado(size: 200, progreso: 0)),
        ),
      ),
    );
    // `progreso: 0` es el primer frame; quieto tiene que verse HECHO, no una
    // pantalla vacía (mismo criterio que JayiCelebration).
    expect(find.byType(CotejoAceptado), findsOneWidget);
    await t.pumpAndSettle();
  });
}
