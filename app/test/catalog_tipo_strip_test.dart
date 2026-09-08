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

    // «el activo oscuro»: CatalogChip con dark:true pinta el fondo del chip
    // activo en cs.onPrimaryContainer (fondo oscuro + texto blanco), no en
    // el cs.primaryContainer claro de las categorías (M-5, revisión final).
    final cs = jayaloTheme(Brightness.light).colorScheme;
    final activo = tester.widget<Material>(
      find
          .ancestor(of: find.text('Todos'), matching: find.byType(Material))
          .first,
    );
    expect(activo.color, cs.onPrimaryContainer);

    await tester.tap(find.text('Paquetes'));
    expect(tocado, 'paquete');
  });
}
