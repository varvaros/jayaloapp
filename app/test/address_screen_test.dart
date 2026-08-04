import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/settings/address_screen.dart';

void main() {
  testWidgets('precarga los campos y guarda lo editado', (t) async {
    Map<String, dynamic>? guardado;
    await t.pumpWidget(MaterialApp(
      home: AddressScreen(
        load: () async => {
          'address': 'Calle Primera 12',
          'sector': 'Parque del Este',
          'city': 'Santo Domingo Este',
          'address_reference': '',
        },
        save: (m) async => guardado = m,
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Parque del Este'), findsOneWidget);
    await t.enterText(find.byKey(const Key('campo-referencia')), 'Casa azul');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(guardado!['address_reference'], 'Casa azul');
  });
}
