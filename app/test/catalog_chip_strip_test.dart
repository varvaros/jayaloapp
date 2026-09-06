import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_chip_strip.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  const cats = [
    (id: 'belleza', name: 'Belleza'),
    (id: 'electronica', name: 'Electrónica'),
  ];

  testWidgets('pinta «Todo» y las categorías; tocar una avisa con su id',
      (tester) async {
    String? tocada;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      onCategory: (id) => tocada = id,
      onTodo: () {},
    )));
    expect(find.text('Todo'), findsOneWidget);
    expect(find.text('Belleza'), findsOneWidget);
    expect(find.text('Electrónica'), findsOneWidget);

    await tester.tap(find.text('Electrónica'));
    expect(tocada, 'electronica');
  });

  testWidgets('el chip activo lleva selected=true en semántica', (tester) async {
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: 'belleza',
      onCategory: (_) {},
      onTodo: () {},
    )));
    final belleza = tester.getSemantics(find.text('Belleza'));
    // ignore: deprecated_member_use
    expect(belleza.hasFlag(SemanticsFlag.isSelected), isTrue);
    final todo = tester.getSemantics(find.text('Todo'));
    // ignore: deprecated_member_use
    expect(todo.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('tocar «Todo» llama onTodo', (tester) async {
    var llamado = false;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: 'belleza',
      onCategory: (_) {},
      onTodo: () => llamado = true,
    )));
    await tester.tap(find.text('Todo'));
    expect(llamado, isTrue);
  });

  testWidgets('sin wholesale no hay chip de mayoreo (Servicio)', (tester) async {
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.text('Al por mayor'), findsNothing);
  });

  testWidgets('con wholesale el chip alterna y avisa con el nuevo valor',
      (tester) async {
    bool? nuevo;
    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      wholesale: false,
      onWholesale: (v) => nuevo = v,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.text('Al por mayor'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    await tester.tap(find.text('Al por mayor'));
    expect(nuevo, isTrue);

    await tester.pumpWidget(host(CatalogChipStrip(
      categorias: cats,
      categoryId: null,
      wholesale: true,
      onWholesale: (v) => nuevo = v,
      onCategory: (_) {},
      onTodo: () {},
    )));
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    await tester.tap(find.text('Al por mayor'));
    expect(nuevo, isFalse);
  });
}
