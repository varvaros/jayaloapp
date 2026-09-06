import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  final rows = <Map<String, dynamic>>[
    {'kind': 'producto', 'category_id': 'belleza', 'n': 2},
    {'kind': 'producto', 'category_id': 'electronica', 'n': 1},
    {'kind': 'servicio', 'category_id': 'plomeria', 'n': 4},
    // kind nulo cuenta como producto (mismo criterio que categoriasConCatalogo).
    {'kind': null, 'category_id': 'hogar', 'n': 3},
    // sin categoría: se ignora.
    {'kind': 'producto', 'category_id': null, 'n': 9},
  ];

  test('countsForKind agrupa por categoría solo el kind pedido', () {
    expect(countsForKind(rows, 'producto'), {
      'belleza': 2,
      'electronica': 1,
      'hogar': 3,
    });
    expect(countsForKind(rows, 'servicio'), {'plomeria': 4});
  });

  test('countsForKind tolera n como num/String y lista vacía', () {
    expect(countsForKind(const [], 'producto'), isEmpty);
    expect(
      countsForKind([
        {'kind': 'producto', 'category_id': 'autos', 'n': 5.0},
      ], 'producto'),
      {'autos': 5},
    );
    expect(
      countsForKind([
        {'kind': 'producto', 'category_id': 'hogar', 'n': '7'},
      ], 'producto'),
      {'hogar': 7},
    );
    expect(
      countsForKind([
        {'kind': 'producto', 'category_id': 'hogar', 'n': null},
      ], 'producto'),
      {'hogar': 0},
    );
  });
}
