import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/session_state.dart';
import '../../domain/back_intent.dart';
import 'home_scroll.dart';

/// Envuelve CADA pantalla del shell. El PopScope tiene que registrarse en las
/// rutas del Navigator ANIDADO del ShellRoute: si se pone en HomeShell (fuera),
/// el navigator interno despacha NavigationNotification(canHandlePop: false),
/// el raíz lo deja pasar (su filtro no mira el popDisposition de su propia
/// ruta) y Android 13+ desregistra el callback de predictive back → el ATRÁS
/// minimiza la app sin llegar a Flutter. Visto en el Redmi con targetSdk 36.
class BackGuard extends StatelessWidget {
  const BackGuard({super.key, required this.child});
  final Widget child;

  void _handleBack(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final home = homePathFor(provider: roleStore.value == RoleState.provider);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: child,
    );
  }
}
