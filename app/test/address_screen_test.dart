import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/geo.dart';
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
          // street/street_number/lat/lng viajan intactos load -> save aunque
          // esta pantalla no los expone como campos editables (hallazgo 2 de
          // la ronda de arreglo 1): sin esto, nada prueba que sobrevivan el
          // viaje completo.
          'street': 'Calle Primera',
          'street_number': '12',
          'lat': 18.4861,
          'lng': -69.9312,
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
    expect(guardado!['street'], 'Calle Primera');
    expect(guardado!['street_number'], '12');
    expect(guardado!['lat'], 18.4861);
    expect(guardado!['lng'], -69.9312);
  });

  testWidgets('si la carga falla NO deja guardar (no machaca la direccion buena)',
      (t) async {
    var guardadas = 0;
    await t.pumpWidget(MaterialApp(
      home: AddressScreen(
        load: () async => throw Exception('sin red'),
        save: (m) async => guardadas++,
      ),
    ));
    await t.pumpAndSettle();

    // El formulario NO se pinta: en blanco es indistinguible de "no tengo
    // direccion", y guardar ese blanco escribia NULL sobre city/sector/street/
    // street_number/address_reference.
    expect(find.text('No pudimos cargar tu dirección'), findsOneWidget);
    expect(find.byKey(const Key('campo-referencia')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    expect(guardadas, 0);
  });

  testWidgets('Reintentar vuelve a cargar y entonces si guarda', (t) async {
    var intentos = 0;
    Map<String, dynamic>? guardado;
    await t.pumpWidget(MaterialApp(
      home: AddressScreen(
        load: () async {
          intentos++;
          if (intentos == 1) throw Exception('sin red');
          return {'address': 'Calle Primera 12', 'city': 'Santo Domingo Este'};
        },
        save: (m) async => guardado = m,
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await t.pumpAndSettle();

    expect(find.text('No pudimos cargar tu dirección'), findsNothing);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(guardado!['address'], 'Calle Primera 12');
    expect(guardado!['city'], 'Santo Domingo Este');
  });

  group('applyGeocodedPlace (hallazgo 1: geocode parcial no debe borrar)', () {
    test('city y sector vacios en el geocode conservan lo que ya habia', () {
      final applied = applyGeocodedPlace(
        place: const GeocodedPlace(
          country: '',
          city: '',
          sector: '',
          street: 'Autopista Las Américas',
          streetNumber: '',
          addressLine: 'Autopista Las Américas',
        ),
        currentAddress: 'Calle Primera 12',
        currentCountry: 'República Dominicana',
        currentStreet: 'Calle Primera',
        currentStreetNumber: '12',
        currentCity: 'Santo Domingo Este',
        currentSector: 'Parque del Este',
      );
      // La via SI vino en el geocode: se actualiza.
      expect(applied.street, 'Autopista Las Américas');
      // Ciudad y sector NO vinieron (geocode parcial): se conserva lo que el
      // usuario ya tenia, no se borra.
      expect(applied.city, 'Santo Domingo Este');
      expect(applied.sector, 'Parque del Este');
      // Pais tampoco vino: igual se conserva.
      expect(applied.country, 'República Dominicana');
    });

    test('un geocode completo SI reemplaza todos los campos', () {
      final applied = applyGeocodedPlace(
        place: const GeocodedPlace(
          country: 'República Dominicana',
          city: 'Santiago',
          sector: 'Los Jardines',
          street: 'Calle Segunda',
          streetNumber: '34',
          addressLine: 'Calle Segunda 34',
        ),
        currentAddress: 'Calle Primera 12',
        currentCountry: 'República Dominicana',
        currentStreet: 'Calle Primera',
        currentStreetNumber: '12',
        currentCity: 'Santo Domingo Este',
        currentSector: 'Parque del Este',
      );
      expect(applied.address, 'Calle Segunda 34');
      expect(applied.street, 'Calle Segunda');
      expect(applied.streetNumber, '34');
      expect(applied.city, 'Santiago');
      expect(applied.sector, 'Los Jardines');
    });
  });
}
