import 'package:flutter/material.dart';
import 'network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import '../../domain/offer_defaults.dart';
import 'brand_kit.dart';
import 'star_score.dart';

/// Fila del catálogo (foto + categoría + nombre + reputación + descripción +
/// precio) que navega a `/catalog/:id`. Extraída de `catalog_screen.dart` para
/// reusarse en "Mi tienda". La línea de reputación se oculta si el `item` no
/// trae `avg_rating`/`reviews_count` (Mi tienda no la pasa).
class ProductListCard extends StatelessWidget {
  const ProductListCard({super.key, required this.item, this.onTap, this.onLongPress});
  final Map<String, dynamic> item;

  /// Sustituye la navegación por defecto al detalle del producto — usado por
  /// "Mi negocio" (Task 6) para que tocar una tarjeta PROPIA abra el editor
  /// en vez del detalle público. `null` = comportamiento de siempre (navegar
  /// a `/product/:id` o `/catalog/:id`).
  final VoidCallback? onTap;

  /// "Mantener presionada → Eliminar de tu tienda" (Task 6, "Mi negocio").
  /// `null` en el catálogo público: ahí no hay nada que borrar.
  final VoidCallback? onLongPress;

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
      // se conserva `/catalog/:id`, con su navbar. [onTap] la reemplaza
      // entera cuando viene dada (tarjeta propia en "Mi negocio").
      onTap: onTap ??
          () {
            final inStore =
                GoRouterState.of(context).uri.path.startsWith('/store/');
            context.push(
                inStore ? '/product/${item['id']}' : '/catalog/${item['id']}');
          },
      onLongPress: onLongPress,
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
                  : JayaloNetworkImage(
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

  /// Reputación del proveedor: las cinco estrellas con medias + el promedio con
  /// su escala + el conteo. Devuelve `null` (fila oculta) si el proveedor aún no
  /// tiene reseñas, para no mostrar un "0.0" que parezca mala nota.
  ///
  /// ⚠️ Antes era UNA estrella y «8.6» a secas, que se lee como 8,6 **sobre 5** —
  /// un negocio mediocre parecía excelente. Cambiado el 2026-08-17 con el resto.
  Widget? _ratingLine(BuildContext context, ColorScheme cs) {
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;
    if (avg <= 0 || count <= 0) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        StarScore(score: avg, size: 13, showNumber: false),
        const SizedBox(width: 4),
        Text('${StarScore.formatScore(avg)}/10',
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

/// Alto de la foto de [ProductGridCard]: lo ÚNICO de la tarjeta que NO crece
/// con la fuente del sistema.
const double _kGridImageHeight = 118;

/// Padding vertical del bloque de texto (10 arriba + 12 abajo).
const double _kGridTextPadding = 22;

/// Alto del bloque de texto de [ProductGridCard] a escala 1, en el CASO PEOR:
/// eyebrow + nombre a 2 líneas + reputación + DOS renglones de atributos +
/// precio, con sus huecos. Medido con el test de `product_list_card_test.dart`,
/// que es quien vigila que siga alcanzando (el caso peor ocupa 261 con la
/// tipografía del entorno de test, ~253 con Roboto: se toma la mayor + margen).
const double _kGridTextBlock = 122;

/// Alto de la celda de la rejilla del catálogo. La tarjeta vive en un
/// `mainAxisExtent` FIJO y todo lo que va bajo la foto es texto, así que con
/// la fuente del sistema en grande —o en una pantalla estrecha, donde la fila
/// de atributos se parte en dos renglones— el bloque crecía, el precio se
/// salía por debajo y quedaba recortado (reporte PO 2026-08-14). Con la fuente
/// por defecto son 262 (6 más que el 256 aprobado — el margen que le faltaba a
/// una tarjeta con dos renglones de atributos), y de ahí crece con el texto.
double catalogGridCardExtent(BuildContext context) {
  // Escala tipográfica efectiva (Android 14 la aplica de forma no lineal, por
  // eso se mide sobre un tamaño representativo del bloque en vez de asumirla).
  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
  return _kGridImageHeight +
      _kGridTextPadding +
      _kGridTextBlock * scale.clamp(1.0, 1.8);
}

/// Alto de un renglón de la fila de atributos: el icono (12) o su texto a la
/// escala del sistema, lo que mida más.
double _attrRunHeight(BuildContext context) {
  final text = MediaQuery.textScalerOf(context).scale(10) * 1.25;
  return text < 12 ? 12 : text;
}

/// Tarjeta de REJILLA del catálogo (mockup aprobado PO 2026-08-10): la foto
/// llena el ancho de la tarjeta arriba; abajo solo lo que decide un vistazo —
/// categoría en eyebrow violeta, nombre a 2 líneas y precio. La descripción
/// NO viaja aquí: vive en la ficha del producto. [ProductListCard] (fila
/// ancha) sigue siendo la de "Mi negocio"/tienda del proveedor.
class ProductGridCard extends StatelessWidget {
  const ProductGridCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final catName = categoryNameById(item['category_id'] as String?);
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;

    Widget placeholder() => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child:
              Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
        );

    return JayaloCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      // Solo vive en el catálogo (shell): misma ruta que la fila ancha.
      onTap: () => GoRouter.of(context).push('/catalog/${item['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(kCardRadius)),
            child: SizedBox(
              height: 118,
              child: img == null
                  ? placeholder()
                  : JayaloNetworkImage(
                      img,
                      fit: BoxFit.cover,
                      frameBuilder: (_, child, frame, wasSync) => wasSync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: child,
                            ),
                      errorBuilder: (_, _, _) => placeholder(),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (catName != null) ...[
                    Text(catName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                            color: cs.primary)),
                    const SizedBox(height: 3),
                  ],
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  if (avg > 0 && count > 0) ...[
                    const SizedBox(height: 3),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      // Estrellas a 11 px: en media tarjeta las cinco más el texto
                      // van justas. ⚠️ Es el sitio más apretado de los diez y el
                      // que hay que mirar primero en el smoke del device.
                      StarScore(score: avg, size: 11, showNumber: false),
                      const SizedBox(width: 3),
                      // Flexible: con muchas reseñas y la fuente en grande
                      // ("9.8/10 (1204)") la línea no cabe en media tarjeta —
                      // se corta con puntos suspensivos en vez de desbordar.
                      Flexible(
                        child: Text(
                            '${StarScore.formatScore(avg)}/10 ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ),
                    ]),
                  ],
                  ?_attrsRow(context, cs),
                  const Spacer(),
                  _gridPrice(cs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fila de atributos (Variante A del mockup, PO 2026-08-11): iconitos con
  /// texto micro entre el nombre y el precio — envío, estado y color, en ese
  /// orden. Solo pinta lo que el producto declara; sin nada, ni el hueco.
  /// El color sigue la regla de la ficha: la lista de `offer_defaults.colors`
  /// gana sobre la columna legada `color`. Texto en `onSurface` (no el muted):
  /// mismo motivo de contraste documentado en la descripción de la fila ancha.
  Widget? _attrsRow(BuildContext context, ColorScheme cs) {
    final condition = item['condition'] as String?;
    final conditionLabel =
        condition == 'nuevo' ? 'Nuevo' : condition == 'usado' ? 'Usado' : null;
    final colorsList = (((item['offer_defaults'] as Map?)
                ?.cast<String, dynamic>())?[OfferDefaults.colors] as List?)
            ?.cast<String>() ??
        const [];
    final colorLabel = colorsList.isNotEmpty
        ? colorsList.join(', ')
        : (item['color'] as String?);
    final attrs = <(IconData, String)>[
      if (item['offers_shipping'] == true)
        (Icons.local_shipping_outlined, 'Traslado'),
      if (conditionLabel != null) (Icons.inventory_2_outlined, conditionLabel),
      if (colorLabel != null && colorLabel.trim().isNotEmpty)
        (Icons.palette_outlined, colorLabel.trim()),
    ];
    if (attrs.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      // DOS renglones como máximo: la celda de la rejilla tiene alto fijo (ver
      // [catalogGridCardExtent], que reserva justo esos dos), así que un tercer
      // renglón —pantalla muy estrecha + fuente muy grande— se recorta aquí en
      // vez de empujar el precio fuera de la tarjeta.
      child: ClipRect(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: _attrRunHeight(context) * 2 + 3),
          child: Wrap(spacing: 10, runSpacing: 3, children: [
            for (final (icon, label) in attrs)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 3.5),
                ConstrainedBox(
                  // Una lista larga de colores se corta con puntos suspensivos
                  // en vez de reventar el ancho de la media tarjeta.
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface)),
                ),
              ]),
          ]),
        ),
      ),
    );
  }

  /// Precio compacto de la rejilla — misma semántica que [_priceLine] de la
  /// fila ancha (fijo / rango / "desde" / "Consultar precio"), a 16px.
  Widget _gridPrice(ColorScheme cs) {
    final price = item['price'] as num?;
    final min = item['price_min'] as num?;
    final max = item['price_max'] as num?;
    final big = TextStyle(
      fontSize: 16,
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
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant));
    }
    final Widget line;
    if (price != null) {
      line = Text(fmtRD(price), maxLines: 1, style: big);
    } else if (max != null) {
      line = Text('${fmtRD(min)} - ${fmtRD(max)}', maxLines: 1, style: big);
    } else {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('desde ',
              style: TextStyle(
                  fontSize: 11.5,
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
}
