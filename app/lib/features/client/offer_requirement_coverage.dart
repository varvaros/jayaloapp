import 'package:flutter/material.dart';

import '../../domain/request_requirements.dart';

/// Lo que el cliente exigió en su solicitud y si ESTA oferta lo cubre, dentro de
/// su tarjeta.
///
/// Público y sin estado a propósito: `_OfferCard` es privado a
/// `request_status_screen.dart`, así que un test de widget no puede montarlo
/// desde afuera; este sí es importable y se prueba aislado. Mismo motivo por el
/// que en ese fichero existe `OfferCardProviderHeader`.
///
/// **No decide nada.** Recibe las filas ya cotejadas y con el texto compuesto
/// por `requirementCoverage`. Si la lista viene vacía —el cliente no exigió nada
/// cotejable, o solo exigió evaluación— no pinta NADA: el ~60% de las
/// solicitudes no pide condiciones y sus tarjetas no deben crecer ni un píxel.
class OfferRequirementCoverage extends StatelessWidget {
  const OfferRequirementCoverage({super.key, required this.coverage});

  final List<({Requirement key, bool covered, String label})> coverage;

  @override
  Widget build(BuildContext context) {
    if (coverage.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'Tus condiciones',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        for (final c in coverage)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tono neutro también en el negativo (decisión PO): sin ámbar ni
                // ícono de alarma. El cliente ve el hueco y decide; no se acusa
                // a un proveedor que quizá cumple y solo no lo declaró.
                Icon(
                  c.covered
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                  size: 13,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    c.label,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
