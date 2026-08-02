import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/request_detail_sheet.dart';
import 'package:jayalo_app/features/shared/collapsing_photo_panel.dart';

/// El PO reportó (2026-08-02, captura de device) que en el detalle de su
/// solicitud la primera línea del título aparecía cortada por el borde
/// inferior de la foto. La hipótesis original era que la causa era el panel
/// de alto FIJO: la lista scrolleaba y su contenido se recortaba contra él.
/// Ese test reproducía la estructura de ENTONCES (`Container(height: 300)` +
/// `Expanded(RequestDetailSheet(...))`, con su propio `ListView` interno) y
/// confirmó la hipótesis.
///
/// **Esa estructura ya no existe** (Task 4): el panel de alto fijo murió a
/// favor de `CollapsingPhotoPanel` (un sliver que se pliega), y
/// `RequestDetailSheet` perdió su `ListView` y su CTA propio (decisión PO
/// 2026-08-02) para poder participar del scroll EXTERNO junto con el panel,
/// dentro de un `SliverFillRemaining(hasScrollBody: false)`. El test viejo ni
/// siquiera compilaba ya: `RequestDetailSheet` no acepta `unreadCount` ni
/// `onSeeOffers`, y no hay `ListView` que encontrar con `find.byType`.
///
/// Se reescribe para comprobar lo que de verdad importa ahora: que la
/// composición real (panel + hoja sin scroll propio) se pliega al arrastrar
/// el contenido. Esta garantía nació de un BLOCKED real en la Task 4 (primera
/// vuelta): con `SliverFillRemaining` en su default (`hasScrollBody: true`) y
/// la hoja con su `ListView` propio, los dos scrolls quedaban aislados — el
/// panel se quedaba fijo en 300.0 mientras el título scrolleaba solo por
/// dentro. `hasScrollBody: false` fue la corrección; este test es la
/// regresión más cara de todo el trabajo — si el panel volviera a quedarse
/// fijo, hay que pararse igual que la primera vez, no improvisar
/// `NestedScrollView`.
void main() {
  final request = <String, dynamic>{
    'id': 'req-1',
    'user_id': 'user-1',
    'title':
        'Teclado Inalámbrico Klip Xtreme con receptor USB y teclado numérico',
    'bullets': <String>['Marca: Klip Xtreme'],
    'created_at': DateTime.now().toIso8601String(),
    'status': 'open',
    'is_wholesale': false,
    'budget_min': null,
    'budget_max': null,
    'image_urls': <String>[],
  };

  /// Réplica de la estructura ACTUAL de la pantalla (Task 4, Step 1b): panel
  /// colapsable + hoja sin scroll propio en un único `CustomScrollView`, con
  /// el CTA anclado abajo, fuera del scroll.
  Widget hostActual() => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                const CollapsingPhotoPanel(
                  images: [],
                  fallbackIcon: Icons.hourglass_top_outlined,
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: RequestDetailSheet(
                    request: request,
                    phase: RequestPhase.withOffers,
                    offers: const [],
                  ),
                ),
              ],
            ),
          ),
          RequestDetailCta(
            offers: const [],
            unreadCount: 0,
            onSeeOffers: () {},
          ),
        ],
      ),
    ),
  );

  double panelHeight(WidgetTester tester) =>
      tester.getSize(find.byType(FlexibleSpaceBar)).height;

  testWidgets(
    'la composición real se pliega al arrastrar el contenido de la hoja '
    '(regresión: esto es justo lo que falló la primera vez)',
    (tester) async {
      // Viewport chico a propósito: con el tamaño default de flutter_test
      // (800x600 lógicos) el contenido corto de prueba casi no desborda y el
      // drag apenas movería el panel un par de píxeles — no por un scroll
      // aislado, sino por falta de contenido que scrollear. En un celular real
      // la hoja es más larga que la pantalla (justo lo que reportó el PO), así
      // que se imita con un viewport angosto en vez de inflar el contenido.
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(hostActual());
      await tester.pumpAndSettle();

      final antes = panelHeight(tester);
      expect(antes, closeTo(300, 1));

      // El CTA ("Ver ofertas") vive FUERA del CustomScrollView, anclado por
      // el Column exterior — esta es la propiedad que el PO pidió al mover
      // el botón a RequestDetailCta. Sin esta aserción, nada en la suite
      // notaría si alguien lo volviera a meter dentro de un sliver (seguiría
      // renderizando, solo que scrolleando con el resto). Se captura su rect
      // ANTES del arrastre para compararlo después.
      final ctaAntes = tester.getRect(find.byType(FilledButton));

      final titulo = find.text(request['title'] as String);
      expect(titulo, findsOneWidget);

      // `dragFrom` desde la esquina superior-izquierda del título, no
      // `tester.drag(titulo, …)` desde su CENTRO: este título es largo y
      // envuelve varias líneas, así que su centro cae más abajo de lo que se
      // ve al inicio — con el viewport angosto de este test, ese centro
      // termina en la zona ocupada por el `RequestDetailCta` (fuera del
      // scroll), y el drag no arrastraba nada. La esquina superior-izquierda
      // siempre está dentro de lo visible en reposo.
      await tester.dragFrom(
        tester.getTopLeft(titulo) + const Offset(4, 4),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();

      final despues = panelHeight(tester);
      expect(
        despues,
        lessThan(antes - 100),
        reason:
            'si el panel se queda en 300.0 es la MISMA trampa que ya '
            'mordió una vez: hasScrollBody:false dejó de bastar y hay que '
            'pararse a investigar, no improvisar NestedScrollView.',
      );

      // El CTA no se movió ni un píxel pese al arrastre: sigue anclado
      // fuera del scroll. Si volviera a vivir dentro de un sliver, este
      // rect cambiaría junto con el contenido y la aserción fallaría.
      final ctaDespues = tester.getRect(find.byType(FilledButton));
      expect(
        ctaDespues,
        equals(ctaAntes),
        reason:
            'el CTA "Ver ofertas" debe quedarse fijo fuera del '
            'CustomScrollView; si se movió es que volvió a colarse dentro '
            'de un sliver.',
      );
    },
  );

  /// Orden de secciones (Task 5, decisión PO 2026-08-02): identidad → ESTADO
  /// → INFORMACIÓN. `req()` genera una solicitud con o sin bullets/presupuesto
  /// para poder probar también la guardia de "INFORMACIÓN" huérfana.
  Map<String, dynamic> req({bool conInfo = true}) => <String, dynamic>{
        'id': 'req-1',
        'user_id': 'user-1',
        'title': 'Teclado Inalámbrico Klip Xtreme',
        'bullets': conInfo ? <String>['Marca: Klip Xtreme'] : <String>[],
        'created_at': DateTime.now().toIso8601String(),
        'status': 'open',
        'is_wholesale': false,
        'budget_min': conInfo ? 5000 : null,
        'budget_max': conInfo ? 12000 : null,
        'image_urls': <String>[],
      };

  // Sin `unreadCount` ni `onSeeOffers`: desde la Task 4, `RequestDetailSheet`
  // ya no los acepta (el CTA vive aparte, en `RequestDetailCta`).
  Widget host(Map<String, dynamic> r) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: RequestDetailSheet(
            request: r,
            phase: RequestPhase.withOffers,
            offers: const [],
          ),
        ),
      );

  testWidgets('el orden es identidad → ESTADO → INFORMACIÓN', (tester) async {
    await tester.pumpWidget(host(req()));
    await tester.pumpAndSettle();

    final titulo =
        tester.getRect(find.text('Teclado Inalámbrico Klip Xtreme')).top;
    final estado = tester.getRect(find.text('ESTADO')).top;
    final info = tester.getRect(find.text('INFORMACIÓN')).top;

    expect(titulo, lessThan(estado));
    expect(estado, lessThan(info));
  });

  testWidgets('sin bullets ni presupuesto no queda INFORMACIÓN huérfano',
      (tester) async {
    await tester.pumpWidget(host(req(conInfo: false)));
    await tester.pumpAndSettle();

    expect(find.text('ESTADO'), findsOneWidget);
    expect(find.text('INFORMACIÓN'), findsNothing);
  });
}
