import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'core/motion.dart';

/// Doctrina de movimiento (decisión PO 2026-07-18): TODA transición de
/// pantalla debe sentirse premium — deslizado suave, nunca el zoom/fade
/// genérico de Android por defecto. Un solo builder aquí cubre las ~15 rutas
/// de `core/router.dart` sin tocarlas una por una.
///
/// Eje HORIZONTAL (3ª directriz del PO, revisión visual en device
/// 2026-07-19: "el deslizamiento de las secciones que sea a la derecha";
/// sustituye al eje vertical del 07-18): la sección entrante LLEGA desde la
/// derecha (8% del ancho) con fade in, y la saliente se guarda hacia la
/// izquierda (4%) atenuándose. Al volver atrás, la reversa deshace el
/// gesto — la de arriba se va por la derecha. Curva `easeInOutCubic` en
/// ambas: el movimiento arranca y termina suave, sin tirones.
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
      // Llega desde la derecha hasta su sitio.
      position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero)
          .animate(incoming),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          // La anterior se guarda hacia la izquierda mientras se atenúa.
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
