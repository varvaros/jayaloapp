import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/rubro_choices.dart';

/// Catálogo tal como lo devuelve `rubrosForCategories` (columnas id,name,category_id).
List<Map<String, dynamic>> _cat(List<(String, String, String)> rows) => [
  for (final (id, name, cat) in rows)
    {'id': id, 'name': name, 'category_id': cat},
];

void main() {
  final catalogo = _cat([
    ('r1', 'Llaves y grifería', 'plomeria'),
    ('r2', 'Destape de tuberías', 'plomeria'),
    ('r3', 'Calentadores', 'plomeria'),
    ('r4', 'Cisternas', 'plomeria'),
  ]);

  test('sin sugerencias de la IA: cero fichas pero TODO el catálogo elegible', () {
    // Regresión del bloqueo del 2026-08-07: el servidor dejó de devolver rubros
    // (se retiró el fallback "top-3" en 35b7263 asumiendo que ambos clientes
    // tenían selector de catálogo) y la app pintaba una sección OBLIGATORIA con
    // cero opciones — sin nada que elegir y sin poder continuar.
    final chips = rubroChipIds(
      suggested: const [],
      selected: const {},
      catalog: catalogo,
    );
    expect(chips, isEmpty);
    expect(
      rubroDropdownIds(catalog: catalogo, shown: chips),
      ['r1', 'r2', 'r3', 'r4'],
    );
  });

  test('las fichas son los sugeridos; el resto va al desplegable', () {
    final chips = rubroChipIds(
      suggested: const ['r2'],
      selected: const {'r2'},
      catalog: catalogo,
    );
    expect(chips, ['r2']);
    expect(rubroDropdownIds(catalog: catalogo, shown: chips), ['r1', 'r3', 'r4']);
  });

  test('lo elegido en el desplegable sube a fichas y sale de las opciones', () {
    // Sin esto el usuario no podría DESmarcar lo que acaba de añadir.
    final chips = rubroChipIds(
      suggested: const ['r2'],
      selected: const {'r2', 'r4'},
      catalog: catalogo,
    );
    expect(chips, ['r2', 'r4']);
    expect(rubroDropdownIds(catalog: catalogo, shown: chips), ['r1', 'r3']);
  });

  test('los añadidos a mano salen en orden de catálogo, no de Set', () {
    // El orden de iteración de un Set no es estable entre rebuilds: las fichas
    // bailarían bajo el dedo del usuario.
    final chips = rubroChipIds(
      suggested: const [],
      selected: const {'r4', 'r1', 'r3'},
      catalog: catalogo,
    );
    expect(chips, ['r1', 'r3', 'r4']);
  });

  test('un sugerido desmarcado sigue siendo ficha (se puede volver a marcar)', () {
    final chips = rubroChipIds(
      suggested: const ['r2'],
      selected: const {},
      catalog: catalogo,
    );
    expect(chips, ['r2']);
  });

  test('un seleccionado ausente del catálogo no se pierde', () {
    // Pasa si el catálogo no cargó: perderlo lo dejaría enviado sin forma de
    // quitarlo desde la pantalla.
    final chips = rubroChipIds(
      suggested: const [],
      selected: const {'rX'},
      catalog: catalogo,
    );
    expect(chips, ['rX']);
  });

  test('no duplica un sugerido que también está seleccionado', () {
    final chips = rubroChipIds(
      suggested: const ['r1'],
      selected: const {'r1'},
      catalog: catalogo,
    );
    expect(chips, ['r1']);
  });

  test('descarta filas del catálogo sin id utilizable', () {
    final roto = [
      {'id': null, 'name': 'rota', 'category_id': 'plomeria'},
      {'id': '', 'name': 'vacía', 'category_id': 'plomeria'},
      {'id': 'r1', 'name': 'Llaves', 'category_id': 'plomeria'},
    ];
    expect(rubroDropdownIds(catalog: roto, shown: const []), ['r1']);
  });

  test('sin catálogo y sin nada elegido no hay ni fichas ni opciones', () {
    expect(
      rubroChipIds(suggested: const [], selected: const {}, catalog: const []),
      isEmpty,
    );
    expect(rubroDropdownIds(catalog: const [], shown: const []), isEmpty);
  });
}
