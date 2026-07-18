/// La barra: píldora flotante con botón circular central elevado.
///
/// Solo dibuja. No sabe de rutas ni de roles — recibe los destinos que
/// `nav_destinations.dart` decidió y avisa por índice. Así se puede cambiar el
/// aspecto sin tocar la navegación.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'nav_destinations.dart';

/// Alto que una barra FLOTANTE no reserva por sí sola. Toda lista del shell
/// debe añadir este padding al final o su último elemento queda debajo de la
/// barra, invisible. Ni `analyze` ni los tests lo detectan: solo se ve
/// recorriendo la lista hasta abajo en un teléfono.
const double kNavBarReservedSpace = 96;

const _pillHeight = 64.0;
const _centerSize = 56.0;

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        // El botón central sobresale por arriba: el padding superior le deja
        // sitio para que no lo recorte el Scaffold.
        padding: const EdgeInsets.fromLTRB(16, _centerSize / 2, 16, 12),
        child: SizedBox(
          height: _pillHeight + _centerSize / 2,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: _pillHeight,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(_pillHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: .10),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: destinations[i].isCenter
                            // Hueco: el círculo se dibuja encima, en el Stack.
                            ? const SizedBox.shrink()
                            : _SideItem(
                                destination: destinations[i],
                                active: i == currentIndex,
                                onTap: () => onSelected(i),
                              ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: _pillHeight - _centerSize / 2 - 4,
                child: _CenterButton(
                  destination: destinations[kCenterIndex],
                  active: currentIndex == kCenterIndex,
                  onTap: () => onSelected(kCenterIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icono lateral. El texto aparece SOLO cuando está activo (decisión PO): la
/// barra queda limpia pero el usuario siempre puede leer dónde está parado.
class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    final reduced = JayaloMotion.reduced(context);
    return Semantics(
      label: destination.label,
      button: true,
      selected: active,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, color: color, size: 24),
            AnimatedSize(
              duration: reduced ? Duration.zero : JayaloMotion.base,
              curve: JayaloMotion.enter,
              child: active
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    )
                  : const SizedBox(width: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// El círculo elevado. Lleva su texto debajo de la píldora cuando está activo,
/// para no meter texto dentro del círculo.
class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: destination.label,
      button: true,
      selected: active,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: cs.primary,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: cs.shadow.withValues(alpha: .35),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: _centerSize,
                height: _centerSize,
                child: Icon(destination.icon, color: cs.onPrimary, size: 28),
              ),
            ),
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                destination.label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }
}
