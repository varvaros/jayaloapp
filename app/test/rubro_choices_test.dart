import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/rubro_choices.dart';

/// Catálogo tal como lo devuelve `rubrosForCategories` (columnas id,name,category_id).
List<Map<String, dynamic>> _cat(List<(String, String, String)> rows) => [
  for (final (id, name, cat) in rows)
    {'id': id, 'name': name, 'category_id': cat},
];

void main() {
  test('la IA no sugirió nada pero el catálogo tiene rubros: HAY que ofrecer opciones', () {
    // Regresión del bloqueo del 2026-08-07: el servidor dejó de devolver rubros
    // (se retiró el fallback "top-3" en 35b7263 asumiendo que ambos clientes
    // tenían selector de catálogo) y la app pintaba una sección OBLIGATORIA con
    // cero fichas — sin nada que elegir y sin poder continuar.
    final ids = rubroChoiceIds(
      catalog: _cat([
        ('r1', 'Llaves y grifería', 'plomeria'),
        ('r2', 'Destape de tuberías', 'plomeria'),
      ]),
      suggested: const [],
    );
    expect(ids, isNotEmpty);
    expect(ids, ['r1', 'r2']);
  });

  test('los sugeridos por la IA van primero, el resto del catálogo detrás', () {
    final ids = rubroChoiceIds(
      catalog: _cat([
        ('r1', 'Llaves y grifería', 'plomeria'),
        ('r2', 'Destape de tuberías', 'plomeria'),
        ('r3', 'Calentadores', 'plomeria'),
      ]),
      suggested: const ['r3'],
    );
    expect(ids.first, 'r3');
    expect(ids, ['r3', 'r1', 'r2']);
  });

  test('no duplica un sugerido que también está en el catálogo', () {
    final ids = rubroChoiceIds(
      catalog: _cat([('r1', 'Llaves y grifería', 'plomeria')]),
      suggested: const ['r1', 'r1'],
    );
    expect(ids, ['r1']);
  });

  test('si el catálogo no cargó, se conservan los sugeridos', () {
    // Fallo de red al leer `rubros`: perder la sugerencia de la IA dejaría al
    // usuario igual de bloqueado que el bug original.
    final ids = rubroChoiceIds(catalog: const [], suggested: const ['r9']);
    expect(ids, ['r9']);
  });

  test('descarta filas del catálogo sin id utilizable', () {
    final ids = rubroChoiceIds(
      catalog: [
        {'id': null, 'name': 'rota', 'category_id': 'plomeria'},
        {'id': '', 'name': 'vacía', 'category_id': 'plomeria'},
        {'id': 'r1', 'name': 'Llaves', 'category_id': 'plomeria'},
      ],
      suggested: const [],
    );
    expect(ids, ['r1']);
  });

  test('sin catálogo y sin sugeridos devuelve vacío (no inventa rubros)', () {
    expect(rubroChoiceIds(catalog: const [], suggested: const []), isEmpty);
  });
}
