import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/session_state.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // El gate garantiza que aquí el rol ya está resuelto (spec §4);
    // no hace falta re-consultar profiles como antes.
    // El ATRÁS del sistema lo maneja BackGuard DENTRO de cada ruta del shell
    // (un PopScope aquí no funciona con predictive back; ver back_guard.dart).
    final provider = roleStore.value == RoleState.provider;
    final loc = GoRouterState.of(context).matchedLocation;
    final tabs = provider
        ? const [
            ('/provider', Icons.inbox_outlined, 'Solicitudes'),
            ('/provider/offers', Icons.local_offer_outlined, 'Mis ofertas'),
            ('/messages', Icons.chat_bubble_outline, 'Mensajes'),
            ('/settings', Icons.settings_outlined, 'Ajustes'),
          ]
        : const [
            ('/client', Icons.receipt_long_outlined, 'Mis solicitudes'),
            ('/client/create', Icons.add_circle_outline, 'Crear'),
            ('/messages', Icons.chat_bubble_outline, 'Mensajes'),
            ('/settings', Icons.settings_outlined, 'Ajustes'),
          ];
    // Match más específico primero (evita que '/client' capture '/client/create').
    var idx = 0;
    var bestLen = -1;
    for (var i = 0; i < tabs.length; i++) {
      final p = tabs[i].$1;
      if (loc == p || loc.startsWith('$p/')) {
        if (p.length > bestLen) {
          bestLen = p.length;
          idx = i;
        }
      }
    }
    // Cambiar de pestaña reemplaza la única página del Navigator anidado (no
    // la empuja encima), y Flutter no anima ese reemplazo por defecto —
    // `pageTransitionsTheme` (doctrina de movimiento, `app.dart`) solo cubre
    // pushes reales, como entrar al detalle de una solicitud, que sigue
    // dentro de la MISMA pestaña (`idx` no cambia, la key tampoco: no hay
    // doble transición). Aquí se anima el cambio de pestaña aparte, con
    // "fade through" (fundido + escala sutil) — el patrón de Material para
    // navegación entre pares, distinto al deslizado jerárquico de un push.
    return Scaffold(
      body: AnimatedSwitcher(
        duration:
            JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        switchInCurve: JayaloMotion.enter,
        switchOutCurve: JayaloMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: JayaloMotion.pressedScale, end: 1)
                .animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(tabs[idx].$1), child: child),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(tabs[i].$1),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
