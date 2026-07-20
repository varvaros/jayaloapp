import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  test('mergeCatalogRatings inyecta avg/count por business_id', () {
    final items = [
      {'id': 'p1', 'business_id': 'b1', 'name': 'A'},
      {'id': 'p2', 'business_id': 'b2', 'name': 'B'},
      {'id': 'p3', 'business_id': null, 'name': 'C'},
    ];
    final ratings = {
      'b1': (avg: 8.7, count: 34),
    };
    final out = mergeCatalogRatings(items, ratings);

    expect(out[0]['avg_rating'], 8.7);
    expect(out[0]['reviews_count'], 34);
    // b2 sin rating: no se agregan claves (la estrella se oculta).
    expect(out[1].containsKey('avg_rating'), isFalse);
    // business_id nulo: intacto.
    expect(out[2].containsKey('avg_rating'), isFalse);
    // No muta la entrada original.
    expect(items[0].containsKey('avg_rating'), isFalse);
  });
}
