import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/geo.dart';

void main() {
  test('composeAddressLine omite vacios y no repite', () {
    expect(
      composeAddressLine(
          street: 'Calle Primera',
          streetNumber: '12',
          sector: 'Parque del Este',
          city: 'Santo Domingo Este'),
      'Calle Primera 12, Parque del Este, Santo Domingo Este',
    );
    expect(
      composeAddressLine(
          street: '', streetNumber: '', sector: 'Alma Rosa', city: 'Alma Rosa'),
      'Alma Rosa',
    );
  });

  test('mapsLinkFor arma un enlace universal', () {
    expect(mapsLinkFor(18.482243, -69.854165),
        'https://www.google.com/maps/search/?api=1&query=18.482243,-69.854165');
  });

  test('splitMapLink separa el enlace del texto', () {
    const body = 'Calle Primera 12\nParque del Este\n'
        'https://www.google.com/maps/search/?api=1&query=18.48,-69.85';
    final r = splitMapLink(body);
    expect(r.text, 'Calle Primera 12\nParque del Este');
    expect(r.mapUrl, 'https://www.google.com/maps/search/?api=1&query=18.48,-69.85');
  });

  test('splitMapLink deja intacto un cuerpo sin enlace', () {
    final r = splitMapLink('Calle Primera 12');
    expect(r.text, 'Calle Primera 12');
    expect(r.mapUrl, isNull);
  });

  test('splitMapLink con DOS lineas de enlace usa la ULTIMA', () {
    // El compositor siempre pone el enlace real al final; si el texto libre
    // del usuario cuela otra linea con ese prefijo, debe quedarse como texto.
    const body = 'https://www.google.com/maps/foo\n'
        'Calle Primera 12\n'
        'https://www.google.com/maps/search/?api=1&query=18.48,-69.85';
    final r = splitMapLink(body);
    expect(r.text, 'https://www.google.com/maps/foo\nCalle Primera 12');
    expect(r.mapUrl,
        'https://www.google.com/maps/search/?api=1&query=18.48,-69.85');
  });

  test('GeocodedPlace.fromJson tolera claves ausentes', () {
    final p = GeocodedPlace.fromJson({'city': 'Santiago'});
    expect(p.city, 'Santiago');
    expect(p.sector, '');
    expect(p.sectorInCatalog, false);
  });
}
