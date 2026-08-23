/// Tarjeta «Fecha pautada» (kind='appointment') — espejo de
/// `src/lib/appointmentMessage.ts` (web). El body lo escribe SOLO el
/// servidor (RPCs de la migración 20260823120000); aquí solo se lee.
library;

import 'dart:convert';
import 'chat_time.dart';

const appointmentStatuses = {
  'proposed',
  'confirmed',
  'superseded',
  'cancelled',
  'expired',
  'followup',
};

class AppointmentPayload {
  const AppointmentPayload({
    required this.appointmentId,
    required this.subject,
    required this.startsAtUtc,
    required this.status,
    this.proposedBy,
    this.doneCustomer,
    this.doneProvider,
  });

  final String appointmentId;
  final String subject;

  /// Instante REAL en UTC (`isUtc == true`) — `starts_at` parseado tal cual,
  /// SIN corrimiento de zona. El nombre lo dice a propósito: NO es hora de
  /// RD. A propósito NO se usa `.toLocal()` (dependería del huso del
  /// dispositivo, que puede no coincidir con el de RD) y tampoco se
  /// pre-corre aquí a hora de pared de RD (eso dejaría un `DateTime`
  /// marcado `isUtc == true` mintiendo sobre serlo — justo el contrato que
  /// esta corrección de zona evita). Para MOSTRAR la hora al usuario, pasar
  /// este valor a [formatAppointmentDate], que aplica el corrimiento fijo
  /// de RD internamente. Para el enlace de Google Calendar, pasarlo TAL
  /// CUAL a [googleCalendarUrl] (ya es UTC verdadero, no hace falta ni daña
  /// volver a llamar `.toUtc()`).
  final DateTime startsAtUtc;
  final String status;
  final String? proposedBy;
  final bool? doneCustomer;
  final bool? doneProvider;
}

AppointmentPayload? parseAppointment(String body) {
  try {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final id = m['appointment_id'];
    final subject = m['subject'];
    final starts = m['starts_at'];
    final status = m['status'];
    if (id is! String ||
        subject is! String ||
        starts is! String ||
        status is! String ||
        !appointmentStatuses.contains(status)) {
      return null;
    }
    return AppointmentPayload(
      appointmentId: id,
      subject: subject,
      startsAtUtc: DateTime.parse(starts).toUtc(),
      status: status,
      proposedBy: m['proposed_by'] as String?,
      doneCustomer: m['done_customer'] as bool?,
      doneProvider: m['done_provider'] as bool?,
    );
  } catch (_) {
    return null;
  }
}

const _mesesCortos = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// Compensación FIJA de República Dominicana: UTC-4 todo el año (huso
/// Atlántico, SIN horario de verano — RD no lo observa). Por eso una
/// constante basta y es exacta siempre; no hace falta el paquete `timezone`.
/// DEBE mantenerse en paso con `America/Santo_Domingo`, fijado en
/// `formatAppointmentDate` de la web (`src/lib/appointmentMessage.ts`). Si
/// alguna vez RD adoptara horario de verano, las dos implementaciones se
/// romperían juntas del mismo modo — quien edite una debe revisar la otra.
const _rdOffset = Duration(hours: 4);

/// "26 ago, 3:00 p. m." — SIEMPRE en la zona fija de RD (UTC-4), nunca la
/// del dispositivo. [utc] debe ser un instante UTC real, como
/// [AppointmentPayload.startsAtUtc].
String formatAppointmentDate(DateTime utc) {
  final rd = utc.toUtc().subtract(_rdOffset);
  return '${rd.day} ${_mesesCortos[rd.month - 1]}, ${formatTimeHM(rd)}';
}

String appointmentPreview(String body) {
  final p = parseAppointment(body);
  return p == null ? '📅 Fecha pautada' : '📅 Fecha pautada: ${p.subject}';
}

/// Enlace "añadir a Google Calendar" (evento de 1 h). Fechas en UTC básico;
/// Google resuelve la presentación local con `ctz`. [startsAtUtc] debe ser
/// UTC real (no el resultado de restar [_rdOffset] — esa hora de pared de RD
/// es solo para mostrar texto, nunca para construir instantes).
String googleCalendarUrl({
  required String subject,
  required DateTime startsAtUtc,
  String details = '',
}) {
  // Segundos REALES del instante (no fijos a "00"): espejo exacto de
  // `utcBasic` en `src/lib/calendarEvent.ts` (web), que ya escribe
  // `getUTCSeconds()`. Fijarlos adelantaba el evento hasta 59 s — inerte hoy
  // porque los dos clientes arman el instante con granularidad de minuto,
  // pero una divergencia solo documentada en un informe se redescubre desde
  // cero la próxima vez que alguien la toque.
  String basic(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}'
      '${d.second.toString().padLeft(2, '0')}Z';
  final start = startsAtUtc.toUtc();
  final end = start.add(const Duration(hours: 1));
  final q = {
    'action': 'TEMPLATE',
    'text': 'Jayalo — $subject',
    'dates': '${basic(start)}/${basic(end)}',
    if (details.isNotEmpty) 'details': details,
    'ctz': 'America/Santo_Domingo',
  };
  return Uri.https('calendar.google.com', '/calendar/render', q).toString();
}
