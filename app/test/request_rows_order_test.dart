import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart'
    show sortRequestRows;

/// Orden de la lista de solicitudes (pedido PO 2026-07-23): las NO VISTAS
/// primero y, dentro de cada grupo, la más reciente arriba.
///
/// `ClosedReason?` (4° elemento, Task 11 ronda 2) no participa del orden:
/// siempre `null` aquí, ninguno de estos casos es sobre la fase `closed`.
(Map<String, dynamic>, RequestPhase, int, ClosedReason?) row(
        String id, String createdAt) =>
    ({'id': id, 'created_at': createdAt}, RequestPhase.withOffers, 1, null);

void main() {
  test('no vistas primero; dentro de cada grupo, la más reciente arriba', () {
    final rows = [
      row('a', '2026-07-20T00:00:00Z'), // vista, vieja
      row('b', '2026-07-22T00:00:00Z'), // NO vista, más nueva
      row('c', '2026-07-21T00:00:00Z'), // NO vista, más vieja
      row('d', '2026-07-23T00:00:00Z'), // vista, la más nueva de todas
    ];
    sortRequestRows(rows, {'b', 'c'});
    // b y c (no vistas) van primero, la más nueva (b) arriba; luego las vistas
    // por recencia: d (23) antes que a (20).
    expect(rows.map((e) => e.$1['id']).toList(), ['b', 'c', 'd', 'a']);
  });

  test('sin no vistas: puro orden por recencia', () {
    final rows = [
      row('vieja', '2026-07-18T00:00:00Z'),
      row('nueva', '2026-07-23T00:00:00Z'),
      row('media', '2026-07-20T00:00:00Z'),
    ];
    sortRequestRows(rows, {});
    expect(rows.map((e) => e.$1['id']).toList(), ['nueva', 'media', 'vieja']);
  });
}
