import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/sello_build.dart';

void main() {
  group('SelloBuild', () {
    test('un build limpio dice rama y commit, y nada mas', () {
      final s = SelloBuild.desdeMapa(
        {'rama': 'feat/fecha-pautada-app', 'sha': '1639bb4', 'sucio': '0'},
      );
      expect(s.conocido, isTrue);
      expect(s.linea, 'feat/fecha-pautada-app · 1639bb4');
    });

    test('el arbol sucio se AVISA, y con palabras', () {
      // Es lo mas importante que puede decir el sello: el codigo que corre no
      // esta en ningun commit. Un simbolo raro al lado del hash no lo dice.
      final s = SelloBuild.desdeMapa(
        {'rama': 'feat/x', 'sha': 'abc1234', 'sucio': '1'},
      );
      expect(s.linea, contains('sin commitear'));
    });

    test('sin sello NO se inventa nada: se dice que no se sabe', () {
      // Un APK viejo (compilado antes de que esto existiera) no trae el
      // meta-data, y en iOS no hay canal. Los dos casos caen aqui.
      for (final m in <Map<Object?, Object?>?>[null, {}, {'rama': '  '}]) {
        final s = SelloBuild.desdeMapa(m);
        expect(s.conocido, isFalse, reason: 'con $m');
        expect(s.linea, 'origen desconocido');
      }
    });

    test('una clave a medias no tumba el resto', () {
      final s = SelloBuild.desdeMapa({'sha': 'abc1234'});
      expect(s.sha, 'abc1234');
      expect(s.rama, 'desconocida');
      expect(s.sucio, isFalse);
    });

    test('el desconocido de fabrica se comporta igual que un mapa vacio', () {
      expect(SelloBuild.desconocido.linea, SelloBuild.desdeMapa(null).linea);
      expect(SelloBuild.desconocido.conocido, isFalse);
    });
  });
}
