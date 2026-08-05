import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/locations.dart';
import 'package:jayalo_app/features/shared/location_coverage_picker.dart';

void main() {
  // Estado que el widget no guarda: el test hace de pantalla anfitriona.
  late String pais;
  late List<String> provincias;
  late List<String> sectores;

  setUp(() {
    pais = kCountries.first;
    provincias = [];
    sectores = [];
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: StatefulBuilder(builder: (c, setLocal) {
        return Scaffold(
          body: SingleChildScrollView(
            child: LocationCoveragePicker(
              country: pais,
              cities: provincias,
              sectors: sectores,
              onChanged: ({required country, required cities, required sectors}) {
                setLocal(() {
                  pais = country;
                  provincias = cities;
                  sectores = sectors;
                });
              },
            ),
          ),
        );
      }),
    ));
  }

  testWidgets('los sectores son la union de las provincias elegidas',
      (tester) async {
    final dos = citiesFor(kCountries.first).take(2).toList();
    provincias = dos;
    await montar(tester);
    final esperados = <String>{
      ...sectorsFor(kCountries.first, dos[0]),
      ...sectorsFor(kCountries.first, dos[1]),
    };
    // El widget expone los sectores disponibles; comprobar contra su lista
    // interna via el callback de "Todos los sectores". El item de un
    // DropdownButtonFormField solo existe en el arbol con el menu abierto,
    // asi que primero hay que abrirlo tocando la etiqueta del campo.
    await tester.tap(find.text('Sector (opcional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🗺️ Todos los sectores'));
    await tester.pumpAndSettle();
    expect(sectores.toSet(), esperados);
  });

  testWidgets('sin provincia elegida no hay sectores que ofrecer',
      (tester) async {
    await montar(tester);
    expect(find.text('🗺️ Todos los sectores'), findsNothing);
  });

  testWidgets('con todos seleccionados se colapsa a un solo chip',
      (tester) async {
    final una = citiesFor(kCountries.first)
        .firstWhere((c) => sectorsFor(kCountries.first, c).length > 1);
    provincias = [una];
    sectores = sectorsFor(kCountries.first, una).toList();
    await montar(tester);
    // Un unico chip resumen, no la lista entera.
    for (final s in sectores) {
      expect(find.widgetWithText(Chip, s), findsNothing);
    }
  });

  testWidgets('quitar una provincia se lleva sus sectores exclusivos',
      (tester) async {
    final ciudades = citiesFor(kCountries.first);
    final a = ciudades[0];
    provincias = [a];
    sectores = sectorsFor(kCountries.first, a).take(1).toList();
    await montar(tester);
    // Quitar la unica provincia deja los sectores vacios.
    await tester.tap(find.byTooltip('Quitar $a'));
    await tester.pumpAndSettle();
    expect(sectores, isEmpty);
  });

  testWidgets('un sector fuera del catalogo sobrevive', (tester) async {
    final una = citiesFor(kCountries.first).first;
    provincias = [una];
    sectores = ['Parque del Este'];
    await montar(tester);
    // Se ofrece y se mantiene seleccionado aunque kLocations no lo conozca.
    expect(find.text('Parque del Este'), findsWidgets);
  });
}
