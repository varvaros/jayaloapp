import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/service_chips_editor.dart';

void main() {
  // Scaffold explícito: los toasts de validación usan `ScaffoldMessenger.of
  // (context).showSnackBar`, que exige un Scaffold descendiente (mismo motivo
  // que el resto de las hojas — `otp_sheet.dart`, `text_editor_sheet.dart`).
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  group('showServiceChipsEditor', () {
    testWidgets('añade chip con el teclado y respeta el tope de 60 chars',
        (tester) async {
      List<String>? result;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showServiceChipsEditor(context, initial: const []);
          },
          child: const Text('abrir'),
        );
      })));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Destapes');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Destapes'), findsOneWidget);

      // 61 caracteres: se rechaza (no se recorta) y avisa.
      final texto61 = 'a' * (kMaxServiceChipLen + 1);
      expect(texto61.length, kMaxServiceChipLen + 1);
      await tester.enterText(find.byType(TextField), texto61);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // No se creó un chip con el texto rechazado — el texto sigue en el
      // campo (se rechaza, no se recorta ni se borra), así que se busca
      // específicamente entre los chips, no en cualquier Text de la hoja.
      expect(find.widgetWithText(InputChip, texto61), findsNothing);
      expect(
          find.textContaining('$kMaxServiceChipLen'), findsWidgets);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(result, ['Destapes']);
    });

    testWidgets('no duplica ignorando tildes/mayúsculas (searchFold)',
        (tester) async {
      List<String>? result;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showServiceChipsEditor(context, initial: const []);
          },
          child: const Text('abrir'),
        );
      })));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Destapes');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Destapes');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'destapés');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Un solo chip: el primero escrito se conserva tal cual.
      expect(find.text('Destapes'), findsOneWidget);
      expect(find.text('destapés'), findsNothing);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(result, ['Destapes']);
    });

    testWidgets('con 20 chips el campo de añadir se deshabilita y avisa',
        (tester) async {
      final veinte = [for (var i = 0; i < kMaxServiceChips; i++) 'Servicio $i'];
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            await showServiceChipsEditor(context, initial: veinte);
          },
          child: const Text('abrir'),
        );
      })));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('$kMaxServiceChips/$kMaxServiceChips'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    testWidgets('quitar con la x elimina el chip', (tester) async {
      List<String>? result;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showServiceChipsEditor(context,
                initial: const ['Destapes', 'Plomería']);
          },
          child: const Text('abrir'),
        );
      })));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Destapes'), findsOneWidget);
      expect(find.text('Plomería'), findsOneWidget);

      // Borra el chip de "Destapes" tocando su x (InputChip.onDeleted). Los
      // chips se pintan en el orden de `initial`, así que el primer ícono de
      // borrar es el de "Destapes" (evita un finder encadenado
      // ancestor→descendant sobre InputChip, que no ubica el ícono interno).
      // `Icons.clear` es el ícono de borrar por defecto de `InputChip` en
      // Material 3 (confirmado con un dump del árbol: `Icons.cancel` NO
      // aparece — ese es el default de M2).
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pumpAndSettle();

      expect(find.text('Destapes'), findsNothing);
      expect(find.text('Plomería'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(result, ['Plomería']);
    });

    testWidgets('Cancelar devuelve null y no conserva los cambios',
        (tester) async {
      List<String>? result = const ['sentinel'];
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showServiceChipsEditor(context,
                initial: const ['Destapes']);
          },
          child: const Text('abrir'),
        );
      })));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Plomería');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('ProviderStoreScreen — chips de servicios (solo lectura)', () {
    // No se monta la pantalla completa (hace fetch de red en initState);
    // se prueba el widget de display que ella usa, igual que
    // `business_cover_edit_test.dart` prueba `BusinessCoverHero` suelto.
    testWidgets('services no vacío muestra los chips y NUNCA el +',
        (tester) async {
      await tester.pumpWidget(host(const ServiceChipsWrap(
        services: ['Destapes', 'Plomería'],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Destapes'), findsOneWidget);
      expect(find.text('Plomería'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('services vacío no dibuja nada (sin CTA en tienda ajena)',
        (tester) async {
      await tester.pumpWidget(
          host(const ServiceChipsWrap(services: <String>[])));
      await tester.pumpAndSettle();

      expect(find.byType(Chip), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });
  });
}
