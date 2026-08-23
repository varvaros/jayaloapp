import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat_time.dart';

void main() {
  final now = DateTime(2026, 7, 17, 20, 0);
  group('formatTimeHM', () {
    test('tarde', () => expect(formatTimeHM(DateTime(2026, 7, 17, 15, 45)), '3:45 p. m.'));
    test('manana', () => expect(formatTimeHM(DateTime(2026, 7, 17, 9, 5)), '9:05 a. m.'));
    test('medianoche', () => expect(formatTimeHM(DateTime(2026, 7, 17, 0, 30)), '12:30 a. m.'));
    test('mediodia', () => expect(formatTimeHM(DateTime(2026, 7, 17, 12, 0)), '12:00 p. m.'));
  });

  group('formatTimeWithDayPart', () {
    // ⚠️ Este formateador es SOLO para la prosa de la fecha pautada. El sello
    // de cada burbuja del chat sigue con `formatTimeHM` a propósito: ver el
    // comentario de las dos funciones en `domain/chat_time.dart`.
    //
    // 🔴 Y HAY UN TERCER ESPEJO, que no es de código sino de SQL: los textos de
    // las notificaciones (push y bandeja) los escribe `hora_rd_en_prosa` en la
    // base de datos, y su caso 4.16 de `scripts/verify-fecha-pautada.sql`
    // pincha EXACTAMENTE estas mismas cadenas. Es lo que impide que la
    // notificación y la tarjeta digan cosas distintas en la misma pantalla — la
    // queja del PO que abrió toda esta tanda. Si se cambia una cadena de aquí,
    // hay que cambiarla ahí; si no, ese caso se pone rojo (que es lo que se
    // quiere).
    String f(int h, int m) =>
        formatTimeWithDayPart(DateTime(2026, 7, 17, h, m));

    // Las CUATRO fronteras, por parejas: es exactamente donde vive un
    // desplazamiento de una hora, y donde una traducción ingenua de
    // «a. m.→mañana / p. m.→tarde» diría la franja equivocada.
    test('madrugada → mañana (05:59 / 06:00)', () {
      expect(f(5, 59), '5:59 de la madrugada');
      expect(f(6, 0), '6:00 de la mañana');
    });

    test('mañana → tarde (11:59 / 12:00)', () {
      expect(f(11, 59), '11:59 de la mañana');
      expect(f(12, 0), '12:00 de la tarde');
    });

    test('tarde → noche (18:59 / 19:00)', () {
      expect(f(18, 59), '6:59 de la tarde');
      expect(f(19, 0), '7:00 de la noche');
    });

    test('noche → madrugada (23:59 / 00:00)', () {
      expect(f(23, 59), '11:59 de la noche');
      expect(f(0, 0), '12:00 de la madrugada');
    });

    test('las 9 de la noche NO son «9:00 tarde»', () {
      // El caso que motiva las cuatro franjas: con el reparto de dos mitades
      // de «a. m./p. m.» esto habría salido como «tarde».
      expect(f(21, 0), '9:00 de la noche');
      expect(f(3, 0), '3:00 de la madrugada');
      expect(f(15, 0), '3:00 de la tarde');
    });
  });
  group('dayKey', () {
    test('mismo dia distinta hora', () => expect(
        dayKey(DateTime(2026, 7, 17, 1)), dayKey(DateTime(2026, 7, 17, 23))));
    test('dias distintos', () => expect(
        dayKey(DateTime(2026, 7, 17)), isNot(dayKey(DateTime(2026, 7, 18)))));
  });
  group('formatDayLabel', () {
    test('hoy', () => expect(formatDayLabel(DateTime(2026, 7, 17, 8), now: now), 'Hoy'));
    test('ayer', () => expect(formatDayLabel(DateTime(2026, 7, 16, 23), now: now), 'Ayer'));
    test('mismo anio', () => expect(formatDayLabel(DateTime(2026, 3, 2), now: now), '2 mar'));
    test('otro anio', () => expect(formatDayLabel(DateTime(2025, 12, 25), now: now), '25 dic 2025'));
  });
  group('formatListTime', () {
    test('hoy → hora', () => expect(formatListTime(DateTime(2026, 7, 17, 15, 45), now: now), '3:45 p. m.'));
    test('ayer', () => expect(formatListTime(DateTime(2026, 7, 16, 10), now: now), 'Ayer'));
    test('antes → fecha', () => expect(formatListTime(DateTime(2026, 7, 1, 10), now: now), '1 jul'));
  });
  group('messagePreview', () {
    test('imagen', () => expect(messagePreview('image', 'https://x/y.jpg'), '📷 Foto'));
    test('direccion', () => expect(messagePreview('address', 'Calle 1'), '📍 Dirección'));
    test('quick con pregunta', () => expect(
        messagePreview('quick', '{"question":"¿Es nuevo?","options":[]}'), '¿Es nuevo?'));
    test('quick corrupto', () => expect(messagePreview('quick', 'no-json'), 'Pregunta'));
    test('texto', () => expect(messagePreview('text', 'hola'), 'hola'));
    // Fija el `case 'appointment':` de verdad, no solo appointmentPreview()
    // por su cuenta: si esa rama se borrara, messagePreview caería al
    // `default` y devolvería el body crudo (un blob JSON), no esta cadena.
    test(
        'fecha pautada',
        () => expect(
              messagePreview('appointment',
                  '{"appointment_id":"a1","subject":"la entrega","starts_at":"2026-08-26T19:00:00Z","status":"proposed"}'),
              '📅 Fecha pautada: la entrega',
            ));
  });
}
