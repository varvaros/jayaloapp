import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/request_detail_sheet.dart';
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

  /// Riesgo del sliver (Step 4 del brief) — YA se materializó una vez en este
  /// mismo plan: la primera versión de la Task 4 metía `RequestDetailSheet`
  /// (que entonces tenía su propio `ListView`) tal cual dentro de un
  /// `SliverFillRemaining` sin especificar `hasScrollBody` (default `true`).
  /// Medido con esa composición: el panel se quedaba en 300.0 → 300.0
  /// mientras el título de la hoja scrolleaba solo, de 322 a 251, dentro de
  /// su propio scroll — los dos quedaban aislados y el panel jamás se
  /// plegaba.
  ///
  /// La corrección (decisión PO 2026-08-02) fue doble: la hoja perdió su
  /// `ListView` propio (ahora es un `Column` sin scroll) y el
  /// `SliverFillRemaining` pasó a `hasScrollBody: false`, para que el
  /// contenido participe del scroll EXTERNO en vez de scrollear por su
  /// cuenta. Este test monta esa composición REAL (panel + hoja real, no la
  /// lista de juguete de arriba) y confirma que el panel sí se pliega. Si
  /// alguna vez vuelve a quedarse fijo en 300.0, es la MISMA trampa: hay que
  /// pararse y reportar `BLOCKED`, no improvisar `NestedScrollView`.
  testWidgets(
    'composición real (panel + SliverFillRemaining hasScrollBody:false + '
    'hoja) se pliega al arrastrar el contenido',
    (tester) async {
      final request = <String, dynamic>{
        'id': 'req-1',
        'title': 'Título de prueba bastante largo para ocupar espacio',
        'bullets': <String>['bullet uno', 'bullet dos'],
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'is_wholesale': false,
        'budget_min': null,
        'budget_max': null,
      };

      // Viewport chico a propósito: el contenido de prueba (panel + hoja con
      // 2 bullets) es corto y en el tamaño default de flutter_test (800x600
      // lógicos) casi no desborda — el drag apenas movía el panel 3px, no
      // porque el scroll siguiera aislado, sino porque no había nada que
      // scrollear. En un celular real la hoja es más larga que la pantalla
      // (ese es justo el problema que reportó el PO), así que se imita eso
      // con un viewport angosto en vez de inflar el contenido de prueba.
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const CollapsingPhotoPanel(
                  images: [],
                  fallbackIcon: Icons.hourglass_top_outlined,
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: RequestDetailSheet(
                    request: request,
                    phase: RequestPhase.waiting,
                    offers: const [],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final antes = alto(tester);
      expect(antes, closeTo(300, 1));

      final titulo = find.text(request['title'] as String);
      expect(titulo, findsOneWidget);

      await tester.drag(titulo, const Offset(0, -260));
      await tester.pumpAndSettle();

      final despues = alto(tester);
      expect(
        despues,
        lessThan(antes - 100),
        reason:
            'si el panel se queda en 300.0, hasScrollBody:false dejó de '
            'bastar y hay que investigar de nuevo, no improvisar '
            'NestedScrollView.',
      );
    },
  );
}
