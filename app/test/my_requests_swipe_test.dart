import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

/// El swipe (Eliminar/Editar) solo aplica mientras la solicitud está viva. En
/// el resto de fases la tarjeta ya NO se queda inerte: cede y dice por qué.
void main() {
  test('las fases vivas no llevan motivo (swipe normal)', () {
    expect(blockedReasonForPhase(RequestPhase.waiting), isNull);
    expect(blockedReasonForPhase(RequestPhase.withOffers), isNull);
  });

  test('las fases cerradas explican el motivo', () {
    expect(blockedReasonForPhase(RequestPhase.accepted),
        'Ya aceptaste una oferta: no puede editarse');
    expect(blockedReasonForPhase(RequestPhase.unlocked),
        'Ya están en contacto: no puede editarse');
    expect(
        blockedReasonForPhase(RequestPhase.completed), 'Solicitud completada');
  });

  test('toda fase de RequestPhase está cubierta', () {
    for (final p in RequestPhase.values) {
      blockedReasonForPhase(p); // no debe lanzar por un case olvidado
    }
  });
}
