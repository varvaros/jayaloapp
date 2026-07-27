import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/geo.dart';

void main() {
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
