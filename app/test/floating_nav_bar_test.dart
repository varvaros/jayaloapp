import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Contrato de la barra, no sus píxeles. Lo importante: que solo el activo
/// lleve texto (decisión PO — limpia como la referencia pero el usuario
/// siempre lee dónde está), que TODOS anuncien su nombre a un lector de
/// pantalla, y que el botón central pueda estar activo.
void main() {
  final dests = destinationsFor(RoleState.provider);

  Widget host(int index, {void Function(int)? onSelected, bool reduced = false}) =>
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            bottomNavigationBar: FloatingNavBar(
              destinations: dests,
              currentIndex: index,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('solo el destino activo muestra su texto', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(find.text('Mis ofertas'), findsOneWidget);
    expect(find.text('Estadísticas'), findsNothing);
    expect(find.text('Mensajes'), findsNothing);
    expect(find.text('Ajustes'), findsNothing);
  });

  testWidgets('el texto se mueve al cambiar de destino', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(3));
    await tester.pumpAndSettle();
    expect(find.text('Mis ofertas'), findsNothing);
    expect(find.text('Mensajes'), findsOneWidget);
  });

  testWidgets('el botón central también puede estar activo y llevar su texto',
      (tester) async {
    await tester.pumpWidget(host(kCenterIndex));
    await tester.pumpAndSettle();
    expect(find.text('Ver solicitudes'), findsOneWidget);
  });

  testWidgets('todos los destinos se anuncian a un lector de pantalla',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    for (final d in dests) {
      expect(find.bySemanticsLabel(d.label), findsOneWidget, reason: d.label);
    }
    handle.dispose();
  });

  testWidgets('tocar un destino avisa con su índice', (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ajustes'));
    await tester.pumpAndSettle();
    expect(tocados, [4]);
  });

  testWidgets('tocar el botón central avisa con el índice del centro',
      (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ver solicitudes'));
    await tester.pumpAndSettle();
    expect(tocados, [kCenterIndex]);
  });

  testWidgets('con reducir animaciones no queda nada animando',
      (tester) async {
    await tester.pumpWidget(host(0, reduced: true));
    await tester.pump();
    // Si algo siguiera animando, pumpAndSettle agotaría su presupuesto.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'el nodo de semántica de un destino lateral y el del centro exponen '
      'la acción de tap (esto es lo que activa el doble-tap de un lector '
      'de pantalla; tester.tap() no lo hubiera cazado porque hace hit-test '
      'por coordenadas, no pasa por SemanticsAction)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();

    final lateral =
        tester.getSemantics(find.bySemanticsLabel('Ajustes')).getSemanticsData();
    expect(lateral.hasAction(SemanticsAction.tap), isTrue,
        reason: 'Ajustes debe exponer la acción de tap, no solo el label');

    final centro = tester
        .getSemantics(find.bySemanticsLabel('Ver solicitudes'))
        .getSemanticsData();
    expect(centro.hasAction(SemanticsAction.tap), isTrue,
        reason: 'Ver solicitudes debe exponer la acción de tap, no solo el label');

    handle.dispose();
  });

  testWidgets(
      'con currentIndex -1 (I2: ninguna pestaña coincide con la ruta, p. ej. '
      '/notifications) no queda nada teñido de primary ni ninguna etiqueta '
      'visible', (tester) async {
    await tester.pumpWidget(host(-1));
    await tester.pumpAndSettle();

    // Ninguno de los 5 destinos muestra su etiqueta: si alguno estuviera
    // "activo" por error, su texto aparecería (regla del PO: el texto solo
    // se ve en el destino activo).
    for (final d in dests) {
      expect(find.text(d.label), findsNothing, reason: d.label);
    }

    // Ningún ícono queda teñido de primary — ni los laterales (_SideItem)
    // ni el círculo central (_CenterButton, que usa cs.primary siempre como
    // fondo del círculo, pero cuyo texto de abajo solo aparece si `active`).
    final cs = Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
    final iconos = tester.widgetList<Icon>(find.descendant(
        of: find.byType(FloatingNavBar), matching: find.byType(Icon)));
    for (final icono in iconos) {
      // El ícono del círculo central es cs.onPrimary (sobre fondo primary),
      // no cs.primary: no cuenta como "teñido de primary" en el sentido de
      // la regla de la barra lateral.
      expect(icono.color, isNot(cs.primary),
          reason: 'ningún ícono debe quedar teñido de primary sin una '
              'pestaña activa');
    }
  });

  testWidgets(
      'kNavBarReservedSpace cubre el alto real que ocupa la barra al renderizarse',
      (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(FloatingNavBar));
    expect(kNavBarReservedSpace, greaterThanOrEqualTo(size.height),
        reason:
            'kNavBarReservedSpace ($kNavBarReservedSpace) se quedó corto '
            'frente al alto real (${size.height})');
  });
}
