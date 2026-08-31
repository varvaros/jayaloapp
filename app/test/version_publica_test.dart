import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/sello_build.dart';

void main() {
  group('tituloVersionPublica', () {
    test('formato normal: nombre + build entre parentesis', () {
      expect(tituloVersionPublica('1.0.4+98'), 'Jayalo v1.0.4 (98)');
    });
    test('sin PackageInfo no se inventa numero', () {
      expect(tituloVersionPublica(null), 'Jayalo');
      expect(tituloVersionPublica('desconocida'), 'Jayalo');
      expect(tituloVersionPublica(''), 'Jayalo');
    });
    test('version sin build (sin +) se muestra tal cual', () {
      expect(tituloVersionPublica('2.0'), 'Jayalo v2.0');
    });
    test('un + colgando no deja parentesis vacios', () {
      expect(tituloVersionPublica('1.0.4+'), 'Jayalo v1.0.4+');
    });
  });

  group('subtituloVersion', () {
    const limpio = SelloBuild(rama: 'master', sha: 'abc1234', sucio: false);
    const sucio = SelloBuild(rama: 'master', sha: 'abc1234', sucio: true);

    test('oculto por defecto: sin subtitulo', () {
      expect(subtituloVersion(limpio, revelado: false), isNull);
    });
    test('revelado (5 toques): la linea completa del sello', () {
      expect(subtituloVersion(limpio, revelado: true), 'master · abc1234');
    });
    test('un arbol SUCIO se enseña SIEMPRE, revelado o no', () {
      expect(subtituloVersion(sucio, revelado: false),
          'master · abc1234 · con cambios sin commitear');
      expect(subtituloVersion(sucio, revelado: true),
          'master · abc1234 · con cambios sin commitear');
    });
  });
}
