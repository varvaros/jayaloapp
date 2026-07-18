import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Regresión de C1: `navBarReservedSpace` sumaba `kNavBarReservedSpace` a un
/// `MediaQuery.padding.bottom` que, con `extendBody: true` (el montaje real
/// de `home_shell.dart`), YA es el alto COMPLETO de la barra — ver el
/// doc-comment de `navBarReservedSpace` en `floating_nav_bar.dart`, que cita
/// la fuente exacta en `_BodyBuilder` del Scaffold de Flutter. El resultado
/// era casi el doble del espacio necesario: un hueco muerto SCROLLEABLE al
/// final de cada lista.
///
/// Una versión anterior de este test montaba una lista más corta que el
/// viewport (`StatsView`, que no scrollea) y medía la posición del último
/// elemento. Con contenido corto ese elemento queda pegado arriba (offset 0)
/// TANTO con el bug como con el fix — el padding duplicado solo agrega
/// espacio scrolleable por debajo, sin mover nada visible — así que el test
/// pasaba en los dos mundos por igual (se comprobó revirtiendo el fix de C1:
/// el test seguía en verde). Por eso aquí la lista tiene que desbordar el
/// viewport de verdad: solo con scroll real se puede llegar al fondo y medir
/// el hueco muerto que el bug deja.
///
/// Se hace scroll hasta `maxScrollExtent` (el fondo real del contenido, sin
/// física de rebote que lo disimule) y se mide el hueco entre el borde
/// inferior del último ítem y el borde superior de la barra flotante. Con el
/// fix ese hueco es ~0 (el padding reservado coincide exactamente con el
/// alto real renderizado de la barra). Con el bug de C1 reintroducido crece
/// en, aproximadamente, `kNavBarReservedSpace` (~132px), porque la lista
/// reserva ese espacio de más y por lo tanto scrollea de más antes de
/// terminar.
void main() {
  testWidgets(
      'con extendBody y una lista que desborda el viewport, el hueco '
      'scrolleable al final no duplica el alto de la barra',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    // Inset inferior típico de un dispositivo con gestos (el caso que
    // `navBarReservedSpace` tiene que absorber sin duplicar).
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);

    final dests = destinationsFor(RoleState.provider);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    const itemHeight = 60.0;
    // 20 * 60 = 1200px de contenido: desborda de sobra los 844px del
    // viewport, incluso sumando el padding reservado más grande (el del
    // bug, ~298px). Sin este desborde la lista no scrollea y el test vuelve
    // a ser ciego (ver doc-comment de arriba).
    const itemCount = 20;
    const lastItemKey = ValueKey('lastItem');

    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        extendBody: true,
        // Builder para que el `context` de la lista sea DESCENDIENTE del
        // body del Scaffold: solo ahí `MediaQuery.paddingOf` ya viene
        // inflado por `extendBody` al alto real de la barra (la inflación
        // la hace `_BodyBuilder`, no el propio `Scaffold`).
        body: Builder(
          builder: (context) => ListView.builder(
            controller: controller,
            // El mismo patrón que usan las pantallas reales del shell (ver
            // p. ej. `my_requests_screen.dart`): el padding inferior es
            // exactamente `navBarReservedSpace(context)`, sin nada más
            // sumado, para que el hueco medido aquí sea el que produce esa
            // función y no un padding extra propio de la pantalla.
            padding: EdgeInsets.only(bottom: navBarReservedSpace(context)),
            itemCount: itemCount,
            itemBuilder: (_, i) => Container(
              key: i == itemCount - 1 ? lastItemKey : null,
              height: itemHeight,
              alignment: Alignment.center,
              child: Text('Item $i'),
            ),
          ),
        ),
        bottomNavigationBar: FloatingNavBar(
          destinations: dests,
          currentIndex: 1,
          onSelected: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Ir al fondo real del scroll con `jumpTo`, no con un `drag`: así no hay
    // física de rebote que temporalmente esconda o exagere el hueco muerto.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final barTop = tester.getTopLeft(find.byType(FloatingNavBar)).dy;
    final lastItemBottom =
        tester.getBottomLeft(find.byKey(lastItemKey)).dy;

    expect(lastItemBottom, lessThanOrEqualTo(barTop + 1),
        reason: 'el último elemento de la lista debe quedar visible por '
            'encima de la barra flotante, no debajo de ella, incluso en el '
            'fondo del scroll');

    final gap = barTop - lastItemBottom;
    // Con el fix el padding reservado coincide con el alto real de la
    // barra: el fondo del scroll llega justo hasta donde empieza la barra y
    // el hueco es ~0. Con el bug de C1 (padding reservado contando la barra
    // dos veces) el fondo del scroll queda ~kNavBarReservedSpace (~132px)
    // más arriba de lo necesario. El umbral de abajo separa ambos mundos
    // con holgura de sobra para variación de plataforma.
    expect(gap, lessThan(60),
        reason:
            'el hueco entre el último elemento y la barra en el fondo del '
            'scroll ($gap px) sugiere que el espacio reservado cuenta el '
            'alto de la barra dos veces (con el bug de C1 este hueco crece '
            'en ~kNavBarReservedSpace, ~132px)');
  });
}
