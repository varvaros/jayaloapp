/// Formato de tiempo del chat (es-DO) — espejo de `src/lib/chatTime.ts` (web).
/// Sin `intl`: implementación manual determinista (testeable sin locale del SO).
library;

import 'dart:convert';

const _months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];

/// "3:45 p. m." — hora 12h como es-DO.
String formatTimeHM(DateTime d) {
  final h12 = ((d.hour + 11) % 12) + 1;
  final mm = d.minute.toString().padLeft(2, '0');
  final suffix = d.hour < 12 ? 'a. m.' : 'p. m.';
  return '$h12:$mm $suffix';
}

/// Clave de agrupación por día calendario.
String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

bool _sameDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

/// "Hoy", "Ayer" o "17 jul" (+ año si difiere).
String formatDayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (_sameDay(d, n)) return 'Hoy';
  if (_sameDay(d, n.subtract(const Duration(days: 1)))) return 'Ayer';
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year != n.year ? '$base ${d.year}' : base;
}

/// Lista: hora si es hoy, "Ayer", o fecha corta.
String formatListTime(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (_sameDay(d, n)) return formatTimeHM(d);
  if (_sameDay(d, n.subtract(const Duration(days: 1)))) return 'Ayer';
  return '${d.day} ${_months[d.month - 1]}';
}

/// ¿El último mensaje es el aviso del cron de inactividad (48 h)?
///
/// El cron escribe ese aviso como un MENSAJE más ("⏳ Este chat está por
/// cerrarse por inactividad…"), así que en la lista se comía el preview del
/// último mensaje real. La lista lo detecta con esto y lo pinta como chip
/// ámbar compacto (mockup aprobado PO 2026-08-10). Conservador: exige la
/// frase completa del cron, un usuario que la mencione de pasada no la
/// escribiría igual con el prefijo del reloj.
bool isInactivityWarning(String body) =>
    body.contains('por cerrarse por inactividad');

/// Preview del último mensaje según su tipo.
String messagePreview(String kind, String body) {
  switch (kind) {
    case 'image':
      return '📷 Foto';
    case 'address':
      return '📍 Dirección';
    case 'quick':
      try {
        final q = (jsonDecode(body) as Map<String, dynamic>)['question'];
        return q is String ? q : 'Pregunta';
      } catch (_) {
        return 'Pregunta';
      }
    default:
      return body;
  }
}
