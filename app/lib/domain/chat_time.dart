/// Formato de tiempo del chat (es-DO) — espejo de `src/lib/chatTime.ts` (web).
/// Sin `intl`: implementación manual determinista (testeable sin locale del SO).
library;

import 'dart:convert';
import 'appointment.dart';

const _months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];

/// "3:45 p. m." — hora 12h como es-DO, COMPACTA.
///
/// Es el sello de tiempo de la interfaz: va en cada burbuja del chat (a 10 px),
/// en la lista de conversaciones y en «Publicada: …». Ahí lo que se quiere es
/// algo corto que se lea de un vistazo, no una frase.
///
/// ⚠️ NO unificar con [formatTimeWithDayPart]: son dos registros distintos a
/// propósito, y el motivo está escrito en el comentario de esa otra función.
String formatTimeHM(DateTime d) {
  final h12 = ((d.hour + 11) % 12) + 1;
  final mm = d.minute.toString().padLeft(2, '0');
  final suffix = d.hour < 12 ? 'a. m.' : 'p. m.';
  return '$h12:$mm $suffix';
}

/// Franja del día en el habla dominicana, para una hora de 0 a 23.
///
/// 🔴 Son CUATRO, no dos. «a. m./p. m.» parte el día por la mitad; las franjas
/// del español NO. Traducir «a. m.→de la mañana / p. m.→de la tarde» diría la
/// hora MAL: las 21:00 no son «las 9 de la tarde» sino de la NOCHE, y las 03:00
/// no son «las 3 de la mañana» sino de la MADRUGADA. Los cortes son los del uso
/// dominicano y están fijados por pruebas en las cuatro fronteras.
String dayPartLabel(int hour) {
  if (hour < 6) return 'de la madrugada';
  if (hour < 12) return 'de la mañana';
  if (hour < 19) return 'de la tarde';
  return 'de la noche';
}

/// "3:45 de la tarde" — hora 12h EN PROSA, con la franja del día.
///
/// Pedido del PO (2026-08-23) tras ver el reloj en el teléfono. Es el registro
/// de la «fecha pautada», donde la hora se LEE como una frase («Se propondrá
/// para 26 ago, 3:00 de la tarde»), y por eso se puede permitir ser larga.
///
/// ⚠️ Vive SOLO en cuatro sitios, y la lista es corta a propósito: la línea de
/// fecha y hora de la tarjeta de fecha pautada, el botón del reloj de la hoja
/// de proponer, el eco en hora de RD de esa hoja, y las etiquetas del selector
/// de hora de la web. Todo lo demás sigue con [formatTimeHM]: un sello de
/// mensaje pintado a 10 px no puede cuadruplicar de largo, y nadie lee la hora
/// de un mensaje como prosa. Si alguien viene a «unificar» las dos, esta es la
/// razón de que sean dos.
String formatTimeWithDayPart(DateTime d) {
  final h12 = ((d.hour + 11) % 12) + 1;
  final mm = d.minute.toString().padLeft(2, '0');
  return '$h12:$mm ${dayPartLabel(d.hour)}';
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
    case 'appointment':
      return appointmentPreview(body);
    default:
      return body;
  }
}
