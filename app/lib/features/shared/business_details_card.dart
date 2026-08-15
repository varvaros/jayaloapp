import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/business_details.dart';

/// Ficha "Detalles del proveedor" — espejo de `BusinessDetailsCard.tsx` de la
/// web. La app solo enseñaba tres chips (categoría, zona, mayorista); esto
/// trae experiencia, fundación, equipo, cobertura, horario, idiomas, pagos y
/// garantía, que es lo que el PO echaba en falta (2026-08-01).
///
/// Qué filas salen y con qué texto lo decide `businessDetailRows`, que es puro
/// y está probado aparte. Aquí solo se dibuja.
class BusinessDetailsCard extends StatelessWidget {
  const BusinessDetailsCard({
    super.key,
    required this.business,
    this.currentYear,
  });

  /// Fila cruda de `provider_businesses` (las columnas de detalle son de
  /// lectura pública, así que sirve igual para la tienda propia y la ajena).
  final Map<String, dynamic> business;

  /// Inyectable para los tests de "hace N años"; por defecto, el año de hoy.
  final int? currentYear;

  static IconData _iconFor(BusinessDetailKind k) => switch (k) {
        BusinessDetailKind.wholesale => Icons.inventory_2_outlined,
        BusinessDetailKind.profession => Icons.engineering_outlined,
        BusinessDetailKind.experience => Icons.workspace_premium_outlined,
        BusinessDetailKind.founded => Icons.event_outlined,
        BusinessDetailKind.team => Icons.groups_outlined,
        BusinessDetailKind.coverage => Icons.pin_drop_outlined,
        BusinessDetailKind.hours => Icons.schedule_outlined,
        BusinessDetailKind.languages => Icons.language_outlined,
        BusinessDetailKind.payments => Icons.account_balance_wallet_outlined,
        BusinessDetailKind.warranty => Icons.verified_user_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final rows = businessDetailRows(
      business,
      currentYear: currentYear ?? DateTime.now().year,
    );
    // Sin datos NO se dibuja el marco: una ficha con el título y nada dentro
    // parece un error de carga.
    if (rows.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.storefront_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text('DETALLES DEL PROVEEDOR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: cs.onSurfaceVariant,
                )),
          ]),
          const SizedBox(height: 14),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_iconFor(r.kind), size: 17, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            )),
                        const SizedBox(height: 1),
                        Text(r.value,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: jayaloHead(context),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
