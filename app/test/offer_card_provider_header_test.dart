import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessCardInfo;
import 'package:jayalo_app/features/client/request_status_screen.dart'
    show OfferCardProviderHeader;

// Cabecera de identidad del proveedor en la lista de ofertas del cliente (PO
// 2026-07-29): avatar, nombre y sellos, encima del precio de cada tarjeta.
// `_OfferCard` es privado a `request_status_screen.dart`, así que se testea
// el widget extraído `OfferCardProviderHeader` en aislado (sin montar
// Supabase), tal como sugiere el brief de la tarea.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  BusinessCardInfo info({
    String name = 'Ferretería El Corito',
    bool whatsappVerified = false,
    bool identityVerified = false,
    bool businessVerified = false,
    bool hasPhysicalLocation = false,
  }) =>
      (
        name: name,
        logoUrl: null,
        whatsappVerified: whatsappVerified,
        identityVerified: identityVerified,
        businessVerified: businessVerified,
        hasPhysicalLocation: hasPhysicalLocation,
      );

  testWidgets(
      'con identidad y con sello: aparecen el nombre y el ✓',
      (tester) async {
    await tester.pumpWidget(wrap(OfferCardProviderHeader(
      info: info(name: 'Ferretería El Corito', whatsappVerified: true),
    )));

    expect(find.text('Ferretería El Corito'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets(
      'con identidad y sin ningún sello: aparece el nombre, NO el ✓',
      (tester) async {
    await tester.pumpWidget(wrap(OfferCardProviderHeader(
      info: info(name: 'Ferretería El Corito'),
    )));

    expect(find.text('Ferretería El Corito'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets(
      'sin identidad (info null): no pinta nada, ni un "Proveedor" fantasma',
      (tester) async {
    await tester.pumpWidget(wrap(const OfferCardProviderHeader(info: null)));

    expect(find.byType(OfferCardProviderHeader), findsOneWidget);
    expect(find.text('Proveedor'), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
    expect(find.byIcon(Icons.verified), findsNothing);
    // El widget se resuelve a un SizedBox vacío (SizedBox.shrink), sin Row ni
    // avatar: nada que ocupe espacio o insinúe una cabecera.
    expect(find.byType(Row), findsNothing);
  });

  // Sello "Tienda física" (PO 2026-08-12) — AUTODECLARADO, nunca junto al ✓
  // verde de verificación de arriba.
  testWidgets(
      'con hasPhysicalLocation: aparece el sello, distinto del ✓ de verificado',
      (tester) async {
    await tester.pumpWidget(wrap(OfferCardProviderHeader(
      info: info(
        name: 'Ferretería El Corito',
        whatsappVerified: true,
        hasPhysicalLocation: true,
      ),
    )));

    expect(find.text('Ferretería El Corito'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.text('Tienda física'), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
  });

  testWidgets('sin hasPhysicalLocation: no aparece el sello', (tester) async {
    await tester.pumpWidget(wrap(OfferCardProviderHeader(
      info: info(name: 'Ferretería El Corito'),
    )));

    expect(find.text('Tienda física'), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
  });
}
