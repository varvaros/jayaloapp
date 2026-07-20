import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'core/motion.dart';

/// SIN animación en los cambios de sección (PO 2026-07-19, 4ª pasada —
/// REVIERTE el deslizado de las directrices 07-18/07-19 anteriores):
/// "veo que WhatsApp, Spotify no tienen loader en cada sección, solo le das
/// clic y pasa… vamos a eliminar la animación de cambio de sección". El
/// deslizado horizontal con frenado de 2s quedó descartado — un solo builder
/// aquí cubre las ~15 rutas de `core/router.dart` sin tocarlas una por una.
///
/// Las 4 excepciones pedidas por el PO (Crear solicitud, Notificaciones, Ver
/// ofertas, menú de Avatar) NO pasan por este builder — cada una es un
/// `CustomTransitionPage`/`showModalBottomSheet`/`showGeneralDialog` con su
/// propia animación, independiente del `PageTransitionsTheme`. Ver
/// `core/router.dart` (`/client/create`, `/notifications`),
/// `client/request_status_screen.dart` (`_showOffers`) y
/// `shared/profile_avatar_button.dart` (`openProfileMenu`).
class _JayaloPageTransitionsBuilder extends PageTransitionsBuilder {
  const _JayaloPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
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
