import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/geo.dart';

/// Unico boton de "abrir en el mapa" FUERA del chat (Task 11). La burbuja del
/// chat (`features/chat/widgets/bubbles.dart`) ya tiene el suyo propio, con su
/// propio manejo de error — a proposito NO se unifica con este: son contextos
/// visuales distintos (una burbuja vs. una tarjeta de pantalla completa).
///
/// `externalApplication` es a proposito: aterriza en la app de Google Maps o
/// Waze del telefono, ya lista para navegar, en vez de un WebView dentro de
/// Jayalo.
class OpenInMapsButton extends StatelessWidget {
  const OpenInMapsButton({
    super.key,
    required this.lat,
    required this.lng,
    this.label = 'Abrir en el mapa',
  });

  final double lat;
  final double lng;
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => launchUrl(
          Uri.parse(mapsLinkFor(lat, lng)),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: Text(label),
      );
}
