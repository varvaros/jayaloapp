import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/appointment_slots.dart';

void main() {
  group('slotFromHm / slotHm', () {
    test('van y vuelven entre "HH:MM" y las partes que da el reloj', () {
      // El `showTimePicker` habla en `TimeOfDay`; el resto del módulo (pasada,
      // fuera de horario, instante) habla en "HH:MM". Estos dos son la única
      // frontera entre ambos, y por eso se prueban aquí y no en el widget.
      expect(slotFromHm(9, 5), '09:05');
      expect(slotFromHm(0, 0), '00:00');
      expect(slotFromHm(23, 59), '23:59');
      expect(slotHm('09:05'), (hour: 9, minute: 5));
      expect(slotHm('9:05'), (hour: 9, minute: 5));
    });

    test('slotHm es null cuando la hora no es una hora del día', () {
      expect(slotHm(''), isNull);
      expect(slotHm('25:00'), isNull);
      expect(slotHm('10:70'), isNull);
      expect(slotHm('diez'), isNull);
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

  group('slotLabel', () {
    test('pinta la hora en prosa, igual que la tarjeta', () {
      // Antes devolvía "09:00" mientras la tarjeta del chat decía
      // "9:00 de la mañana": la app se contradecía a sí misma. Ahora las dos
      // salen del MISMO `formatTimeWithDayPart`.
      expect(slotLabel('09:00', false), '9:00 de la mañana');
      expect(slotLabel('15:00', false), '3:00 de la tarde');
      expect(slotLabel('00:00', false), '12:00 de la madrugada');
      expect(slotLabel('12:30', false), '12:30 de la tarde');
      expect(slotLabel('23:45', false), '11:45 de la noche');
      // Las cuatro fronteras están fijadas en `chat_time_test.dart`; aquí solo
      // se comprueba que el selector usa ESE formateador y no otro.
      expect(slotLabel('05:59', false), '5:59 de la madrugada');
      expect(slotLabel('19:00', false), '7:00 de la noche');
    });

    test('anota solo lo que está fuera de horario', () {
      expect(slotLabel('09:00', true), '9:00 de la mañana (fuera de horario)');
    });

    test('una hora que no se puede leer se devuelve tal cual', () {
      // No debe reventar: la anotación es cosmética y el bloqueo real de una
      // hora imposible lo hace `localStartsAt` devolviendo null.
      expect(slotLabel('', false), '');
      expect(slotLabel('25:00', true), '25:00 (fuera de horario)');
    });
  });

  group('nextHalfHour', () {
    // Es la hora con la que se ABRE el reloj cuando aún no hay ninguna elegida.
    // Lo que se está fijando es que ese valor de arranque SIEMPRE sea futuro:
    // antes se abría en la hora de ahora, que `isSlotInPast` cuenta como
    // pasada (corte <=), y el usuario del camino más común se llevaba el aviso
    // rojo sin haber hecho nada raro.
    ({int hour, int minute}) f(int h, int m, [int s = 0]) =>
        nextHalfHour(DateTime(2026, 8, 24, h, m, s));

    test('sube SIEMPRE de tramo, también en la media hora clavada', () {
      // El caso que de verdad importa: a las 10:00:00 devolver las 10:00 sería
      // repetir el bug —la RPC exige futuro ESTRICTO—, así que se va a las
      // 10:30. Las dos fronteras del tramo, por parejas.
      expect(f(10, 0), (hour: 10, minute: 30));
      expect(f(10, 29), (hour: 10, minute: 30));
      expect(f(10, 30), (hour: 11, minute: 0));
      expect(f(10, 31), (hour: 11, minute: 0));
      expect(f(10, 59), (hour: 11, minute: 0));
    });

    test('los segundos no cambian el resultado', () {
      // Subiendo siempre de tramo, el resultado ya queda por delante de `now`
      // con o sin segundos: si algún día se miraran, esto lo diría.
      expect(f(10, 0, 59), (hour: 10, minute: 30));
      expect(f(10, 29, 59), (hour: 10, minute: 30));
    });

    test('lo que sale es SIEMPRE posterior a la hora que entró', () {
      // La propiedad, sobre las horas de pared del día: no hay ni un minuto en
      // el que el reloj se abra sobre algo que ya pasó. El único hueco es la
      // vuelta a medianoche, y lo fija el caso de abajo.
      for (var m = 0; m < 24 * 60 - 30; m++) {
        final r = f(m ~/ 60, m % 60);
        expect(r.hour * 60 + r.minute, greaterThan(m),
            reason: 'a las ${m ~/ 60}:${m % 60} devolvió $r');
      }
    });

    test('DA LA VUELTA a medianoche: es la limitación conocida', () {
      // A partir de las 23:30 ya no queda media hora en el día, así que sale
      // 00:00 — que con el día puesto en HOY vuelve a ser pasada. Se acepta
      // porque a esa hora CUALQUIER hora de hoy está pasada y no hay respuesta
      // buena; el aviso (ahora anunciado al lector de pantalla) lo cubre.
      expect(f(23, 0), (hour: 23, minute: 30));
      expect(f(23, 30), (hour: 0, minute: 0));
      expect(f(23, 59), (hour: 0, minute: 0));
      expect(f(0, 0), (hour: 0, minute: 30));
    });
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
