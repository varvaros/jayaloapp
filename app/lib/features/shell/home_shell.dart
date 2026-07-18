import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../core/session_state.dart';
import 'floating_nav_bar.dart';
import 'nav_destinations.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // El gate garantiza que aquí el rol ya está resuelto (spec §4).
    // El ATRÁS del sistema lo maneja BackGuard DENTRO de cada ruta del shell
    // (un PopScope aquí no funciona con predictive back; ver back_guard.dart).
    final dests = destinationsFor(roleStore.value);
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = activeIndex(dests, loc);

    // Cambiar de pestaña reemplaza la única página del Navigator anidado (no
    // la empuja encima), y Flutter no anima ese reemplazo por defecto —
    // `pageTransitionsTheme` (doctrina de movimiento, `app.dart`) solo cubre
    // pushes reales, como entrar al detalle de una solicitud, que sigue
    // dentro de la MISMA pestaña (`idx` no cambia, la key tampoco: no hay
    // doble transición). Aquí se anima el cambio de pestaña aparte, con
    // "fade through" (fundido + escala sutil) — el patrón de Material para
    // navegación entre pares, distinto al deslizado jerárquico de un push.
    return Scaffold(
      // La barra FLOTA: el cuerpo se extiende por debajo de ella. Cada
      // pantalla reserva `kNavBarReservedSpace` al final de su scroll.
      extendBody: true,
      body: AnimatedSwitcher(
        duration:
            JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        switchInCurve: JayaloMotion.emphasized,
        switchOutCurve: JayaloMotion.emphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero)
                    .animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(dests[idx].route), child: child),
      ),
      bottomNavigationBar: FloatingNavBar(
        destinations: dests,
        currentIndex: idx,
        onSelected: (i) => context.go(dests[i].route),
      ),
    );
  }
}
