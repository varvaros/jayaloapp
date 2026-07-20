import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';

/// Doctrina de movimiento (PO 2026-07-19, 4ª pasada — REVIERTE el deslizado
/// horizontal de la 3ª pasada del mismo día): "WhatsApp, Spotify no tienen
/// loader en cada sección, solo le das clic y pasa… vamos a eliminar la
/// animación de cambio de sección". Un cambio de sección corriente (push vía
/// `PageTransitionsTheme`, sin `CustomTransitionPage` propio) debe resolver
/// SIN transición: nada de `SlideTransition`/`FadeTransition` de por medio, y
/// la pantalla nueva visible en el primer frame. Este test fija el contrato:
/// si alguien reintroduce un deslizado en el `pageTransitionsTheme` general
/// sin querer, lo detecta.
///
/// Las 4 excepciones pedidas por el PO (Crear solicitud, Notificaciones, Ver
/// ofertas, menú de Avatar) NO pasan por este builder — cada una tiene su
/// propio `CustomTransitionPage`/sheet/dialog con su propia animación (ver
/// `core/router.dart`, `client/request_status_screen.dart`,
/// `shared/profile_avatar_button.dart`); no las cubre este test.
void main() {
  testWidgets(
      'el push de una ruta corriente NO anima: sin slide/fade, la pantalla '
      'nueva aparece en el primer frame', (tester) async {
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
    // Un solo pump (sin avanzar tiempo): con transición la pantalla nueva
    // seguiría a mitad de camino; sin transición ya está completa.
    await tester.pump();

    expect(find.text('nueva pantalla'), findsOneWidget);
    expect(find.byType(SlideTransition), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
