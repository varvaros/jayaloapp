import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/request_requirements.dart';
import 'brand_kit.dart';

/// `symbols` → listado: círculo mudo con el ícono. `chips` → píldora con
/// ícono y texto completo. `tiles` → pantallas de DETALLE (plantilla aprobada
/// PO 2026-08-11): eyebrow «REQUISITOS» + una tarjeta horizontal por requisito
/// en el tono teal "requisito", mismo molde que `detailTileBlock` — el
/// requisito no es un dato más y se distingue por color, no por otra forma.
enum RequirementBadgeVariant { symbols, chips, tiles }

/// Equivalentes Material de los íconos lucide que usa la web
/// (`RequestRequirementBadges.tsx`): Truck, Wrench, ClipboardCheck,
/// ReceiptText, Landmark.
const _icons = <Requirement, IconData>{
  Requirement.shipping: Icons.local_shipping_outlined,
  Requirement.installation: Icons.handyman_outlined,
  Requirement.evaluation: Icons.fact_check_outlined,
  Requirement.fiscal: Icons.receipt_long_outlined,
  Requirement.state: Icons.account_balance_outlined,
};

/// Lo que el cliente exige en esta solicitud.
///
/// Sin requisitos activos no dibuja NADA —ni el [padding]—, así que quien lo
/// usa no necesita envolverlo en un condicional ni le queda un hueco vertical
/// fantasma cuando la solicitud no exige nada.
class RequestRequirementBadges extends StatelessWidget {
  const RequestRequirementBadges({
    super.key,
    required this.req,
    required this.variant,
    this.padding,
  });

  final RequestRequirements req;
  final RequirementBadgeVariant variant;

  /// Separación con lo de arriba, aplicada SOLO cuando hay algo que pintar.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final keys = activeRequirements(req);
    if (keys.isEmpty) return const SizedBox.shrink();

    final tone = Theme.of(context).brightness == Brightness.dark
        ? JayaloStatus.requisitoDark
        : JayaloStatus.requisitoLight;

    final body = switch (variant) {
      RequirementBadgeVariant.symbols => Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final k in keys)
            Tooltip(
              // En el listado el símbolo es mudo: el tooltip es lo único que
              // dice qué significa, igual que el `title` de la web.
              message: requirementLabel(k).chip,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icons[k], size: 12, color: tone.ink),
              ),
            ),
        ],
      ),
      RequirementBadgeVariant.chips => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in keys)
            Tooltip(
              message: requirementLabel(k).hint,
              // `StatusChip` en vez de otra píldora propia: misma geometría que
              // "Al por mayor" y "Ya ofertaste", que es justo al lado de donde
              // van estos chips.
              child: StatusChip(
                label: requirementLabel(k).chip,
                icon: _icons[k],
                tone: tone,
              ),
            ),
        ],
      ),
      RequirementBadgeVariant.tiles => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text('REQUISITOS',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          for (final (i, k) in keys.indexed)
            Padding(
              padding:
                  EdgeInsets.only(bottom: i + 1 < keys.length ? 9 : 0),
              child: Tooltip(
                message: requirementLabel(k).hint,
                child: _requirementTile(context, k, tone),
              ),
            ),
        ],
      ),
    };

    final p = padding;
    return p == null ? body : Padding(padding: p, child: body);
  }

  /// Mismo molde que la tarjeta de `detailTileBlock` (pastilla 38 con el
  /// ícono, etiqueta tenue arriba, valor debajo) pero tinturado con el par
  /// teal "requisito": el fondo es el `bg` del tono y la pastilla va blanca
  /// translúcida para que el ícono respire sobre él.
  Widget _requirementTile(
      BuildContext context, Requirement k, ({Color bg, Color ink}) tone) {
    // «Comprobante fiscal» arriba, «Requerido» debajo — el "Requiere …" del
    // chip se parte en etiqueta + valor para leerse como las demás tarjetas.
    final label = requirementLabel(k).short.toUpperCase();
    final value =
        k == Requirement.fiscal ? 'Requerido (NCF)' : 'Requerido';
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_icons[k], size: 19, color: tone.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      color: tone.ink.withValues(alpha: .75),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text(value,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.25,
                      color: tone.ink,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ]),
    );
  }
}
