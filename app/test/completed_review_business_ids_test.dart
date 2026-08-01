import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/request_status_screen.dart'
    show completedReviewBusinessIds;

// Task 9 (corrección de PO, 2026-08-01): la solicitud completada monta UN
// BusinessReviewPanel por cada negocio con el que REALMENTE se cerró. Con el
// modelo de hasta 3 finalistas puede haber varias ofertas `accepted` a la vez
// y cada una se completa por separado, así que elegir "la primera aceptada"
// atribuía la calificación al proveedor equivocado y dejaba sin forma de
// calificar al segundo/tercer finalista completado.
Map<String, dynamic> offer(String bizId, {required String status}) =>
    {'business_id': bizId, 'status': status};

void main() {
  test('dos ofertas completadas de negocios distintos → los dos, en orden', () {
    final ids = completedReviewBusinessIds([
      offer('biz1', status: 'completed'),
      offer('biz2', status: 'completed'),
    ]);
    expect(ids, ['biz1', 'biz2']);
  });

  test(
      'una accepted (no completada) + otra completed → solo la completada, '
      'aunque la accepted vaya primera en la lista', () {
    final ids = completedReviewBusinessIds([
      offer('biz-accepted', status: 'accepted'),
      offer('biz-completed', status: 'completed'),
    ]);
    expect(ids, ['biz-completed']);
  });

  test('dos ofertas completadas del MISMO negocio → un solo id (deduplicado)',
      () {
    final ids = completedReviewBusinessIds([
      offer('biz1', status: 'completed'),
      offer('biz1', status: 'completed'),
    ]);
    expect(ids, ['biz1']);
  });

  test('sin ofertas completadas → lista vacía', () {
    expect(
      completedReviewBusinessIds([
        offer('biz1', status: 'accepted'),
        offer('biz2', status: 'pending'),
        offer('biz3', status: 'rejected'),
      ]),
      isEmpty,
    );
  });

  test('business_id nulo se descarta', () {
    final ids = completedReviewBusinessIds([
      {'status': 'completed'}, // sin business_id
      offer('biz1', status: 'completed'),
    ]);
    expect(ids, ['biz1']);
  });
}
