/// Sistema central de movimiento (doctrina PO 2026-07-18): la app debe
/// sentirse premium — rápida, con respuesta inmediata al toque y transiciones
/// fluidas que nunca estorban. TODA duración y curva de animación sale de
/// aquí; no se escriben `Duration(milliseconds: …)` ni `Curves.…` sueltos en
/// las pantallas, para que la velocidad y el carácter del movimiento sean
/// idénticos en toda la app.
library;

import 'package:flutter/material.dart';

abstract final class JayaloMotion {
  /// Feedback táctil inmediato (escala al presionar, cambios de estado
  /// pequeños). Nunca debe retrasar la interacción.
  static const fast = Duration(milliseconds: 150);

  /// La duración de trabajo: cascadas de entrada, cross-fade de pestañas,
  /// aparición de elementos.
  static const base = Duration(milliseconds: 250);

  /// Transiciones de pantalla y desvanecidos de color de tarjeta.
  static const page = Duration(milliseconds: 300);

  /// Entrada: desacelera al llegar (el estándar de la app).
  static const enter = Curves.easeOutCubic;

  /// Salida / reversa: acelera al irse.
  static const exit = Curves.easeInCubic;

  /// Movimientos que van y vuelven en el mismo gesto (steppers, énfasis).
  static const emphasized = Curves.easeInOutCubic;

  /// Escala de una superficie mientras está presionada.
  static const pressedScale = .98;

  /// Mantener presionado para confirmar un cobro (equivalente nativo del
  /// hold-to-confirm de la web). Deliberadamente más largo que `fast`/`base`:
  /// es una confirmación de dinero, no feedback táctil.
  static const holdConfirm = Duration(milliseconds: 900);

  /// Accesibilidad: con "reducir animaciones" del sistema el movimiento se
  /// apaga (mismo criterio que JayaloLoader).
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
