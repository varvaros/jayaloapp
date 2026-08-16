import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/geo.dart';

void main() {
  group('composeStreetLine', () {
    test('calle y número cuando el geocoder los separa', () {
      expect(
        composeStreetLine(
            thoroughfare: 'Calle Duarte', subThoroughfare: '45', street: 'Calle Duarte 45'),
        'Calle Duarte 45',
      );
    });
    test('solo el nombre si no hay número', () {
      expect(composeStreetLine(thoroughfare: 'Calle Duarte'), 'Calle Duarte');
    });
    // El caso que motiva el respaldo: varios Android dejan `thoroughfare` vacío
    // y mandan la línea de la calle en `street`. Sin esto el campo quedaba en
    // blanco justo donde el código anterior sí lo llenaba.
    test('cae a street cuando thoroughfare viene vacío', () {
      expect(
        composeStreetLine(thoroughfare: '', subThoroughfare: null, street: 'Calle Duarte 45'),
        'Calle Duarte 45',
      );
    });
    test('street no gana si thoroughfare trae algo', () {
      expect(
        composeStreetLine(thoroughfare: 'Calle Duarte', street: 'Otra cosa, Santo Domingo'),
        'Calle Duarte',
      );
    });
    test('recorta espacios y no deja la cadena en blanco', () {
      expect(composeStreetLine(thoroughfare: '  ', street: '  '), '');
      expect(composeStreetLine(), '');
    });
  });

  test('une campos no vacíos', () {
    expect(
      formatPlacemarkAddress(street: 'Calle 1', subLocality: 'Los Prados', locality: 'Santo Domingo', administrativeArea: 'D.N.'),
      'Calle 1, Los Prados, Santo Domingo, D.N.',
    );
  });
  test('omite vacíos y nulos', () {
    expect(formatPlacemarkAddress(street: 'Calle 1', locality: 'SD'), 'Calle 1, SD');
  });
  test('deduplica repetidos', () {
    expect(formatPlacemarkAddress(locality: 'SD', administrativeArea: 'SD'), 'SD');
  });
  test('vacío si todo nulo', () {
    expect(formatPlacemarkAddress(), '');
  });
}
