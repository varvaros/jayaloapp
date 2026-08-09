import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/add_store_item_screen.dart';

/// El precio del alta rápida admite lo que la gente escribe de verdad
/// ("5,000", "RD$5000") — mismo criterio que el presupuesto de crear
/// solicitud: solo dígitos, vacío = null ("Consultar precio").
void main() {
  test('vacío es null (consultar precio)', () {
    expect(parseStoreItemPrice(''), isNull);
    expect(parseStoreItemPrice('   '), isNull);
  });

  test('dígitos pelados', () {
    expect(parseStoreItemPrice('2500'), 2500);
  });

  test('separadores y prefijo de moneda se ignoran', () {
    expect(parseStoreItemPrice('5,000'), 5000);
    expect(parseStoreItemPrice('RD\$5000'), 5000);
    expect(parseStoreItemPrice('RD\$ 12,500'), 12500);
  });

  test('sin ningún dígito es null', () {
    expect(parseStoreItemPrice('gratis'), isNull);
  });

  // BUG PO 08-09: un punto/coma seguido de 1-2 dígitos AL FINAL es
  // separador DECIMAL (los precios RD$ son enteros — se redondea, no se
  // trunca). Seguido de exactamente 3 dígitos sigue siendo separador de
  // MILES, como ya cubren los tests de arriba.
  test('separador decimal (1-2 dígitos finales) se redondea, no multiplica',
      () {
    expect(parseStoreItemPrice('3000.0'), 3000);
    expect(parseStoreItemPrice('3000.50'), 3001);
  });

  test('separador de miles con 3 dígitos sigue funcionando igual', () {
    expect(parseStoreItemPrice('3.000'), 3000);
    expect(parseStoreItemPrice('1,500'), 1500);
  });

  test('RD\$5,000 sigue dando 5000', () {
    expect(parseStoreItemPrice('RD\$5,000'), 5000);
  });

  test('vacío sigue dando null', () {
    expect(parseStoreItemPrice(''), isNull);
  });
}
