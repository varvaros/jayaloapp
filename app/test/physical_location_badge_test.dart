import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/physical_location_badge.dart';

/// Sello "Tienda física" (PO 2026-08-18): pegado a la portada en la tienda
/// pública y en "Mi negocio". Lo que se fija aquí es el contrato de `maybe`:
/// sin local devuelve `null`, para que ningún llamador monte un hueco vacío.
void main() {
  test('sin local declarado no hay widget', () {
    expect(PhysicalLocationBadge.maybe(hasPhysicalLocation: false), isNull);
  });

  test('con local declarado devuelve el badge', () {
    expect(PhysicalLocationBadge.maybe(hasPhysicalLocation: true),
        isA<PhysicalLocationBadge>());
  });

  testWidgets('pinta la etiqueta «Tienda física»', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PhysicalLocationBadge()),
    ));
    expect(find.text('Tienda física'), findsOneWidget);
  });
}
