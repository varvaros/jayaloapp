import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart';
import 'package:jayalo_app/features/shared/business_cover_hero.dart';
import 'package:jayalo_app/features/shared/local_image_guard.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Junta un directorio y un nombre de fichero sin depender del paquete
/// `path` (no es dependencia directa del proyecto).
String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

void main() {
  group('BusinessCoverHero editable', () {
    testWidgets('sin portada y editable: aparece + Añadir portada',
        (t) async {
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'Mi negocio', coverUrl: null, onCoverTap: () {})));
      expect(find.text('Añadir portada'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
    });
    testWidgets('con portada y editable: NO hay + encima', (t) async {
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'Mi negocio', coverUrl: 'https://x/y.jpg', onCoverTap: () {})));
      expect(find.text('Añadir portada'), findsNothing);
    });
    testWidgets('sin callbacks (tienda pública): cero indicios de edición',
        (t) async {
      await t.pumpWidget(
          _wrap(const BusinessCoverHero(name: 'Ajeno', coverUrl: null)));
      expect(find.text('Añadir portada'), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });
    testWidgets('tocar la portada editable dispara el callback', (t) async {
      var taps = 0;
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'N', coverUrl: 'https://x/y.jpg', onCoverTap: () => taps++)));
      await t.tap(find.byType(BusinessCoverHero));
      expect(taps, 1);
    });

    testWidgets('logo vacío y editable: badge + al tocar dispara el callback',
        (t) async {
      var taps = 0;
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'N', logoUrl: null, onLogoTap: () => taps++)));
      expect(find.byIcon(Icons.add), findsOneWidget);
      await t.tap(find.byIcon(Icons.add));
      expect(taps, 1);
    });

    testWidgets('logo con imagen y editable: sin badge +', (t) async {
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'N', logoUrl: 'https://x/logo.jpg', onLogoTap: () {})));
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('coverBusy pinta un spinner superpuesto', (t) async {
      await t.pumpWidget(_wrap(const BusinessCoverHero(
          name: 'N', coverUrl: null, coverBusy: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // El spinner reemplaza a la píldora "+ Añadir portada" mientras sube.
      expect(find.text('Añadir portada'), findsNothing);
    });

    testWidgets('long-press en la portada dispara onCoverLongPress',
        (t) async {
      var pressed = 0;
      await t.pumpWidget(_wrap(BusinessCoverHero(
          name: 'N',
          coverUrl: 'https://x/y.jpg',
          onCoverTap: () {},
          onCoverLongPress: () => pressed++)));
      await t.longPress(find.byType(BusinessCoverHero));
      expect(pressed, 1);
    });
  });

  group('validateLocalImage', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('jayalo_img_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File makeFile(String name, {int bytes = 100}) {
      final f = File(_join(tmp.path, name));
      f.writeAsBytesSync(List.filled(bytes, 0));
      return f;
    }

    test('extensión válida y tamaño chico: sin error', () {
      final f = makeFile('foto.jpg');
      expect(validateLocalImage(f), isNull);
    });

    test('acepta jpeg, png y webp', () {
      expect(validateLocalImage(makeFile('a.jpeg')), isNull);
      expect(validateLocalImage(makeFile('b.png')), isNull);
      expect(validateLocalImage(makeFile('c.webp')), isNull);
    });

    test('extensión no soportada: mensaje de error', () {
      final f = makeFile('doc.pdf');
      expect(validateLocalImage(f), isNotNull);
    });

    test('mayor a 5MB: mensaje de error', () {
      final f = makeFile('grande.jpg', bytes: 5 * 1024 * 1024 + 1);
      expect(validateLocalImage(f), isNotNull);
    });

    test('exactamente 5MB: sin error (el límite es inclusivo)', () {
      final f = makeFile('justo.jpg', bytes: 5 * 1024 * 1024);
      expect(validateLocalImage(f), isNull);
    });
  });

  group('MyBusinessView — cableado portada/logo', () {
    // Scaffold explícito: `_toast` usa `ScaffoldMessenger.of(context).
    // showSnackBar`, que exige un Scaffold descendiente — sin él Flutter
    // revienta con "no descendant Scaffolds to present to".
    Widget host(Widget child) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(body: child),
        );

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
      seals: ['Negocio verificado'],
      services: <String>[],
      raw: {
        'is_wholesale': true,
        'experience_years': 12,
        'service_area': 'ambos',
        'warranty': '6 meses',
      },
    );

    // Mismo negocio, YA con portada — para probar la rama "hay algo que
    // quitar" del ternario de `onCoverLongPress` en `my_business_screen.dart`.
    const negocioConPortada = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: null,
      coverUrl: 'https://x/portada.jpg',
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: 'Todo en herramientas',
      seals: ['Negocio verificado'],
      services: <String>[],
      raw: {
        'is_wholesale': true,
        'experience_years': 12,
        'service_area': 'ambos',
        'warranty': '6 meses',
      },
    );

    // Mismo negocio, YA con logo.
    const negocioConLogo = (
      id: 'biz-1',
      name: 'Ferretería Pérez',
      logoUrl: 'https://x/logo.jpg',
      coverUrl: null,
      verified: true,
      categoryId: 'ferreteria',
      city: 'Santiago',
      wholesale: true,
      description: 'Todo en herramientas',
      seals: ['Negocio verificado'],
      services: <String>[],
      raw: {
        'is_wholesale': true,
        'experience_years': 12,
        'service_area': 'ambos',
        'warranty': '6 meses',
      },
    );

    testWidgets(
        'tocar la portada llama a pickImage y luego updateCover con el id del negocio',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('jayalo_cover_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final file = File(_join(tmp.path, 'nueva.jpg'))
        ..writeAsBytesSync(List.filled(100, 0));

      String? calledBusinessId;
      String? calledPath;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        pickImage: () async => XFile(file.path),
        updateCover: (businessId, filePath) async {
          calledBusinessId = businessId;
          calledPath = filePath;
          return 'https://cdn/covers/biz-1.jpg';
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BusinessCoverHero));
      await tester.pumpAndSettle();

      expect(calledBusinessId, 'biz-1');
      expect(calledPath, file.path);
    });

    // Fix round 1 (revisor, Important): el ternario de `onCoverLongPress`
    // en `my_business_screen.dart` («solo ofrecer quitar si hay algo que
    // quitar») no tenía cobertura a nivel de pantalla — una inversión
    // pasaría en verde. Las dos siguientes prueban las DOS ramas.
    testWidgets('sin portada: long-press no ofrece quitar (nada que quitar)',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio, // coverUrl: null
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      // Se apunta al nombre (fuera del logo) para no depender de dónde cae
      // el centro geométrico del hero completo.
      await tester.longPress(find.text(negocio.name));
      await tester.pumpAndSettle();

      expect(find.text('¿Quitar la portada?'), findsNothing);
    });

    testWidgets('con portada: long-press SÍ ofrece el diálogo de confirmación',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConPortada, // coverUrl set
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      await tester.longPress(find.text(negocioConPortada.name));
      await tester.pumpAndSettle();

      expect(find.text('¿Quitar la portada?'), findsOneWidget);
    });

    // Mismo par de ramas para el logo — el ternario de `onLogoLongPress` es
    // independiente del de portada y podría invertirse sin que lo anterior
    // lo cazara.
    testWidgets('sin logo: long-press no ofrece quitar (nada que quitar)',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocio, // logoUrl: null
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      // `businessCoverHeroLogoKey` ancla la tarjeta del logo sin ambigüedad:
      // el ícono de tienda del placeholder también aparece (a otro tamaño)
      // en `BusinessDetailsCard`, más abajo en el mismo ListView.
      await tester.longPress(find.byKey(businessCoverHeroLogoKey));
      await tester.pumpAndSettle();

      expect(find.text('¿Quitar el logo?'), findsNothing);
    });

    testWidgets('con logo: long-press SÍ ofrece el diálogo de confirmación',
        (tester) async {
      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConLogo, // logoUrl set, coverUrl null
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
      )));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(businessCoverHeroLogoKey));
      await tester.pumpAndSettle();

      expect(find.text('¿Quitar el logo?'), findsOneWidget);
    });

    // Fix round 1 (revisor, Important): flujo COMPLETO de remoción —
    // confirmar en el diálogo debe llamar al doble `clearCover`/`clearLogo`
    // con el id del negocio y el estado local debe volver a `null` (la UI
    // vuelve a mostrar "+ Añadir portada").
    testWidgets(
        'long-press con portada → confirmar → clearCover(id) y vuelve a mostrar + Añadir portada',
        (tester) async {
      String? clearedId;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConPortada,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        clearCover: (businessId) async => clearedId = businessId,
      )));
      await tester.pumpAndSettle();

      await tester.longPress(find.text(negocioConPortada.name));
      await tester.pumpAndSettle();
      expect(find.text('¿Quitar la portada?'), findsOneWidget);

      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();

      expect(clearedId, 'biz-1');
      // El estado local quedó en null: reaparece la píldora de vacío.
      expect(find.text('Añadir portada'), findsOneWidget);
    });

    testWidgets(
        'long-press con logo → confirmar → clearLogo(id) y vuelve a mostrar el badge +',
        (tester) async {
      String? clearedId;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocioConLogo,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        clearLogo: (businessId) async => clearedId = businessId,
      )));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(businessCoverHeroLogoKey));
      await tester.pumpAndSettle();
      expect(find.text('¿Quitar el logo?'), findsOneWidget);

      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();

      expect(clearedId, 'biz-1');
      // Con logoUrl null de nuevo, reaparece el placeholder + el badge + —
      // ambos acotados a la tarjeta del logo (mismo motivo que arriba).
      final logoCard = find.byKey(businessCoverHeroLogoKey);
      expect(
          find.descendant(
              of: logoCard, matching: find.byIcon(Icons.storefront_outlined)),
          findsOneWidget);
      expect(find.descendant(of: logoCard, matching: find.byIcon(Icons.add)),
          findsOneWidget);
    });

    // Fix round 1 (revisor, Important): el rechazo de `validateLocalImage`
    // dentro de `_changeCover` debe mostrar el toast y NUNCA llamar a
    // `updateCover` — sin esto, un fichero inválido subiría igual.
    testWidgets(
        '_changeCover: extensión inválida muestra el toast y NO llama a updateCover',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('jayalo_cover_bad_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final badFile = File(_join(tmp.path, 'archivo.pdf'))
        ..writeAsBytesSync(List.filled(100, 0));

      var updateCoverCalled = false;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        pickImage: () async => XFile(badFile.path),
        updateCover: (businessId, filePath) async {
          updateCoverCalled = true;
          return 'https://cdn/covers/biz-1.jpg';
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BusinessCoverHero));
      await tester.pumpAndSettle();

      expect(updateCoverCalled, isFalse);
      expect(find.text('Formato no soportado. Usa JPG, PNG o WEBP.'),
          findsOneWidget);
    });

    testWidgets(
        '_changeCover: fichero > 5MB muestra el toast y NO llama a updateCover',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('jayalo_cover_toobig_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final bigFile = File(_join(tmp.path, 'grande.jpg'))
        ..writeAsBytesSync(List.filled(5 * 1024 * 1024 + 1, 0));

      var updateCoverCalled = false;

      await tester.pumpWidget(host(MyBusinessView(
        business: negocio,
        productos: const [],
        servicios: const [],
        reviews: const [],
        rating: null,
        pickImage: () async => XFile(bigFile.path),
        updateCover: (businessId, filePath) async {
          updateCoverCalled = true;
          return 'https://cdn/covers/biz-1.jpg';
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BusinessCoverHero));
      await tester.pumpAndSettle();

      expect(updateCoverCalled, isFalse);
      expect(find.text('La imagen no puede pesar más de 5 MB.'),
          findsOneWidget);
    });
  });
}
