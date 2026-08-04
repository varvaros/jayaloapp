import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

/// El swipe (Eliminar/Editar) solo aplica mientras la solicitud está viva. En
/// el resto de fases la tarjeta ya NO se queda inerte: cede y dice por qué.
///
/// Editar y borrar dejaron de ir juntos el 2026-08-03 (permisos partidos por
/// fase): este fichero cubre el motivo de EDITAR; el de BORRAR y el caso
/// `closed` viven en my_requests_closed_card_test.dart.
void main() {
  test('las fases vivas no llevan motivo (swipe normal)', () {
    expect(blockedEditReasonForPhase(RequestPhase.waiting), isNull);
    expect(blockedEditReasonForPhase(RequestPhase.withOffers), isNull);
  });

  test('las fases cerradas explican el motivo', () {
    expect(blockedEditReasonForPhase(RequestPhase.accepted),
        'Ya aceptaste una oferta: no puede editarse');
    expect(blockedEditReasonForPhase(RequestPhase.unlocked),
        'Ya están en contacto: no puede editarse');
    expect(blockedEditReasonForPhase(RequestPhase.completed),
        'Solicitud completada');
  });

  test('toda fase de RequestPhase está cubierta', () {
    for (final p in RequestPhase.values) {
      blockedEditReasonForPhase(p); // no debe lanzar por un case olvidado
      blockedDeleteReasonForPhase(p); // idem
    }
  });
}
