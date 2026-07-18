import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'core/motion.dart';

/// Doctrina de movimiento (decisión PO 2026-07-18): TODA transición de
/// pantalla debe sentirse premium — deslizado suave, nunca el zoom/fade
/// genérico de Android por defecto. Un solo builder aquí cubre las ~15 rutas
/// de `core/router.dart` sin tocarlas una por una.
///
/// Eje VERTICAL (2ª directriz del PO): la sección entrante SUBE desde abajo
/// (8% del alto) con fade in, y la saliente se GUARDA hacia arriba (4%)
/// atenuándose. Curva `easeInOutCubic` en ambas: el movimiento arranca y
/// termina suave, sin tirones — es lo que da la sensación de que la sección
/// "se acomoda" en vez de aparecer de golpe.
///
/// `secondaryAnimation` (la saliente) solo corre al EMPUJAR una ruta encima;
/// al volver, la de abajo baja de vuelta a su sitio.
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
    // easeInOutCubic en las dos direcciones: entra y sale con la misma
    // suavidad, sin arranque brusco.
    final incoming = CurvedAnimation(
        parent: animation,
        curve: JayaloMotion.emphasized,
        reverseCurve: JayaloMotion.emphasized);
    final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: JayaloMotion.emphasized,
        reverseCurve: JayaloMotion.emphasized);
    return SlideTransition(
      // Sube desde abajo hasta su sitio.
      position: Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
          .animate(incoming),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          // La anterior se guarda hacia arriba mientras se atenúa.
          position: Tween<Offset>(
                  begin: Offset.zero, end: const Offset(0, -.04))
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
