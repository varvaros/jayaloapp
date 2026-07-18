import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';

/// Doctrina de movimiento (PO 2026-07-18): toda navegación debe deslizar en
/// VERTICAL (la sección sube a su sitio, la anterior se guarda hacia arriba)
/// con easeInOutCubic, nunca el zoom/fade genérico de Android. Este test fija
/// el contrato: si alguien revierte `pageTransitionsTheme` sin querer, el
/// `SlideTransition` desaparece (el zoom por defecto de M3 usa Scale+Fade, no
/// Slide) y el test lo detecta.
void main() {
  testWidgets('el push de una ruta sube deslizando, no usa el zoom por defecto',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('nueva pantalla')),
              )),
              child: const Text('ir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // a mitad de camino

    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(FadeTransition), findsWidgets);

    // El eje es VERTICAL: a mitad de camino la entrante está desplazada en Y
    // y no en X (si alguien la vuelve horizontal, esto falla).
    final offsets = tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((w) => w.position.value)
        .where((o) => o != Offset.zero)
        .toList();
    expect(offsets, isNotEmpty, reason: 'debe haber desplazamiento en curso');
    for (final o in offsets) {
      expect(o.dx, 0, reason: 'sin componente horizontal');
      expect(o.dy, isNot(0), reason: 'el movimiento es vertical');
    }

    await tester.pumpAndSettle();
    expect(find.text('nueva pantalla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
