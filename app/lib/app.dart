import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'core/motion.dart';

/// Doctrina de movimiento (decisión PO 2026-07-18): TODA transición de
/// pantalla debe sentirse premium — deslizado suave, nunca el zoom/fade
/// genérico de Android por defecto. Un solo builder aquí cubre las ~15 rutas
/// de `core/router.dart` sin tocarlas una por una.
///
/// Eje HORIZONTAL (3ª directriz del PO, revisión visual en device
/// 2026-07-19: "el deslizamiento de las secciones que sea a la derecha";
/// sustituye al eje vertical del 07-18): la sección entrante LLEGA desde la
/// derecha (8% del ancho) con fade in, y la saliente se guarda hacia la
/// izquierda (4%) atenuándose. Al volver atrás, la reversa deshace el
/// gesto — la de arriba se va por la derecha. Curva `easeInOutCubic` en
/// ambas: el movimiento arranca y termina suave, sin tirones.
///
/// `secondaryAnimation` (la saliente) solo corre al EMPUJAR una ruta encima;
/// al volver, la de abajo baja de vuelta a su sitio.
class _JayaloPageTransitionsBuilder extends PageTransitionsBuilder {
  const _JayaloPageTransitionsBuilder();

  // PO 2026-07-19 (3ª pasada): "el deslizamiento de la pantalla debe ser con
  // un frenado de 2 segundos". Con la curva `brake` (easeOutQuint) casi todo
  // el recorrido sucede en los primeros ~400ms — lo que se percibe rápido —
  // y el resto de los 2s es la frenada: el último tramo aterriza despacio.
  // `MaterialRouteTransitionMixin.transitionDuration` lee este getter del
  // builder del theme (verificado en el código de Flutter 3.44), así que
  // esto aplica a TODAS las rutas MaterialPage sin tocarlas una a una.
  @override
  Duration get transitionDuration => JayaloMotion.screenSlide;

  // La VUELTA es corta (PO 2026-07-19, misma sesión: "al dar atrás se siente
  // muy lenta la salida"): los 2s con `brake` invertida dejaban ~1.5s de
  // pantalla quieta antes de moverse. Al volver no hay nada que saborear —
  // salida en `page` (300ms).
  @override
  Duration get reverseTransitionDuration => JayaloMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Accesibilidad: con "reducir animaciones" la pantalla cambia sin
    // movimiento (el sistema ya acorta la ruta; no se pelea con él).
    if (JayaloMotion.reduced(context)) return child;
    // A la ida, curva `brake` (frenada larga). A la VUELTA, `exit`
    // (easeInCubic): el movimiento arranca al instante — con `brake` invertida
    // la reversa se quedaba quieta casi todo el recorrido y se sentía lenta.
    final incoming = CurvedAnimation(
        parent: animation,
        curve: JayaloMotion.brake,
        reverseCurve: JayaloMotion.exit);
    final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: JayaloMotion.brake,
        reverseCurve: JayaloMotion.exit);
    return SlideTransition(
      // Llega desde la derecha hasta su sitio.
      position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero)
          .animate(incoming),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          // La anterior se guarda hacia la izquierda mientras se atenúa.
          position: Tween<Offset>(
                  begin: Offset.zero, end: const Offset(-.04, 0))
              .animate(outgoing),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: .4).animate(outgoing),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Física de scroll con frenado largo (PO 2026-07-19, 4ª pasada: "el scroll
/// de la pantalla ponle 2 segundos de frenado").
///
/// Solo cambia la FRICCIÓN del fling; el arrastre con el dedo, el rebote y el
/// clamp de los bordes siguen siendo los de Material/Android. Se reusa la
/// simulación de Flutter (`ClampingScrollSimulation`) en vez de escribir una
/// propia: la única diferencia con el default es el parámetro `friction`
/// ([JayaloMotion.scrollFriction], que documenta la aritmética de la
/// duración). Cuando la posición está FUERA de rango, `super` devuelve un
/// `ScrollSpringSimulation` (el muelle que devuelve el contenido al borde) —
/// ese caso se deja intacto: no es un fling, es una corrección de límite.
class JayaloScrollPhysics extends ClampingScrollPhysics {
  const JayaloScrollPhysics({super.parent});

  @override
  JayaloScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      JayaloScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final sim = super.createBallisticSimulation(position, velocity);
    if (sim is! ClampingScrollSimulation) return sim;
    return ClampingScrollSimulation(
      position: sim.position,
      velocity: sim.velocity,
      friction: JayaloMotion.scrollFriction,
      tolerance: toleranceFor(position),
    );
  }
}

/// Aplica [JayaloScrollPhysics] a TODA la app de una vez (listas, sheets,
/// scrollables anidados) sin tocar pantalla por pantalla. Un widget que pase
/// su propia `physics` explícita sigue mandando — p. ej. el
/// `NeverScrollableScrollPhysics` de `SkeletonList`.
class JayaloScrollBehavior extends MaterialScrollBehavior {
  const JayaloScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const JayaloScrollPhysics();
}

/// Los colores salen de `core/brand.dart` (tokens portados de la web) para que
/// app y jayalo.com se vean como la misma marca.
ThemeData jayaloTheme(Brightness b) {
  final cs = jayaloScheme(b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.standard,
    // "F1 · Rellenos suaves" (elegida por el PO): la receta única de campo de
    // texto — fondo gris suave, radius 12, sin borde. Los TextField que no
    // pasan decoración explícita la heredan de aquí.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      // Solo Android: es la única plataforma que empaqueta la app (iOS
      // descartado, ver memoria del proyecto).
      TargetPlatform.android: _JayaloPageTransitionsBuilder(),
    }),
  );
}

class JayaloApp extends StatelessWidget {
  const JayaloApp({super.key, required this.router});
  final GoRouter router;
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Jayalo',
        theme: jayaloTheme(Brightness.light),
        darkTheme: jayaloTheme(Brightness.dark),
        // FIJADO A CLARO (decisión PO 2026-07-19): el rediseño cálido (arena,
        // headers violeta) es solo para modo claro; el oscuro cálido (violeta)
        // sigue pendiente de diseño. Hasta entonces la app se ve SIEMPRE en el
        // tema claro, sin importar el modo del sistema — así el rediseño se ve
        // en todos los teléfonos. Quitar este `themeMode` reactiva el tema
        // oscuro azul viejo.
        themeMode: ThemeMode.light,
        scrollBehavior: const JayaloScrollBehavior(),
        routerConfig: router,
      );
}
