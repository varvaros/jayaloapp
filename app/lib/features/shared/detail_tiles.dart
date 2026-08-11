import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'brand_kit.dart';

/// Bloque de detalle estructurado (mockup aprobado PO 2026-08-09 para la hoja
/// de oferta; extendido al detalle del catálogo con la Variante B aprobada
/// 2026-08-11): cada dato = una TARJETA HORIZONTAL a lo ancho con el ícono en
/// pastilla a la izquierda, etiqueta tenue arriba y valor debajo; las filas
/// con `true` en el 4º campo llevan check verde a la derecha (capacidades).
///
/// Vivía privado en `offer_actions.dart`; se extrae aquí porque el detalle del
/// producto usa exactamente el mismo bloque (mismo motivo documentado en
/// `collapsing_photo_panel.dart`). Solo se muestran los datos que existen:
/// con `rows` vacía no se pinta ni el eyebrow.
List<Widget> detailTileBlock(
  BuildContext context, {
  required String eyebrow,
  required List<(IconData, String, String, bool)> rows,
}) {
  if (rows.isEmpty) return const [];
  final cs = Theme.of(context).colorScheme;
  final ok = Theme.of(context).brightness == Brightness.dark
      ? JayaloColors.dSuccess
      : JayaloColors.success;

  Widget card(IconData icon, String label, String value, bool check) =>
      Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: .8,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(value,
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.25,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (check) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle_outline, size: 20, color: ok),
          ],
        ]),
      );

  return [
    Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 9),
      child: Text(eyebrow,
          style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.6,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    ),
    for (var i = 0; i < rows.length; i++)
      Padding(
        padding: EdgeInsets.only(bottom: i + 1 < rows.length ? 9 : 0),
        child: card(rows[i].$1, rows[i].$2, rows[i].$3, rows[i].$4),
      ),
  ];
}

/// Tarjeta lila del precio, DESPUÉS de los detalles (mockup aprobado PO
/// 2026-08-09): el único acento de color del bloque — el ojo termina en el
/// monto antes del CTA. Degradado sobre `primary` para que funcione igual en
/// claro y oscuro. `emphasized: false` es para valores que NO son una cifra
/// ("Consultar precio"): la tarjeta cierra el bloque igual, pero sin gritar.
Widget detailPriceCard(BuildContext context,
    {required String value, bool emphasized = true}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.fromLTRB(17, 14, 17, 15),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(kCardRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.primary.withValues(alpha: .10),
          cs.primary.withValues(alpha: .20),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRECIO',
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.6,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value,
            style: emphasized
                ? Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: jayaloHead(context))
                : TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
      ],
    ),
  );
}
