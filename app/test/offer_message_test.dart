import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_message.dart';

void main() {
  group('composeOfferMessage', () {
    test('producto: envío con costo, instalación gratis, sin evaluación', () {
      final m = composeOfferMessage(
        isService: false,
        offersShipping: true,
        shippingPrice: 300,
        offersInstallation: true,
        installationPrice: 0,
      );
      expect(m, 'Envío: RD\$300 · Instalación incluida');
    });

    test('producto: evaluación con costo', () {
      final m = composeOfferMessage(
        isService: false,
        requiresEvaluation: true,
        evaluationPrice: 500,
      );
      expect(m, 'Evaluación: RD\$500');
    });

    test('producto sin extras => mensaje vacío (columna default \'\')', () {
      expect(composeOfferMessage(isService: false), '');
    });

    test('servicio: disponibilidad + duración + evaluación', () {
      final m = composeOfferMessage(
        isService: true,
        availabilityNote: 'Lun a Vie',
        estimatedDuration: '2 días',
        requiresEvaluation: true,
      );
      expect(m,
          'Disponibilidad: Lun a Vie · Duración: 2 días · Requiere evaluación en sitio');
    });

    test('servicio: los toggles de producto NO aplican', () {
      final m = composeOfferMessage(
        isService: true,
        offersShipping: true,
        shippingPrice: 300,
      );
      expect(m, '');
    });
  });
}
