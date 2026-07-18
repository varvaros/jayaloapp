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
    final showNavBar = showsNavBar(loc);

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
      // pantalla reserva `kNavBarReservedSpace` al final de su scroll. Dentro
      // de una conversación la barra se oculta (decisión PO: ahí no se
      // navega, se conversa) y `extendBody` deja de tener sentido — sin él el
      // cuerpo ocupa el alto normal y el campo de escribir del chat queda
      // donde debe, sin el hueco que dejaría el espacio reservado para una
      // barra que ya no está.
      extendBody: showNavBar,
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
        // `idx` puede ser -1 (I2: ninguna pestaña coincide, p. ej.
        // `/notifications`) — `dests[idx]` reventaría con RangeError. Ahí
        // basta con la propia ubicación como key: sigue siendo estable y
        // distinta de cualquier pestaña real.
        child: KeyedSubtree(
            key: ValueKey(idx >= 0 ? dests[idx].route : loc), child: child),
      ),
      bottomNavigationBar: showNavBar
          ? FloatingNavBar(
              destinations: dests,
              currentIndex: idx,
              onSelected: (i) => context.go(dests[i].route),
            )
          : null,
    );
  }
}
