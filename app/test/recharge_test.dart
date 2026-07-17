import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/recharge.dart';

void main() {
  group('shouldOfferRecharge', () {
    test('sin wallet (balance null) → ofrecer recarga', () {
      expect(shouldOfferRecharge(balance: null, cost: 1), isTrue);
    });
    test('saldo menor al costo → ofrecer recarga', () {
      expect(shouldOfferRecharge(balance: 2, cost: 3), isTrue);
    });
    test('saldo exacto → alcanza, no ofrecer', () {
      expect(shouldOfferRecharge(balance: 3, cost: 3), isFalse);
    });
    test('saldo de sobra → no ofrecer', () {
      expect(shouldOfferRecharge(balance: 10, cost: 3), isFalse);
    });
  });
}
