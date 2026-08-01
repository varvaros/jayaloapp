import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/collapsing_photo_panel.dart';

/// Pedido PO 2026-08-01: en el detalle de solicitud la foto ocupaba 300px
/// FIJOS (un `Container` de alto fijo con la lista debajo en un `Expanded`),
/// así que el formulario de oferta —que es largo— vivía en un tercio de
/// pantalla y no había forma de ver la ventana completa. Ahora el panel es un
/// sliver que se pliega al bajar.
void main() {
  Widget host(Widget panel) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              panel,
              SliverList.builder(
                itemCount: 40,
                itemBuilder: (_, i) => SizedBox(height: 60, child: Text('fila $i')),
              ),
            ],
          ),
        ),
      );

  double panelHeight(WidgetTester tester) =>
      tester.getSize(find.byType(FlexibleSpaceBar)).height;

  testWidgets('en reposo ocupa el alto expandido', (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.handyman_outlined,
    )));
    await tester.pumpAndSettle();

    expect(panelHeight(tester), closeTo(300, 1));
  });

  testWidgets('al hacer scroll se pliega y le deja la pantalla al contenido',
      (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.handyman_outlined,
    )));
    await tester.pumpAndSettle();
    final antes = panelHeight(tester);

    await tester.drag(find.text('fila 3'), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(panelHeight(tester), lessThan(antes - 200),
        reason: 'el panel tiene que encogerse casi del todo, no moverse un poco');
  });

  testWidgets('plegado del todo sigue visible como barra: no desaparece',
      (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.handyman_outlined,
    )));
    await tester.pumpAndSettle();

    await tester.drag(find.text('fila 3'), const Offset(0, -600));
    await tester.pumpAndSettle();

    // `pinned`: queda la barra colapsada arriba, que es donde vive el botón
    // de atrás. Si llegara a 0 el usuario se quedaría sin salida.
    expect(panelHeight(tester), greaterThan(0));
  });

  testWidgets('el leading (atrás) sigue tocable con el panel plegado',
      (tester) async {
    var vueltas = 0;
    await tester.pumpWidget(host(CollapsingPhotoPanel(
      images: const [],
      fallbackIcon: Icons.handyman_outlined,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new),
        onPressed: () => vueltas++,
      ),
    )));
    await tester.pumpAndSettle();

    await tester.drag(find.text('fila 3'), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(vueltas, 1);
  });

  testWidgets('sin fotos pinta el ícono de respaldo, nunca un hueco roto',
      (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.inventory_2_outlined,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });
}
