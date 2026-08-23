import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/appointment.dart';

void main() {
  const body =
      '{"appointment_id":"a1","subject":"la entrega","starts_at":"2026-08-26T19:00:00Z","status":"proposed","proposed_by":"u1"}';

  test('parsea un body válido y expone el instante UTC real', () {
    final p = parseAppointment(body)!;
    expect(p.subject, 'la entrega');
    expect(p.status, 'proposed');
    expect(p.proposedBy, 'u1');
    // Contrato de zona (corrección de la tarea sobre el brief original):
    // startsAt es el instante UTC VERDADERO — NUNCA `.toLocal()`, que
    // dependería del huso del dispositivo y podría no ser el de RD. La hora
    // de pared en RD (fija UTC-4) se obtiene con formatAppointmentDate, no
    // leyendo los campos de este DateTime directamente.
    expect(p.startsAt.isUtc, isTrue);
    expect(p.startsAt, DateTime.utc(2026, 8, 26, 19, 0));
  });

  test('null ante JSON roto o incompleto', () {
    expect(parseAppointment('basura'), isNull);
    expect(parseAppointment('{"subject":"x"}'), isNull);
  });

  test('null ante status desconocido', () {
    const bad =
        '{"appointment_id":"a1","subject":"x","starts_at":"2026-08-26T19:00:00Z","status":"bogus"}';
    expect(parseAppointment(bad), isNull);
  });

  test('preview degrada sin reventar', () {
    expect(appointmentPreview(body), '📅 Fecha pautada: la entrega');
    expect(appointmentPreview('basura'), '📅 Fecha pautada');
  });

  test(
      'formatAppointmentDate fija RD (UTC-4) cruzando el día — no puede '
      'coincidir por casualidad con el huso de la máquina que corre el test',
      () {
    // 2026-08-27T02:00:00Z en UTC-4 (RD) es 2026-08-26 22:00 (10:00 p. m.):
    // día calendario Y meridiano distintos del UTC crudo. Si el corrimiento
    // de -4h se borrara, o se reintrodujera `.toLocal()` (que aquí no
    // depende del reloj del SO en absoluto, así que no hay huso de máquina
    // que pueda hacer coincidir el resultado por accidente), saldría
    // "27 ago, 2:00 a. m." — una cadena totalmente distinta.
    final utc = DateTime.utc(2026, 8, 27, 2, 0);
    expect(formatAppointmentDate(utc), '26 ago, 10:00 p. m.');
  });

  test('googleCalendarUrl arma el render link con fechas UTC básicas', () {
    final url = googleCalendarUrl(
      subject: 'la entrega',
      startsAtUtc: DateTime.utc(2026, 8, 26, 19, 0),
      details: 'Chat de Jayalo',
    );
    expect(url, contains('calendar.google.com/calendar/render'));
    expect(url, contains('dates=20260826T190000Z%2F20260826T200000Z'));
    expect(url, contains('Jayalo'));
  });
}
