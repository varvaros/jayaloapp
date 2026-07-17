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
  });
}
