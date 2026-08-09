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

  testWidgets('reelegir el mismo pais no borra provincias ni sectores',
      (tester) async {
    final una = citiesFor(kCountries.first).first;
    provincias = [una];
    sectores = sectorsFor(kCountries.first, una).take(1).toList();
    await montar(tester);
    // Con un solo pais en el catalogo, el desplegable de pais excluye el
    // pais actual de sus propias opciones (igual que provincia y sector
    // excluyen lo ya elegido), asi que no queda nada que ofrecer y tocarlo
    // no debe abrir un menu ni tocar la seleccion vigente.
    await tester.tap(find.text('País'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownMenuItem<String>), findsNothing);
    expect(provincias, [una]);
    expect(sectores, sectorsFor(kCountries.first, una).take(1).toList());
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
    expect(find.widgetWithText(Chip, kAllSectorsLabel), findsOneWidget);
    // Y ese chip resumen realmente controla la seleccion: quitarlo la vacia.
    await tester.tap(find.byTooltip('Quitar $kAllSectorsLabel'));
    await tester.pumpAndSettle();
    expect(sectores, isEmpty);
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

  testWidgets(
      'quitar una provincia conserva el sector fuera de catalogo y '
      'descarta solo los exclusivos de esa provincia', (tester) async {
    final ciudades = citiesFor(kCountries.first);
    final a = ciudades[0];
    final b = ciudades[1];
    final sectoresB = sectorsFor(kCountries.first, b).toSet();
    // Un sector que solo pertenece a 'a', calculado en vez de asumido, por si
    // el catalogo cambia.
    final exclusivoDeA = sectorsFor(kCountries.first, a)
        .firstWhere((s) => !sectoresB.contains(s));
    provincias = [a, b];
    sectores = [exclusivoDeA, 'Parque del Este'];
    await montar(tester);
    await tester.tap(find.byTooltip('Quitar $a'));
    await tester.pumpAndSettle();
    // El caso que motiva la union en availableSectors: el sector exclusivo
    // de 'a' se va con ella, pero el que ningun catalogo conoce sobrevive,
    // en la misma operacion y con 'b' todavia presente.
    expect(sectores, isNot(contains(exclusivoDeA)));
    expect(sectores, contains('Parque del Este'));
  });

  testWidgets(
      'elegir un sector no vacia la provincia cuando el anfitrion muta '
      'las listas in-place (como hace la pantalla real)', (tester) async {
    // `provider_onboarding_screen.dart` no reasigna `provincias = cities;`
    // como el resto de este archivo: hace `_cities..clear()..addAll(cities)`
    // sobre la lista que YA tiene. Si el widget reenvia su propia `cities`
    // por referencia (el bug que este test caza), `clear()` vacia tambien el
    // origen antes de que `addAll` pueda copiar nada.
    //
    // Se elige el sector por "Todos los sectores" y no por un item
    // individual: este test es sobre el bug de alias de listas (el fix de
    // arriba en este mismo archivo), no sobre el bug — ya arreglado, ver los
    // tests de mas abajo — de `DropdownButtonFormField` reteniendo su
    // `value` entre rebuilds. Usar "Todos" mantiene este test enfocado en un
    // solo hallazgo a la vez, y ejercita el mismo camino de codigo en
    // `_addSector` de todas formas.
    final una = citiesFor(kCountries.first).first;
    final todosLosSectoresDeUna = sectorsFor(kCountries.first, una);
    provincias = [una];
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
                  provincias
                    ..clear()
                    ..addAll(cities);
                  sectores
                    ..clear()
                    ..addAll(sectors);
                });
              },
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Sector (opcional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kAllSectorsLabel));
    await tester.pumpAndSettle();
    expect(sectores.toSet(), todosLosSectoresDeUna.toSet());
    // La provincia elegida antes de tocar el sector debe seguir ahi.
    expect(provincias, [una]);
    expect(find.widgetWithText(Chip, una), findsOneWidget);
  });

  testWidgets(
      'elegir provincias una por una, buscando, sobrevive a picks repetidos',
      (tester) async {
    // Antes esto ejercitaba el gotcha del `_DropdownButtonFormFieldState`
    // retenido ("exactly one item"); con la hoja de busqueda ese estado no
    // existe, pero el COMPORTAMIENTO que fijaba sigue vigente: dos picks
    // seguidos funcionan y el elegido sale de las opciones. Se busca en
    // minusculas y sin la tilde a proposito: es la promesa del buscador.
    // (Con el orden alfabetico, "Distrito Nacional" ya no esta arriba: sin
    // buscador el tap caeria fuera del viewport de la hoja.)
    final ciudades = citiesFor(kCountries.first);
    final a = ciudades[0]; // Distrito Nacional
    final b = ciudades[1]; // Santo Domingo
    await montar(tester);
    await tester.tap(find.text('Provincia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'distrito');
    await tester.pumpAndSettle();
    await tester.tap(find.text(a));
    await tester.pumpAndSettle();
    expect(provincias, [a]);
    expect(find.widgetWithText(Chip, a), findsOneWidget);
    // Segundo pick: la hoja se vuelve a abrir limpia, sin retener nada.
    await tester.tap(find.text('Provincia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'santo domingo');
    await tester.pumpAndSettle();
    await tester.tap(find.text(b));
    await tester.pumpAndSettle();
    expect(provincias, [a, b]);
    expect(find.widgetWithText(Chip, b), findsOneWidget);
  });

  testWidgets('elegir un sector individual (no "Todos") buscando funciona',
      (tester) async {
    final una = citiesFor(kCountries.first).first;
    final sectorElegido = sectorsFor(kCountries.first, una).first; // Naco
    provincias = [una];
    await montar(tester);
    await tester.tap(find.text('Sector (opcional)'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), sectorElegido.toLowerCase());
    await tester.pumpAndSettle();
    await tester.tap(find.text(sectorElegido));
    await tester.pumpAndSettle();
    expect(sectores, [sectorElegido]);
    expect(find.widgetWithText(Chip, sectorElegido), findsOneWidget);
  });
}
