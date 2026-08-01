import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';

/// El proveedor califica al cliente en ofertas COMPLETADAS, con cliente
/// conocido y sin reseña previa. Tres términos.
///
/// ⚠️ Este fichero fijaba antes la condición COPIADA de la web, que añade
/// `purchase_completed === true`. Ese cuarto término dejaba el botón INVISIBLE
/// PARA SIEMPRE por el camino de la app (hallazgo Critical de la revisión final,
/// 2026-08-01): en la app nadie escribe esa columna, así que una oferta cerrada
/// desde la app queda con `status='completed'` y `purchase_completed = NULL`.
/// La web puede exigirlo porque tiene un flujo de dos pasos; la app tiene uno.
void main() {
  Map<String, dynamic> offer({
    String status = 'completed',
    bool? purchase,
    String? customerId = 'cli',
  }) =>
      {
        'id': 'o1',
        'status': status,
        'purchase_completed': purchase,
        'customer_id': customerId,
      };

  test('caso REAL de la app: completada con purchase_completed NULL sí aplica',
      () {
    // Es el caso que producía `mark_conversation_completed`, y el que el
    // término copiado de la web descartaba. Si alguien lo reintroduce, este
    // test falla.
    expect(needsCustomerReview(offer(purchase: null), const {}), isTrue);
  });

  test('purchase_completed no influye: true, false o null dan lo mismo', () {
    // La app no usa esa columna. Fijarlo evita que vuelva a colarse en la
    // condición "por paridad" con la web.
    expect(needsCustomerReview(offer(purchase: true), const {}), isTrue);
    expect(needsCustomerReview(offer(purchase: false), const {}), isTrue);
    expect(needsCustomerReview(offer(purchase: null), const {}), isTrue);
  });

  test('no aplica si ya hay reseña', () {
    expect(needsCustomerReview(offer(), const {'o1'}), isFalse);
  });

  test('no aplica si la oferta no está completada', () {
    expect(needsCustomerReview(offer(status: 'accepted'), const {}), isFalse);
    expect(needsCustomerReview(offer(status: 'pending'), const {}), isFalse);
    expect(needsCustomerReview(offer(status: 'rejected'), const {}), isFalse);
  });

  test('no aplica sin customer_id', () {
    expect(needsCustomerReview(offer(customerId: null), const {}), isFalse);
  });
}
