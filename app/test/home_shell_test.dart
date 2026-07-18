import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// HomeShell envuelve su `body` en un `AnimatedSwitcher` keyed por la raíz de
/// pestaña ("fade through" de Material para navegación entre pares), porque
/// go_router NO anima el reemplazo de la única página del Navigator anidado
/// cuando se cambia de pestaña — solo anima los pushes reales (detalle),
/// que ya cubre `pageTransitionsTheme` y no deben re-animarse dos veces.
///
/// Este test aísla el contrato de `AnimatedSwitcher` + `KeyedSubtree` que
/// `home_shell.dart` usa, sin la complejidad de un GoRouter real: misma key
/// (push dentro de la pestaña) no debe cruzar-desvanecer; key distinta
/// (cambio de pestaña) sí.
void main() {
  Widget harness(String tabKey, String label) => MaterialApp(
        home: Scaffold(
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, .04), end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(tabKey), child: Text(label)),
          ),
        ),
      );

  testWidgets('misma key (push dentro de la pestaña) no cruza-desvanece',
      (tester) async {
    await tester.pumpWidget(harness('client', 'solicitudes'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness('client', 'detalle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Con la misma key, AnimatedSwitcher reemplaza en el sitio: el texto
    // viejo NUNCA coexiste con el nuevo en ningún frame.
    expect(find.text('solicitudes'), findsNothing);
    expect(find.text('detalle'), findsOneWidget);
  });

  testWidgets('key distinta (cambio de pestaña) sí cruza-desvanece',
      (tester) async {
    await tester.pumpWidget(harness('client', 'solicitudes'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness('messages', 'mensajes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // A mitad de la transición ambos coexisten (cross-fade real).
    expect(find.text('solicitudes'), findsOneWidget);
    expect(find.text('mensajes'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('solicitudes'), findsNothing);
    expect(find.text('mensajes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
