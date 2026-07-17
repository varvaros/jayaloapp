import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    return Scaffold(
      body: child,
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
