import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/wholesale.dart';

void main() {
  test('mapea división y empaque', () {
    expect(wholesaleSplitLabel('lotes_iguales'), 'En lotes iguales');
    expect(wholesalePackagingLabel('por_cantidad'), 'Empaque por cantidad');
  });
  test('desconocido/null → vacío o slug crudo', () {
    expect(wholesaleSplitLabel(null), '');
    expect(wholesalePackagingLabel('xyz'), 'xyz');
  });
  test('options en orden', () {
    expect(kWholesaleSplitOptions.map((e) => e.$1).toList(),
        ['todo_junto', 'lotes_iguales', 'cantidades_especificas', 'no_importa']);
    expect(kWholesalePackagingOptions.map((e) => e.$1).toList(),
        ['individual', 'por_cantidad', 'caja', 'bolsa', 'otro']);
  });
}
