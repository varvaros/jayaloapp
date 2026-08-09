import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/searchable_picker.dart';

/// Pedido PO 2026-08-08: los dropdowns largos de la app (rubros, provincias,
/// sectores) ganan un buscador y orden alfabético. Este widget compartido es
/// el que sustituye a los `DropdownButtonFormField` "adder" en esos sitios.
void main() {
  Widget host({
    required List<PickerItem> items,
    List<PickerItem> pinned = const [],
    ValueChanged<String>? onPick,
    bool enabled = true,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SearchablePickerField(
            hint: 'Provincia',
            items: items,
            pinned: pinned,
            enabled: enabled,
            onPick: onPick ?? (_) {},
          ),
        ),
      );

  const provincias = [
    PickerItem('esp', 'Espaillat'),
    PickerItem('eba', 'Ébano'),
    PickerItem('daj', 'Dajabón'),
    PickerItem('azu', 'Azua'),
  ];

  testWidgets('abre la hoja con las opciones en alfabético insensible a tildes',
      (t) async {
    await t.pumpWidget(host(items: provincias));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    final ys = [
      for (final label in ['Azua', 'Dajabón', 'Ébano', 'Espaillat'])
        t.getTopLeft(find.text(label)).dy,
    ];
    // Ébano ENTRE Dajabón y Espaillat: el sort() por defecto lo mandaría al
    // final de todo (orden por código Unicode).
    expect(ys[0] < ys[1] && ys[1] < ys[2] && ys[2] < ys[3], isTrue,
        reason: 'esperado Azua < Dajabón < Ébano < Espaillat, y = $ys');
  });

  testWidgets('el buscador filtra sin tildes ni mayúsculas', (t) async {
    await t.pumpWidget(host(items: provincias));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'eban');
    await t.pumpAndSettle();

    expect(find.text('Ébano'), findsOneWidget);
    expect(find.text('Azua'), findsNothing);
    expect(find.text('Dajabón'), findsNothing);
  });

  testWidgets('elegir devuelve el value y cierra la hoja', (t) async {
    String? picked;
    await t.pumpWidget(host(items: provincias, onPick: (v) => picked = v));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    await t.tap(find.text('Dajabón'));
    await t.pumpAndSettle();

    expect(picked, 'daj');
    expect(find.byType(TextField), findsNothing,
        reason: 'la hoja debe cerrarse al elegir');
  });

  testWidgets('lo fijado va PRIMERO y no se ordena con el resto', (t) async {
    await t.pumpWidget(host(
      items: provincias,
      pinned: const [PickerItem('*', '🗺️ Todos los sectores')],
    ));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    final yPinned = t.getTopLeft(find.text('🗺️ Todos los sectores')).dy;
    final yAzua = t.getTopLeft(find.text('Azua')).dy;
    expect(yPinned < yAzua, isTrue,
        reason: '"Todos los sectores" es la acción principal, no una opción '
            'más de la T');
  });

  testWidgets('sin opciones el campo queda deshabilitado', (t) async {
    await t.pumpWidget(host(items: const [], enabled: true));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    expect(find.byType(TextField), findsNothing,
        reason: 'no hay nada que elegir: no se abre hoja vacía');
  });

  testWidgets('sin coincidencias muestra un vacío honesto', (t) async {
    await t.pumpWidget(host(items: provincias));
    await t.tap(find.text('Provincia'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'zzz');
    await t.pumpAndSettle();

    expect(find.textContaining('Sin resultados'), findsOneWidget);
  });
}
