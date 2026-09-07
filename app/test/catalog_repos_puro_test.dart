import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart';

void main() {
  test('negocioCatalogoDe: verificado = identidad o negocio', () {
    const b = (
      name: 'getto',
      logoUrl: null,
      whatsappVerified: true,
      identityVerified: false,
      businessVerified: true,
      hasPhysicalLocation: true,
      description: 'Electrónica',
      city: 'SDE',
    );
    final n = negocioCatalogoDe(b);
    expect(n.verificado, isTrue);
    expect(n.city, 'SDE');
    expect(n.description, 'Electrónica');
    expect(n.hasPhysicalLocation, isTrue);
  });
  test('mergeCatalogRatings también hornea la reputación en un paquete', () {
    final k = paqueteComoItem({
      'id': 'k',
      'business_id': 'b1',
      'name': 'Chicha',
      'price': 3000,
      'items': const [],
      'image_url': null,
    });
    final out = mergeCatalogRatings([k], {'b1': (avg: 9.0, count: 2)});
    expect(out.single['avg_rating'], 9.0);
    expect(out.single['kind'], 'paquete');
  });
}
