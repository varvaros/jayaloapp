import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/inbox_offer_action.dart';

void main() {
  test('sin oferta (null) → none', () {
    expect(
      inboxOfferActionFor(status: null, unlocked: false),
      InboxOfferAction.none,
    );
  });

  test('pendiente → offered ("Ya ofertaste")', () {
    expect(
      inboxOfferActionFor(status: 'pending', unlocked: false),
      InboxOfferAction.offered,
    );
  });

  test('aceptada y sin desbloquear → unlock (el botón "Conversar")', () {
    expect(
      inboxOfferActionFor(status: 'accepted', unlocked: false),
      InboxOfferAction.unlock,
    );
  });

  test(
    'completada y sin desbloquear → unlocked (la venta ya cerró, no se '
    'vuelve a cobrar)',
    () {
      expect(
        inboxOfferActionFor(status: 'completed', unlocked: false),
        InboxOfferAction.unlocked,
      );
    },
  );

  test('desbloqueada gana sobre el status, sea cual sea', () {
    expect(
      inboxOfferActionFor(status: 'accepted', unlocked: true),
      InboxOfferAction.unlocked,
    );
    expect(
      inboxOfferActionFor(status: 'completed', unlocked: true),
      InboxOfferAction.unlocked,
    );
    expect(
      inboxOfferActionFor(status: 'pending', unlocked: true),
      InboxOfferAction.unlocked,
    );
    expect(
      inboxOfferActionFor(status: null, unlocked: true),
      InboxOfferAction.unlocked,
    );
  });

  test('rechazada → none', () {
    expect(
      inboxOfferActionFor(status: 'rejected', unlocked: false),
      InboxOfferAction.none,
    );
  });

  test('cancelada → none', () {
    expect(
      inboxOfferActionFor(status: 'cancelled', unlocked: false),
      InboxOfferAction.none,
    );
  });
}
