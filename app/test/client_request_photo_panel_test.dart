import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/collapsing_photo_panel.dart';

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

  double alto(WidgetTester t) =>
      t.getSize(find.byType(FlexibleSpaceBar)).height;

  testWidgets('en reposo ocupa el alto expandido', (tester) async {
    await tester.pumpWidget(
      host(
        const CollapsingPhotoPanel(
          images: [],
          fallbackIcon: Icons.inventory_2_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(alto(tester), closeTo(300, 1));
  });

  testWidgets('al bajar se encoge de verdad', (tester) async {
    await tester.pumpWidget(
      host(
        const CollapsingPhotoPanel(
          images: [],
          fallbackIcon: Icons.inventory_2_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final inicial = alto(tester);

    await tester.drag(find.text('fila 3'), const Offset(0, -250));
    await tester.pumpAndSettle();

    expect(alto(tester), lessThan(inicial - 100));
  });

  testWidgets('el botón atrás sigue tocable con el panel plegado', (
    tester,
  ) async {
    var pulsado = false;
    await tester.pumpWidget(
      host(
        CollapsingPhotoPanel(
          images: const [],
          fallbackIcon: Icons.inventory_2_outlined,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => pulsado = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('fila 3'), const Offset(0, -250));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(pulsado, isTrue);
  });

  testWidgets('sin fotos sale el ícono de fase y no hay miniatura', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CollapsingPhotoPanel(
          images: [],
          fallbackIcon: Icons.hourglass_top_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);
    // La miniatura es un cuadro de 76: sin segunda foto no debe existir.
    expect(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 76 && w.height == 76,
      ),
      findsNothing,
    );
  });

  // El test de la miniatura tocable con dos fotos queda fuera:
  // `JayaloNetworkImage` pide red y en `flutter_test` toda petición HTTP
  // devuelve 400, así que la imagen nunca se monta. Se verifica a mano en el
  // Step 3 de la Task 6 (punto 8).

  // El test de "composición real (panel + hoja) se pliega al arrastrar" YA NO
  // vive aquí (revisión 2026-08-02): era un duplicado del de
  // `client_request_detail_sheet_test.dart`, que afirma lo mismo y además
  // comprueba que el CTA queda anclado fuera del scroll y arrastra desde la
  // esquina superior-izquierda del título (esta versión arrastraba desde el
  // CENTRO, frágil con títulos que envuelven varias líneas). Ese fichero es
  // ahora el único dueño de la regresión del plegado, y desde la misma
  // revisión monta el widget REAL de la pantalla (`RequestDetailBody`) en vez
  // de una réplica hecha a mano.
  //
  // Este fichero se queda con lo suyo: el `CollapsingPhotoPanel` aislado.
}
