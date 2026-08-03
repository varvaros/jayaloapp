import 'package:flutter/material.dart';

import '../../domain/request_requirements.dart';

/// Aviso previo al envío cuando la oferta no cubre algo que el cliente marcó
/// como condición. **No bloquea nunca**: el proveedor decide.
///
/// Devuelve `true` si eligió enviar de todos modos; `false` si eligió editar o
/// descartó el diálogo. Se espera DENTRO del manejador de enviar, así que no
/// hay ningún "ya lo acusé" que guardar en el estado de la pantalla —ni que
/// reiniciar, ni que se pueda quedar pegado. La web sí lo guarda, y que ese
/// acuse sobreviviera a un cambio de negocio fue el único bug serio de aquella
/// rama.
Future<bool> showOfferRequirementsWarning(
  BuildContext context,
  List<Requirement> unmet,
) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('El cliente pide algo que tu oferta no cubre'),
      content: SingleChildScrollView(
        // Cuatro requisitos con su explicación no caben en una pantalla pequeña
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta solicitud requiere ${unmetRequirementsMessage(unmet)} y no lo '
              'marcaste en tu oferta. Si sí lo cumples, edítalo antes de enviar; '
              'si no, quedará registrado en tu oferta que no lo cumples.',
            ),
            const SizedBox(height: 12),
            for (final k in unmet)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requirementLabel(k).chip,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      requirementLabel(k).hint,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Editar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Enviar de todos modos'),
        ),
      ],
    ),
  );
  // Descartar tocando fuera equivale a "no envíes todavía": el default seguro
  // es NO mandar una oferta que el proveedor quizá quería corregir.
  return ok ?? false;
}
