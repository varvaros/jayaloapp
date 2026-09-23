import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_image.dart';
import 'package:jayalo_app/features/admin/recruit_screen.dart';

/// «En el reclutador, ponle las imágenes a las solicitudes, así puedo
/// identificarlas bien» (PO 2026-09-22). La fila de Reclutar era solo
/// título + zona + fecha: dos «Instalación de piezas de baño» eran
/// indistinguibles.
Map<String, dynamic> _fila(String id, {String? imageUrl, List<String>? imageUrls}) => {
  'id': id,
  'title': 'Solicitud $id',
  'zone': 'Piantini',
  'description': 'D',
  'budget_min': 1000,
  'budget_max': 2000,
  'urgency': 'normal',
  'kind': 'product',
  'created_at': '2026-09-14T10:00:00Z',
  'image_url': imageUrl,
  'image_urls': imageUrls,
};

void main() {
  group('firstRequestImage — la misma regla que Mis solicitudes', () {
    test('image_url primaria manda', () {
      expect(firstRequestImage(_fila('a', imageUrl: 'https://x/1.jpg', imageUrls: ['https://x/2.jpg'])), 'https://x/1.jpg');
    });
    test('sin primaria, la primera de image_urls', () {
      expect(firstRequestImage(_fila('a', imageUrls: ['https://x/2.jpg', 'https://x/3.jpg'])), 'https://x/2.jpg');
    });
    test('las cadenas vacías no cuentan como foto', () {
      expect(firstRequestImage(_fila('a', imageUrl: '', imageUrls: ['', 'https://x/3.jpg'])), 'https://x/3.jpg');
    });
    test('sin ninguna foto, null', () {
      expect(firstRequestImage(_fila('a')), isNull);
      expect(firstRequestImage(_fila('a', imageUrls: const [])), isNull);
    });
  });

  Widget app(List<Map<String, dynamic>> filas) => MaterialApp(
    home: RecruitScreen(
      load: ({int limit = 100}) async => filas,
      coverage: (ids) async => {for (final id in ids) id: 0},
    ),
  );

  testWidgets('cada fila lleva su miniatura, con la URL de su solicitud', (t) async {
    await t.pumpWidget(app([
      _fila('a', imageUrl: 'https://x/a.jpg'),
      _fila('b', imageUrls: ['https://x/b.jpg']),
    ]));
    await t.pumpAndSettle();
    final thumbs = t.widgetList<RecruitThumb>(find.byType(RecruitThumb)).toList();
    expect(thumbs.map((w) => w.url), ['https://x/a.jpg', 'https://x/b.jpg']);
  });

  testWidgets('una solicitud sin foto enseña el hueco, no revienta ni desaparece', (t) async {
    await t.pumpWidget(app([_fila('sinfoto')]));
    await t.pumpAndSettle();
    expect(find.text('Solicitud sinfoto'), findsOneWidget);
    final thumb = t.widget<RecruitThumb>(find.byType(RecruitThumb));
    expect(thumb.url, isNull);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
