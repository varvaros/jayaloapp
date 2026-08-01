import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

/// Hallazgo de la revisión final (2026-08-01): calificar desde un chat de
/// PRODUCTO nunca llegaba a `business_reviews`.
///
/// La política de INSERT de esa tabla (migración 20260729210000) exige
///   EXISTS (SELECT 1 FROM provider_offers o
///            WHERE o.customer_id = auth.uid()
///              AND o.business_id = business_reviews.business_id
///              AND o.unlocked_at IS NOT NULL)
/// y un chat de `product_interest` no tiene ninguna fila así: el cliente
/// escribió por un artículo de la tienda, no por una oferta a una solicitud.
/// La escritura rebotaba con 42501 y el `catch` best-effort de `RatingPanel`
/// se la tragaba, así que el usuario veía "Gracias por tu calificación" y la
/// reputación no se movía: un fallo TOTAL indistinguible del éxito.
///
/// Decisión del PO: aceptar el límite. Sin negocio resuelto ni se intenta la
/// escritura, así que no hay fallo silencioso; la nota sigue guardándose en
/// `conversation_ratings`.
void main() {
  test('los chats de OFERTA sí resuelven negocio para la reseña', () {
    expect(canResolveReviewBusiness('offer'), isTrue);
  });

  test('los chats de PRODUCTO no lo resuelven: la RLS los rechazaría', () {
    expect(canResolveReviewBusiness('product_interest'), isFalse,
        reason: 'sin negocio no se intenta la escritura, que es lo que evita '
            'el 42501 tragado en silencio');
  });

  test('un kind desconocido o nulo tampoco lo resuelve', () {
    // `get_or_create_conversation` solo crea 'offer' y 'product_interest',
    // pero el gate debe fallar CERRADO ante cualquier otra cosa.
    expect(canResolveReviewBusiness(null), isFalse);
    expect(canResolveReviewBusiness(''), isFalse);
    expect(canResolveReviewBusiness('otro'), isFalse);
  });
}
