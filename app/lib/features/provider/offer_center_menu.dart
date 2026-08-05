/// Qué destinos ofrece el botón central mientras se redacta una oferta, y
/// cuáles están vivos.
///
/// Función libre y sin `BuildContext` a propósito: es la única parte de esta
/// feature con reglas propias, y así se prueba sin montar una pantalla que
/// necesita red y sesión.
library;

import 'package:flutter/material.dart';

import '../../core/center_action.dart';

/// Los cuatro son atajos a botones que YA existen en el formulario; aquí no se
/// inventa ningún camino nuevo.
///
/// Con el álbum lleno se APAGAN los tres que solo sirven para traer fotos, pero
/// **"Mi tienda" sigue vivo**: además de fotos autocompleta precio, color,
/// envío, instalación y estado, y eso vale igual con las cinco fotos puestas.
///
/// No se esconde ninguno: un arco que pasa de cuatro satélites a uno se lee
/// como un fallo. (Diverge a propósito del formulario, donde los botones
/// desaparecen al llegar al tope.)
List<CenterMenuItem> buildOfferCenterMenu({
  required bool busy,
  required int photoCount,
  required int maxPhotos,
  required VoidCallback onCamera,
  required VoidCallback onGallery,
  required VoidCallback onStore,
  required VoidCallback onPortfolio,
}) {
  final haySitio = photoCount < maxPhotos;
  return [
    CenterMenuItem(
        icon: Icons.photo_camera_outlined,
        label: 'Cámara',
        onTap: onCamera,
        enabled: !busy && haySitio),
    CenterMenuItem(
        icon: Icons.photo_library_outlined,
        label: 'Galería',
        onTap: onGallery,
        enabled: !busy && haySitio),
    CenterMenuItem(
        icon: Icons.storefront_outlined,
        label: 'Mi tienda',
        onTap: onStore,
        enabled: !busy),
    CenterMenuItem(
        icon: Icons.collections_bookmark_outlined,
        label: 'Trabajos',
        onTap: onPortfolio,
        enabled: !busy && haySitio),
  ];
}
