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
  test('cualquier forma rara es 0: nunca se promete lo que no se sabe', () {
    expect(welcomeCreditsFrom(null), 0);
    expect(welcomeCreditsFrom([]), 0);
    expect(welcomeCreditsFrom({'welcome_credits': -2}), 0);
    expect(welcomeCreditsFrom({'welcome_credits': 'cinco'}), 0);
    expect(welcomeCreditsFrom({'otra': 1}), 0);
  });
}
