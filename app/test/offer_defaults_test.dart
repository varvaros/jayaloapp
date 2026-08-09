import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_defaults.dart';

void main() {
  group('buildOfferDefaults', () {
    test('omite claves vacías y nulas', () {
      final d = buildOfferDefaults(brand: ' Bosch ', warranty: '', hourlyRate: null);
      expect(d, {'brand': 'Bosch'});
    });

    test('sin ningún campo devuelve un mapa vacío', () {
      expect(buildOfferDefaults(), <String, dynamic>{});
    });

    test('serializa el molde completo de producto', () {
      final d = buildOfferDefaults(
        pricingMode: 'range',
        shippingPrice: 250,
        installationPrice: 500,
        evaluationPrice: 100,
        brand: 'Bosch',
        warranty: '1 año',
        delivery: '3 días',
        colors: const ['Negro', 'Blanco'],
      );
      expect(d, {
        'pricing_mode': 'range',
        'shipping_price': 250,
        'installation_price': 500,
        'evaluation_price': 100,
        'brand': 'Bosch',
        'warranty': '1 año',
        'delivery': '3 días',
        'colors': ['Negro', 'Blanco'],
      });
    });

    test('serializa el molde de servicio con pricing_mode hourly', () {
      final d = buildOfferDefaults(
        pricingMode: 'hourly',
        hourlyRate: 500,
        estimatedHours: 3,
        availability: 'Esta semana',
        duration: '2 horas',
      );
      expect(d, {
        'pricing_mode': 'hourly',
        'hourly_rate': 500,
        'estimated_hours': 3,
        'availability': 'Esta semana',
        'duration': '2 horas',
      });
    });

    test('strings se guardan trimmeados', () {
      final d = buildOfferDefaults(availability: '  Hoy  ', duration: ' 1 hora ');
      expect(d, {'availability': 'Hoy', 'duration': '1 hora'});
    });

    test('lista de colores vacía se omite', () {
      final d = buildOfferDefaults(brand: 'X', colors: const []);
      expect(d.containsKey(OfferDefaults.colors), isFalse);
    });
  });

  group('OfferDefaults', () {
    test('claves canónicas', () {
      expect(OfferDefaults.pricingMode, 'pricing_mode');
      expect(OfferDefaults.hourlyRate, 'hourly_rate');
      expect(OfferDefaults.estimatedHours, 'estimated_hours');
      expect(OfferDefaults.availability, 'availability');
      expect(OfferDefaults.duration, 'duration');
      expect(OfferDefaults.shippingPrice, 'shipping_price');
      expect(OfferDefaults.installationPrice, 'installation_price');
      expect(OfferDefaults.evaluationPrice, 'evaluation_price');
      expect(OfferDefaults.brand, 'brand');
      expect(OfferDefaults.warranty, 'warranty');
      expect(OfferDefaults.delivery, 'delivery');
      expect(OfferDefaults.colors, 'colors');
    });
  });
}
