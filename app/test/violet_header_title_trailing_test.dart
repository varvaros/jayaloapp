import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// Slot `titleTrailing` (PO 2026-07-28, sellos de verificación): pegado al
/// título, aditivo, sin tocar `title`/`subtitle`. `null` por defecto para que
/// las demás pantallas que usan `VioletHeader` no vean ningún cambio.
void main() {
  Widget host(Widget header) => MaterialApp(home: Scaffold(body: header));

  testWidgets('titleTrailing null: la cabecera se ve como siempre, sin ✓',
      (tester) async {
    await tester.pumpWidget(host(const VioletHeader(
      title: 'Andreína',
      subtitle: 'Reparación de nevera',
      titleAlign: HeaderTitleAlign.center,
    )));

    expect(find.text('Andreína'), findsOneWidget);
    expect(find.text('Reparación de nevera'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('titleTrailing presente: el sello aparece junto al título',
      (tester) async {
    await tester.pumpWidget(host(VioletHeader(
      title: 'Andreína',
      subtitle: 'Reparación de nevera',
      titleAlign: HeaderTitleAlign.center,
      titleTrailing: const Icon(Icons.verified, size: 14, color: Colors.white),
    )));

    expect(find.text('Andreína'), findsOneWidget);
    // El subtítulo se queda intacto: el sello se SUMA, nunca lo sustituye.
    expect(find.text('Reparación de nevera'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets(
      'título largo + titleTrailing en un ancho de teléfono típico: sigue '
      'truncando con ellipsis, sin overflow', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(host(VioletHeader(
      title: 'Un nombre de proveedor bastante largo que no cabe en el header',
      subtitle: 'Un asunto de conversación igual de largo para el chat',
      titleAlign: HeaderTitleAlign.center,
      titleTrailing: const Icon(Icons.verified, size: 14, color: Colors.white),
      leading: const BackButton(color: Colors.white),
      actions: const [Icon(Icons.more_vert, color: Colors.white)],
    )));
    await tester.pumpAndSettle();

    // Ninguna excepción de layout (overflow de RenderFlex, etc.) — el Row
    // interno del título se achica con `Flexible` en vez de desbordar.
    expect(tester.takeException(), isNull);

    final titleText = tester.widget<Text>(find.text(
        'Un nombre de proveedor bastante largo que no cabe en el header'));
    expect(titleText.overflow, TextOverflow.ellipsis);
    expect(titleText.maxLines, 1);
  });
}
