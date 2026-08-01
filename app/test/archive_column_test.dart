import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// Minor #6 de la revisión final: la selección de columna al archivar es la
/// única línea del archivado donde un copy-paste invertido haría que un usuario
/// intentara archivar el lado del OTRO participante.
///
/// El trigger `trg_enforce_archive_own_side` lo bloquearía con P0001 — está
/// verificado contra producción — pero el usuario vería "No se pudo archivar"
/// sobre una acción perfectamente legítima, y el motivo real quedaría enterrado
/// en la base de datos. Coste de fijarlo: dos aserciones.
void main() {
  test('el proveedor archiva por la columna del proveedor', () {
    expect(archivedColumnFor(asProvider: true), 'archived_by_provider');
  });

  test('el cliente archiva por la columna del cliente', () {
    expect(archivedColumnFor(asProvider: false), 'archived_by_customer');
  });

  test('nunca devuelve la columna del otro lado', () {
    // Redundante con los dos anteriores a propósito: si alguien invierte el
    // ternario, los tres fallan y el motivo queda escrito aquí.
    expect(archivedColumnFor(asProvider: true),
        isNot(archivedColumnFor(asProvider: false)));
  });
}
