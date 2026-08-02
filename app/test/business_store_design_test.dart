import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/business_cover_hero.dart';
import 'package:jayalo_app/features/shared/business_details_card.dart';

/// Pedido PO 2026-08-01: "la sección de la tienda en la app aún no tiene el
/// diseño que se coordinó (como en la web)". Faltaban dos piezas: el hero de
/// portada (`cover_url`, que la app no leía en ningún sitio) y la ficha de
/// detalles completa. El bloque de confianza sí se había portado en su día.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('BusinessCoverHero', () {
    testWidgets('sin portada sigue mostrando la identidad, no un hueco',
        (tester) async {
      await tester.pumpWidget(host(const BusinessCoverHero(name: 'El Corito')));
      await tester.pumpAndSettle();

      expect(find.text('El Corito'), findsOneWidget);
    });

    testWidgets('un negocio sin nombre no deja la portada muda',
        (tester) async {
      await tester.pumpWidget(host(const BusinessCoverHero(name: '')));
      await tester.pumpAndSettle();

      expect(find.text('Tu negocio'), findsOneWidget);
    });

    testWidgets('pinta el subtítulo y los sellos que se le pasen',
        (tester) async {
      await tester.pumpWidget(host(const BusinessCoverHero(
        name: 'El Corito',
        subtitle: 'Ferretería · Santiago',
        seals: ['Identidad verificada', 'RNC verificado'],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Ferretería · Santiago'), findsOneWidget);
      expect(find.text('Identidad verificada'), findsOneWidget);
      expect(find.text('RNC verificado'), findsOneWidget);
    });
  });

  group('BusinessDetailsCard', () {
    testWidgets('un negocio sin ningún detalle no dibuja la ficha vacía',
        (tester) async {
      await tester.pumpWidget(host(const BusinessDetailsCard(business: {})));
      await tester.pumpAndSettle();

      expect(find.textContaining('DETALLES'), findsNothing);
    });

    testWidgets('pinta una fila por dato, con etiqueta y valor',
        (tester) async {
      await tester.pumpWidget(host(const BusinessDetailsCard(business: {
        'experience_years': 12,
        'service_area': 'ambos',
        'payment_methods': ['efectivo', 'transferencia'],
        'warranty': '6 meses',
      })));
      await tester.pumpAndSettle();

      expect(find.text('Experiencia'), findsOneWidget);
      expect(find.text('12 años'), findsOneWidget);
      expect(find.text('Cobertura'), findsOneWidget);
      expect(find.text('En taller y a domicilio'), findsOneWidget);
      expect(find.text('Pagos'), findsOneWidget);
      expect(find.text('Efectivo, Transferencia'), findsOneWidget);
      expect(find.text('Garantía'), findsOneWidget);
      expect(find.text('6 meses'), findsOneWidget);
    });

    testWidgets('el horario semanal llega resumido, no crudo', (tester) async {
      await tester.pumpWidget(host(const BusinessDetailsCard(business: {
        'service_hours': {
          'mon': {'open': '08:00', 'close': '17:00'},
          'tue': {'open': '08:00', 'close': '17:00'},
          'wed': {'open': '08:00', 'close': '17:00'},
        },
      })));
      await tester.pumpAndSettle();

      expect(find.text('Lunes a miércoles 8:00 AM a 5:00 PM'), findsOneWidget);
    });
  });
}
