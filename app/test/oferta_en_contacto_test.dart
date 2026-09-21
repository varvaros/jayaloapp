import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart' show ClosedReason;
import 'package:jayalo_app/features/client/request_status_screen.dart';

/// Vista del CLIENTE sobre sus ofertas (PO 2026-09-21): la que ya está «En
/// contacto» se sube a lo alto de la lista y lleva su propio botón al chat,
/// sin tener que abrir el detalle para encontrarlo.
Map<String, dynamic> oferta(
  String id, {
  String status = 'pending',
  String? unlockedAt,
}) => {'id': id, 'status': status, 'unlocked_at': unlockedAt};

void main() {
  group('enContacto — la MISMA condición que pinta el chip', () {
    test('aceptada y desbloqueada, sin chat cerrado', () {
      expect(
        enContacto(oferta('a', status: 'accepted', unlockedAt: 'x'), null),
        isTrue,
      );
    });

    test('aceptada pero sin desbloquear todavía: no', () {
      expect(enContacto(oferta('a', status: 'accepted'), null), isFalse);
    });

    test('pendiente: no', () {
      expect(enContacto(oferta('a', unlockedAt: 'x'), null), isFalse);
    });

    test('con el chat cerrado: NO, aunque esté desbloqueada', () {
      // El chip ahí dice «Chat cerrado» o «No concretada». Ofrecer un botón
      // «Hablar con el proveedor» sobre un chat muerto es mentirle al cliente.
      expect(
        enContacto(
          oferta('a', status: 'accepted', unlockedAt: 'x'),
          ClosedReason.notAgreed,
        ),
        isFalse,
      );
    });

    test('completada: no — ya no es «en contacto»', () {
      expect(
        enContacto(oferta('a', status: 'completed', unlockedAt: 'x'), null),
        isFalse,
      );
    });
  });

  group('ofertasEnContactoPrimero', () {
    test('la desbloqueada sube a la primera', () {
      final out = ofertasEnContactoPrimero([
        oferta('p1'),
        oferta('p2'),
        oferta('u', status: 'accepted', unlockedAt: 'x'),
        oferta('p3'),
      ], const {});
      expect([for (final o in out) o['id']], ['u', 'p1', 'p2', 'p3']);
    });

    test('el resto conserva su orden: el servidor ya lo decidió', () {
      final out = ofertasEnContactoPrimero([
        oferta('p1'),
        oferta('p2'),
        oferta('p3'),
      ], const {});
      expect([for (final o in out) o['id']], ['p1', 'p2', 'p3']);
    });

    test('con varias desbloqueadas, todas arriba y en su orden relativo', () {
      final out = ofertasEnContactoPrimero([
        oferta('p1'),
        oferta('u1', status: 'accepted', unlockedAt: 'x'),
        oferta('p2'),
        oferta('u2', status: 'accepted', unlockedAt: 'x'),
      ], const {});
      expect([for (final o in out) o['id']], ['u1', 'u2', 'p1', 'p2']);
    });

    test('una con el chat cerrado NO sube', () {
      final out = ofertasEnContactoPrimero([
        oferta('p1'),
        oferta('cerrada', status: 'accepted', unlockedAt: 'x'),
      ], const {'cerrada': ClosedReason.notAgreed});
      expect([for (final o in out) o['id']], ['p1', 'cerrada']);
    });

    test('sin ofertas no revienta', () {
      expect(ofertasEnContactoPrimero(const [], const {}), isEmpty);
    });
  });
}
