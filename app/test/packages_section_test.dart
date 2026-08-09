import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/money.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart';
import 'package:jayalo_app/features/provider/package_editor_screen.dart';

/// Sección "Paquetes" de "Mi negocio" + su editor (Task 7, 2026-08-09):
/// espejo simplificado de `PackageEditorDialog.tsx` de la web — alta,
/// edición y borrado de paquetes/planes reutilizables, sin `is_featured`
/// ("Más popular", fuera de alcance de esta tarea).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  /// El editor de paquetes es un `ListView` largo (foto + 3 campos + N filas
  /// de item + botón) — con el viewport de prueba por defecto (800×600) las
  /// filas de más y el botón "Guardar" nacen fuera del `cacheExtent` y ni se
  /// montan. Mismo patrón que `store_item_editor_test.dart` (Task 6).
  void setTallPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('MyBusinessView — sección Paquetes (Task 7)', () {
    const negocio = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: null,
      coverUrl: null,
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: 'Todo en herramientas',
      seals: <String>['Negocio verificado'],
      services: <String>[],
      raw: <String, dynamic>{},
    );

    /// La portada editorial ocupa mucho del viewport de prueba (800×600) —
    /// mismo motivo que `bajar()` en `my_business_screen_test.dart`. La
    /// sección PAQUETES va después de SERVICIOS, así que hace falta bajar
    /// más que en ese archivo.
    ///
    /// Por clave (2026-08-09, tercera vuelta): `find.byType(ListView)` dejó
    /// de bastar en cuanto PAQUETES tiene contenido — el carril horizontal
    /// de tarjetas compactas monta su propio `ListView`, y `tester.drag`
    /// exige un único match.
    Future<void> bajar(WidgetTester tester) async {
      await tester.drag(
          find.byKey(const Key('mi-negocio-scroll')), const Offset(0, -1200));
      await tester.pumpAndSettle();
    }

    testWidgets('(a) sin paquetes el dueño ve «+ Añadir paquete»',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        reviews: const [],
        rating: null,
        onAddPackage: () async {},
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('PAQUETES'), findsOneWidget);
      expect(find.text('Añadir paquete'), findsOneWidget);
    });

    testWidgets(
        '(b) con paquetes se pintan nombre y precio y la fila «+ Añadir…» al final',
        (tester) async {
      final paquetes = [
        {
          'id': 'pk1',
          'name': 'Plan Básico',
          'price': 1500,
          'items': ['Corte', 'Lavado'],
        },
      ];
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        reviews: const [],
        rating: null,
        onAddPackage: () async {},
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('Plan Básico'), findsOneWidget);
      expect(find.text(fmtRD(1500)), findsOneWidget);
      // La fila de alta sigue disponible aunque ya haya paquetes.
      expect(find.text('Añadir paquete'), findsOneWidget);
    });

    testWidgets(
        '(c) mantener presionado un paquete pide confirmar («Eliminar», no '
        '«Quitar») antes de llamar al doble de deletePackage', (tester) async {
      String? deletedId;
      final paquetes = [
        {'id': 'pk1', 'name': 'Plan Básico', 'price': 1500, 'items': <String>[]},
      ];
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        reviews: const [],
        rating: null,
        onDeletePackage: (item) async => deletedId = item['id'] as String?,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.longPress(find.text('Plan Básico'));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar este paquete?'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(deletedId, isNull); // aún no confirmó

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(deletedId, 'pk1');
    });

    testWidgets('cancelar el borrado NO llama al doble de deletePackage',
        (tester) async {
      var called = false;
      final paquetes = [
        {'id': 'pk1', 'name': 'Plan Básico', 'price': 1500, 'items': <String>[]},
      ];
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        reviews: const [],
        rating: null,
        onDeletePackage: (item) async => called = true,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.longPress(find.text('Plan Básico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets('tocar un paquete propio llama a onEditPackage con la fila',
        (tester) async {
      Map<String, dynamic>? edited;
      final paquetes = [
        {'id': 'pk1', 'name': 'Plan Básico', 'price': 1500, 'items': <String>[]},
      ];
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        reviews: const [],
        rating: null,
        onEditPackage: (item) async => edited = item,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      await tester.tap(find.text('Plan Básico'));
      await tester.pumpAndSettle();

      expect(edited, paquetes.first);
    });

    // Pedido PO 2026-08-09 (TERCERA vuelta, tras mostrar un ejemplo — grid de
    // tarjetas tipo "match" de una app de citas — y pedir «los paquetes y
    // trabajos deben hacer scroll HORIZONTAL, que la foto sea más pequeña»):
    // PAQUETES es un carril con `scrollDirection: Axis.horizontal` y la
    // tarjeta de un paquete sigue con la foto ARRIBA a todo el ancho DE LA
    // TARJETA (`width: double.infinity`), pero angosta y con la foto más
    // chica que la iteración anterior (168 → 120).
    testWidgets(
        '(e) PAQUETES es un carril horizontal y la tarjeta pinta la foto '
        'arriba, a todo el ancho de la tarjeta', (tester) async {
      final paquetes = [
        {
          'id': 'pk1',
          'name': 'Plan Básico',
          'price': 1500,
          'image_url': 'https://x/plan.jpg',
          'items': <String>[],
        },
      ];
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: paquetes,
        reviews: const [],
        rating: null,
        onAddPackage: () async {},
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      // El carril de PAQUETES es un `ListView` horizontal (el otro
      // `ListView` en pantalla es el vertical de toda la vista).
      final carril =
          tester.widgetList<ListView>(find.byType(ListView)).firstWhere(
              (lv) => lv.scrollDirection == Axis.horizontal);
      expect(carril.scrollDirection, Axis.horizontal);

      final img = tester.widget<Image>(find.byType(Image).first);
      expect(img.width, double.infinity);
      expect(img.height, 120);
    });

    testWidgets('sin onAddPackage la fila de alta no existe', (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        paquetes: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();
      await bajar(tester);

      expect(find.text('Añadir paquete'), findsNothing);
    });
  });

  group('PackageEditorScreen (Task 7)', () {
    testWidgets('(a) guardar sin nombre avisa y no llama al doble de save',
        (tester) async {
      var called = false;
      await tester.pumpWidget(host(Scaffold(
        body: PackageEditorScreen(
          businessId: 'biz-1',
          save: ({
            id,
            required businessId,
            required name,
            description = '',
            price,
            required items,
            imageUrl,
          }) async {
            called = true;
          },
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Ponle un nombre al paquete.'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('(b) añadir y quitar filas de items', (tester) async {
      await tester.pumpWidget(host(Scaffold(
        body: PackageEditorScreen(businessId: 'biz-1'),
      )));
      await tester.pumpAndSettle();

      // Arranca con UNA fila de item, sin botón de quitar (mínimo 1 fila).
      expect(find.byKey(const Key('campo-item-0')), findsOneWidget);
      expect(find.byKey(const Key('boton-quitar-item-0')), findsNothing);

      await tester.tap(find.byKey(const Key('boton-agregar-item')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('campo-item-0')), findsOneWidget);
      expect(find.byKey(const Key('campo-item-1')), findsOneWidget);
      expect(find.byKey(const Key('boton-quitar-item-0')), findsOneWidget);
      expect(find.byKey(const Key('boton-quitar-item-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('boton-quitar-item-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('campo-item-0')), findsOneWidget);
      expect(find.byKey(const Key('campo-item-1')), findsNothing);
      // Con una sola fila, el botón de quitar vuelve a desaparecer.
      expect(find.byKey(const Key('boton-quitar-item-0')), findsNothing);
    });

    testWidgets(
        '(c) guardar llama a savePackage con items sin vacíos y price '
        'parseado o null', (tester) async {
      setTallPhoneSize(tester);
      Map<String, dynamic>? captured;
      await tester.pumpWidget(host(Scaffold(
        body: PackageEditorScreen(
          businessId: 'biz-1',
          save: ({
            id,
            required businessId,
            required name,
            description = '',
            price,
            required items,
            imageUrl,
          }) async {
            captured = {
              'id': id,
              'businessId': businessId,
              'name': name,
              'description': description,
              'price': price,
              'items': items,
              'imageUrl': imageUrl,
            };
          },
        ),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('campo-nombre-paquete')), 'Plan Full');
      await tester.enterText(
          find.byKey(const Key('campo-precio-paquete')), '1500');
      await tester.enterText(find.byKey(const Key('campo-item-0')), 'Corte');
      await tester.tap(find.byKey(const Key('boton-agregar-item')));
      await tester.pumpAndSettle();
      // La fila añadida se deja EN BLANCO a propósito: debe filtrarse.
      await tester.enterText(find.byKey(const Key('campo-item-1')), '  ');
      await tester.tap(find.byKey(const Key('boton-agregar-item')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-item-2')), ' Lavado ');

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['id'], isNull);
      expect(captured!['businessId'], 'biz-1');
      expect(captured!['name'], 'Plan Full');
      expect(captured!['price'], 1500.0);
      expect(captured!['items'], ['Corte', 'Lavado']);
    });

    testWidgets(
        '(d) modo edición: precarga desde `initial` y guarda con el id',
        (tester) async {
      Map<String, dynamic>? captured;
      final initial = {
        'id': 'pk1',
        'business_id': 'biz-1',
        'name': 'Plan Básico',
        'description': 'Incluye lo esencial.',
        'price': 900,
        'items': ['Corte'],
        'image_url': null,
      };
      await tester.pumpWidget(host(Scaffold(
        body: PackageEditorScreen(
          businessId: 'biz-1',
          initial: initial,
          save: ({
            id,
            required businessId,
            required name,
            description = '',
            price,
            required items,
            imageUrl,
          }) async {
            captured = {'id': id, 'name': name, 'price': price, 'items': items};
          },
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Editar paquete'), findsOneWidget);
      expect(find.text('Plan Básico'), findsOneWidget);
      expect(find.text('Incluye lo esencial.'), findsOneWidget);
      expect(find.text('900'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(captured!['id'], 'pk1');
      expect(captured!['name'], 'Plan Básico');
      expect(captured!['price'], 900.0);
      expect(captured!['items'], ['Corte']);
    });
  });
}
