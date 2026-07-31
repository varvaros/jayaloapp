import 'package:flutter/material.dart';

/// Confirmación de "marcar como no concretado". Vive aparte porque la usan DOS
/// pantallas (la lista de chats y el ⋮ del chat) y ninguna debe ser dueña del
/// copy: es una acción IRREVERSIBLE y el aviso tiene que decir lo mismo en los
/// dos sitios.
///
/// El copy es el que ya estaba EN PRODUCCIÓN en el ⋮ del chat
/// (`chat_screen.dart:1034-1048`), con una frase más: ahora que los dos
/// participantes pueden marcarlo, hay que decir que el otro también lo verá.
///
/// Devuelve true solo si el usuario confirma.
Future<bool> confirmMarkLost(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Marcar como no concretado?'),
      content: const Text(
        'Esta acción es definitiva, la conversación no se puede reabrir. '
        'La otra persona también la verá como no concretada.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sí, marcar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
