import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/locations.dart';

void main() {
  group('árbol', () {
    test('las ciudades dependen del país', () {
      expect(citiesOf('República Dominicana'), contains('Santiago'));
      expect(citiesOf('Narnia'), isEmpty);
      expect(citiesOf(null), isEmpty);
    });

    test('los sectores dependen de la ciudad', () {
      expect(sectorsOf('República Dominicana', 'Distrito Nacional'),
          contains('Piantini'));
      // Piantini es del Distrito Nacional, no de Santiago.
      expect(sectorsOf('República Dominicana', 'Santiago'),
          isNot(contains('Piantini')));
      expect(sectorsOf('República Dominicana', null), isEmpty);
      expect(sectorsOf(null, 'Santiago'), isEmpty);
    });
  });

  group('normalizeLoose', () {
    test('ignora tildes y mayúsculas', () {
      expect(normalizeLoose('Bánica'), normalizeLoose('BANICA'));
      expect(normalizeLoose('  Higüey '), 'higuey');
    });
    test('vacío para nulo', () => expect(normalizeLoose(null), ''));
  });

  group('matchLocation', () {
    test('resuelve ciudad y sector del geocoder', () {
      final r = matchLocation(
          country: 'República Dominicana',
          locality: 'Distrito Nacional',
          subLocality: 'Naco');
      expect(r.city, 'Distrito Nacional');
      expect(r.sector, 'Naco');
    });

    test('tolera tildes y mayúsculas distintas', () {
      final r = matchLocation(
          country: 'República Dominicana',
          locality: 'SANTIAGO',
          subLocality: 'pekin');
      expect(r.city, 'Santiago');
      expect(r.sector, 'Pekín');
    });

    test('deduce la ciudad cuando el geocoder solo da el sector', () {
      final r = matchLocation(
          country: 'República Dominicana', locality: 'Piantini');
      expect(r.city, 'Distrito Nacional');
      expect(r.sector, 'Piantini');
    });

    test('no inventa un sector de otra ciudad', () {
      // "Naco" no pertenece a Santiago: con la ciudad ya resuelta, el sector
      // que no cuadra se descarta en vez de colarse.
      final r = matchLocation(
          country: 'República Dominicana',
          locality: 'Santiago',
          subLocality: 'Naco');
      expect(r.city, 'Santiago');
      expect(r.sector, isNull);
    });

    test('nada que no esté en el catálogo', () {
      final r = matchLocation(
          country: 'República Dominicana',
          locality: 'Ciudad Inventada',
          subLocality: 'Sector Inventado');
      expect(r.city, isNull);
      expect(r.sector, isNull);
    });

    test('ciudad resuelta sin sector no cae al fallback', () {
      // 'Santiago' es ciudad. Sin este corte, el fallback la buscaría como
      // SECTOR por todo el país y devolvería la provincia que la contuviera.
      final r = matchLocation(
          country: 'República Dominicana', locality: 'Santiago');
      expect(r.city, 'Santiago');
      expect(r.sector, isNull);
    });

    test('Villa Mella (está en dos provincias) resuelve determinista', () {
      // Dato duplicado heredado del catálogo de la web: sin ciudad que lo
      // desempate gana la primera entrada del árbol. El test fija el resultado
      // para que reordenar el mapa no lo cambie en silencio.
      final r = matchLocation(
          country: 'República Dominicana', subLocality: 'Villa Mella');
      expect(r.city, 'Distrito Nacional');
      expect(r.sector, 'Villa Mella');
      // Con la provincia correcta explícita, sí cae donde debe.
      final r2 = matchLocation(
          country: 'República Dominicana',
          locality: 'Santo Domingo Norte',
          subLocality: 'Villa Mella');
      expect(r2.city, 'Santo Domingo Norte');
      expect(r2.sector, 'Villa Mella');
    });

    test('país desconocido devuelve vacío', () {
      final r = matchLocation(country: 'Narnia', locality: 'Naco');
      expect(r.city, isNull);
      expect(r.sector, isNull);
    });
  });
}
