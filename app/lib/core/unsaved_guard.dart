import 'package:flutter/material.dart';

/// Registro de "hay cambios sin guardar en la pantalla actual".
///
/// Existe porque `BackGuard` envuelve CADA pantalla del shell con
/// `PopScope(canPop: false)` e intercepta todo el atras del sistema, incluido
/// el predictive back de Android 13+ (ver back_guard.dart). Una pantalla no
/// puede poner su propio PopScope encima sin pelearse con el, asi que en vez
/// de competir, le da a BackGuard una forma de preguntar.
///
/// Guarda una FUNCION, no un booleano: la suciedad se calcula en el momento de
/// salir. El formulario de oferta tiene once controladores de texto y
/// mantenerlos sincronizados con listeners seria una fuente de bugs sin
/// ninguna ventaja, porque el valor solo hace falta una vez.
///
/// Patron igual al de `roleStore` y `homeScrollController`: singleton de
/// modulo, no InheritedWidget, porque quien pregunta (BackGuard) esta en otra
/// rama del arbol que quien responde.
bool Function()? _check;

/// Registra la comprobacion, o la quita con `null`. Quien registra DEBE quitar
/// en `dispose`, o una pantalla muerta seguira bloqueando el atras de la
/// siguiente.
void setUnsavedGuard(bool Function()? check) => _check = check;

/// `false` si no hay nada registrado. Se consulta en cada llamada.
bool hasUnsavedChanges() => _check?.call() ?? false;

/// Pregunta si se puede tirar el trabajo. `true` = el usuario quiere salir.
Future<bool> confirmDiscard(BuildContext context) async {
  final salir = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Salir y descartar los cambios?'),
      content: const Text('Perderás lo que escribiste en esta oferta.'),
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
