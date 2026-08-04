import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart'
    show dealOfferIds;

/// `dealOfferIds` es el filtro que decide qué ofertas van a
/// `closedConversationOfferIds` (Task 7, ronda de arreglo 1). Es el requisito
/// de rendimiento del brief convertido en test: solo `accepted`/`completed`
/// tienen conversación (verificado contra producción 2026-08-03: cero
/// conversaciones para pending/rejected/cancelled), así que si alguien mete
/// otro estado al filtro, esto salta.
Map<String, dynamic> offer(String id, String status) =>
    {'id': id, 'status': status};

void main() {
  test('solo entran accepted y completed', () {
    final ids = dealOfferIds([
      offer('a', 'accepted'),
      offer('b', 'completed'),
    ]);
    expect(ids, ['a', 'b']);
  });

  test('pending, rejected y cancelled NO entran', () {
    final ids = dealOfferIds([
      offer('a', 'pending'),
      offer('b', 'rejected'),
      offer('c', 'cancelled'),
    ]);
    expect(ids, isEmpty);
  });

  test('lista vacía entra, lista vacía sale (evita la consulta de más)', () {
    expect(dealOfferIds([]), isEmpty);
  });

  test('preserva los ids correctos, no solo el conteo', () {
    final ids = dealOfferIds([
      offer('x1', 'pending'),
      offer('x2', 'accepted'),
      offer('x3', 'rejected'),
      offer('x4', 'completed'),
      offer('x5', 'cancelled'),
    ]);
    expect(ids, ['x2', 'x4']);
  });
}
