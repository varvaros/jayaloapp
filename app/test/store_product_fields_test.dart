import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// `storeProductFields` es la forma ÚNICA del payload de un producto de la
/// tienda: la comparten crear (`saveProductToStore`) y editar
/// (`updateStoreProduct`). Lo que se blinda aquí es lo que un `UPDATE` de
/// Postgres hace mal si el mapa se arma "solo con lo que cambió": omitir una
/// columna la deja como estaba.
void main() {
  Map<String, dynamic> base({
    double? price,
    double? priceMin,
    double? priceMax,
    String? condition,
    String? brand,
    String? warranty,
  }) =>
      storeProductFields(
        name: 'Taladro',
        description: 'De 800W',
        categoryId: 'ferreteria',
        kind: 'producto',
        price: price,
        priceMin: priceMin,
        priceMax: priceMax,
        condition: condition,
        brand: brand,
        warranty: warranty,
      );

  test('los tres precios viajan SIEMPRE, aunque sean null', () {
    // Un producto que pasa de rango a precio fijo tiene que LIMPIAR el rango:
    // si `price_min`/`price_max` no viajaran, el UPDATE los dejaría intactos y
    // la tarjeta del catálogo seguiría pintando el rango viejo.
    final f = base(price: 900);
    expect(f.containsKey('price'), isTrue);
    expect(f.containsKey('price_min'), isTrue);
    expect(f.containsKey('price_max'), isTrue);
    expect(f['price'], 900);
    expect(f['price_min'], isNull);
    expect(f['price_max'], isNull);
  });

  test('"Consultar precio" deja los tres en null, no ausentes', () {
    final f = base();
    expect(f['price'], isNull);
    expect(f['price_min'], isNull);
    expect(f['price_max'], isNull);
  });

  test('condition viaja aunque sea null (poder borrarlo)', () {
    expect(base(condition: null).containsKey('condition'), isTrue);
    expect(base(condition: 'usado')['condition'], 'usado');
  });

  test('marca y garantía vacías se guardan como null, no como cadena vacía',
      () {
    final f = base(brand: '   ', warranty: '');
    expect(f['brand'], isNull);
    expect(f['warranty'], isNull);
  });

  test('marca y garantía se recortan', () {
    final f = base(brand: '  Bosch ', warranty: ' 1 año ');
    expect(f['brand'], 'Bosch');
    expect(f['warranty'], '1 año');
  });

  // `business_id`, `user_id` y `rubro` son del INSERT: el editor no los toca
  // (el rubro sale del negocio, no del formulario). Si alguien los metiera
  // aquí, `updateStoreProduct` empezaría a reescribirlos sin querer.
  test('no incluye business_id, user_id ni rubro', () {
    final f = base(price: 100);
    expect(f.containsKey('business_id'), isFalse);
    expect(f.containsKey('user_id'), isFalse);
    expect(f.containsKey('rubro'), isFalse);
  });

  test('los booleanos de logística arrancan en false', () {
    final f = base(price: 100);
    expect(f['offers_shipping'], isFalse);
    expect(f['offers_installation'], isFalse);
    expect(f['requires_evaluation'], isFalse);
  });
}
