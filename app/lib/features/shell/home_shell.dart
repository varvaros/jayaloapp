import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool? _provider;

  @override
  void initState() {
    super.initState();
    isProviderAccount().then((p) {
      if (!mounted) return;
      setState(() => _provider = p);
      // Aterriza en el home correcto según el rol.
      final loc = GoRouterState.of(context).matchedLocation;
      if (p && loc == '/client') context.go('/provider');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final provider = _provider!;
    final loc = GoRouterState.of(context).matchedLocation;
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
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(tabs[i].$1),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
