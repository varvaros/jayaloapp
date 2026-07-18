import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';

/// El contrato de Estadísticas. La tarjeta de catálogo es deliberadamente
/// INERTE: el catálogo navegable es un spec aparte (decisión PO 2026-07-18) y
/// una tarjeta que parece tocable pero no hace nada es peor que una apagada.
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

  testWidgets('muestra trabajos, clientes e ingresos formateados en RD\$',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 12, servicios: 3)));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsWidgets);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('RD\$128,500'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
  });

  testWidgets('la tarjeta de catálogo muestra el conteo y NO es tocable',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 12, servicios: 3)));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 productos'), findsOneWidget);
    expect(find.textContaining('3 servicios'), findsOneWidget);

    final catalogo = tester.widget<CatalogCard>(find.byType(CatalogCard));
    expect(catalogo.onTap, isNull,
        reason: 'el catálogo navegable es un spec aparte; hasta entonces la '
            'tarjeta no debe responder al toque');
  });

  testWidgets('sin trabajos completados muestra el estado vacío',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
    }, productos: 0, servicios: 0)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
  });

  testWidgets('singular y plural del catálogo', (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 1, servicios: 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 producto ·'), findsOneWidget);
    expect(find.textContaining('1 servicio'), findsOneWidget);
  });
}
