/// La barra: píldora flotante con botón circular central elevado.
///
/// Solo dibuja. No sabe de rutas ni de roles — recibe los destinos que
/// `nav_destinations.dart` decidió y avisa por índice. Así se puede cambiar el
/// aspecto sin tocar la navegación.
library;

import 'package:flutter/material.dart';

import '../../core/center_action.dart';
import '../../core/motion.dart';
import 'center_arc_menu.dart';
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
    this.badges = const {},
    this.centerButtonKey,
    this.centerIconOverride,
    this.centerLabelOverride,
    this.centerMenuItems,
  });

  final List<NavDestination> destinations;

  /// Contador de badge por ruta de destino (hoy solo "Solicitudes"). 0 o
  /// ausente = sin badge. La barra no sabe qué significa: solo lo pinta.
  final Map<String, int> badges;

  /// Índice del destino activo, o `-1` (lo que devuelve
  /// [activeIndex] cuando la ruta actual no es ninguna pestaña — ver I2) para
  /// que la barra se pinte sin nada teñido y sin ninguna etiqueta visible.
  /// No hace falta ningún caso especial: `-1` nunca coincide con ningún
  /// índice real de [destinations] ni con [kCenterIndex].
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Key opcional para anclar una guía de onboarding sobre el botón central
  /// (no cambia el aspecto: solo permite medir su rect). Ver home_shell.
  final GlobalKey? centerButtonKey;

  /// Ícono y etiqueta con los que se pinta el centro cuando la pantalla al
  /// frente se APROPIÓ del botón (ver `core/center_action.dart`). `null` = los
  /// del destino, que es el caso en todas las pantallas menos crear solicitud.
  /// La barra sigue sin saber QUÉ hace el botón: solo lo pinta y avisa por
  /// [onSelected], igual que hace con los badges.
  final IconData? centerIconOverride;
  final String? centerLabelOverride;

  /// Destinos que el centro DESPLIEGA en arco al tocarlo, o `null` para el
  /// comportamiento de siempre (un toque = un `onSelected`). La barra sigue sin
  /// saber qué hace cada ítem: solo lo pinta y lo avisa, igual que con los
  /// badges. Quien lo dibuja es `center_arc_menu.dart`.
  final List<CenterMenuItem>? centerMenuItems;

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
                                  badge: badges[destinations[i].route] ?? 0,
                                  onTap: () => onSelected(i),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: _pillHeight - _centerSize / 2 - _centerButtonLift,
                child: KeyedSubtree(
                  key: centerButtonKey,
                  child: _CenterButton(
                    destination: destinations[kCenterIndex],
                    active: currentIndex == kCenterIndex,
                    iconOverride: centerIconOverride,
                    labelOverride: centerLabelOverride,
                    menuItems: centerMenuItems,
                    onTap: () => onSelected(kCenterIndex),
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
      // ⚠️ Asume que el botón central está centrado en el ancho de la barra:
      // hoy es el índice del medio de 5 y su `Positioned` no lleva `left`/
      // `right`, así que coincide. Si algún día el layout deja de ser
      // simétrico, la muesca se pintaría aquí mientras el botón está en otro
      // punto — un desfase visual SILENCIOSO (ningún test ni `analyze` lo
      // detecta, porque nada ata este valor a la posición real del botón).
      // En ese caso hay que pasar el centro real en vez de asumirlo.
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
    this.badge = 0,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  /// Conteo del badge (0 = sin badge). Se dibuja como una píldora roja pequeña
  /// sobre el ícono, estilo notificación (99+ como tope).
  final int badge;

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
            // El ícono con su badge encima (Stack sin recorte para que la
            // píldora roja pueda sobresalir por la esquina superior derecha).
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(destination.icon, color: color, size: 24),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.primaryContainer, width: 1.5),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onError,
                          fontSize: 9.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              // `Duration.zero` es el caso patológico de `AnimatedSize`
              // (distinto de `AnimatedSwitcher`/`SizeTransition`, que sí lo
              // toleran bien — ver `home_shell.dart`): con duration cero, el
              // `RenderAnimatedSize` completa su animación DENTRO de su
              // propio `performLayout`, y notificar a sus listeners desde
              // ahí dispara un `markNeedsLayout` sobre sí mismo a mitad de
              // layout → "A RenderAnimatedSize was mutated in its own
              // performLayout implementation" en CADA cambio de destino
              // activo con "reducir animaciones" activado (reproducido en
              // `floating_nav_bar_test.dart`). 1ms es imperceptible para el
              // usuario — cumple la doctrina de "sin movimiento" tanto como
              // cero — pero deja al menos un frame entre el inicio y el fin
              // de la animación, evitando la completitud síncrona que
              // dispara el bug.
              duration:
                  reduced ? const Duration(milliseconds: 1) : JayaloMotion.base,
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

/// El círculo elevado. Cuando está activo agrega su etiqueta justo debajo del
/// círculo — dentro del área de la píldora, no debajo de ella — sin mover el
/// círculo ni un píxel: la etiqueta se posiciona con un `Stack` +
/// `Positioned` que no participa en el tamaño del widget (a diferencia de un
/// `Column`, que habría empujado el círculo hacia arriba al aparecer el
/// texto, desalineándolo de la muesca fija tallada en la píldora — ese fue
/// C1).
class _CenterButton extends StatefulWidget {
  const _CenterButton({
    required this.destination,
    required this.active,
    required this.onTap,
    this.iconOverride,
    this.labelOverride,
    this.menuItems,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  /// Ver [FloatingNavBar.centerIconOverride]. `null` = los del destino.
  final IconData? iconOverride;
  final String? labelOverride;

  /// No-nulo = tocar el botón DESPLIEGA en vez de avisar por [onTap].
  final List<CenterMenuItem>? menuItems;

  @override
  State<_CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<_CenterButton>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _anim;
  late final Animation<double> _curved;

  bool get _open => _portal.isShowing;

  @override
  void initState() {
    super.initState();
    // Construir aquí, no en la declaración del campo: con `late final ...
    // = AnimationController(...)` el inicializador es PEREZOSO — si la
    // pantalla nunca abre el menú, `_anim`/`_curved` no se tocan hasta que
    // `dispose()` lee `_anim` por primera vez, y para entonces el elemento ya
    // está desactivado: `createTicker` revienta con "Looking up a
    // deactivated widget's ancestor is unsafe" (reventaba prácticamente CADA
    // test que renderiza `FloatingNavBar`, abra o no el arco). Construir
    // ansiosamente aquí garantiza que ya existan cuando `dispose()` los pida.
    _anim = AnimationController(
      vsync: this,
      duration: JayaloMotion.base,
      reverseDuration: JayaloMotion.base,
    );
    _curved = CurvedAnimation(
      parent: _anim,
      curve: JayaloMotion.enter,
      reverseCurve: JayaloMotion.exit,
    );
  }

  @override
  void didUpdateWidget(_CenterButton old) {
    super.didUpdateWidget(old);
    // La pantalla soltó el botón (envió la oferta, salió) con el arco abierto:
    // cerrarlo sin animación, porque lo que lo justificaba ya no existe.
    if (widget.menuItems == null && _open) {
      _anim.value = 0;
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    final items = widget.menuItems;
    if (items == null || items.isEmpty) {
      widget.onTap();
      return;
    }
    if (_open) {
      _close();
    } else {
      JayaloHaptics.tabChange();
      _portal.show();
      if (JayaloMotion.reduced(context)) {
        _anim.value = 1;
      } else {
        _anim.forward(from: 0);
      }
      setState(() {});
    }
  }

  void _close() {
    if (!_open) return;
    if (JayaloMotion.reduced(context)) {
      _anim.value = 0;
      _portal.hide();
      setState(() {});
      return;
    }
    _anim.reverse().whenComplete(() {
      if (!mounted) return;
      _portal.hide();
      setState(() {});
    });
    setState(() {});
  }

  void _pick(CenterMenuItem item) {
    _close();
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // PO 2026-07-20: el círculo central (+) usa el violeta del header
    // (`primary`) en AMBOS temas — antes en claro era `onPrimaryContainer` (el
    // violeta oscuro). En oscuro `primary` ya era el azul dPrimary, sin cambio.
    // La etiqueta activa se queda en `onPrimaryContainer` (violeta oscuro),
    // legible sobre la píldora lila igual que las etiquetas laterales — un
    // violeta primario pequeño sobre lila no llegaría al 4.5:1 de texto.
    final circleColor = cs.primary;
    final label = widget.labelOverride ?? widget.destination.label;
    return Semantics(
      label: label,
      button: true,
      selected: widget.active,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => BackButtonListener(
          // El arco NO es una ruta: sin esto el atrás del sistema saldría de
          // la pantalla dejándolo abierto. Los hijos de `OverlayPortal` siguen
          // en el árbol lógico, así que este listener los alcanza. NO se toca
          // `BackGuard` ni se añade un `PopScope`: con predictive back ahí hay
          // un gotcha conocido (ver `back_guard.dart`).
          onBackButtonPressed: () async {
            if (!_open) return false;
            _close();
            return true;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: Semantics(
                    label: 'Cerrar menú',
                    button: true,
                    child: FadeTransition(
                      opacity: _curved,
                      child: ColoredBox(
                        color:
                            Theme.of(context).colorScheme.scrim.withValues(alpha: .32),
                      ),
                    ),
                  ),
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.center,
                followerAnchor: Alignment.center,
                child: CenterArcMenu(
                  animation: _curved,
                  items: widget.menuItems ?? const [],
                  centerRadius: _centerSize / 2,
                  onPick: _pick,
                ),
              ),
            ],
          ),
        ),
        // Stack en vez de Column: el círculo (`Material`, único hijo NO
        // posicionado) es el que fija el tamaño del widget. La etiqueta va en
        // un `Positioned` — no cuenta para el tamaño ni empuja al círculo —
        // así que su centro queda idéntico esté activo o no (regresión C1: ver
        // test "el círculo central no se sale de la muesca al activarse").
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            CompositedTransformTarget(
              link: _link,
              child: Material(
                color: circleColor,
                shape: const CircleBorder(),
                elevation: 6,
                shadowColor: cs.shadow.withValues(alpha: .35),
                child: InkWell(
                  onTap: _toggle,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: _centerSize,
                    height: _centerSize,
                    child: AnimatedRotation(
                      turns: _open ? .125 : 0,
                      duration: JayaloMotion.reduced(context)
                          ? Duration.zero
                          : JayaloMotion.base,
                      curve: JayaloMotion.enter,
                      child: Icon(
                          _open
                              ? Icons.close
                              : (widget.iconOverride ?? widget.destination.icon),
                          color: cs.onPrimary,
                          size: 28),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.active)
              Positioned(
                top: _centerSize + 2,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
