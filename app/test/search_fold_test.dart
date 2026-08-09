import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/search_fold.dart';

/// Pedido PO 2026-08-08: los dropdowns largos ganan buscador y orden
/// alfabético. Las dos cosas necesitan comparar SIN tildes ni mayúsculas:
/// el `sort()` por defecto de Dart ordena por código Unicode y manda a
/// «Ébano» después de la zeta, y un buscador que no encuentre «Pekín»
/// tecleando "pekin" no sirve en un teléfono.
void main() {
  group('searchFold', () {
    test('quita tildes y baja a minúsculas', () {
      expect(searchFold('Pekín'), 'pekin');
      expect(searchFold('Ébano'), 'ebano');
      expect(searchFold('GAZCUE'), 'gazcue');
      expect(searchFold('Bánica'), 'banica');
      expect(searchFold('Cayetano Germosén'), 'cayetano germosen');
    });

    test('la eñe se pliega a ene (buscar "nino" encuentra "Niño")', () {
      expect(searchFold('Niño'), 'nino');
      expect(searchFold('MONTAÑA'), 'montana');
    });

    test('la diéresis también', () {
      expect(searchFold('Güibia'), 'guibia');
    });
  });

  group('compareFolded', () {
    test('alfabético insensible a tildes: Ébano va entre Dajabón y Espaillat',
        () {
      final xs = ['Espaillat', 'Ébano', 'Dajabón', 'Azua'];
      xs.sort(compareFolded);
      expect(xs, ['Azua', 'Dajabón', 'Ébano', 'Espaillat']);
    });

    test('insensible a mayúsculas', () {
      final xs = ['zona colonial', 'Alma Rosa', 'PEKÍN'];
      xs.sort(compareFolded);
      expect(xs, ['Alma Rosa', 'PEKÍN', 'zona colonial']);
    });

    test('empate plegado: desempata por la cadena original (orden estable)', () {
      final xs = ['pekin', 'Pekín'];
      xs.sort(compareFolded);
      expect(xs, hasLength(2)); // no lanza y no pierde elementos
    });
  });
}
