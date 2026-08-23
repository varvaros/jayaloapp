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
  final _slots = halfHourSlots();
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
    setState(() {
      _date = picked;
      // Cambiar de día puede dejar PASADA la hora ya elegida (p. ej. venía de
      // mañana y se pasa a hoy). El servidor la rechazaría con «La fecha debe
      // ser futura»; se suelta aquí en vez de dejar elegido algo imposible.
      if (_time != null && isSlotInPast(_time!, picked, widget.now)) {
        _time = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayHours = hoursForDate(_hours, _date);
    final starts = localStartsAt(_date, _time ?? '');
    final canSend = _subject.text.trim().isNotEmpty && starts != null;

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
              const SizedBox(height: 12),
              Text('Hora',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  key: const Key('appt.slots'),
                  scrollDirection: Axis.horizontal,
                  itemCount: _slots.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final slot = _slots[i];
                    // Fuera de horario = solo una ANOTACIÓN: el horario es una
                    // sugerencia y se puede pautar igual. Ya pasada = la RPC la
                    // rechaza, así que se deshabilita de verdad.
                    final past = isSlotInPast(slot, _date, widget.now);
                    final label =
                        slotLabel(slot, isSlotOutsideHours(slot, dayHours));
                    final selected = _time == slot;
                    return OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            selected ? cs.primary : Colors.transparent,
                        foregroundColor:
                            selected ? Colors.white : cs.onSurface,
                        // Sin estos, Material desvanece el texto a su gris por
                        // defecto e IGNORA el foreground (ya mordió en las
                        // burbujas violeta).
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor:
                            cs.onSurface.withValues(alpha: .38),
                        side: BorderSide(
                          color: selected
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: past ? .4 : 1),
                        ),
                      ),
                      onPressed:
                          past ? null : () => setState(() => _time = slot),
                      child: Text(label, style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
              if (dayHours != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Horario publicado ese día: ${dayHours.open} a '
                  '${dayHours.close}. Puedes pautar fuera de ese rango si '
                  'ambos están de acuerdo.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
              if (starts != null) ...[
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
