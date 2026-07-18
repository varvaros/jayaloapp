import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'core/motion.dart';

/// Doctrina de movimiento (decisión PO 2026-07-18): TODA transición de
/// pantalla debe sentirse premium — deslizado suave con ease-out, nunca el
/// zoom/fade genérico de Android por defecto. Un solo builder aquí cubre las
/// ~15 rutas de `core/router.dart` sin tocarlas una por una.
///
/// La entrante desliza desde la derecha (6% del ancho) + fade in; la saliente
/// (bajo `secondaryAnimation`, solo se anima al EMPUJAR una ruta encima, no al
/// volver) se desliza levemente a la izquierda y se atenúa — el efecto de
/// profundidad tipo "shared axis" de Material 3, no un corte plano.
class _JayaloPageTransitionsBuilder extends PageTransitionsBuilder {
  const _JayaloPageTransitionsBuilder();

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
    final incoming = CurvedAnimation(
        parent: animation,
        curve: JayaloMotion.enter,
        reverseCurve: JayaloMotion.exit);
    final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: JayaloMotion.enter,
        reverseCurve: JayaloMotion.exit);
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(.06, 0), end: Offset.zero)
          .animate(incoming),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
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
        routerConfig: router,
      );
}
