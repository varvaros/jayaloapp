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

  group('catalogPriceLabel', () {
    test('precio fijo se muestra directo', () {
      expect(
        catalogPriceLabel(price: 1500, priceMin: null, priceMax: null),
        'RD\$1,500',
      );
    });

    test('precio fijo gana sobre el rango si ambos vienen', () {
      // Caso defensivo: la web nunca manda los dos a la vez, pero si pasara
      // el precio fijo es la fuente de verdad (mismo orden que la web).
      expect(
        catalogPriceLabel(price: 500, priceMin: 100, priceMax: 900),
        'RD\$500',
      );
    });

    test('rango completo muestra "min - max"', () {
      expect(
        catalogPriceLabel(price: null, priceMin: 1000, priceMax: 2500),
        'RD\$1,000 - RD\$2,500',
      );
    });

    test('solo price_min muestra "desde"', () {
      expect(
        catalogPriceLabel(price: null, priceMin: 800, priceMax: null),
        'desde RD\$800',
      );
    });

    test('sin ningún precio invita a consultar, nunca queda vacío', () {
      expect(
        catalogPriceLabel(price: null, priceMin: null, priceMax: null),
        'Consultar precio',
      );
    });
  });

  group('requestBudgetLabel (presupuesto estimado de la solicitud)', () {
    test('rango con ambos extremos', () {
      expect(requestBudgetLabel(5000, 12000), 'RD\$5,000 - RD\$12,000');
    });
    test('solo mínimo → "desde"', () {
      expect(requestBudgetLabel(5000, null), 'desde RD\$5,000');
    });
    test('solo máximo → "hasta"', () {
      expect(requestBudgetLabel(null, 12000), 'hasta RD\$12,000');
    });
    test('sin presupuesto (nulos o cero) → null, no se pinta la fila', () {
      expect(requestBudgetLabel(null, null), isNull);
      expect(requestBudgetLabel(0, 0), isNull);
    });
  });
}
