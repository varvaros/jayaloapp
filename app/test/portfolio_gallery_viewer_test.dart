import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/portfolio_gallery_viewer.dart';

/// Modal galería de un TRABAJO en la tienda pública del cliente (pedido PO
/// 2026-08-09: "Trabajos no abre"). Fotos a pantalla grande con swipe
/// horizontal, indicador de posición, título/descripción visibles, cierre
/// con la X o el gesto de atrás. Sin botones de edición — es la vista del
/// cliente ("Mi negocio" sigue abriendo su editor propio, sin cambios).
void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  group('PortfolioGalleryViewer (pintado directo)', () {
    testWidgets('pinta título, descripción e indicador "1 / N" con varias fotos',
        (tester) async {
      await tester.pumpWidget(host(const PortfolioGalleryViewer(
        images: [
          'https://x/1.jpg',
          'https://x/2.jpg',
          'https://x/3.jpg',
        ],
        title: 'Instalación de verja',
        description: 'Verja perimetral en hierro forjado.',
      )));
      await tester.pump();

      expect(find.text('Instalación de verja'), findsOneWidget);
      expect(find.text('Verja perimetral en hierro forjado.'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('con una sola foto no pinta el indicador de posición',
        (tester) async {
      await tester.pumpWidget(host(const PortfolioGalleryViewer(
        images: ['https://x/1.jpg'],
        title: 'Pintura de fachada',
      )));
      await tester.pump();

      expect(find.textContaining(' / '), findsNothing);
      expect(find.text('Pintura de fachada'), findsOneWidget);
    });

    testWidgets('sin descripción no pinta nada extra (no revienta)',
        (tester) async {
      await tester.pumpWidget(host(const PortfolioGalleryViewer(
        images: ['https://x/1.jpg'],
        title: 'Solo título',
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Solo título'), findsOneWidget);
    });

    testWidgets('deslizar a la siguiente foto avanza el indicador',
        (tester) async {
      await tester.pumpWidget(host(const PortfolioGalleryViewer(
        images: ['https://x/1.jpg', 'https://x/2.jpg'],
        title: 'Con dos fotos',
      )));
      await tester.pump();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('sin fotos: no revienta, sigue mostrando título',
        (tester) async {
      await tester.pumpWidget(host(const PortfolioGalleryViewer(
        images: [],
        title: 'Sin fotos',
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sin fotos'), findsOneWidget);
    });
  });

  group('showPortfolioGallery (empuja y cierra)', () {
    testWidgets('abre sobre la pantalla actual y la X lo cierra',
        (tester) async {
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPortfolioGallery(
                context,
                images: const ['https://x/1.jpg'],
                title: 'Instalación de verja',
                description: 'Detalle del trabajo.',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Instalación de verja'), findsOneWidget);
      expect(find.text('Detalle del trabajo.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Instalación de verja'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('el gesto de atrás (Navigator.pop) también cierra la galería',
        (tester) async {
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPortfolioGallery(
                context,
                images: const ['https://x/1.jpg'],
                title: 'Pintura de fachada',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Pintura de fachada'), findsOneWidget);

      // Simula el back del sistema (Android), sin depender de encontrar la X.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Pintura de fachada'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
