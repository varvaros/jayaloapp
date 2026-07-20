import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/product_list_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  testWidgets('muestra nombre y precio', (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'category_id': 'ferreteria',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Taladro'), findsOneWidget);
    expect(find.textContaining('2,500'), findsOneWidget);
  });

  testWidgets('sin avg_rating/reviews_count no dibuja la línea de reputación',
      (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
    })));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('con reputación dibuja la estrella', (tester) async {
    await tester.pumpWidget(host(const ProductListCard(item: {
      'id': 'p1',
      'name': 'Taladro',
      'price': 2500,
      'avg_rating': 4.5,
      'reviews_count': 8,
    })));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
