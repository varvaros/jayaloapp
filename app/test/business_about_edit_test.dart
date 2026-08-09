import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart';

void main() {
  group('MyBusinessView — descripción editable (Task 4)', () {
    // Scaffold explícito: `_toast` usa `ScaffoldMessenger.of(context).
    // showSnackBar`, que exige un Scaffold descendiente (mismo motivo que
    // `business_cover_edit_test.dart`).
    Widget host(Widget child) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(body: child),
        );

    const negocioSinDescripcion = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: null,
      coverUrl: null,
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: null,
      seals: <String>['Negocio verificado'],
      services: <String>[],
      raw: <String, dynamic>{},
    );

    const negocioConDescripcion = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: null,
      coverUrl: null,
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: 'Todo en herramientas desde 1998.',
      seals: <String>['Negocio verificado'],
      services: <String>[],
      raw: <String, dynamic>{},
    );

    testWidgets('(a) sin descripción el dueño ve «+ Añadir descripción»',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocioSinDescripcion,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Añadir descripción'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
    });

    testWidgets('(b) con descripción se ve el texto y NO el +', (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConDescripcion,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Todo en herramientas desde 1998.'), findsOneWidget);
      expect(find.text('Añadir descripción'), findsNothing);
    });

    testWidgets(
        '(c) tocar abre el sheet, escribir y guardar llama al doble con el texto nuevo',
        (tester) async {
      String? calledBusinessId;
      String? calledDescription;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocioSinDescripcion,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        updateDescription: (businessId, description) async {
          calledBusinessId = businessId;
          calledDescription = description;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Añadir descripción'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Herrería y ferretería.');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(calledBusinessId, 'biz-1');
      expect(calledDescription, 'Herrería y ferretería.');
      // Estado local actualizado: ya no se ve la píldora de vacío.
      expect(find.text('Herrería y ferretería.'), findsOneWidget);
      expect(find.text('Añadir descripción'), findsNothing);
    });

    testWidgets('cancelar el sheet NO llama al doble inyectado', (tester) async {
      var called = false;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConDescripcion,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        updateDescription: (businessId, description) async {
          called = true;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todo en herramientas desde 1998.'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.text('Todo en herramientas desde 1998.'), findsOneWidget);
    });
  });
}
