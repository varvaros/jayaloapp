import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/reputation_screen.dart';
// MetricTile vive en brand_kit.dart (I3): reputation_screen.dart ya no lo
// define, solo lo usa.
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// El contrato de la pantalla de reputación. El umbral de 5 muestras para el
/// tiempo de respuesta es la regla de la web (`src/lib/responseTime.ts`): con
/// menos, la mediana miente y NO se muestra nada — ni la cifra ni un "sin
/// datos", que solo genera preguntas.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  testWidgets('con 4 muestras NO muestra el tiempo de respuesta',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 4,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regularmente respondes'), findsNothing);
  });

  testWidgets('con 5 muestras SÍ muestra el tiempo de respuesta',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 5,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regularmente respondes'), findsOneWidget);
  });

  testWidgets('sin reseñas muestra el estado vacío, no una rejilla de ceros',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 0,
      'reviews_count': 0,
      'completed_purchases': 0,
      'requests_count': 0,
      'median_response_minutes': null,
      'response_samples': 0,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no tienes'), findsOneWidget);
    expect(find.byType(MetricTile), findsNothing);
  });

  testWidgets('con actividad muestra las cifras', (tester) async {
    // Escala 1-10: un 9.0 es lo que este fixture quería decir con el 4.5 de
    // cuando la app escribía 1-5 por error (arreglado 2026-08-17).
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 9.0,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 5,
    })));
    await tester.pumpAndSettle();
    // La calificación va en un Text.rich con la reseña pegada
    // («9.0/10 · 3 reseñas»), así que se busca por contenido.
    expect(find.textContaining('9.0/10'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('7'), findsOneWidget);
    // Plantilla PO 2026-08-11: etiquetas de tarjeta y la escena de Jayi.
    expect(find.text('CALIFICACIÓN'), findsOneWidget);
    expect(find.text('SOLICITUDES HECHAS'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.byKey(const ValueKey('jayi_estrella')), findsOneWidget);
  });
}
