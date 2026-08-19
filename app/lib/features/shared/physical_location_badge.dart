import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'brand_kit.dart';

/// Sello "Tienda física" (PO 2026-08-12), AUTODECLARADO: el proveedor dice que
/// atiende en un local abierto al público y nadie lo comprueba. Por eso es una
/// píldora teal con tono `requisito` y NUNCA lleva el ✓ verde de la tarjeta de
/// reputación, que sí verifica Jayalo.
///
/// Vive aquí y no dentro de una pantalla porque lo pintan dos: la tienda
/// pública que ve el cliente (`provider_store_screen`) y "Mi negocio"
/// (`my_business_screen`). Pedido PO 2026-08-18: en ambas va pegado a la
/// portada, lo primero que se ve debajo.
class PhysicalLocationBadge extends StatelessWidget {
  const PhysicalLocationBadge({super.key});

  /// `null` cuando el negocio no declara local: así el llamador no monta un
  /// sliver (ni una fila) vacía que deje un hueco. Mismo idioma que
  /// `TeamGalleryBlock.maybe`.
  static Widget? maybe({required bool hasPhysicalLocation}) =>
      hasPhysicalLocation ? const PhysicalLocationBadge() : null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Tienda física',
          icon: Icons.storefront_outlined,
          tone: dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight,
        ),
      ),
    );
  }
}
