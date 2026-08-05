import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/location_body.dart';

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
}
