/// Lógica pura de los cupos de finalista. Espejo de la web
/// (jayalo-main/src/lib/finalistSlots.ts). Copy EXACTO — no reformular.
const int kMaxFinalists = 3;

/// ¿El cliente todavía puede aceptar otro finalista?
bool canAcceptMore(int acceptedCount) => acceptedCount < kMaxFinalists;

/// ¿La solicitud está cerrada a ofertas nuevas (3 finalistas)?
bool isClosedToOffers(int acceptedCount) => acceptedCount >= kMaxFinalists;

/// Mensaje de cupos restantes que ve el cliente.
String clientSlotsMessage(int acceptedCount) {
  final remaining = kMaxFinalists - acceptedCount;
  if (remaining <= 0) return 'Completaste tu selección (3 de 3)';
  if (acceptedCount == 0) return 'Puedes aceptar hasta 3';
  return 'Puedes aceptar $remaining más';
}

enum SlotTone { green, yellow, orange, red }

class SlotSignal {
  const SlotSignal(this.tone, this.text);
  final SlotTone tone;
  final String text;
}

/// Escalera de FOMO que ve el proveedor según finalistas seleccionados.
SlotSignal providerSlotSignal(int acceptedCount, int offersCount) {
  // Copy del PO (2026-09-04): «N de 3 seleccionados» no se entendía; el
  // proveedor quiere saber si TODAVÍA puede ofertar. Espejo exacto de la web
  // (`src/lib/finalistSlots.ts`): si cambia aquí, cambia allá.
  if (acceptedCount >= 3) {
    return const SlotSignal(SlotTone.red, 'Esta solicitud ya está llena');
  }
  if (acceptedCount == 2) {
    return const SlotSignal(
        SlotTone.orange, 'Aún puedes ofertar — ¡último lugar!');
  }
  if (acceptedCount == 1) {
    return const SlotSignal(SlotTone.yellow, 'Aún puedes ofertar');
  }
  if (offersCount == 0) {
    return const SlotSignal(SlotTone.green, '¡Haz la primera oferta!');
  }
  return const SlotSignal(SlotTone.green, '3 lugares disponibles');
}
