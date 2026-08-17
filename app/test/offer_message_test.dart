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
      expect(m, 'Traslado: RD\$300 · Instalación incluida');
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

    test('producto: detalles (marca/color/garantía/entrega) + logística', () {
      final m = composeOfferMessage(
        isService: false,
        brand: 'Bosch',
        colors: ['Rojo', 'Azul'],
        warranty: '1 año',
        deliveryTime: '2 días',
        offersShipping: true,
        shippingPrice: 0,
      );
      expect(m,
          'Marca: Bosch · Color: Rojo, Azul · Garantía: 1 año · Entrega: 2 días · Traslado gratis');
    });

    test('servicio: los detalles de producto NO aplican', () {
      expect(
          composeOfferMessage(
              isService: true, brand: 'Bosch', colors: ['Rojo']),
          '');
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

    test('producto: el traslado ya no se llama envío', () {
      expect(composeOfferMessage(isService: false, offersShipping: true, shippingPrice: 300),
          'Traslado: RD\$300');
      expect(composeOfferMessage(isService: false, offersShipping: true), 'Traslado gratis');
    });

    test('servicio: materiales antes de la evaluación', () {
      expect(
        composeOfferMessage(
            isService: true,
            estimatedDuration: '2 días',
            includesMaterials: true,
            requiresEvaluation: true),
        'Duración: 2 días · Materiales incluidos · Requiere evaluación en sitio',
      );
    });

    test('includesMaterials nulo no emite nada', () {
      expect(composeOfferMessage(isService: true, includesMaterials: null), '');
    });
  });

  group('freeTextFromOfferMessage', () {
    // REGRESIÓN 2026-08-17: las ofertas enviadas ANTES del renombre dicen «Envío» en
    // su `message`. El detalle pinta la tarjeta «Traslado» con los mismos datos, así
    // que si el lector no reconoce la etiqueta vieja, el cliente ve la línea repetida
    // debajo de su propia tarjeta. Esto no se migra: son datos vivos.
    test('formato histórico: «Envío: RD\$300» lo cubre la tarjeta Traslado', () {
      expect(freeTextFromOfferMessage('Envío: RD\$300', {'Traslado'}), '');
      expect(freeTextFromOfferMessage('Envío gratis', {'Traslado'}), '');
    });

    test('formato nuevo: «Traslado: RD\$300» también lo cubre', () {
      expect(freeTextFromOfferMessage('Traslado: RD\$300', {'Traslado'}), '');
      expect(freeTextFromOfferMessage('Traslado gratis', {'Traslado'}), '');
    });

    test('sin la tarjeta Traslado, la parte sobrevive como texto', () {
      expect(freeTextFromOfferMessage('Envío: RD\$300', {'Estado'}), 'Envío: RD\$300');
    });

    test('materiales: las dos formas las cubre la tarjeta Materiales', () {
      expect(freeTextFromOfferMessage('Materiales incluidos', {'Materiales'}), '');
      expect(freeTextFromOfferMessage('Materiales no incluidos', {'Materiales'}), '');
    });
    test('mensaje 100% estructurado con todos los tiles => vacío', () {
      final m = composeOfferMessage(
        isService: false,
        condition: 'Nuevo',
        warranty: '3 días',
        offersShipping: true,
      );
      expect(m, 'Estado: Nuevo · Garantía: 3 días · Traslado gratis');
      expect(
        freeTextFromOfferMessage(m, {'Estado', 'Garantía', 'Traslado'}),
        '',
      );
    });

    test('el texto libre de la web se conserva', () {
      expect(
        freeTextFromOfferMessage(
            'Garantía: 1 año · Trato directo, factura disponible',
            {'Garantía'}),
        'Trato directo, factura disponible',
      );
    });

    test('parte estructurada SIN tile se conserva (oferta vieja sin columna)',
        () {
      expect(
        freeTextFromOfferMessage('Marca: Bosch · Envío gratis', {'Traslado'}),
        'Marca: Bosch',
      );
    });

    test('las partes sin dos puntos se cubren por su tile', () {
      expect(freeTextFromOfferMessage('Instalación incluida', {'Instalación'}),
          '');
      expect(
          freeTextFromOfferMessage(
              'Requiere evaluación en sitio', {'Evaluación'}),
          '');
      expect(freeTextFromOfferMessage('Envío gratis', <String>{}),
          'Envío gratis');
    });

    test('mensaje vacío y sin tiles', () {
      expect(freeTextFromOfferMessage('', <String>{}), '');
      expect(freeTextFromOfferMessage('Solo prosa de la web', <String>{}),
          'Solo prosa de la web');
    });
  });

  group('conditionFromOfferMessage', () {
    test('ida y vuelta con Nuevo', () {
      final m = composeOfferMessage(isService: false, condition: 'Nuevo');
      expect(conditionFromOfferMessage(m), 'Nuevo');
    });

    test('ida y vuelta con Usado', () {
      final m = composeOfferMessage(isService: false, condition: 'Usado');
      expect(conditionFromOfferMessage(m), 'Usado');
    });

    test('lo encuentra aunque no sea la primera parte', () {
      final m = composeOfferMessage(
        isService: false,
        condition: 'Usado',
        brand: 'Rimax',
        warranty: '7 dias',
        offersShipping: true,
      );
      expect(conditionFromOfferMessage(m), 'Usado');
    });

    test('mensaje sin condicion devuelve vacio', () {
      final m = composeOfferMessage(isService: false, brand: 'Rimax');
      expect(conditionFromOfferMessage(m), '');
    });

    test('mensaje de servicio devuelve vacio', () {
      final m = composeOfferMessage(
          isService: true, availabilityNote: 'Lunes a viernes');
      expect(conditionFromOfferMessage(m), '');
    });

    test('mensaje vacio devuelve vacio', () {
      expect(conditionFromOfferMessage(''), '');
    });

    test('un valor que no es Nuevo ni Usado no se acepta', () {
      expect(conditionFromOfferMessage('Estado: Reacondicionado'), '');
    });

    test('el texto libre de la web no dispara falsos positivos', () {
      // La web todavia tiene caja de comentario y su texto acaba en la misma
      // columna `message`. Mencionar el estado en prosa no debe colar.
      expect(
        conditionFromOfferMessage(
            'Silla Rimax en buen estado: Nuevo modelo 2026'),
        '',
      );
      expect(conditionFromOfferMessage('El estado: nuevo, sin uso'), '');
    });
  });
}
