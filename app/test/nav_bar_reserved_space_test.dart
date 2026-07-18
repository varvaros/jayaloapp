import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Regresión de C1: `navBarReservedSpace` sumaba `kNavBarReservedSpace` a un
/// `MediaQuery.padding.bottom` que, con `extendBody: true` (el montaje real
/// de `home_shell.dart`), YA es el alto COMPLETO de la barra — ver el
/// doc-comment de `navBarReservedSpace` en `floating_nav_bar.dart`, que cita
/// la fuente exacta en `_BodyBuilder` del Scaffold de Flutter. El resultado
/// era casi el doble del espacio necesario: un hueco muerto al final de
/// cada lista.
///
/// Ningún test anterior lo detectó porque todos montaban listas VACÍAS
/// (`EmptyState`), donde un hueco de más no se nota. Aquí se monta
/// `StatsView` con datos reales — una pantalla real del shell, no un mock —
/// dentro de un `Scaffold` con `extendBody: true` y una `FloatingNavBar` de
/// verdad como `bottomNavigationBar`, tal como lo arma `home_shell.dart`.
void main() {
  testWidgets(
      'con extendBody y una lista con contenido, el último elemento queda '
      'visible por encima de la barra y el hueco no es desproporcionado '
      '(espacio reservado del orden del alto real de la barra, no el doble)',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    // Inset inferior típico de un dispositivo con gestos (el caso que
    // `navBarReservedSpace` tiene que absorber sin duplicar).
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);

    final dests = destinationsFor(RoleState.provider);

    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        extendBody: true,
        body: const StatsView(
          data: {
            'clients_count': 8,
            'completed_count': 12,
            'points_invested': 45,
            'revenue_total': 128500,
            'avg_rating': 4.8,
            'reviews_count': 9,
          },
          productos: 12,
          servicios: 3,
        ),
        bottomNavigationBar: FloatingNavBar(
          destinations: dests,
          currentIndex: 1,
          onSelected: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(FloatingNavBar)).dy;
    final barHeight = tester.getSize(find.byType(FloatingNavBar)).height;
    // Último elemento real de StatsView (sección "LO QUE OFRECES", ver
    // stats_screen.dart): la tarjeta de catálogo.
    final lastItemBottom = tester.getBottomLeft(find.byType(CatalogCard)).dy;

    expect(lastItemBottom, lessThanOrEqualTo(barTop),
        reason: 'el último elemento de la lista debe quedar visible por '
            'encima de la barra flotante, no debajo de ella');

    final gap = barTop - lastItemBottom;
    // Antes del fix el hueco sumaba prácticamente otro `kNavBarReservedSpace`
    // completo (~132px) de más; con el fix debe quedar muy por debajo del
    // alto real de la barra — el orden de magnitud es el padding propio que
    // `StatsView` añade a mano (24px), no el alto de la barra otra vez.
    expect(gap, lessThan(barHeight),
        reason:
            'el hueco entre el último elemento y la barra ($gap) es del '
            'orden del alto de la barra ($barHeight px): señal de que el '
            'espacio reservado está contando la barra dos veces otra vez');
  });
}
