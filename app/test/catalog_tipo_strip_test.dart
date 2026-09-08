import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/catalog_tipo_strip.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  testWidgets('cinco chips con conteo, el activo oscuro, y avisa al tocar', (
    tester,
  ) async {
    String? tocado;
    await tester.pumpWidget(
      host(
        CatalogTipoStrip(
          tipo: 'todos',
          conteos: const {
            'todos': 14,
            'producto': 7,
            'servicio': 5,
            'paquete': 3,
            'proveedor': 8,
          },
          onTipo: (t) => tocado = t,
        ),
      ),
    );
    for (final l in [
      'Todos',
      'Productos',
      'Servicios',
      'Paquetes',
      'Proveedores',
    ]) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.text('Paquetes'));
    expect(tocado, 'paquete');
  });
}
