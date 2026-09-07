import 'package:flutter/material.dart';
import 'network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show BusinessCardInfo;
import '../../domain/catalog.dart';
import '../../domain/money.dart';
import '../client/catalog_articulos.dart' show tipoDeItem;
import 'brand_kit.dart';
import 'star_score.dart';

/// Fila del catálogo (foto + categoría + nombre + reputación + descripción +
/// precio) que navega a `/catalog/:id`. Extraída de `catalog_screen.dart` para
/// reusarse en "Mi tienda". La línea de reputación se oculta si el `item` no
/// trae `avg_rating`/`reviews_count` (Mi tienda no la pasa).
class ProductListCard extends StatelessWidget {
  const ProductListCard({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
  });
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
      onTap:
          onTap ??
          () {
            final inStore = GoRouterState.of(
              context,
            ).uri.path.startsWith('/store/');
            context.push(
              inStore ? '/product/${item['id']}' : '/catalog/${item['id']}',
            );
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
                  Text(
                    catName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .8,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
                ?_ratingLine(context, cs),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // onSurface (no onSurfaceVariant): el muted #847D8F sobre
                    // la tarjeta blanca queda ~3.2:1, bajo el mínimo 4.5:1.
                    // El peso normal + tamaño menor ya lo separan del nombre.
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: cs.onSurface,
                    ),
                  ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarScore(score: avg, size: 13, showNumber: false),
          const SizedBox(width: 4),
          Text(
            '${StarScore.formatScore(avg)}/10',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: jayaloHead(context),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
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
      return Text(
        'Consultar precio',
        maxLines: 1,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      );
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
          Text(
            'desde ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(fmtRD(min), style: big),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: line,
      ),
    );
  }

  Widget _imagePlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
  );
}

/// Padding vertical del bloque de texto de [ProductGridCard] (10 arriba + 12
/// abajo).
const double _kGridTextPadding = 22;

/// Alto del bloque de texto de [ProductGridCard] a escala 1, en el CASO PEOR:
/// nombre a 2 líneas + línea de tienda + reputación + precio, con sus huecos
/// (≈94 medidos; se toma 104 para dejar margen a la fuente del entorno de
/// test). `product_list_card_test.dart` vigila que siga alcanzando.
const double _kGridTextBlock = 104;

/// Alto de la celda de la rejilla del catálogo: la foto es CUADRADA (tan alta
/// como ancha la celda, [cellWidth]) y debajo va el bloque de texto, que crece
/// con la fuente del sistema. Antes la foto medía 118 fijos y el bloque de
/// texto la superaba (PO 2026-09-05: «manda el texto, no la foto»).
/// [conIncluido] suma el alto de la línea «lo incluido» (paquetes con
/// `items`), que se pinta bajo el nombre en las tarjetas de paquete.
double catalogGridCardExtent(
  BuildContext context,
  double cellWidth, {
  bool conIncluido = false,
}) {
  // Escala tipográfica efectiva (Android 14 la aplica de forma no lineal, por
  // eso se mide sobre un tamaño representativo del bloque).
  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
  final escala = scale.clamp(1.0, 1.8);
  return cellWidth +
      _kGridTextPadding +
      _kGridTextBlock * escala +
      (conIncluido ? 28 * escala : 0);
}

/// Foto de catálogo: `cover`, fundido suave al cargar (doctrina de
/// movimiento) y placeholder neutro sin foto o con error. Compartida por la
/// tarjeta de rejilla y la de carrusel. Sin [url]: si el negocio tiene
/// [logoUrl] se muestra su logo redondo (42 % del alto) centrado sobre
/// `cs.primaryContainer` — mejor "de qué negocio es" que un icono genérico
/// cuando el ítem no tiene foto propia (PO catálogo por artículos 09-07).
Widget catalogImage(String? url, ColorScheme cs, {String? logoUrl}) {
  Widget placeholder() {
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Container(
        color: cs.primaryContainer,
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: .42,
          heightFactor: .42,
          child: ClipOval(
            child: JayaloNetworkImage(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.storefront_outlined, color: cs.onPrimaryContainer),
            ),
          ),
        ),
      );
    }
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 34, color: cs.onSurfaceVariant),
    );
  }

  if (url == null) return placeholder();
  return JayaloNetworkImage(
    url,
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
  );
}

/// Insignia de tipo (Producto/Servicio/Paquete) sobre la foto — solo cuando la
/// tarjeta la pide (`showTypeTag`, hoy únicamente el catálogo POR ARTÍCULOS
/// separado por secciones: en la rejilla mixta de siempre el tipo ya lo dice
/// la sección/chip). Colores por tipo: Producto en `cs.surface` (neutro, es
/// el "default"), Servicio en `cs.primary` violeta y Paquete en
/// `cs.onPrimaryContainer` (violeta oscuro), ambos con texto blanco para que
/// se lean sobre la foto. Se pinta dentro de un `Stack` sobre la imagen,
/// `Positioned(left: 8, top: 8)` — quien la usa la envuelve así.
Widget catalogTypeBadge(BuildContext context, String tipo) {
  final cs = Theme.of(context).colorScheme;
  final (Color bg, Color fg, String label) = switch (tipo) {
    'servicio' => (cs.primary, Colors.white, 'Servicio'),
    'paquete' => (cs.onPrimaryContainer, Colors.white, 'Paquete'),
    _ => (cs.surface, jayaloHead(context), 'Producto'),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      boxShadow: const [
        BoxShadow(
          color: JayaloColors.warmShadow,
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
        color: fg,
      ),
    ),
  );
}

/// «Lo incluido» de un paquete: la lista de `items` separada por «·», bajo el
/// nombre, en ambas tarjetas (rejilla y carrusel). `null` para producto o
/// servicio, o para un paquete sin `items` cargados.
Widget? catalogIncluidoLine(Map<String, dynamic> item, ColorScheme cs) {
  if (tipoDeItem(item) != 'paquete') return null;
  final items = (item['items'] as List?)?.cast<String>() ?? const <String>[];
  if (items.isEmpty) return null;
  return Text(
    items.join(' · '),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      height: 11 / 10.5,
      color: cs.onSurfaceVariant,
    ),
  );
}

/// Ruta del detalle: los paquetes abren `/package/:id` (no tienen ficha en
/// `/catalog` ni `/product`); producto y servicio conservan la ruta de
/// siempre, resuelta según si la tarjeta vive en el shell del catálogo o en
/// la tienda del proveedor (navigator raíz, ver comentario en
/// [ProductListCard.onTap]).
void _abrirDetalle(BuildContext context, Map<String, dynamic> item) {
  final id = item['id'];
  if (tipoDeItem(item) == 'paquete') {
    context.push('/package/$id');
    return;
  }
  context.push('/catalog/$id');
}

/// Línea «de quién es»: icono de tienda + nombre del negocio y, si declara
/// local y [sello] lo permite, el sufijo «· Tienda física» en la tinta teal
/// del tono `requisito` (AUTODECLARADO: nunca el verde de verificado — ver
/// `PhysicalLocationBadge`). Va como texto y no como píldora porque en media
/// tarjeta la píldora no cabe. `null` sin negocio: la tarjeta se encoge, no
/// inventa un «Proveedor» fantasma.
Widget? storeLine(
  BuildContext context,
  BusinessCardInfo? negocio, {
  bool sello = true,
}) {
  if (negocio == null) return null;
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final teal =
      (dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight).ink;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(Icons.storefront_outlined, size: 12, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: negocio.name,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: cs.onSurfaceVariant,
              ),
              children: [
                if (sello && negocio.hasPhysicalLocation)
                  TextSpan(
                    text: ' · Tienda física',
                    style: TextStyle(color: teal, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Precio del catálogo a un [size] dado — misma semántica que [_priceLine] de
/// la fila ancha (fijo / rango / «desde» / «Consultar precio»). Un
/// [FittedBox] encoge un rango largo a una línea sin achicar los cortos.
Widget catalogPriceLine(
  ColorScheme cs,
  Map<String, dynamic> item, {
  required double size,
}) {
  final price = item['price'] as num?;
  final min = item['price_min'] as num?;
  final max = item['price_max'] as num?;
  final big = TextStyle(
    fontSize: size,
    height: 1,
    fontWeight: FontWeight.w700,
    color: cs.primary,
    letterSpacing: -.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  if (price == null && min == null) {
    return Text(
      'Consultar precio',
      maxLines: 1,
      style: TextStyle(
        fontSize: size * .78,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    );
  }
  final Widget line;
  if (price != null) {
    line = Text(fmtRD(price), maxLines: 1, style: big);
  } else if (max != null) {
    // Guion simple con espacios: paridad EXACTA con `catalogPriceLabel` de la web.
    line = Text('${fmtRD(min)} - ${fmtRD(max)}', maxLines: 1, style: big);
  } else {
    line = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'desde ',
          style: TextStyle(
            fontSize: size * .72,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(fmtRD(min), style: big),
      ],
    );
  }
  return Align(
    alignment: Alignment.centerLeft,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: line,
    ),
  );
}

/// Tarjeta de REJILLA del catálogo (mockup aprobado PO 2026-09-05, camino 3):
/// foto CUADRADA arriba y debajo solo lo que decide un vistazo — nombre a 2
/// líneas, de quién es ([storeLine]), reputación si la hay y precio. La
/// categoría ya no viaja aquí (la dice el chip o la sección) ni los atributos
/// envío/estado/color (viven en la ficha del producto). [ProductListCard]
/// (fila ancha) sigue siendo la de «Mi negocio»/tienda del proveedor.
class ProductGridCard extends StatelessWidget {
  const ProductGridCard({
    super.key,
    required this.item,
    this.negocio,
    this.showTypeTag = false,
  });
  final Map<String, dynamic> item;

  /// Cabecera del negocio dueño del producto (nombre, local). `null` = no
  /// resolvió (consulta caída o negocio borrado): la línea no se pinta.
  final BusinessCardInfo? negocio;

  /// Insignia de tipo (Producto/Servicio/Paquete) sobre la foto — apagada por
  /// defecto porque la rejilla mixta de siempre ya lo dice por chip/sección;
  /// la enciende el catálogo POR ARTÍCULOS, donde una sección puede traer
  /// paquetes mezclados con productos.
  final bool showTypeTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['reviews_count'] as num?)?.toInt() ?? 0;
    final incluido = catalogIncluidoLine(item, cs);

    return JayaloCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      onTap: () => _abrirDetalle(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kCardRadius),
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  catalogImage(img, cs, logoUrl: negocio?.logoUrl),
                  if (showTypeTag)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: catalogTypeBadge(context, tipoDeItem(item)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context),
                    ),
                  ),
                  if (incluido != null) ...[
                    const SizedBox(height: 3),
                    incluido,
                  ],
                  ?storeLine(context, negocio),
                  if (avg > 0 && count > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Estrellas a 11 px: en media tarjeta las cinco más el
                        // texto van justas — mirar primero en el smoke del device.
                        StarScore(score: avg, size: 11, showNumber: false),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '${StarScore.formatScore(avg)}/10 ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(),
                  catalogPriceLine(cs, item, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de CARRUSEL de la portada del catálogo (PO 2026-09-05, ancho
/// 150 desde el catálogo por artículos 09-07): foto CUADRADA (antes apaisada
/// de 96 — «manda el texto, no la foto», mismo criterio que [ProductGridCard]
/// desde 09-05), nombre a 2 líneas, lo incluido si es paquete, de quién es
/// (sin sello: no cabe) y precio. Sin estrellas ni atributos — es de un
/// vistazo. Alto por contenido: quien la apila la mete en un `Row` con
/// `stretch` dentro de un `IntrinsicHeight`, así todas las tarjetas de la
/// fila miden igual.
class ProductCarouselCard extends StatelessWidget {
  const ProductCarouselCard({
    super.key,
    required this.item,
    this.negocio,
    this.width = 150,
    this.showTypeTag = false,
  });
  final Map<String, dynamic> item;
  final BusinessCardInfo? negocio;
  final double width;

  /// Ver [ProductGridCard.showTypeTag]: apagada por defecto.
  final bool showTypeTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    final incluido = catalogIncluidoLine(item, cs);
    return SizedBox(
      width: width,
      child: JayaloCard(
        padding: EdgeInsets.zero,
        margin: EdgeInsets.zero,
        onTap: () => _abrirDetalle(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(kCardRadius),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    catalogImage(img, cs, logoUrl: negocio?.logoUrl),
                    if (showTypeTag)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: catalogTypeBadge(context, tipoDeItem(item)),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context),
                    ),
                  ),
                  if (incluido != null) ...[
                    const SizedBox(height: 3),
                    incluido,
                  ],
                  ?storeLine(context, negocio, sello: false),
                  const SizedBox(height: 6),
                  catalogPriceLine(cs, item, size: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
