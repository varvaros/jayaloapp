import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';

/// Doctrina de movimiento (PO 2026-07-19, revisión visual en device;
/// sustituye al eje vertical del 07-18): toda navegación debe deslizar en
/// HORIZONTAL (la sección entra desde la derecha, la anterior se guarda a la
/// izquierda) con easeInOutCubic, nunca el zoom/fade genérico de Android.
/// Este test fija el contrato: si alguien revierte `pageTransitionsTheme` sin
/// querer, el `SlideTransition` desaparece (el zoom por defecto de M3 usa
/// Scale+Fade, no Slide) y el test lo detecta.
void main() {
  testWidgets(
      'el push de una ruta entra deslizando desde la derecha, no usa el zoom '
      'por defecto', (tester) async {
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

    // El eje es HORIZONTAL: a mitad de camino la entrante está desplazada en
    // X y no en Y (si alguien la vuelve vertical, esto falla).
    final offsets = tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((w) => w.position.value)
        .where((o) => o != Offset.zero)
        .toList();
    expect(offsets, isNotEmpty, reason: 'debe haber desplazamiento en curso');
    for (final o in offsets) {
      expect(o.dy, 0, reason: 'sin componente vertical');
      expect(o.dx, isNot(0), reason: 'el movimiento es horizontal');
    }

    await tester.pumpAndSettle();
    expect(find.text('nueva pantalla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
