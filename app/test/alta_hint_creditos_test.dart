import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/onboarding/provider_onboarding_screen.dart'
    show hintCreditosDeAlta;

/// El alta guiada decía «Empiezas con 0 créditos» mientras el intro que el
/// proveedor ACABA de ver le prometía 5 (`bonus_config.welcome_credits` = 5 en
/// producción, medido 2026-09-21). Las dos frases no podían ser ciertas a la
/// vez.
void main() {
  test('con bono, el alta lo celebra en vez de decir que empiezas sin nada', () {
    expect(
      hintCreditosDeAlta(5),
      'Empiezas con 5 créditos de regalo: ofertar es GRATIS; solo pagas al '
      'desbloquear un contacto.',
    );
  });

  test('el número sale del servidor, no está escrito a mano', () {
    expect(hintCreditosDeAlta(3), startsWith('Empiezas con 3 créditos'));
  });

  test('sin bono vuelve la frase de siempre, palabra por palabra', () {
    // Literal original del fichero: si el bono se apaga, el alta no puede
    // prometer un regalo que no existe.
    expect(
      hintCreditosDeAlta(0),
      'Empiezas con 0 créditos: ofertar es GRATIS; solo pagas al desbloquear '
      'un contacto.',
    );
  });

  test('un bono negativo o absurdo se trata como si no hubiera', () {
    expect(hintCreditosDeAlta(-2), hintCreditosDeAlta(0));
  });
}
