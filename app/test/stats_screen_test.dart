import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart'
    show CatalogCard;

/// El contrato de Estadísticas.
///
/// Task 4 (2026-07-18): el catálogo (productos/servicios) y "trabajos
/// realizados" SALIERON hacia "Mi negocio" (`/provider/business`) —
/// decisión PO verbatim: "lo movemos aquí". Esta suite verifica la MUDANZA,
/// no solo la llegada: Estadísticas ya no debe mostrar ninguna de las dos.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  const conActividad = {
    'clients_count': 8,
    'completed_count': 12,
    'points_invested': 45,
    'revenue_total': 128500,
    'avg_rating': 4.8,
    'reviews_count': 9,
  };

  testWidgets('muestra clientes, facturado y créditos invertidos',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('RD\$128,500'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
  });

  testWidgets('calificación y reseñas quedan como dos métricas separadas',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('calificación'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.textContaining('reseñas'), findsOneWidget);
  });

  testWidgets(
      'ya NO muestra el catálogo ni trabajos realizados (se movieron a Mi negocio)',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogCard), findsNothing);
    expect(find.textContaining('LO QUE OFRECES'), findsNothing);
    expect(find.textContaining('productos'), findsNothing);
    expect(find.textContaining('servicios'), findsNothing);
    expect(find.textContaining('trabajos realizados'), findsNothing);
    // El 12 de completed_count no debe colarse en ningún tile visible.
    expect(find.text('12'), findsNothing);
  });

  testWidgets('sin trabajos completados ni reseñas muestra el estado vacío',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
  });
}
