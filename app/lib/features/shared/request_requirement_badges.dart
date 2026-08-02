import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/request_requirements.dart';
import 'brand_kit.dart';

/// `symbols` → listado: círculo mudo con el ícono. `chips` → detalle: píldora
/// con ícono y texto completo.
enum RequirementBadgeVariant { symbols, chips }

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
    };

    final p = padding;
    return p == null ? body : Padding(padding: p, child: body);
  }
}
