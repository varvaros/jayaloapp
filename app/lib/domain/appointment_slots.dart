/// Lógica pura del selector de «fecha pautada» (hoja de proponer del chat) —
/// espejo de `src/lib/appointmentSlots.ts` (web).
///
/// Vive fuera del widget para poder probarse: lo que de verdad se puede
/// equivocar es la aritmética (el día local, el día de la semana, el techo del
/// calendario y el cotejo contra el horario del negocio), no el layout.
///
/// ⚠️ El horario que devuelve `get_conversation_service_hours` es una
/// SUGERENCIA: `null` significa a la vez «el negocio no tiene horario» (hoy:
/// TODOS los negocios vivos) y «no eres participante», y la RPC toma el negocio
/// MÁS ANTIGUO del proveedor, que no tiene por qué ser el de este trato. Por eso
/// aquí solo se ANOTA una hora como «fuera de horario»; nunca se impide
/// elegirla. Lo que sí se rechaza son las horas PASADAS, porque esas las
/// rechaza también el servidor.
///
/// ⚠️ Divergencia CONSCIENTE con la web: la app ya no ofrece una lista de
/// medias horas (el PO pidió un reloj de verdad en vez de la tira de fichas
/// arrastrable), así que aquí NO existe `halfHourSlots`; la web mantiene su
/// `<select>` y por tanto su lista. Todo lo demás sigue siendo espejo, y una
/// hora sigue viajando como el mismo texto `"HH:MM"` en las dos orillas — lo
/// que cambia es de dónde sale y con cuánta finura (la app admite CUALQUIER
/// minuto; la web, medias horas).
library;

import 'chat_time.dart';

/// Tope que valida `propose_scheduled_date` («La fecha no puede pasar de 90
/// días»).
const int appointmentMaxDays = 90;

/// Último día que se OFRECE en el calendario.
///
/// Uno menos que el tope del servidor, y a propósito: la RPC compara instantes
/// (`_starts_at > clock_timestamp() + interval '90 days'`), no días. Si se
/// ofreciera hoy+90, a las 09:00 todas las horas posteriores a las 09:00 de ese
/// último día rebotarían con «La fecha no puede pasar de 90 días» — la interfaz
/// estaría anunciando un día que casi entero va a rechazar. Con hoy+89 la franja
/// completa del último día cabe siempre dentro del tope. Misma decisión que
/// `OFFERED_MAX_DAYS` en `src/lib/appointmentSlots.ts`.
const int offeredMaxDays = appointmentMaxDays - 1;

/// Claves del `jsonb` de horario, en el orden de la semana. Idénticas a las de
/// la web (`DAYS` de `src/lib/providerDetails.ts`) y a las que ya usa
/// `summarizeHours` en `domain/business_details.dart`.
const List<String> appointmentDayKeys = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

/// Tramo publicado de un día: `null` = cerrado o sin dato.
typedef DayHours = ({String open, String close});

/// Horario semanal normalizado. Una clave AUSENTE es «el negocio no dijo nada
/// de ese día»; una clave presente con `null` es «cerrado». Para lo que hace
/// esta pantalla las dos se comportan igual (no se anota nada), pero se
/// conservan distintas para no inventar dato.
typedef ServiceHours = Map<String, DayHours?>;

String _pad2(int n) => n.toString().padLeft(2, '0');

/// "HH:MM" a partir de las partes que devuelve el reloj del sistema
/// (`TimeOfDay`). La hora del formulario viaja como TEXTO por todo el módulo
/// (así el cotejo contra `service_hours`, que también es texto, no necesita
/// convertir nada), y esta es la única puerta de entrada.
String slotFromHm(int hour, int minute) => '${_pad2(hour)}:${_pad2(minute)}';

/// Partes de una hora "HH:MM", o `null` si no es una hora del día. Puerta de
/// SALIDA hacia el reloj del sistema (para reabrirlo en la hora ya elegida).
({int hour, int minute})? slotHm(String slot) {
  final at = _minutesOfDay(slot);
  return at == null ? null : (hour: at ~/ 60, minute: at % 60);
}

/// Límites del `showDatePicker`: hoy y hoy+89, los dos como fecha LOCAL a
/// medianoche (ver [offeredMaxDays]).
///
/// `first` va SIN hora a propósito: `showDatePicker` exige
/// `initialDate >= firstDate`, así que un `firstDate` con la hora de ahora
/// dejaría fuera el propio «hoy». Y la suma va por PARTES de la fecha (el
/// constructor de `DateTime` normaliza el desborde de mes/año), no sumando
/// milisegundos: así ni un cambio de horario ni un febrero corto corren el
/// resultado.
({DateTime first, DateTime last}) appointmentDateBounds(DateTime now) => (
      first: DateTime(now.year, now.month, now.day),
      last: DateTime(now.year, now.month, now.day + offeredMaxDays),
    );

/// Clave de [appointmentDayKeys] (lun…dom) para una fecha local.
String dayKeyForDate(DateTime date) =>
    // DateTime.weekday: 1 = lunes … 7 = domingo, ya en el orden de las claves.
    appointmentDayKeys[date.weekday - 1];

DayHours? _dayHours(Object? raw) {
  if (raw is! Map) return null;
  final open = raw['open'];
  final close = raw['close'];
  if (open is! String || close is! String || open.isEmpty || close.isEmpty) {
    return null;
  }
  return (open: open, close: close);
}

/// Normaliza el `jsonb` de `get_conversation_service_hours` a [ServiceHours].
/// Devuelve `null` cuando no hay horario o el dato no tiene la forma esperada —
/// que es un estado NORMAL, nunca un error que mostrar.
ServiceHours? parseServiceHours(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, DayHours?>{};
  for (final key in appointmentDayKeys) {
    if (!raw.containsKey(key)) continue;
    final value = raw[key];
    if (value == null) {
      out[key] = null;
    } else {
      final parsed = _dayHours(value);
      // Una forma que no reconocemos NO se guarda: guardarla como `null` la
      // haría indistinguible de un «cerrado» declarado por el proveedor.
      if (parsed != null) out[key] = parsed;
    }
  }
  return out;
}

/// Tramo publicado para la fecha elegida (`null` = cerrado, sin horario o sin
/// fecha aún).
DayHours? hoursForDate(ServiceHours? hours, DateTime? date) {
  if (hours == null || date == null) return null;
  return hours[dayKeyForDate(date)];
}

int? _minutesOfDay(String time) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// ¿Esa media hora cae fuera del horario publicado? Sin horario → `false`: no
/// se anota nada y todas las horas se ofrecen igual.
bool isSlotOutsideHours(String slot, DayHours? dayHours) {
  if (dayHours == null) return false;
  final open = _minutesOfDay(dayHours.open);
  final close = _minutesOfDay(dayHours.close);
  final at = _minutesOfDay(slot);
  if (open == null || close == null || at == null) return false;
  if (open == close) return false; // dato ambiguo: no se anota
  if (close > open) return at < open || at >= close;
  // Tramo que cruza la medianoche (p. ej. 20:00 a 02:00).
  return at >= close && at < open;
}

/// Cómo se LEE una hora elegida: en prosa y con la franja del día, más la
/// anotación de «fuera de horario» detrás si toca.
///
/// El formato sale de [formatTimeWithDayPart], el MISMO que pinta la tarjeta
/// del chat (vía `formatAppointmentDate`); no hay un segundo formateador.
/// Antes esto devolvía "15:00" mientras la tarjeta de al lado decía
/// "3:00 p. m." y la app se contradecía sola.
///
/// La fecha del ancla es irrelevante y nunca sale de aquí: la hora del
/// formulario es una hora de PARED, no un instante.
///
/// Una hora que no se puede leer se devuelve tal cual: la anotación es
/// cosmética y quien de verdad frena una hora imposible es [localStartsAt].
String slotLabel(String slot, bool outside) {
  final hm = slotHm(slot);
  final texto = hm == null
      ? slot
      : formatTimeWithDayPart(DateTime(2000, 1, 1, hm.hour, hm.minute));
  return outside ? '$texto (fuera de horario)' : texto;
}

/// ¿Esa media hora del día elegido ya pasó?
///
/// Ojo a la diferencia con [isSlotOutsideHours]: el horario del negocio es una
/// SUGERENCIA y sus horas se siguen pudiendo elegir, pero una hora pasada la
/// RECHAZA el servidor («La fecha debe ser futura»), así que se deshabilita.
/// El corte es `<=` porque la RPC exige futuro ESTRICTO.
bool isSlotInPast(String slot, DateTime? date, DateTime now) {
  final at = localStartsAt(date, slot);
  if (at == null) return false;
  return !at.isAfter(now);
}

/// Instante que se manda a la RPC: fecha + hora en la zona del DISPOSITIVO.
/// `repos.proposeScheduledDate` lo pasa a UTC al serializarlo, así que el
/// servidor recibe el instante real. Aquí NO se corrige ningún huso a mano: el
/// corrimiento de RD solo lo aplica `formatAppointmentDate` para MOSTRAR.
DateTime? localStartsAt(DateTime? date, String slot) {
  final at = _minutesOfDay(slot);
  if (date == null || at == null) return null;
  return DateTime(date.year, date.month, date.day, at ~/ 60, at % 60);
}
