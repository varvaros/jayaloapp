import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/finalist_slots.dart';

void main() {
  test('kMaxFinalists es 3', () {
    expect(kMaxFinalists, 3);
  });

  test('canAcceptMore hasta llegar a 3', () {
    expect(canAcceptMore(0), true);
    expect(canAcceptMore(2), true);
    expect(canAcceptMore(3), false);
  });

  test('isClosedToOffers solo en 3', () {
    expect(isClosedToOffers(2), false);
    expect(isClosedToOffers(3), true);
  });

  test('clientSlotsMessage con copy exacto', () {
    expect(clientSlotsMessage(0), 'Puedes aceptar hasta 3');
    expect(clientSlotsMessage(1), 'Puedes aceptar 2 más');
    expect(clientSlotsMessage(2), 'Puedes aceptar 1 más');
    expect(clientSlotsMessage(3), 'Completaste tu selección (3 de 3)');
  });

  test('providerSlotSignal — escalera de color y copy exacto', () {
    expect(providerSlotSignal(0, 0).tone, SlotTone.green);
    expect(providerSlotSignal(0, 0).text, '¡Haz la primera oferta!');
    expect(providerSlotSignal(0, 4).text, '3 lugares disponibles');
    expect(providerSlotSignal(1, 5).tone, SlotTone.yellow);
    // Copy del PO (2026-09-04): «N de 3» no se entendía. Espejo exacto de la
    // web (finalistSlots.ts).
    expect(providerSlotSignal(1, 5).text, 'Aún puedes ofertar');
    expect(providerSlotSignal(2, 5).tone, SlotTone.orange);
    expect(providerSlotSignal(2, 5).text, 'Aún puedes ofertar — ¡último lugar!');
    expect(providerSlotSignal(3, 6).tone, SlotTone.red);
    expect(providerSlotSignal(3, 6).text, 'Esta solicitud ya está llena');
  });
}
