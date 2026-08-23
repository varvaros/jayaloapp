import 'package:flutter/material.dart';
import '../../../core/motion.dart';
import '../../../data/repos.dart';
import '../../../domain/appointment.dart';
import '../../../domain/appointment_slots.dart';

/// Hoja de «proponer fecha pautada» — espejo de `ProposeDateDialog.tsx` (web).
///
/// Toda la aritmética vive en `domain/appointment_slots.dart` (probada); aquí
/// solo hay estado de formulario. La hoja NO llama a la RPC: devuelve lo
/// elegido y quien la abrió decide (misma división que el resto del chat, y
/// deja el manejo de errores del servidor en un solo sitio).
///
/// Devuelve `null` si el usuario la cierra sin proponer.
Future<({String subject, DateTime startsAt})?> showProposeDateSheet(
  BuildContext context, {
  required String convId,
  required String defaultSubject,

  /// Reloj de la hoja, fijado al ABRIRLA: una pantalla que lleva horas abierta
  /// no puede quedarse ofreciendo el «hoy» de ayer. Inyectable para pruebas.
  DateTime? now,

  /// El horario del negocio. Inyectable para pruebas; por defecto la RPC real.
  Future<Map<String, dynamic>?> Function(String convId) loadHours =
      conversationServiceHours,
}) =>
    showModalBottomSheet<({String subject, DateTime startsAt})>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: JayaloMotion.sheetMenu,
      builder: (ctx) => ProposeDateSheetBody(
        convId: convId,
        defaultSubject: defaultSubject,
        now: now ?? DateTime.now(),
        loadHours: loadHours,
      ),
    );

/// Cuerpo de la hoja. Público solo para poder montarlo en las pruebas de
/// widget; en la app se abre siempre por [showProposeDateSheet].
class ProposeDateSheetBody extends StatefulWidget {
  const ProposeDateSheetBody({
    super.key,
    required this.convId,
    required this.defaultSubject,
    required this.now,
    required this.loadHours,
  });

  final String convId;
  final String defaultSubject;
  final DateTime now;
  final Future<Map<String, dynamic>?> Function(String convId) loadHours;

  @override
  State<ProposeDateSheetBody> createState() => _ProposeDateSheetBodyState();
}

/// Mismo tope que la RPC («El motivo no puede pasar de 60 caracteres») y que
/// el diálogo de la web.
const int _subjectMax = 60;

/// El prellenado (nombre del producto o título de la solicitud) puede pasarse
/// del tope. Se corta por RUNAS, no por unidades UTF-16, para no partir un
/// emoji en dos — mismo criterio que `sanitizeChatText`.
String _clampSubject(String raw) {
  final runas = raw.trim().runes.toList();
  return runas.length > _subjectMax
      ? String.fromCharCodes(runas.take(_subjectMax))
      : raw.trim();
}

class _ProposeDateSheetBodyState extends State<ProposeDateSheetBody> {
  late final TextEditingController _subject =
      TextEditingController(text: _clampSubject(widget.defaultSubject));
  DateTime? _date;
  String? _time;
  ServiceHours? _hours;

  @override
  void initState() {
    super.initState();
    _loadHours();
  }

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  /// `null` es lo NORMAL (ningún negocio en producción tiene horario) y además
  /// no se distingue de «no participas»: nunca se pinta un error con esto, ni
  /// se bloquea nada. Sin horario, todas las horas se ofrecen sin anotar.
  Future<void> _loadHours() async {
    Map<String, dynamic>? raw;
    try {
      raw = await widget.loadHours(widget.convId);
    } catch (_) {
      raw = null;
    }
    if (mounted) setState(() => _hours = parseServiceHours(raw));
  }

  Future<void> _pickDate() async {
    final b = appointmentDateBounds(widget.now);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? b.first,
      firstDate: b.first,
      lastDate: b.last,
      currentDate: b.first,
      helpText: 'Elige el día',
    );
    // `showDatePicker` tarda lo que el usuario quiera: sin el guard el
    // setState corre sobre un widget que pudo desmontarse.
    if (picked == null || !mounted) return;
    // Cambiar de día puede dejar PASADA la hora ya elegida (p. ej. venía de
    // mañana y se pasa a hoy). NO se suelta la hora: se conserva y el aviso de
    // abajo lo dice, igual que cuando la hora pasada se elige en el reloj.
    // Borrarla en silencio dejaba al usuario mirando un formulario que se
    // vació solo.
    setState(() => _date = picked);
  }

  /// Reloj del sistema, en español y en 12 h.
  ///
  /// Cualquier MINUTO vale. La tira de fichas que había antes solo ofrecía
  /// medias horas; nada río abajo depende de eso (el servidor guarda un
  /// `timestamptz` cualquiera y los enlaces de calendario ya escriben los
  /// segundos reales), así que el reloj no redondea nada — un selector que
  /// corrigiera a escondidas la hora del usuario se sentiría roto.
  Future<void> _pickTime() async {
    final hm = _time == null ? null : slotHm(_time!);
    final picked = await showTimePicker(
      context: context,
      initialTime: hm == null
          ? TimeOfDay.fromDateTime(widget.now)
          : TimeOfDay(hour: hm.hour, minute: hm.minute),
      helpText: 'Elige la hora',
      // 12 h de verdad, y en español (pedido PO 2026-08-23).
      //
      // 🔴 No basta con localizar la app: `flutter_localizations` declara
      // `timeOfDayFormat: "H:mm"` (24 h) para TODOS los `es_*` menos `es_US`,
      // así que un reloj en `es` o `es_DO` saldría en 24 h — justo el formato
      // que el PO quiere fuera, y el que contradice a la tarjeta del chat
      // («3:00 de la tarde»). `Localizations.override` cambia el idioma SOLO
      // de este diálogo: los textos siguen siendo los mismos del español
      // («Cancelar», «ACEPTAR», «a.m.», «p.m.»), lo único que cambia es que
      // el reloj se pinta de 1 a 12 con AM/PM.
      //
      // El conmutador del diálogo dice «a.m./p.m.» y NO las cuatro franjas:
      // eso es lo que trae Material y no hay gancho para cambiarlo. El texto
      // que se queda en pantalla —el botón de aquí abajo— sí las usa.
      //
      // El `alwaysUse24HourFormat: false` es la otra mitad: si el teléfono
      // tiene puesto el reloj de 24 h, Material lo impone por encima del
      // idioma. La tarjeta del chat SIEMPRE se lee en 12 h, así que el
      // selector tiene que hacer juego pase lo que pase en los ajustes del
      // aparato.
      builder: (ctx, child) => Localizations.override(
        context: ctx,
        locale: const Locale('es', 'US'),
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
      ),
    );
    // Igual que con el calendario: el usuario puede tardar lo que quiera.
    if (picked == null || !mounted) return;
    setState(() => _time = slotFromHm(picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayHours = hoursForDate(_hours, _date);
    final starts = localStartsAt(_date, _time ?? '');
    // Con un reloj libre no hay nada que «deshabilitar» (las fichas pasadas sí
    // se podían apagar una a una). Se comprueba DESPUÉS de elegir y se dice en
    // castellano, sin tirar lo ya elegido: el servidor la rechazaría con «La
    // fecha debe ser futura» y rebotar contra el servidor algo que la pantalla
    // ya sabe es de mala educación.
    final past = _time != null && isSlotInPast(_time!, _date, widget.now);
    final canSend = _subject.text.trim().isNotEmpty && starts != null && !past;

    return SafeArea(
      child: Padding(
        // La hoja va por encima del Scaffold del chat, así que aquí el inset
        // del teclado sí llega íntegro.
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proponer fecha pautada',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              // Jayalo NO confirma ni respalda la fecha: la acuerdan las dos
              // partes y la plataforma solo la deja anotada.
              Text(
                'La otra parte tiene que confirmarla. El acuerdo es entre '
                'ustedes: Jayalo solo lo anota en el chat.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                maxLength: _subjectMax,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '¿Para qué?',
                  hintText: 'Ej.: entrega del mueble',
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_date == null
                    ? 'Elegir el día'
                    : 'Día: ${_date!.day.toString().padLeft(2, '0')}/'
                        '${_date!.month.toString().padLeft(2, '0')}/'
                        '${_date!.year}'),
              ),
              const SizedBox(height: 4),
              // Un solo control, como el del día: abre el reloj del sistema.
              // Antes había una tira de 48 fichas de media hora que había que
              // ARRASTRAR para llegar a la hora buscada (el PO la probó en un
              // teléfono de verdad y pidió un selector normal).
              //
              // La hora elegida se lee en 12 h, igual que la tarjeta del chat,
              // y con su anotación de «fuera de horario» si toca: el horario
              // del negocio es una SUGERENCIA, se anota pero no cierra nada.
              OutlinedButton.icon(
                key: const Key('appt.time'),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(_time == null
                    ? 'Elegir la hora'
                    : 'Hora: ${slotLabel(_time!, isSlotOutsideHours(_time!, dayHours))}'),
              ),
              if (past) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // La hora elegida NO se borra: sigue puesta en el botón de
                  // arriba y basta con tocar el reloj (o el día) otra vez.
                  child: Text(
                    'Esa hora ya pasó. Elige una más tarde o cambia el día.',
                    key: const Key('appt.past'),
                    style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
                  ),
                ),
              ],
              if (dayHours != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Horario publicado ese día: ${dayHours.open} a '
                  '${dayHours.close}. Puedes pautar fuera de ese rango si '
                  'ambos están de acuerdo.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
              // El eco en hora de RD solo cuando la fecha SE PUEDE proponer:
              // con una hora pasada, «Se propondrá para…» sería mentira, y ahí
              // manda el aviso de arriba.
              if (starts != null && !past) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Se devuelve el instante elegido YA en hora de RD, que es
                  // como se leerá la tarjeta: si el teléfono está en otro huso,
                  // el desfase se ve AQUÍ y no después en el chat.
                  child: Text(
                    'Se propondrá para ${formatAppointmentDate(starts.toUtc())}, '
                    'hora de República Dominicana.',
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor:
                          cs.onSurface.withValues(alpha: .12),
                      disabledForegroundColor:
                          cs.onSurface.withValues(alpha: .38),
                    ),
                    onPressed: canSend
                        ? () => Navigator.of(context).pop((
                              subject: _subject.text.trim(),
                              startsAt: starts,
                            ))
                        : null,
                    child: const Text('Proponer fecha'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
