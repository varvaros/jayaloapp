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
/// Con DUEÑO explicito, como `center_action`: crear-solicitud se APILA con
/// `push` encima de una pantalla que puede tener su propio guard registrado
/// (el detalle de solicitud del proveedor). Sin dueño, el dispose de la
/// pantalla de arriba borraria el registro de la de abajo, que sigue viva.
///
/// Patron igual al de `roleStore` y `homeScrollController`: singleton de
/// modulo, no InheritedWidget, porque quien pregunta (BackGuard) esta en otra
/// rama del arbol que quien responde.
Object? _owner;
bool Function()? _check;
String? _message;

/// Registra la comprobacion de ESTA pantalla. Pisa cualquier registro previo:
/// la pantalla mas reciente es la visible y la unica que puede perder trabajo.
/// `message` es el cuerpo del dialogo de descarte; sin el se usa uno generico.
void takeUnsavedGuard({
  required Object owner,
  required bool Function() check,
  String? message,
}) {
  _owner = owner;
  _check = check;
  _message = message;
}

/// Quita el registro SOLO si sigue siendo de `owner`. Inofensivo si otra
/// pantalla ya registro encima (mismo contrato que `releaseCenterAction`).
/// Quien registra DEBE soltar en `dispose`, o una pantalla muerta seguira
/// bloqueando el atras de la siguiente.
void releaseUnsavedGuard(Object owner) {
  if (!identical(_owner, owner)) return;
  _owner = null;
  _check = null;
  _message = null;
}

/// `false` si no hay nada registrado. Se consulta en cada llamada.
bool hasUnsavedChanges() => _check?.call() ?? false;

/// Pregunta si se puede tirar el trabajo. `true` = el usuario quiere salir.
/// El cuerpo lo pone quien registro el guard, porque quien pregunta (BackGuard,
/// la navbar) no sabe si lo que se pierde es una oferta o una solicitud.
Future<bool> confirmDiscard(BuildContext context) async {
  final salir = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Salir y descartar los cambios?'),
      content: Text(_message ?? 'Perderás lo que escribiste.'),
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
