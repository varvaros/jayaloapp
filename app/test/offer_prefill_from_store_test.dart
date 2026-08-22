import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_duration.dart';
import 'package:jayalo_app/domain/store_product_prefill.dart';

/// Task 9: prellenado extendido de la oferta al elegir "De mi tienda".
///
/// `computeStoreProductPrefill` es la lógica PURA que usa
/// `_applyStoreProduct` (`request_detail_screen.dart`) — se prueba aislada
/// porque montar la pantalla entera exige una sesión de Supabase real desde
/// `initState` (`requestById`/`myBusinessForOffer` truenan sin ella incluso
/// en un widget test, verificado antes de escribir esto: `Supabase.instance`
/// exige `Supabase.initialize`, y ya inicializado, `myBusinessForOffer` hace
/// `!` sobre el usuario autenticado y truena igual sin sesión real). El
/// mismo criterio que ya usa `offer_card_provider_header_test.dart`: extraer
/// lo puro en vez de simular Supabase.
///
/// Por eso (c) del brief ("tras prellenar, el guard de salida NO avisa") no
/// tiene un test de runtime aquí: es una garantía mecánica de
/// `_applyStoreProduct` (`_cleanSnapshot = _formSnapshot();` incondicional al
/// final del método, fuera del `setState`) que no depende de ningún dato de
/// entrada — nada que `computeStoreProductPrefill` (que no conoce el
/// snapshot) pudiera hacer fallar.
const _svcModes = ['fixed', 'range', 'hourly', 'needs_evaluation'];

void main() {
  group('computeStoreProductPrefill — producto con molde completo (a)', () {
    final item = {
      'price': 2500,
      'color': 'Rojo',
      'condition': 'nuevo',
      'offers_shipping': true,
      'offers_installation': true,
      'requires_evaluation': false,
      'brand': 'Bosch',
      'warranty': '1 año',
      'offer_defaults': {
        'delivery': '2-3 días',
        'shipping_price': 150,
        'installation_price': 300,
        'evaluation_price': 500,
        'colors': ['Rojo', 'Negro', 'Azul'],
      },
    };

    final r = computeStoreProductPrefill(
      item,
      isService: false,
      svcModes: _svcModes,
      existingColors: const [],
    );

    test('marca y garantía (de las columnas reales)', () {
      expect(r.brand, 'Bosch');
      expect(r.warranty, '1 año');
    });

    test('entrega (del molde)', () {
      expect(r.delivery, '2-3 días');
    });

    test('colores: la lista completa del molde, sin duplicar el de color', () {
      expect(r.colorsToAdd, ['Rojo', 'Negro', 'Azul']);
    });

    test('no duplica un color que el proveedor ya tenía elegido', () {
      final r2 = computeStoreProductPrefill(
        item,
        isService: false,
        svcModes: _svcModes,
        existingColors: const ['Negro'],
      );
      expect(r2.colorsToAdd, ['Rojo', 'Azul']);
    });

    test('precios de envío/instalación/evaluación en sus campos', () {
      expect(r.shippingPrice, '150');
      expect(r.installationPrice, '300');
      expect(r.evaluationPrice, '500');
    });

    test('precio fijo y condición siguen viniendo de las columnas base', () {
      expect(r.fixed, isTrue);
      expect(r.price, '2500');
      expect(r.condition, 'Nuevo');
    });
  });

  group('computeStoreProductPrefill — servicio hourly (b)', () {
    final item = {
      'offers_shipping': false,
      'offers_installation': false,
      'requires_evaluation': false,
      'offer_defaults': {
        'pricing_mode': 'hourly',
        'hourly_rate': 450,
        'estimated_hours': 3,
        'availability': 'Fin de semana',
        'duration': '2 días',
      },
    };

    final r = computeStoreProductPrefill(
      item,
      isService: true,
      svcModes: _svcModes,
      existingColors: const [],
    );

    test('activa el modo por hora (índice 2 de _svcModes)', () {
      expect(r.svcMode, 2);
    });

    test('tarifa + horas + disponibilidad + duración rellenos', () {
      expect(r.hourlyRate, '450');
      expect(r.estimatedHours, '3');
      expect(r.availability, 'Fin de semana');
      // Ya no es texto libre: llega partida en número + unidad.
      expect(r.duration, (value: 2, unit: OfferDurationUnit.dias));
    });
  });

  group('computeStoreProductPrefill — el molde no reinyecta texto libre', () {
    // El jsonb `offer_defaults.duration` es un canal SIN PUERTA (sin
    // pre-chequeo en pantalla, sin `payloadHasContactInfo`, sin trigger de BD)
    // y su única salida es `provider_offers.estimated_duration`, que sí está
    // vigilada. Se sanea en la LECTURA para que los moldes YA guardados
    // tampoco puedan meter basura por la puerta de atrás.
    StoreProductPrefill conDuracion(String d) => computeStoreProductPrefill(
          {
            'offers_shipping': false,
            'offers_installation': false,
            'requires_evaluation': false,
            'offer_defaults': {'duration': d},
          },
          isService: true,
          svcModes: _svcModes,
          existingColors: const [],
        );

    test('una duración ilegible llega como null y no toca el formulario', () {
      expect(conDuracion('A definir según evaluación').duration, isNull);
      expect(conDuracion('8 horas (1 día laboral)').duration, isNull);
      expect(conDuracion('d').duration, isNull);
      expect(conDuracion('809 555 1234').duration, isNull);
      expect(conDuracion('').duration, isNull);
    });

    test('una duración legible sí pasa, con y sin tilde', () {
      expect(conDuracion('3 semanas').duration,
          (value: 3, unit: OfferDurationUnit.semanas));
      expect(conDuracion('30 minutos').duration,
          (value: 30, unit: OfferDurationUnit.minutos));
      expect(conDuracion('1 dia').duration,
          (value: 1, unit: OfferDurationUnit.dias));
    });
  });

  group('computeStoreProductPrefill — pricing_mode ignorado si no es servicio',
      () {
    test('un producto no mueve el índice de servicio aunque el molde lo traiga',
        () {
      final r = computeStoreProductPrefill(
        {
          'price': 900,
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
          'offer_defaults': {'pricing_mode': 'hourly'},
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      // El precio fijo ya puso svcMode en 0; pricing_mode no aplica sin
      // isService, así que sigue en 0 (no en el índice de 'hourly').
      expect(r.svcMode, 0);
    });
  });

  group('computeStoreProductPrefill — regresión sin offer_defaults (d)', () {
    // Ítem de tienda "vieja data": nunca pasó por el editor con molde (Task
    // 6), así que no tiene `offer_defaults` ni columnas brand/warranty. El
    // mapeo tiene que comportarse EXACTO a como era antes de la Task 9.
    test('precio fijo', () {
      final r = computeStoreProductPrefill(
        {
          'price': 1200,
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.fixed, isTrue);
      expect(r.svcMode, 0);
      expect(r.price, '1200');
      expect(r.priceMin, isNull);
      expect(r.priceMax, isNull);
      expect(r.hourlyRate, isNull);
      expect(r.brand, isNull);
      expect(r.warranty, isNull);
      expect(r.delivery, isNull);
      expect(r.colorsToAdd, isEmpty);
    });

    test('precio en rango', () {
      final r = computeStoreProductPrefill(
        {
          'price_min': 800,
          'price_max': 1500,
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.fixed, isFalse);
      expect(r.svcMode, 1);
      expect(r.priceMin, '800');
      expect(r.priceMax, '1500');
    });

    test('color: se agrega si no está ya elegido', () {
      final r = computeStoreProductPrefill(
        {
          'color': 'Verde',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.colorsToAdd, ['Verde']);
    });

    test('condición: nuevo/usado tal cual antes', () {
      final nuevo = computeStoreProductPrefill(
        {
          'condition': 'nuevo',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(nuevo.condition, 'Nuevo');

      final usado = computeStoreProductPrefill(
        {
          'condition': 'usado',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(usado.condition, 'Usado');
    });

    test('booleanos: envío/instalación/evaluación tal cual el ítem', () {
      final r = computeStoreProductPrefill(
        {
          'offers_shipping': true,
          'offers_installation': false,
          'requires_evaluation': true,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.offersShipping, isTrue);
      expect(r.offersInstallation, isFalse);
      expect(r.requiresEvaluation, isTrue);
    });

    test('booleanos ausentes: false (mismo default que antes)', () {
      final r = computeStoreProductPrefill(
        {},
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.offersShipping, isFalse);
      expect(r.offersInstallation, isFalse);
      expect(r.requiresEvaluation, isFalse);
    });
  });

  group('computeStoreProductPrefill — marca/garantía: columna manda (Task 6)',
      () {
    test('columna presente: gana sobre el jsonb', () {
      final r = computeStoreProductPrefill(
        {
          'brand': 'Columna SA',
          'warranty': 'Columna 2 años',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
          'offer_defaults': {'brand': 'Jsonb SA', 'warranty': 'Jsonb 1 año'},
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.brand, 'Columna SA');
      expect(r.warranty, 'Columna 2 años');
    });

    test('columna null/vacía: cae al jsonb', () {
      final r = computeStoreProductPrefill(
        {
          'brand': null,
          'warranty': '',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
          'offer_defaults': {'brand': 'Jsonb SA', 'warranty': 'Jsonb 1 año'},
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.brand, 'Jsonb SA');
      expect(r.warranty, 'Jsonb 1 año');
    });

    test('sin offer_defaults, columna presente: se usa igual (no depende del molde)',
        () {
      final r = computeStoreProductPrefill(
        {
          'brand': 'Columna SA',
          'warranty': 'Columna 2 años',
          'offers_shipping': false,
          'offers_installation': false,
          'requires_evaluation': false,
        },
        isService: false,
        svcModes: _svcModes,
        existingColors: const [],
      );
      expect(r.brand, 'Columna SA');
      expect(r.warranty, 'Columna 2 años');
    });
  });
}
