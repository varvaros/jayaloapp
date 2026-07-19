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

// Mapa de la iteración 2 (decisión del PO, orden vinculante — tabla en
// `docs/superpowers/plans/2026-07-18-navbar-iteracion-2.md` §0.1). Los dos
// roles ahora COMPARTEN el centro (`/client/create`): un proveedor también
// puede solicitar. `/settings` y `/provider/stats` salieron del mapa — sus
// rutas siguen vivas, se llega por el menú del avatar en el AppBar.
const _cliente = [
  // "Solicitudes" a secas (PO 2026-07-19; antes "Mis solicitudes" — largo
  // para la barra).
  NavDestination(
      route: '/client',
      icon: Icons.receipt_long_outlined,
      label: 'Solicitudes'),
  NavDestination(
      route: '/catalog',
      icon: Icons.storefront_outlined,
      label: 'Catálogo'),
  NavDestination(
      route: '/client/create',
      icon: Icons.add,
      label: 'Nueva solicitud',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/client/reputation',
      icon: Icons.workspace_premium_outlined,
      label: 'Reputación'),
];

const _proveedor = [
  // Puesto 0, razón del PO: "la primera ventana de interés es las
  // solicitudes sin responder que tenga de su rubro". Coincide con su
  // pantalla de aterrizaje (`redirectTarget` → `/provider`).
  NavDestination(
      route: '/provider',
      icon: Icons.inbox_outlined,
      label: 'Solicitudes'),
  NavDestination(
      route: '/provider/offers',
      icon: Icons.local_offer_outlined,
      label: 'Mis ofertas'),
  // Mismo centro que el cliente: "habíamos olvidado que un proveedor
  // también puede solicitar". Ya no es 🔍 "Ver solicitudes".
  NavDestination(
      route: '/client/create',
      icon: Icons.add,
      label: 'Crear solicitud',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/provider/business',
      icon: Icons.store_outlined,
      label: 'Mi negocio'),
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

/// Rutas que siguen vivas dentro del shell (se llega por el menú del avatar)
/// pero que la iteración 2 sacó del mapa de la barra. Sin esta lista,
/// `/provider/stats` heredaría el puesto 0 ("Solicitudes") solo porque su
/// URL empieza por `/provider` — un accidente de nomenclatura, no una
/// relación real de bandeja→detalle como la de `/provider/request/:id`.
/// `activeIndex` debe tratarlas como "ninguna pestaña" (-1), igual que
/// `/notifications` o `/settings` (estas dos ya dan -1 solas: ningún
/// destino restante comparte su prefijo).
const _excludedFromNav = {'/provider/stats'};

/// Índice del destino activo para una ubicación del router, o `-1` si
/// ninguno coincide (p. ej. `/notifications`: está dentro del shell —
/// `showsNavBar` la deja mostrar la barra— pero no es ninguna de sus 5
/// pestañas). Encender el índice 0 en ese caso mentía: la barra marcaba
/// "Solicitudes" como activa estando en Notificaciones. Quien pinta la
/// barra ([FloatingNavBar]) debe tratar `-1` como "ningún destino
/// seleccionado", no como "el primero".
///
/// Gana el prefijo MÁS LARGO. Dos casos por los que importa:
/// - '/provider' (puesto 0, "Solicitudes") es prefijo de '/provider/offers'
///   y '/provider/business' — sin la regla del más largo, esas rutas
///   encenderían el puesto 0 en vez del suyo propio.
/// - '/client' (puesto 0 del cliente) es prefijo de '/client/create' (el
///   centro, compartido con el proveedor) — sin la regla del más largo,
///   crear una solicitud encendería "Solicitudes" (cliente) en vez del centro.
int activeIndex(List<NavDestination> dests, String location) {
  if (_excludedFromNav.contains(location)) return -1;
  var best = -1;
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
