import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

/// Bug del PO (2026-08-25): al cerrarse un chat por inactividad, el proveedor
/// leía "Puedes calificar la transacción" y no tenía calificador. Una de las dos
/// causas era que YA había calificado: el panel desaparece, pero el cartel de
/// chat cerrado solo le decía "Ya enviaste tu calificación" al CLIENTE, así que
/// al proveedor le quedaba una promesa sin explicación.
///
/// La nota no es simétrica, y ese es justo el punto: el cliente califica en
/// cualquier chat cerrado, el proveedor solo en los de OFERTA (ver
/// `canResolveReviewBusiness`). En un chat de PRODUCTO el proveedor nunca pudo
/// calificar, así que decirle "ya enviaste" sería la misma mentira por la puerta
/// de al lado.
void main() {
  test('el cliente ve la nota cuando ya calificó', () {
    expect(
        showsRatingSentNote(
            isProvider: false,
            kind: 'offer',
            hasRating: true,
            customerReviewed: false),
        isTrue);
  });

  test('el cliente NO ve la nota si aún no ha calificado', () {
    expect(
        showsRatingSentNote(
            isProvider: false,
            kind: 'offer',
            hasRating: false,
            customerReviewed: false),
        isFalse);
  });

  test('el proveedor ve la nota cuando ya calificó al cliente en una oferta',
      () {
    expect(
        showsRatingSentNote(
            isProvider: true,
            kind: 'offer',
            hasRating: false,
            customerReviewed: true),
        isTrue);
  });

  test('el proveedor NO ve la nota si todavía no ha calificado', () {
    expect(
        showsRatingSentNote(
            isProvider: true,
            kind: 'offer',
            hasRating: false,
            customerReviewed: false),
        isFalse);
  });

  test('en un chat de PRODUCTO el proveedor nunca ve la nota', () {
    // Ahí no hay calificador para él por construcción, así que tampoco puede
    // haber "ya enviaste".
    for (final reviewed in [true, false]) {
      expect(
          showsRatingSentNote(
              isProvider: true,
              kind: 'product_interest',
              hasRating: false,
              customerReviewed: reviewed),
          isFalse);
    }
  });

  test('el cliente SÍ ve la nota en un chat de producto', () {
    // Su panel no mira el kind: cualquier chat cerrado sin calificar lo trae.
    expect(
        showsRatingSentNote(
            isProvider: false,
            kind: 'product_interest',
            hasRating: true,
            customerReviewed: false),
        isTrue);
  });

  test('cada rol mira SU propia calificación, no la del otro', () {
    // El cliente con `customerReviewed` (que es del proveedor) no ve nada...
    expect(
        showsRatingSentNote(
            isProvider: false,
            kind: 'offer',
            hasRating: false,
            customerReviewed: true),
        isFalse);
    // ...y el proveedor con `hasRating` (que es del cliente), tampoco.
    expect(
        showsRatingSentNote(
            isProvider: true,
            kind: 'offer',
            hasRating: true,
            customerReviewed: false),
        isFalse);
  });
}
