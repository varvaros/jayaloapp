import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/appointment_slots.dart';

void main() {
  group('halfHourSlots', () {
    test('cubre el día entero en pasos de media hora', () {
      final slots = halfHourSlots();
      expect(slots.length, 48);
      expect(slots.first, '00:00');
      expect(slots[1], '00:30');
      expect(slots[19], '09:30');
      expect(slots.last, '23:30');
    });
  });

  group('appointmentDateBounds', () {
    test('el techo es hoy+89, UNO MENOS que el tope del servidor', () {
      // La RPC rechaza `_starts_at > clock_timestamp() + 90 días`: compara
      // INSTANTES, no días. Ofrecer hoy+90 anunciaría un día cuyas horas
      // posteriores a la hora actual rebotarían con «La fecha no puede pasar
      // de 90 días». Con hoy+89 la franja completa del último día cabe.
      expect(offeredMaxDays, appointmentMaxDays - 1);
      final b = appointmentDateBounds(DateTime(2026, 8, 23, 9, 0));
      expect(b.last, DateTime(2026, 11, 20));
      expect(b.last.difference(b.first).inDays, 89);
    });

    test('el mínimo es HOY a medianoche local, no el instante actual', () {
      // Con la hora dentro, showDatePicker rechazaría el propio «hoy» como
      // initialDate por ser anterior a firstDate.
      final b = appointmentDateBounds(DateTime(2026, 8, 23, 23, 59));
      expect(b.first, DateTime(2026, 8, 23));
      expect(b.first.hour, 0);
      expect(b.first.minute, 0);
    });

    test('la aritmética va por PARTES de la fecha (cruza mes y año)', () {
      final b = appointmentDateBounds(DateTime(2026, 12, 31, 12, 0));
      expect(b.last, DateTime(2027, 3, 30));
    });
  });

  group('dayKeyForDate', () {
    test('lunes…domingo en las claves de la web (mon..sun)', () {
      expect(dayKeyForDate(DateTime(2026, 8, 24)), 'mon'); // lunes
      expect(dayKeyForDate(DateTime(2026, 8, 29)), 'sat');
      expect(dayKeyForDate(DateTime(2026, 8, 23)), 'sun'); // domingo
    });
  });

  group('parseServiceHours', () {
    test('normaliza el jsonb del servidor', () {
      final h = parseServiceHours({
        'mon': {'open': '09:00', 'close': '17:00'},
        'sun': null,
        'notes': 'lo que sea',
        'bogus': {'open': '09:00'},
      })!;
      expect(h['mon'], (open: '09:00', close: '17:00'));
      expect(h.containsKey('sun'), isTrue);
      expect(h['sun'], isNull);
      // Un día con forma inválida no se inventa: no entra al mapa.
      expect(h.containsKey('bogus'), isFalse);
      expect(h.containsKey('tue'), isFalse);
    });

    test('null cuando no hay horario — es el caso NORMAL, no un error', () {
      expect(parseServiceHours(null), isNull);
      expect(parseServiceHours('basura'), isNull);
      expect(parseServiceHours([1, 2]), isNull);
    });
  });

  group('hoursForDate', () {
    final hours = parseServiceHours({
      'mon': {'open': '09:00', 'close': '17:00'},
      'sun': null,
    });

    test('devuelve el tramo del día de la semana elegido', () {
      expect(hoursForDate(hours, DateTime(2026, 8, 24)),
          (open: '09:00', close: '17:00'));
    });

    test('null si ese día está cerrado, no hay fecha o no hay horario', () {
      expect(hoursForDate(hours, DateTime(2026, 8, 23)), isNull); // domingo
      expect(hoursForDate(hours, DateTime(2026, 8, 25)), isNull); // sin clave
      expect(hoursForDate(hours, null), isNull);
      expect(hoursForDate(null, DateTime(2026, 8, 24)), isNull);
    });
  });

  group('isSlotOutsideHours', () {
    const day = (open: '09:00', close: '17:00');

    test('dentro del tramo: no se anota', () {
      expect(isSlotOutsideHours('09:00', day), isFalse);
      expect(isSlotOutsideHours('16:30', day), isFalse);
    });

    test('fuera del tramo: se anota (el cierre ya está fuera)', () {
      expect(isSlotOutsideHours('08:30', day), isTrue);
      expect(isSlotOutsideHours('17:00', day), isTrue);
      expect(isSlotOutsideHours('23:30', day), isTrue);
    });

    test('sin horario o dato ambiguo: nunca se anota', () {
      expect(isSlotOutsideHours('03:00', null), isFalse);
      expect(isSlotOutsideHours('03:00', (open: '09:00', close: '09:00')),
          isFalse);
      expect(isSlotOutsideHours('03:00', (open: 'x', close: 'y')), isFalse);
    });

    test('tramo que cruza la medianoche (20:00 a 02:00)', () {
      const nocturno = (open: '20:00', close: '02:00');
      expect(isSlotOutsideHours('21:00', nocturno), isFalse);
      expect(isSlotOutsideHours('01:30', nocturno), isFalse);
      expect(isSlotOutsideHours('02:00', nocturno), isTrue);
      expect(isSlotOutsideHours('12:00', nocturno), isTrue);
    });
  });

  test('slotLabel anota solo lo que está fuera de horario', () {
    expect(slotLabel('09:00', false), '09:00');
    expect(slotLabel('09:00', true), '09:00 (fuera de horario)');
  });

  group('isSlotInPast', () {
    final now = DateTime(2026, 8, 24, 10, 0);

    test('la hora EXACTA de ahora ya cuenta como pasada', () {
      // La RPC exige futuro ESTRICTO («La fecha debe ser futura»), así que el
      // corte es <=, no <.
      expect(isSlotInPast('10:00', DateTime(2026, 8, 24), now), isTrue);
    });

    test('antes de ahora, en el día de hoy: pasada', () {
      expect(isSlotInPast('09:30', DateTime(2026, 8, 24), now), isTrue);
    });

    test('después de ahora o en otro día: no pasada', () {
      expect(isSlotInPast('10:30', DateTime(2026, 8, 24), now), isFalse);
      expect(isSlotInPast('00:00', DateTime(2026, 8, 25), now), isFalse);
    });

    test('sin fecha elegida no se deshabilita nada', () {
      expect(isSlotInPast('00:00', null, now), isFalse);
    });
  });

  group('localStartsAt', () {
    test('arma el instante en la zona del DISPOSITIVO (no en UTC)', () {
      final at = localStartsAt(DateTime(2026, 8, 24), '15:30')!;
      expect(at.isUtc, isFalse);
      expect(at, DateTime(2026, 8, 24, 15, 30));
    });

    test('null si falta la fecha o la hora no es válida', () {
      expect(localStartsAt(null, '15:30'), isNull);
      expect(localStartsAt(DateTime(2026, 8, 24), ''), isNull);
      expect(localStartsAt(DateTime(2026, 8, 24), '25:00'), isNull);
    });
  });
}
