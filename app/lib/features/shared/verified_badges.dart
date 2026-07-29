import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Sellos de verificación (PO 2026-07-28): "deberían aparecer en el nombre del
/// perfil y en el avatar del cliente y de quien oferta".
///
/// Dos presentaciones del MISMO dato para no repetir el ✓ en seis sitios:
/// [VerifiedTick] se ancla al avatar y [VerifiedLabel] va junto al nombre.
/// Ambos se pintan solo si hay al menos un sello.
Color _tickColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dSuccess
        : JayaloColors.success;

/// ✓ pequeño para anclar sobre un avatar (envolver en un `Stack`).
class VerifiedTick extends StatelessWidget {
  const VerifiedTick({
    super.key,
    required this.whatsappVerified,
    required this.idVerified,
    this.size = 16,
  });

  final bool whatsappVerified;
  final bool idVerified;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!whatsappVerified && !idVerified) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Icon(Icons.verified, size: size, color: _tickColor(context)),
    );
  }
}

/// Etiqueta textual junto al nombre. La identidad manda sobre el WhatsApp:
/// es el sello más fuerte y mostrar los dos satura la fila.
///
/// El copy es NEUTRO a propósito ("Identidad verificada", no "Proveedor
/// verificado"): este widget pinta el sello de la CONTRAPARTE, y la contraparte
/// es un cliente tantas veces como un proveedor. Con el copy viejo, un
/// proveedor que abría el chat de un cliente con identidad verificada leía
/// "Proveedor verificado" junto al nombre de ese cliente — falso.
/// `provider_store_screen.dart` mantiene su propia lista de sellos con
/// "Proveedor verificado", y ahí sí es correcto: el sujeto siempre es un
/// proveedor.
class VerifiedLabel extends StatelessWidget {
  const VerifiedLabel({
    super.key,
    required this.whatsappVerified,
    required this.idVerified,
  });

  final bool whatsappVerified;
  final bool idVerified;

  @override
  Widget build(BuildContext context) {
    if (!whatsappVerified && !idVerified) return const SizedBox.shrink();
    final label = idVerified ? 'Identidad verificada' : 'WhatsApp verificado';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.verified, size: 14, color: _tickColor(context)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(fontSize: 11.5, color: _tickColor(context))),
    ]);
  }
}
