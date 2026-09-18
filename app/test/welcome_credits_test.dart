import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  test('lee welcome_credits de una fila', () {
    expect(
      welcomeCreditsFrom({'welcome_credits': 5, 'referral_credits': 5}),
      5,
    );
  });
  test(
    'acepta la fila envuelta en lista (forma de PostgREST para RETURNS TABLE)',
    () {
      expect(
        welcomeCreditsFrom([
          {'welcome_credits': 3},
        ]),
        3,
      );
    },
  );
  test('acepta el número como texto', () {
    expect(welcomeCreditsFrom({'welcome_credits': '7'}), 7);
  });
  test('acepta una cadena DECIMAL: «5.0» son 5, no 0', () {
    // Un `numeric` de Postgres serializado a texto llega así, y con
    // `int.tryParse` daba 0 en SILENCIO — y 0 es justo el valor que borra la
    // lámina de la moneda.
    expect(welcomeCreditsFrom({'welcome_credits': '5.0'}), 5);
  });
  test('cualquier forma rara es 0: nunca se promete lo que no se sabe', () {
    expect(welcomeCreditsFrom(null), 0);
    expect(welcomeCreditsFrom([]), 0);
    expect(welcomeCreditsFrom({'welcome_credits': -2}), 0);
    expect(welcomeCreditsFrom({'welcome_credits': 'cinco'}), 0);
    expect(welcomeCreditsFrom({'otra': 1}), 0);
  });
}
