/// La barra: píldora flotante con botón circular central elevado.
///
/// Solo dibuja. No sabe de rutas ni de roles — recibe los destinos que
/// `nav_destinations.dart` decidió y avisa por índice. Así se puede cambiar el
/// aspecto sin tocar la navegación.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'nav_destinations.dart';

const _pillHeight = 64.0;
const _centerSize = 56.0;

/// Alto propio de la barra SIN el inset de zona segura del sistema (el
/// `SafeArea(top: false)` interno se lo suma aparte).
///
/// Derivado de las piezas que dibuja `FloatingNavBar.build` (para que no
/// pueda desincronizarse si cambian `_pillHeight`/`_centerSize`):
///   padding superior (`_centerSize / 2`) + SizedBox (`_pillHeight +
///   _centerSize / 2`) + padding inferior (`12`)
///   = `_pillHeight + _centerSize + 12` = 64 + 56 + 12 = 132.
///
/// OJO: esta constante NO es lo que una lista del shell debe reservar. Con
/// `home_shell.dart` usando `extendBody: true`, el propio `Scaffold` ya mete
/// el alto COMPLETO de la barra (esto + el inset) dentro del `MediaQuery` que
/// ve el cuerpo — así lo hace `_BodyBuilder` en
/// `flutter/lib/src/material/scaffold.dart`:
///   `bottom = extendBody ? max(metrics.padding.bottom,
///   bottomWidgetsHeight) : metrics.padding.bottom`
/// Sumarle esta constante al padding de una lista cuenta el alto de la barra
/// DOS veces (fue el bug de C1: dejaba un hueco muerto de ~132px al final de
/// cada lista). La función [navBarReservedSpace] es la que deben usar las
/// pantallas; esta constante suelta solo sirve para contextos sin
/// `BuildContext` disponible y para el test de coherencia que la compara con
/// el alto real renderizado.
const double kNavBarReservedSpace = _pillHeight + _centerSize + 12;

/// Espacio real que debe reservar una lista del shell para que su último
/// elemento no quede tapado por la barra flotante.
///
/// Con `extendBody: true` (el caso normal dentro del shell) el `Scaffold` ya
/// infla `MediaQuery.paddingOf(context).bottom` al alto completo de la barra
/// — no hace falta (ni hay que) sumarle nada más encima. Cuando la barra
/// está OCULTA (`extendBody: false`, p. ej. dentro de un chat) ese mismo
/// valor es simplemente el inset real del dispositivo, que es justo lo que
/// hace falta ahí también.
double navBarReservedSpace(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;

  /// Índice del destino activo, o `-1` (lo que devuelve
  /// [activeIndex] cuando la ruta actual no es ninguna pestaña — ver I2) para
  /// que la barra se pinte sin nada teñido y sin ninguna etiqueta visible.
  /// No hace falta ningún caso especial: `-1` nunca coincide con ningún
  /// índice real de [destinations] ni con [kCenterIndex].
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
      onTap: onTap,
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
      onTap: onTap,
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
