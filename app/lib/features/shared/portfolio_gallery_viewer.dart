import 'package:flutter/material.dart';

import 'network_image.dart';

/// Modal galería de un TRABAJO (`provider_portfolio_items`) en la tienda
/// pública del cliente — pedido PO 2026-08-09: "Trabajos no abre" (las
/// tarjetas de `PortfolioTile` en `provider_store_screen.dart` no abrían
/// nada). Fotos a pantalla grande con swipe horizontal, indicador de
/// posición, título/descripción visibles, cierre con la X o el gesto de
/// atrás. Solo lectura — sin botones de edición: es la vista del CLIENTE.
/// "Mi negocio" (dueño) sigue abriendo su propio editor al tocar un trabajo,
/// sin cambios en esta tarea.
///
/// Mismo espíritu que `showPhotoViewer` (`shared/brand_kit.dart`, usado por
/// el detalle de producto para el zoom de fotos) pero NO se reusa ese widget
/// tal cual: le falta título/descripción y esta vista los necesita SIEMPRE
/// visibles, no solo las fotos.
Future<void> showPortfolioGallery(
  BuildContext context, {
  required List<String> images,
  required String title,
  String? description,
}) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) => PortfolioGalleryViewer(
        images: images,
        title: title,
        description: description,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ));

class PortfolioGalleryViewer extends StatefulWidget {
  const PortfolioGalleryViewer({
    super.key,
    required this.images,
    required this.title,
    this.description,
  });

  final List<String> images;
  final String title;
  final String? description;

  @override
  State<PortfolioGalleryViewer> createState() =>
      _PortfolioGalleryViewerState();
}

class _PortfolioGalleryViewerState extends State<PortfolioGalleryViewer> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (images.isEmpty)
          const Center(
              child: Icon(Icons.photo_outlined,
                  size: 64, color: Colors.white38))
        else
          PageView.builder(
            controller: _page,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Center(
              child: JayaloNetworkImage(
                images[i],
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                    color: Colors.white38),
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white24,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.close, size: 22, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Panel inferior: posición (2+ fotos) + título + descripción, sobre
        // un degradado negro para que el texto blanco se lea encima de
        // cualquier foto (incluida una clara).
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (images.length > 1) ...[
                    Text('${_index + 1} / ${images.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70)),
                    const SizedBox(height: 6),
                  ],
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  if (widget.description != null &&
                      widget.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(widget.description!,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: .85))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
