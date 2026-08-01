import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';

/// Paridad EXACTA con la web (`ProviderOffersSection.tsx:705`): el proveedor
/// califica al cliente solo en ofertas completadas, con compra confirmada,
/// con cliente conocido y sin reseña previa.
void main() {
  Map<String, dynamic> offer({
    String status = 'completed',
    bool? purchase = true,
    String? customerId = 'cli',
  }) =>
      {
        'id': 'o1',
        'status': status,
        'purchase_completed': purchase,
        'customer_id': customerId,
      };

  test('caso feliz: completada, comprada, con cliente y sin reseña', () {
    expect(needsCustomerReview(offer(), const {}), isTrue);
  });

  test('no aplica si ya hay reseña', () {
    expect(needsCustomerReview(offer(), const {'o1'}), isFalse);
  });

  test('no aplica si la oferta no está completada', () {
    expect(needsCustomerReview(offer(status: 'accepted'), const {}), isFalse);
  });

  test('no aplica si la compra no se confirmó', () {
    expect(needsCustomerReview(offer(purchase: null), const {}), isFalse);
    expect(needsCustomerReview(offer(purchase: false), const {}), isFalse);
  });

  test('no aplica sin customer_id', () {
    expect(needsCustomerReview(offer(customerId: null), const {}), isFalse);
  });
}
