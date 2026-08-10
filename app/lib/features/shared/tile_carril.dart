/// Carril horizontal de tarjetas compactas para PAQUETES y TRABAJOS — extraído
/// de "Mi negocio" (pedido PO 2026-08-09, tercera vuelta, tras mostrar un
/// ejemplo de grid de tarjetas tipo "match": `_TileCarril`/`_PackageTile`/
/// `_PortfolioTile` en `my_business_screen.dart`, commit `c88d355`) al pedir
/// el PO el MISMO carril para la tienda pública que ve el cliente
/// (`provider_store_screen.dart`): "con todo lo que se ha hecho del lado del
/// proveedor, pero debe verse del lado del cliente". Ambas pantallas montan
/// este archivo — nada de copiar/pegar el widget dos veces.
///
/// La única diferencia entre "Mi negocio" (dueño) y la tienda pública
/// (cliente) es capacidad de edición: [PortfolioTile]/[PackageTile] reciben
/// `onTap`/`onLongPress` opcionales — el dueño los cablea a editar/borrar, la
/// tienda pública los deja en `null` (solo lectura, sin gesto).
library;

import 'package:flutter/material.dart';

import '../../domain/money.dart';
import 'brand_kit.dart';
import 'network_image.dart';

/// Alto de la foto en las tarjetas compactas de [PortfolioTile]/[PackageTile]
/// (rango 110-130 pedido por el PO). La foto va ARRIBA a todo el ancho de la
/// tarjeta angosta, con el texto debajo.
const double kTileImageHeight = 120;

final BorderRadius kTileImageRadius = BorderRadius.only(
  topLeft: Radius.circular(kCardRadius),
  topRight: Radius.circular(kCardRadius),
);

/// Fracción del ancho de pantalla que ocupa cada tarjeta del carril: ~44%
/// deja ver dos tarjetas completas y el asomo de una tercera.
const double kCarrilCardWidthFraction = 0.44;

/// Alto fijo del carril de TRABAJOS: foto + título (hasta 2 líneas). Con
/// margen sobre el cálculo "a ojo" a propósito — en `flutter test` el texto
/// mide bastante más que en el device real (fuente de respaldo del entorno
/// de test), así que un alto ajustado revienta con `RenderFlex overflowed`
/// solo en la suite.
const double kPortfolioCarrilHeight = 230;

/// Alto fijo del carril de PAQUETES: igual que [kPortfolioCarrilHeight] más
/// la fila de precio.
const double kPackageCarrilHeight = 260;

/// `SizedBox(height: ...)` + `ListView` con `scrollDirection:
/// Axis.horizontal`, padding lateral 16 y separación 12 entre tarjetas. La
/// fila «+ Añadir…» de "Mi negocio" queda FUERA de este widget, a todo el
/// ancho, debajo (la pinta quien monta el carril).
class TileCarril extends StatelessWidget {
  const TileCarril({
    super.key,
    required this.items,
    required this.tileBuilder,
    required this.height,
  });

  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic> item) tileBuilder;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cardWidth =
        MediaQuery.sizeOf(context).width * kCarrilCardWidthFraction;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) =>
            SizedBox(width: cardWidth, child: tileBuilder(items[i])),
      ),
    );
  }
}

/// Trabajo del portafolio: tarjeta compacta del carril de TRABAJOS, con la
/// foto arriba (a todo el ancho DE LA TARJETA) + título debajo. En "Mi
/// negocio" tocar abre el editor y mantener presionado pide confirmar el
/// borrado (Task 8); en la tienda pública ambos van `null` (solo lectura).
/// `margin: EdgeInsets.zero` porque el espaciado entre tarjetas lo pone
/// [TileCarril] (separador + padding del carril), no el margen individual de
/// `JayaloCard`.
class PortfolioTile extends StatelessWidget {
  const PortfolioTile({super.key, required this.item, this.onTap, this.onLongPress});
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return JayaloCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: kTileImageRadius,
            child: img == null || img.isEmpty
                ? tilePlaceholder(cs, Icons.photo_outlined)
                : JayaloNetworkImage(
                    img,
                    width: double.infinity,
                    height: kTileImageHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        tilePlaceholder(cs, Icons.photo_outlined),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(item['title'] as String? ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Paquete/plan: tarjeta compacta del carril de PAQUETES, con la foto arriba
/// (a todo el ancho DE LA TARJETA) + nombre y precio debajo. Mismo trato de
/// `onTap`/`onLongPress` que [PortfolioTile] (editar/borrar en "Mi negocio",
/// `null` en la tienda pública). Mismo motivo de `margin: EdgeInsets.zero`.
class PackageTile extends StatelessWidget {
  const PackageTile({super.key, required this.item, this.onTap, this.onLongPress});
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = item['image_url'] as String?;
    final price = item['price'] as num?;
    return JayaloCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: kTileImageRadius,
            child: img == null || img.isEmpty
                ? tilePlaceholder(cs, Icons.inventory_2_outlined)
                : JayaloNetworkImage(
                    img,
                    width: double.infinity,
                    height: kTileImageHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        tilePlaceholder(cs, Icons.inventory_2_outlined),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['name'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                // (price == null || price == 0): la columna es NOT NULL
                // DEFAULT 0, así que un precio en blanco se guarda como 0, no
                // como null — sin este OR, "Consultar precio" quedaba
                // inalcanzable para un paquete guardado sin precio.
                Text(
                    (price == null || price == 0)
                        ? 'Consultar precio'
                        : fmtRD(price),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto vacía/rota de un [PortfolioTile]/[PackageTile]: mismo contenedor gris
/// con ícono en ambos, a todo el ancho de la tarjeta.
Widget tilePlaceholder(ColorScheme cs, IconData icon) => Container(
      width: double.infinity,
      height: kTileImageHeight,
      alignment: Alignment.center,
      color: cs.surfaceContainerHighest,
      child: Icon(icon, color: cs.onSurfaceVariant, size: 34),
    );
