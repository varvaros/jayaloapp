/// Qué destinos ve cada rol en la barra, y cuál está activo según la ruta.
///
/// Lógica pura a propósito: nada de widgets aquí. La barra
/// (`floating_nav_bar.dart`) solo dibuja lo que este archivo decide, y así el
/// mapa de destinos de cada rol se prueba sin montar un MaterialApp.
library;

import 'package:flutter/material.dart';

import '../../core/session_state.dart';

/// Posición del botón central: 2 iconos, el centro, 2 iconos.
const kCenterIndex = 2;

class NavDestination {
  const NavDestination({
    required this.route,
    required this.icon,
    required this.label,
    this.isCenter = false,
  });

  final String route;
  final IconData icon;
  final String label;

  /// El círculo elevado del medio. Es un destino como los demás — puede estar
  /// activo y llevar su punto — solo que se dibuja distinto.
  final bool isCenter;
}

const _cliente = [
  NavDestination(
      route: '/client',
      icon: Icons.receipt_long_outlined,
      label: 'Mis solicitudes'),
  NavDestination(
      route: '/client/reputation',
      icon: Icons.workspace_premium_outlined,
      label: 'Reputación'),
  NavDestination(
      route: '/client/create',
      icon: Icons.add,
      label: 'Nueva solicitud',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
];

const _proveedor = [
  NavDestination(
      route: '/provider/offers',
      icon: Icons.local_offer_outlined,
      label: 'Mis ofertas'),
  NavDestination(
      route: '/provider/stats',
      icon: Icons.insights_outlined,
      label: 'Estadísticas'),
  NavDestination(
      route: '/provider',
      icon: Icons.search,
      label: 'Ver solicitudes',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
];

/// El gate garantiza que dentro del shell el rol ya está resuelto; el fallback
/// al cliente existe solo para que un estado transitorio no reviente la barra.
List<NavDestination> destinationsFor(RoleState role) =>
    role == RoleState.provider ? _proveedor : _cliente;

/// Si la barra debe verse en esta ubicación.
///
/// Dentro de una conversación no se navega, se conversa (como WhatsApp o
/// Messenger): la barra flotante solo tapa el campo de escribir y roba
/// ~132 px en una pantalla donde el teclado ya se come la mitad. La LISTA de
/// conversaciones (`/messages`) sí es navegación y conserva la barra; solo el
/// detalle (`/messages/<id>`) la oculta.
bool showsNavBar(String location) =>
    location == '/messages' || !location.startsWith('/messages/');

/// Índice del destino activo para una ubicación del router.
///
/// Gana el prefijo MÁS LARGO: '/provider/stats' empieza por '/provider' (el
/// botón central del proveedor), así que si ganara el primero que coincide,
/// estar en Estadísticas encendería el botón del medio.
int activeIndex(List<NavDestination> dests, String location) {
  var best = 0;
  var bestLen = -1;
  for (var i = 0; i < dests.length; i++) {
    final p = dests[i].route;
    if ((location == p || location.startsWith('$p/')) && p.length > bestLen) {
      bestLen = p.length;
      best = i;
    }
  }
  return best;
}
