import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/widgets/rating_form.dart';
import 'package:jayalo_app/features/shared/star_score.dart';

/// La nota que el cliente da en el chat se guardaba SOLO en
/// `conversation_ratings`, tabla que nadie promedia: la reputación pública del
/// proveedor sale de `business_reviews`. Es decir, calificar desde la app no
/// movía las estrellas. Este test fija que ahora escribe en las dos.

/// Elige una nota en el control de estrellas (1-10). El control mapea el toque a
/// decimos del ancho total, asi que se toca en la fraccion correspondiente — ya
/// no hay botones numerados que buscar por texto.
Future<void> elegirNota(WidgetTester tester, int n) async {
  final r = tester.getRect(find.byType(StarScoreInput));
  await tester.tapAt(Offset(r.left + r.width * (n / 10) - 1, r.center.dy));
  await tester.pump();
}

void main() {
  testWidgets('al enviar, escribe también la reseña del negocio', (
    tester,
  ) async {
    final escritas = <(String, int, String)>[];
    var convGuardada = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          businessId: 'biz1',
          onDone: () {},
          submitConversation: (_) async => convGuardada = true,
          submitBusinessReview: (b, r, c) async => escritas.add((b, r, c)),
        ),
      ),
    ));
    await elegirNota(tester, 9); // nota 9 sobre 10
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    expect(convGuardada, isTrue);
    expect(escritas, hasLength(1));
    expect(escritas.single.$1, 'biz1');
    expect(escritas.single.$2, 9,
        reason: 'business_reviews.rating es 1-10 desde 20260619014535: '
            'la nota va TAL CUAL, sin convertir de escala');
  });

  testWidgets('si la reseña del negocio falla, la calificación igual se '
      'reporta como enviada', (tester) async {
    var terminado = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          businessId: 'biz1',
          onDone: () => terminado = true,
          submitConversation: (_) async {},
          submitBusinessReview: (_, _, _) async => throw Exception('red'),
        ),
      ),
    ));
    await elegirNota(tester, 7);
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(terminado, isTrue,
        reason: 'la nota ya quedó guardada: no se rompe el flujo del usuario');
  });

  testWidgets('sin businessId no intenta escribir la reseña del negocio', (
    tester,
  ) async {
    var intentos = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          onDone: () {},
          submitConversation: (_) async {},
          submitBusinessReview: (_, _, _) async => intentos++,
        ),
      ),
    ));
    await elegirNota(tester, 8);
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(intentos, 0);
  });
}
