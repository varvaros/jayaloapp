import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/wholesale.dart';

/// Los datos de mayoreo de una solicitud, en una tarjeta cuyo encabezado ES el
/// rotulo "Al por mayor" (variante A aprobada por el PO 2026-08-04).
///
/// Antes eran un chip pequenito junto al titulo mas cuatro lineas de texto
/// plano perdidas bajo "Informacion", a dos secciones de distancia.
///
/// **No decide nada**: recibe los cuatro datos crudos de la fila y los pinta.
/// La traduccion de slugs la hacen `wholesaleSplitLabel` y
/// `wholesalePackagingLabel`, que ya tienen sus propios tests.
///
/// Se dibuja SIEMPRE que la solicitud sea de mayoreo, aunque no haya ni un
/// dato: el rotulo es identidad de la solicitud, no informacion opcional.
class WholesaleCard extends StatelessWidget {
  const WholesaleCard({
    super.key,
    this.quantity,
    this.split,
    this.packaging,
    this.note,
  });

  final int? quantity;
  final String? split;
  final String? packaging;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tono =
        dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight;
    final tieneNota = note != null && note!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tono.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.storefront_outlined, size: 19, color: tono.ink),
            const SizedBox(width: 7),
            Text('Al por mayor',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tono.ink)),
          ]),
          if (quantity != null) ...[
            const SizedBox(height: 10),
            _fila(context, 'Cantidad', '$quantity'),
          ],
          if (split != null)
            _fila(context, 'División', wholesaleSplitLabel(split)),
          if (packaging != null)
            _fila(context, 'Empaque', wholesalePackagingLabel(packaging)),
          if (tieneNota) ...[
            const SizedBox(height: 9),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.25)),
            const SizedBox(height: 8),
            Text('Detalle',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            // El detalle es texto libre del cliente y puede ser largo: va a
            // ancho completo, no en una fila de dos columnas.
            Text(note!.trim(),
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: cs.onSurface)),
          ],
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, String etiqueta, String valor) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(valor,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
