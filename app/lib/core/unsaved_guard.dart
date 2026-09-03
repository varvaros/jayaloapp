import 'package:flutter/material.dart';

/// Registro de "hay cambios sin guardar en la pantalla actual".
///
/// Existe porque `BackGuard` envuelve CADA pantalla del shell con
/// `PopScope(canPop: false)` e intercepta todo el atras del sistema, incluido
/// el predictive back de Android 13+ (ver back_guard.dart). Una pantalla no
/// puede poner su propio PopScope encima sin pelearse con el, asi que en vez
/// de competir, le da a BackGuard una forma de preguntar. La navbar
/// (home_shell) pregunta por el mismo camino antes de cambiar de pestaña.
///
/// Guarda una FUNCION, no un booleano: la suciedad se calcula en el momento de
/// salir. El formulario de oferta tiene once controladores de texto y
/// mantenerlos sincronizados con listeners seria una fuente de bugs sin
/// ninguna ventaja, porque el valor solo hace falta una vez.
///
/// Patron igual al de `roleStore` y `homeScrollController`: singleton de
/// modulo, no InheritedWidget, porque quien pregunta (BackGuard) esta en otra
/// rama del arbol que quien responde.
class _GuardEntry {
  _GuardEntry(this.owner, this.check, this.message);
  final Object owner;
  final bool Function() check;
  final String? message;
}

/// PILA, no un solo hueco. Las pantallas se APILAN de verdad: crear-solicitud
/// se empuja con `push` encima de cualquier otra (el ＋ de la barra lo hace
/// desde donde sea), y cuando muere, la de abajo sigue viva y sucia. Con un
/// solo registro, ese `dispose` dejaba el store en null y la pantalla de abajo
/// perdia el aviso para siempre — justo el bug que este guard viene a eliminar.
final List<_GuardEntry> _stack = [];

_GuardEntry? get _top => _stack.isEmpty ? null : _stack.last;

/// Registra la comprobacion de ESTA pantalla en el tope de la pila.
///
/// Si el `owner` YA esta registrado, se actualiza EN SU SITIO en vez de subir
/// al tope: una pantalla de abajo que re-registra despues de un await (el
/// `_prefillFromOffer` del detalle de oferta) no debe robarle el turno a la que
/// el usuario tiene delante.
///
/// `message` es el cuerpo del dialogo de descarte; sin el se usa uno generico.
void takeUnsavedGuard({
  required Object owner,
  required bool Function() check,
  String? message,
}) {
  final entry = _GuardEntry(owner, check, message);
  final i = _stack.indexWhere((e) => identical(e.owner, owner));
  if (i == -1) {
    _stack.add(entry);
  } else {
    _stack[i] = entry;
  }
}

/// Quita el registro de `owner` este donde este en la pila. Inofensivo si ya no
/// esta. Quien registra DEBE soltar en `dispose`, o una pantalla muerta seguira
/// bloqueando el atras de la siguiente.
void releaseUnsavedGuard(Object owner) {
  _stack.removeWhere((e) => identical(e.owner, owner));
}

/// `false` si no hay nada registrado. Manda el TOPE de la pila — la pantalla
/// que el usuario tiene delante es la unica que puede perder trabajo ahora
/// mismo. Se consulta en cada llamada.
bool hasUnsavedChanges() => _top?.check() ?? false;

/// Pregunta si se puede tirar el trabajo. `true` = el usuario quiere salir.
/// El cuerpo lo pone quien registro el guard, porque quien pregunta (BackGuard,
/// la navbar) no sabe si lo que se pierde es una oferta o una solicitud.
Future<bool> confirmDiscard(BuildContext context) async {
  final salir = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Salir y descartar los cambios?'),
      content: Text(_top?.message ?? 'Perderás lo que escribiste.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Seguir editando'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('Salir y descartar',
              style: TextStyle(color: Theme.of(c).colorScheme.error)),
        ),
      ],
    ),
  );
  return salir == true;
}

// ── Segundo gancho: «un paso atrás» DENTRO de la pantalla (spec §5.3) ──────

class _BackStepEntry {
  _BackStepEntry(this.owner, this.step);
  final Object owner;
  final bool Function() step;
}

/// Misma disciplina que `_stack`: pila por dueño, manda el tope, quien
/// registra suelta en `dispose`. Vive aparte del guard de cambios sin
/// guardar porque responde a OTRA pregunta: no «¿se pierde algo?», sino
/// «¿hay algo que deshacer antes de salir?». El creador de solicitudes
/// registra aquí su «Atrás» de la conversación; BackGuard lo consulta
/// PRIMERO. La navbar (home_shell) no: cambiar de pestaña no es un paso.
final List<_BackStepEntry> _backSteps = [];

/// Registra el «paso atrás» de ESTA pantalla. `step` devuelve `true` si
/// consumió el gesto (deshizo algo) y `false` si no había nada que deshacer
/// — entonces BackGuard sigue con el flujo de siempre. Re-registrar el mismo
/// `owner` lo actualiza en su sitio (no le roba el turno a la de arriba).
void takeBackStep({required Object owner, required bool Function() step}) {
  final entry = _BackStepEntry(owner, step);
  final i = _backSteps.indexWhere((e) => identical(e.owner, owner));
  if (i == -1) {
    _backSteps.add(entry);
  } else {
    _backSteps[i] = entry;
  }
}

/// Quita el registro de `owner`. Inofensivo si no está. Quien registra DEBE
/// soltar en `dispose`, o una pantalla muerta se comería el atrás de la
/// siguiente para siempre.
void releaseBackStep(Object owner) {
  _backSteps.removeWhere((e) => identical(e.owner, owner));
}

/// `true` si la pantalla del tope consumió el gesto. `false` si no hay nada
/// registrado o el tope dijo que no tenía nada que deshacer.
bool tryBackStep() =>
    _backSteps.isEmpty ? false : _backSteps.last.step();
