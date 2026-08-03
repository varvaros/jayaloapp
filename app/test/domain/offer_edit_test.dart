import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_edit.dart';

/// Regla del botón "Ver mi oferta" (pedido PO 2026-08-03): el detalle entra en
/// modo edición SOBRE SÍ MISMO. Tiene que decir que sí exactamente cuando la
/// compuerta de `request_detail_screen.dart:1559-1560` va a pintar el
/// formulario; si no, el botón queda muerto.
void main() {
  group('canEditOfferInPlace', () {
    test('pendiente y sin desbloquear: sí', () {
      expect(
        canEditOfferInPlace({'status': 'pending', 'unlocked_at': null}),
        isTrue,
      );
    });

    test('aceptada: no (nunca se edita una aceptada, pedido PO)', () {
      expect(
        canEditOfferInPlace({'status': 'accepted', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('rechazada: no', () {
      expect(
        canEditOfferInPlace({'status': 'rejected', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('completada: no', () {
      expect(
        canEditOfferInPlace({'status': 'completed', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('desbloqueada gana sobre el status: no, aunque siga pending', () {
      // Mismo criterio que la tarjeta: `unlocked_at` manda (bug PO 2026-07-23).
      expect(
        canEditOfferInPlace({
          'status': 'pending',
          'unlocked_at': '2026-08-03T10:00:00Z',
        }),
        isFalse,
      );
    });

    test('status nulo: NO, aunque la tarjeta lo trate como pending', () {
      // Este es el caso que justifica la regla. La tarjeta defaultea a
      // 'pending' y mostraría "Ya enviaste tu oferta", pero la compuerta
      // compara en crudo y no abriría el formulario. Decir que sí aquí sería
      // ofrecer un botón que no hace nada.
      expect(
        canEditOfferInPlace({'status': null, 'unlocked_at': null}),
        isFalse,
      );
    });

    test('sin la clave status: no', () {
      expect(canEditOfferInPlace({'unlocked_at': null}), isFalse);
    });

    test('un status inesperado del futuro: no', () {
      expect(
        canEditOfferInPlace({'status': 'expired', 'unlocked_at': null}),
        isFalse,
      );
    });
  });
}
