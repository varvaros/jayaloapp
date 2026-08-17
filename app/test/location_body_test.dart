import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/location_body.dart';
import 'package:jayalo_app/domain/geo.dart';

void main() {
  test('el cuerpo lleva el enlace al mapa cuando hay coordenadas', () {
    final b = buildLocationBody(
      address: 'Calle Primera 12',
      cityLine: 'Parque del Este, Santo Domingo Este',
      reference: 'Casa azul',
      lat: 18.48,
      lng: -69.85,
    );
    expect(b, contains('Calle Primera 12'));
    expect(b, contains('Referencia: Casa azul'));
    expect(b, contains('https://www.google.com/maps/search/?api=1&query=18.48,-69.85'));
    expect(b!.split('\n').last, startsWith('https://www.google.com/maps/'));
  });

  test('sin coordenadas no hay enlace, pero el cuerpo sigue valiendo', () {
    final b = buildLocationBody(
        address: 'Calle Primera 12', cityLine: '', reference: '', lat: null, lng: null);
    expect(b, 'Calle Primera 12');
  });

  test('sin nada devuelve null', () {
    expect(
        buildLocationBody(
            address: '', cityLine: '', reference: '', lat: null, lng: null),
        isNull);
  });

  test('el cuerpo del local pone el nombre primero y el enlace al final', () {
    final body = businessAddressBody(
      name: 'Ferretería El Corito',
      address: 'Calle Duarte 45',
      cityLine: 'Los Prados, Santiago',
      lat: 19.451,
      lng: -70.697,
    );
    expect(body.split('\n').first, 'Ferretería El Corito');
    expect(body.split('\n').last, mapsLinkFor(19.451, -70.697));
  });

  test('el cuerpo del local sin coordenadas no lleva enlace', () {
    final body = businessAddressBody(
      name: 'Ferretería El Corito',
      address: 'Calle Duarte 45',
      cityLine: 'Los Prados, Santiago',
      lat: null,
      lng: null,
    );
    expect(body, 'Ferretería El Corito\nCalle Duarte 45\nLos Prados, Santiago');
  });
}
