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

/// Cuánto sube el botón central por encima del centro vertical de su propio
/// diámetro respecto al borde superior de la píldora — la misma cifra usada
/// por el `Positioned(bottom: ...)` de [_CenterButton] más abajo (repetida
/// ahí porque ese cálculo se expresa "desde abajo" del stack, no "desde
/// arriba" de la píldora; los dos deben moverse juntos si cambia el diseño).
const _centerButtonLift = 4.0;

/// Margen entre el aro de la muesca y el borde real del botón (spec §3):
/// dibuja un halo visible del color de la píldora alrededor del círculo, en
/// vez de que la muesca calce exactamente con su silueta.
const _notchMargin = 6.0;
const _notchRadius = _centerSize / 2 + _notchMargin;

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
              SizedBox(
                height: _pillHeight,
                child: CustomPaint(
                  // Iteración 2 (spec §3): la píldora deja de ser un
                  // `Container` con `BoxDecoration` — ahora se dibuja con un
                  // `CustomPaint` cuyo path incluye la muesca cóncava que
                  // abraza al botón central (referencia conceptual:
                  // `CircularNotchedRectangle` de Material, usada tal cual
                  // dentro de `buildPillNotchPath`). El color sigue viniendo
                  // de los mismos tokens que la iteración 1 (spec §2): nada
                  // de eso cambió, solo CÓMO se pinta.
                  painter: PillNotchPainter(
                    color: cs.primaryContainer,
                    shadowColor: cs.shadow.withValues(alpha: .10),
                    notchCenterY: _centerButtonLift,
                    notchRadius: _notchRadius,
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
              ),
              Positioned(
                bottom: _pillHeight - _centerSize / 2 - _centerButtonLift,
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

/// Camino de la píldora con la muesca cóncava que abraza al botón central
/// (spec §3, iteración 2).
///
/// Se construye en dos pasos, ambos con API pública de `dart:ui`/Material:
/// 1. Un estadio (rectángulo con las puntas totalmente redondeadas, radio =
///    alto/2) — la misma silueta que antes dibujaba el `BoxDecoration`.
/// 2. `CircularNotchedRectangle` (la clase que usa `BottomAppBar` para
///    tallarle sitio a un `FloatingActionButton`) tallando un mordisco
///    alrededor de un círculo "invitado" centrado en `notchCenterX`.
///
/// Se intersectan ambos paths: el resultado es el estadio con la muesca
/// tallada donde se superponen (el centro superior), sin tocar sus puntas
/// redondeadas (la muesca no llega tan lejos). No hace falta reimplementar
/// a mano la curva de Bézier de la muesca — es exactamente la fórmula que ya
/// usa Material para el mismo propósito.
Path buildPillNotchPath({
  required Size size,
  required double notchCenterX,
  required double notchCenterY,
  required double notchRadius,
}) {
  final host = Offset.zero & size;
  final stadium = Path()
    ..addRRect(RRect.fromRectAndRadius(host, Radius.circular(size.height / 2)));

  if (notchRadius <= 0) return stadium;

  final guest = Rect.fromCircle(
    center: Offset(notchCenterX, notchCenterY),
    radius: notchRadius,
  );
  final notched = const CircularNotchedRectangle().getOuterPath(host, guest);
  return Path.combine(PathOperation.intersect, stadium, notched);
}

/// Pinta la píldora (fondo + sombra) siguiendo el path con la muesca —
/// sustituye al `Container`/`BoxDecoration` de la iteración 1. La sombra usa
/// la MISMA receta que antes (blur 20, offset (0,6), alpha .10 sobre
/// `cs.shadow`) pero trazando el path con la muesca en vez de un rectángulo,
/// tal como pide el spec §3 ("La sombra debe seguir el path de la muesca, no
/// un rectángulo").
class PillNotchPainter extends CustomPainter {
  const PillNotchPainter({
    required this.color,
    required this.shadowColor,
    required this.notchCenterY,
    required this.notchRadius,
  });

  final Color color;
  final Color shadowColor;
  final double notchCenterY;
  final double notchRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildPillNotchPath(
      size: size,
      notchCenterX: size.width / 2,
      notchCenterY: notchCenterY,
      notchRadius: notchRadius,
    );

    canvas.save();
    canvas.translate(0, 6);
    canvas.drawPath(
      path,
      // Misma receta que la BoxShadow de la iteración 1 (blur 20, alpha
      // .10): `BoxShadow.toPaint()` ya sabe convertir blurRadius a la sigma
      // del MaskFilter, no hay que reimplementar esa conversión a mano.
      BoxShadow(color: shadowColor, blurRadius: 20).toPaint(),
    );
    canvas.restore();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant PillNotchPainter oldDelegate) =>
      color != oldDelegate.color ||
      shadowColor != oldDelegate.shadowColor ||
      notchCenterY != oldDelegate.notchCenterY ||
      notchRadius != oldDelegate.notchRadius;
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
    // Iteración 2 (spec §2): sobre la píldora teñida (`primaryContainer`) el
    // activo va con el color pleno (`onPrimaryContainer` — accentFg/claro,
    // dForeground/oscuro) y el inactivo es el MISMO tono atenuado, no otro
    // color. En oscuro el spec da un token distinto para el inactivo
    // (dMutedFg, ya poblado en `onSurfaceVariant`) en vez de una opacidad —
    // se respeta tal cual dice la tabla; la opacidad de 0.6 en claro se
    // eligió para llegar al mínimo WCAG 3:1 (ver test de contraste).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? cs.onPrimaryContainer
        : (isDark ? cs.onSurfaceVariant : cs.onPrimaryContainer.withValues(alpha: .6));
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
    // Iteración 2 (spec §2): el círculo NO usa el mismo rol en los dos temas
    // — en claro es `onPrimaryContainer` (accentFg, el violeta oscuro de la
    // marca) y en oscuro es `primary` (dPrimary, el azul: la web tampoco usa
    // violeta como primario en oscuro, ver core/brand.dart). No hay un único
    // rol de ColorScheme que cubra ambos casos, así que se resuelve por
    // brillo — mismo patrón que ya usa brand.dart para dark vs. light.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final circleColor = isDark ? cs.primary : cs.onPrimaryContainer;
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
            color: circleColor,
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
                    color: circleColor),
              ),
            ),
        ],
      ),
    );
  }
}
