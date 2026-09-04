import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

/// El ⋮ enseña el ítem SIEMPRE (proveedor + chat abierto) y lo pinta gris con
/// el motivo cuando no se puede — decisión PO 2026-09-04: ni oculto ni activo.
/// `null` es el único valor que lo habilita.
void main() {
  test('solo canReveal habilita', () {
    expect(whatsappMenuReason(WhatsappRevealGate.canReveal), isNull);
    for (final g in [
      WhatsappRevealGate.optedOut,
      WhatsappRevealGate.noPhone,
      WhatsappRevealGate.unknown,
    ]) {
      expect(whatsappMenuReason(g), isNotNull, reason: '$g debe salir gris');
    }
  });

  test('los motivos son el copy cerrado con el PO', () {
    expect(whatsappMenuReason(WhatsappRevealGate.optedOut),
        'El cliente prefiere solo el chat de Jayalo');
    expect(whatsappMenuReason(WhatsappRevealGate.noPhone),
        'El cliente no dejó un teléfono');
    expect(whatsappMenuReason(WhatsappRevealGate.unknown),
        'No pudimos comprobarlo');
  });
}
