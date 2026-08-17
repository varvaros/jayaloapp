import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/shared/request_requirement_badges.dart';

// GOTCHA para quien vuelva a medir el ancho de estos chips en un viewport
// angosto (Task 6, revisión 2026-08-02): `flutter test` sin una fuente real
// cargada mide el texto con la fuente de respaldo del entorno de test, que
// dibuja cada carácter como un cuadrado de ~1 em — NO una fuente proporcional
// como la que corre en el device (~0.5 em/carácter en promedio). Medido con
// TextPainter a `fontSize: 12`: "Requiere envío" (14 car.) dio 171.5px de
// ancho en el entorno de test (~12.25 px/car., ~1.02 em) contra ~80.9px
// (~5.78 px/car., ~0.48 em) cargando la fuente real vía `FontLoader`. Es
// decir: **el texto mide ~2× lo real dentro de un `testWidgets`.**
//
// Consecuencia concreta: si alguien monta `RequestRequirementBadges` (o
// cualquiera de los tres detalles que la usan) dentro de un viewport angosto
// (~320-360 lógicos) en un test, va a ver `RenderFlex overflowed` en el `Row`
// interno de `StatusChip` — y esto NO ocurre en el device a escala de texto
// normal. Con los números reales (~0.5 em/car.), el chip más largo,
// "Requiere suplidor del Estado" (28 car.), mide ~172px de texto real; sumando
// ícono + separación + relleno de `StatusChip` (~38px) da ~210px, que cabe
// con holgura en los ~276px útiles de un teléfono de 320dp con el padding de
// 22px por lado que usan los tres detalles.
//
// Donde SÍ hay un desborde real: con `textScaler` de accesibilidad alto
// (~2.0), ese mismo chip pasaría de ~210px a ~382px, más ancho que los 276px
// disponibles a 320dp. Pero eso es un problema de `StatusChip` en general
// (sin protección ante escalado de texto alto), no de
// `RequestRequirementBadges` en particular: cualquier otra píldora de la app
// que use `StatusChip` con una etiqueta larga tiene el mismo riesgo. Nuestras
// etiquetas de requisitos solo lo exponen primero por ser las más largas de
// toda la app. Arreglarlo de raíz implica tocar `StatusChip` (compartido por
// muchas pantallas), así que queda fuera del alcance de esta tarea — ver
// seguimiento en `task_f49a193c`.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: jayaloTheme(brightness),
        home: Scaffold(body: child),
      );

  const todos = RequestRequirements(
    withShipping: true,
    withInstallation: true,
    requiresEvaluation: true,
    requiresFiscalReceipt: true,
    requiresStateSupplier: true,
  );

  testWidgets('sin requisitos no dibuja nada', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    expect(find.textContaining('Requiere'), findsNothing);
  });

  testWidgets('el padding NO se aplica cuando no hay nada que pintar',
      (tester) async {
    // Si el padding se aplicara igual, cada detalle sin requisitos quedaría con
    // un hueco vertical fantasma bajo el título.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
      padding: EdgeInsets.only(top: 40),
    )));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(RequestRequirementBadges)).height,
      0,
      reason: 'sin requisitos el widget debe ocupar cero',
    );
  });

  testWidgets('chips: los cinco textos, en orden canónico', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    final textos = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(RequestRequirementBadges),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .toList();
    expect(textos, [
      'Requiere traslado',
      'Requiere instalación',
      'Requiere evaluación previa',
      'Requiere comprobante fiscal',
      'Requiere suplidor del Estado',
    ]);
  });

  testWidgets('chips: la evaluación SÍ aparece (divergencia con la web)',
      (tester) async {
    // La web la excluye del detalle porque allí ya tiene su chip ámbar propio.
    // La app no lo tiene: si se copiara la exclusión, el requisito quedaría
    // invisible en los tres detalles.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresEvaluation: true),
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Requiere evaluación previa'), findsOneWidget);
  });

  testWidgets('symbols: cinco íconos y ningún texto', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RequestRequirementBadges),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: 'en el listado los símbolos son mudos: el texto vive en el detalle',
    );
  });

  testWidgets('symbols: solo pinta los activos', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });

  testWidgets('el tono cambia entre claro y oscuro', (tester) async {
    Color colorDelIcono() => tester
        .widget<Icon>(find.byIcon(Icons.receipt_long_outlined))
        .color!;

    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoLight.ink);

    await tester.pumpWidget(host(
      const RequestRequirementBadges(
        req: RequestRequirements(requiresFiscalReceipt: true),
        variant: RequirementBadgeVariant.symbols,
      ),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoDark.ink);
  });

  testWidgets(
      'guardado con hasAnyRequirement: sin requisitos no corre a los chips '
      'que van después dentro de un Wrap',
      (tester) async {
    // Reproduce el patrón de los tres sitios de listado (inbox del proveedor
    // y las dos tarjetas de "Mis solicitudes"): sin `hasAnyRequirement` como
    // guarda, `RequestRequirementBadges` entra igual al `Wrap` como
    // `SizedBox.shrink()`, y un hijo de ancho cero IGUAL consume su
    // `spacing` — el chip siguiente se corre 8px aunque no haya nada que ver.
    const req = RequestRequirements.none;
    await tester.pumpWidget(host(
      Wrap(
        spacing: 8,
        children: [
          const Text('antes', key: Key('antes')),
          if (hasAnyRequirement(req))
            const RequestRequirementBadges(
              req: req,
              variant: RequirementBadgeVariant.symbols,
            ),
          const Text('después', key: Key('despues')),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    final antes = tester.getRect(find.byKey(const Key('antes')));
    final despues = tester.getRect(find.byKey(const Key('despues')));

    expect(
      despues.left,
      antes.right + 8,
      reason: 'sin requisitos, "después" debe pegarse justo tras el spacing '
          'del Wrap; si el guardado faltara, quedaría a antes.right + 16 '
          'por el spacing extra que mete el SizedBox.shrink() invisible',
    );
  });

  // ── Variante tiles (plantilla PO 2026-08-11) ──────────────────────────────

  testWidgets('tiles: eyebrow REQUISITOS + etiqueta arriba y Requerido debajo',
      (tester) async {
    const req = RequestRequirements(
      withShipping: true,
      requiresFiscalReceipt: true,
    );
    await tester.pumpWidget(host(
      const RequestRequirementBadges(
        req: req,
        variant: RequirementBadgeVariant.tiles,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('REQUISITOS'), findsOneWidget);
    expect(find.text('TRASLADO'), findsOneWidget);
    expect(find.text('Requerido'), findsOneWidget);
    // El fiscal lleva la sigla: es el único cuyo "qué es" no se entiende
    // sin ella.
    expect(find.text('COMPROBANTE FISCAL'), findsOneWidget);
    expect(find.text('Requerido (NCF)'), findsOneWidget);
  });

  testWidgets('tiles: sin requisitos no pinta ni el eyebrow', (tester) async {
    await tester.pumpWidget(host(
      const RequestRequirementBadges(
        req: RequestRequirements.none,
        variant: RequirementBadgeVariant.tiles,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('REQUISITOS'), findsNothing);
  });
}
