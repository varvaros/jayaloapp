import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';

void main() {
  testWidgets('el menu de admin ofrece las DOS herramientas, cada una con su ruta',
      (t) async {
    final rutas = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminMenuItems(
          esAdmin: true,
          onSelect: rutas.add,
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Registro rápido'), findsOneWidget);
    expect(find.text('Reclutar'), findsOneWidget);
    expect(find.text('Solicitudes sin proveedor'), findsOneWidget);

    await t.tap(find.text('Reclutar'));
    await t.pumpAndSettle();
    expect(rutas, ['/admin/recruit']);
  });

  testWidgets('quien no es admin no ve ninguna de las dos', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminMenuItems(esAdmin: false, onSelect: _nada)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Registro rápido'), findsNothing);
    expect(find.text('Reclutar'), findsNothing);
  });
}

void _nada(String _) {}
