import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/widgets/rating_form.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

/// El detalle de solicitud completada PROMETÍA "Califica al proveedor para
/// ayudar a la comunidad" y no tenía ningún control para hacerlo. Este panel
/// cierra esa promesa. Escala 1-10, igual que la web.

/// Elige una nota en el control de estrellas (1-10). El control mapea el toque a
/// decimos del ancho total, asi que se toca en la fraccion correspondiente — ya
/// no hay botones numerados que buscar por texto.
Future<void> elegirNota(WidgetTester tester, int n) async {
  final r = tester.getRect(find.byType(StarScoreInput));
  await tester.tapAt(Offset(r.left + r.width * (n / 10) - 1, r.center.dy));
  await tester.pump();
}

void main() {
  testWidgets('sin reseña previa muestra el formulario y guarda la nota', (
    tester,
  ) async {
    final guardadas = <(String, int, String)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async => null,
          submit: (b, r, c) async => guardadas.add((b, r, c)),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // el panel se carga a sí mismo
    expect(find.text('Califica al proveedor'), findsOneWidget);
    await elegirNota(tester, 10);
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(guardadas.single.$1, 'biz1');
    expect(guardadas.single.$2, 10);
  });

  testWidgets('con reseña previa muestra la nota dada, no el formulario', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async => (rating: 8, comment: 'Todo bien'),
          submit: (_, _, _) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Califica al proveedor'), findsNothing);
    expect(find.textContaining('8'), findsOneWidget);
    expect(find.text('Todo bien'), findsOneWidget);
    expect(find.text('Enviar calificación'), findsNothing);
  });

  testWidgets('mientras no sabe si hay reseña, no pinta nada', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return (rating: 8, comment: null);
          },
          submit: (_, _, _) async {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Califica al proveedor'), findsNothing,
        reason: 'pintar el formulario y luego reemplazarlo por la nota ya '
            'dada sería un parpadeo');
    await tester.pumpAndSettle();
    expect(find.textContaining('8'), findsOneWidget);
  });
}
