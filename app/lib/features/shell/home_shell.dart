import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/session_state.dart';
import '../../domain/back_intent.dart';
import 'home_scroll.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  void _handleBack(BuildContext context, String loc, String home) {
    final c = homeScrollController;
    final atTop = !c.hasClients || c.offset <= 8;
    switch (backActionFor(location: loc, homePath: home, atTop: atTop)) {
      case BackAction.goHome:
        context.go(home);
      case BackAction.scrollTop:
        c.animateTo(0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic);
      case BackAction.confirmExit:
        _confirmExit(context);
    }
  }

  Future<void> _confirmExit(BuildContext context) async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir de Jayalo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Quedarme')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (salir == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // El gate garantiza que aquí el rol ya está resuelto (spec §4);
    // no hace falta re-consultar profiles como antes.
    final provider = roleStore.value == RoleState.provider;
    final loc = GoRouterState.of(context).matchedLocation;
    final home = homePathFor(provider: provider);
    final tabs = provider
        ? const [
            ('/provider', Icons.inbox_outlined, 'Solicitudes'),
            ('/provider/offers', Icons.local_offer_outlined, 'Mis ofertas'),
            ('/settings', Icons.settings_outlined, 'Ajustes'),
          ]
        : const [
            ('/client', Icons.receipt_long_outlined, 'Mis solicitudes'),
            ('/client/create', Icons.add_circle_outline, 'Crear'),
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
    // El ATRÁS del sistema nunca minimiza: home → tope → confirmar salida
    // (backActionFor). Con go() no hay stack que popear, así que se intercepta.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context, loc, home);
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (i) => context.go(tabs[i].$1),
          destinations: [
            for (final t in tabs)
              NavigationDestination(icon: Icon(t.$2), label: t.$3),
          ],
        ),
      ),
    );
  }
}
