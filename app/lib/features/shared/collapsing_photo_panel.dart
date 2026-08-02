import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'network_image.dart';

/// Panel de foto de cabecera que se PLIEGA al hacer scroll.
///
/// Antes esto vivía inline en `request_detail_screen.dart` como un `Container`
/// de alto FIJO (300 + notch) con la lista debajo en un `Expanded`: la foto no
/// se movía nunca y el formulario de oferta —precio, disponibilidad, detalles,
/// hasta 4 fotos, aviso de costo— quedaba encajonado en un tercio de pantalla.
/// El PO lo pidió plegable (2026-08-01) "para que la ventana se vea completa".
///
/// Se extrae aquí en vez de quedarse inline porque el detalle del interés de
/// producto necesita exactamente el mismo panel.
///
/// Devuelve un SLIVER: hay que meterlo en un `CustomScrollView`, no en una
/// `Column`.
class CollapsingPhotoPanel extends StatelessWidget {
  const CollapsingPhotoPanel({
    super.key,
    required this.images,
    required this.fallbackIcon,
    this.expandedHeight = 300,
    this.leading,
    this.onOpenViewer,
  });

  /// URLs ya filtradas (sin vacías). Lista vacía = panel lila con el ícono.
  final List<String> images;

  /// Ícono grande cuando no hay fotos, o cuando la primera falla al cargar
  /// (`handyman_outlined` para servicio, `inventory_2_outlined` para producto).
  final IconData fallbackIcon;

  final double expandedHeight;

  /// Va como `leading` de la barra, así que sigue tocable con el panel
  /// plegado — si desapareciera al colapsar, el usuario se quedaría sin salida.
  final Widget? leading;

  /// Abre el visor a pantalla completa en la foto `index`. Nulo = las fotos no
  /// son tocables.
  final void Function(int index)? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Mismos colores que tenía inline: ámbar cuando hay foto (la foto lo tapa
    // casi todo, el ámbar solo asoma en los bordes) y lila con el ícono
    // violeta cuando no hay ninguna (pedido PO 2026-07-19, mismo criterio que
    // el detalle del cliente).
    const amberPanelDark = Color(0xFF3A2C12);
    const amberPanelLight = Color(0xFFF0C48C);
    final amberPanel = dark ? amberPanelDark : amberPanelLight;
    final amberInk = dark ? amberPanelLight : const Color(0xFF6B4514);
    final emptyTone =
        dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight;

    Widget fallback(Color color) =>
        Center(child: Icon(fallbackIcon, size: 120, color: color));

    return SliverAppBar(
      pinned: true,
      expandedHeight: expandedHeight,
      // El color de la BARRA PLEGADA, no el del panel abierto: `FlexibleSpaceBar`
      // desvanece su `background` al colapsar, así que lo que queda arriba es
      // esto. Con foto va el color de la hoja, para que la barra plegada se
      // funda con el contenido; el ámbar solo tiñe el panel abierto, por
      // detrás de la foto (visto en device 2026-08-01: con ámbar quedaba una
      // franja melocotón que no pega con nada).
      backgroundColor: images.isEmpty ? emptyTone.bg : cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: leading,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      flexibleSpace: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        child: FlexibleSpaceBar(
          // `none` y no `parallax`: con parallax el fondo se dibuja más alto
          // que el espacio y la 2ª miniatura se sale del recorte al plegar.
          collapseMode: CollapseMode.none,
          background: Stack(
            children: [
              Positioned.fill(
                child: images.isEmpty
                    ? fallback(emptyTone.ink)
                    : GestureDetector(
                        onTap: onOpenViewer == null
                            ? null
                            : () => onOpenViewer!(0),
                        child: JayaloNetworkImage(
                          images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback(amberInk),
                        ),
                      ),
              ),
              // Miniatura de la 2ª foto pegada al borde derecho (máx. 2
              // visibles). Se va con el panel al plegarse, por eso vive en el
              // `background` y no en las `actions`.
              if (images.length > 1)
                Positioned(
                  top: 30,
                  right: 0,
                  child: GestureDetector(
                    onTap:
                        onOpenViewer == null ? null : () => onOpenViewer!(1),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                      child: JayaloNetworkImage(
                        images[1],
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 76,
                          height: 76,
                          color: amberPanel,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
