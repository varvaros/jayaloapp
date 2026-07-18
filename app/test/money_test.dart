import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/money.dart';

/// El formato de dinero es el mismo de la web: RD$ + entero con coma de
/// miles, sin decimales (los precios en RD$ no se muestran con centavos).
void main() {
  test('nulo devuelve cadena vacía, no "RD\$0"', () {
    expect(fmtRD(null), '');
  });

  test('cero se muestra explícito', () {
    expect(fmtRD(0), 'RD\$0');
  });

  test('por debajo de mil no lleva coma', () {
    expect(fmtRD(999), 'RD\$999');
  });

  test('el salto de los miles pone una coma', () {
    expect(fmtRD(1000), 'RD\$1,000');
  });

  test('los millones llevan dos comas', () {
    expect(fmtRD(1234567), 'RD\$1,234,567');
  });

  test('los decimales se redondean, no se truncan a la baja', () {
    expect(fmtRD(1999.6), 'RD\$2,000');
  });
}
