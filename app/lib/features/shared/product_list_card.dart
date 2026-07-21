import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import 'brand_kit.dart';

/// Fila del catálogo (foto + categoría + nombre + reputación + descripción +
/// precio) que navega a `/catalog/:id`. Extraída de `catalog_screen.dart` para
/// reusarse en "Mi tienda". La línea de reputación se oculta si el `item` no
/// trae `avg_rating`/`reviews_count` (Mi tienda no la pasa).
class ProductListCard extends StatelessWidget {
  const ProductListCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final desc = (item['description'] as String? ?? '').trim();
    final catName = categoryNameById(item['category_id'] as String?);
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return JayaloCard(
      padding: const EdgeInsets.all(10),
      // Desde la TIENDA del proveedor (`/store/:bid`, ruta del navigator
      // RAÍZ) hay que usar la variante top-level `/product/:id`: empujar la
      // ruta del shell `/catalog/:id` desde ahí montaba el detalle DEBAJO de
      // la tienda y se veía vacío (QA PO 2026-07-21). En el catálogo (shell)
      // se conserva `/catalog/:id`, con su navbar.
      onTap: () {
        final inStore =
            GoRouterState.of(context).uri.path.startsWith('/store/');
        context.push(
            inStore ? '/product/${item['id']}' : '/catalog/${item['id']}');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(kCardRadius - 6),
            child: SizedBox(
              width: 104,
              height: 104,
              child: img == null
                  ? _imagePlaceholder(cs)
                  : Image.network(
                      img,
                      fit: BoxFit.cover,
                      // Fundido suave al cargar (doctrina de movimiento).
                      frameBuilder: (_, child, frame, wasSync) => wasSync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: child,
                            ),
                      errorBuilder: (_, _, _) => _imagePlaceholder(cs),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (catName != null) ...[
                  Text(catName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .8,
                          color: cs.primary)),
                  const SizedBox(height: 3),
                ],
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: jayaloHead(context))),
                ?_ratingLine(context, cs),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // onSurface (no onSurfaceVariant): el muted #847D8F sobre
                      // la tarjeta blanca queda ~3.2:1, bajo el mínimo 4.5:1.
                      // El peso normal + tamaño menor ya lo separan del nombre.
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: cs.onSurface)),
                ],
                const SizedBox(height: 8),
                _priceLine(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reputación del proveedor: ★ + promedio a 1 decimal + conteo (misma
  /// convención que Estadísticas/Reputación — escala de la app, no 5 estrellas).
  /// Devuelve `null` (fila oculta) si el proveedor aún no tiene reseñas, para no
  /// mostrar un "0.0" que parezca mala nota.
  Widget? _ratingLine(BuildContext context, ColorScheme cs) {
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;
    if (avg <= 0 || count <= 0) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
        const SizedBox(width: 3),
        Text(avg.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context))),
        const SizedBox(width: 4),
        Text('($count)',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// Precio protagonista (20px, bold, violeta de marca). Un [FittedBox] deja
  /// que un rango largo ("RD$500 – RD$1,200") se encoja a una sola línea sin
  /// que los precios cortos se vean pequeños. "desde" va como prefijo tenue y
  /// "Consultar precio" en gris (no es una cifra: no debe gritar en violeta).
  Widget _priceLine(ColorScheme cs) {
    final price = item['price'] as num?;
    final min = item['price_min'] as num?;
    final max = item['price_max'] as num?;
    final big = TextStyle(
      fontSize: 20,
      height: 1,
      fontWeight: FontWeight.w700,
      color: cs.primary,
      letterSpacing: -.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (price == null && min == null) {
      return Text('Consultar precio',
          maxLines: 1,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant));
    }

    final Widget line;
    if (price != null) {
      line = Text(fmtRD(price), maxLines: 1, style: big);
    } else if (max != null) {
      // Guion simple con espacios: paridad EXACTA con `catalogPriceLabel` /
      // `formatProductHitPrice` de la web (no un guion largo tipográfico).
      line = Text('${fmtRD(min)} - ${fmtRD(max)}', maxLines: 1, style: big);
    } else {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('desde ',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant)),
          Text(fmtRD(min), style: big),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
          fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: line),
    );
  }

  Widget _imagePlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
      );
}
