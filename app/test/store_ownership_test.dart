import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/store_ownership.dart';

/// Bug I-5 (revisión final 09-20): un proveedor con DOS negocios podía ver
/// «Pedir cotización» en su propia segunda tienda, porque la guarda de
/// «dueño» comparaba contra un solo negocio elegido sin `ORDER BY` (`.limit(1)`
/// de `myBusinessId()`). Estos casos blindan que la decisión pura mire TODOS
/// los negocios del proveedor, no solo el primero que llegue.
void main() {
  group('esDuenoDe', () {
    test('dueño de su único negocio', () {
      expect(esDuenoDe(['b1'], 'b1'), isTrue);
    });

    test('NO dueño de un negocio ajeno', () {
      expect(esDuenoDe(['b1'], 'b2'), isFalse);
    });

    test(
      'proveedor con DOS negocios es dueño de la PRIMERA y de la SEGUNDA tienda',
      () {
        // Antes del arreglo, `myBusinessId()` sin `ORDER BY` podía devolver
        // 'b1' aunque el proveedor estuviera mirando 'b2' — la comparación
        // `id == businessId` salía en falso y «Pedir cotización» quedaba
        // visible en su propia tienda. Con la lista completa, las dos dan
        // dueño = true sin importar cuál devolvió primero el servidor.
        expect(esDuenoDe(['b1', 'b2'], 'b1'), isTrue);
        expect(esDuenoDe(['b1', 'b2'], 'b2'), isTrue);
      },
    );

    test('sin negocios (comprador puro) nunca es dueño', () {
      expect(esDuenoDe(const [], 'b1'), isFalse);
    });
  });
}
