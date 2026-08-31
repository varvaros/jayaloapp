import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/catalog.dart';

void main() {
  const todas = <Category>[
    (id: 'ferreteria', name: 'Ferretería'),
    (id: 'hogar', name: 'Hogar'),
    (id: 'electronica', name: 'Electrónica'),
  ];

  group('categoriasNavegables', () {
    test('sin conteos (null) no filtra: mejor lista completa que hoja vacía',
        () {
      expect(categoriasNavegables(todas, null), todas);
    });

    test('con conteos deja solo las categorías vivas, en el orden original',
        () {
      final r = categoriasNavegables(todas, {'electronica', 'ferreteria'});
      expect(r.map((c) => c.id), ['ferreteria', 'electronica']);
    });

    test('la SELECCIONADA nunca se oculta aunque no esté viva', () {
      final r = categoriasNavegables(todas, {'electronica'},
          seleccionada: 'hogar');
      expect(r.map((c) => c.id), ['hogar', 'electronica']);
    });

    test('conjunto vacío sin selección = lista vacía', () {
      expect(categoriasNavegables(todas, const {}), isEmpty);
    });

    test('conjunto vacío CON selección conserva solo la seleccionada', () {
      final r =
          categoriasNavegables(todas, const {}, seleccionada: 'ferreteria');
      expect(r.map((c) => c.id), ['ferreteria']);
    });

    test('una seleccionada que no existe en la lista no inventa entradas', () {
      final r = categoriasNavegables(todas, {'hogar'},
          seleccionada: 'no-existe');
      expect(r.map((c) => c.id), ['hogar']);
    });
  });
}
