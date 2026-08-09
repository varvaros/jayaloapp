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
    Widget host(Widget child) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: child,
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
  });
}
