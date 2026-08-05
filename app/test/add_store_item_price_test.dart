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
}
