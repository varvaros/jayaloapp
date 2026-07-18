import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/reputation_screen.dart';

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
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 5,
    })));
    await tester.pumpAndSettle();
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('7'), findsOneWidget);
  });
}
