/// Sistema central de movimiento (doctrina PO 2026-07-18): la app debe
/// sentirse premium — rápida, con respuesta inmediata al toque y transiciones
/// fluidas que nunca estorban. TODA duración y curva de animación sale de
/// aquí; no se escriben `Duration(milliseconds: …)` ni `Curves.…` sueltos en
/// las pantallas, para que la velocidad y el carácter del movimiento sean
/// idénticos en toda la app.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fricción que hace que un fling de [velocity] px/s tarde [target] en
/// detenerse del todo.
///
/// Flutter NO tiene la prop `decelerationRate` de React Native (allí es un
/// float de 0 a 1 donde acercarse a 1 frena más lento; valores ≥1 no son
/// válidos porque implicarían que nunca se detiene). El equivalente aquí es
/// la fricción de `ClampingScrollSimulation`, pero como número suelto no
/// dice nada — así que se despeja al revés: se pide la DURACIÓN del frenado
/// y de ahí sale la fricción.
///
/// Se invierte la fórmula de `ClampingScrollSimulation._flingDuration`:
///   t = dr·inf · (v / (friction·coef/inf))^(1/(dr-1))
/// despejando:
///   friction = inf/coef · v / (t/(dr·inf))^(dr-1)
double frictionForBrake(Duration target, {double velocity = 3000}) {
  const inflexion = 0.35;
  // 0.84·g expresado en píxeles lógicos/s² (mismo valor que usa Flutter).
  const coef = 9.80665 * 39.37 * 160.0 * 0.84;
  final decelRate = math.log(0.78) / math.log(0.9);
  final t = target.inMicroseconds / Duration.microsecondsPerSecond;
  final referenceVelocity =
      velocity / math.pow(t / (decelRate * inflexion), decelRate - 1);
  return referenceVelocity * inflexion / coef;
}

abstract final class JayaloMotion {
  /// Feedback táctil inmediato (escala al presionar, cambios de estado
  /// pequeños). Nunca debe retrasar la interacción.
  static const fast = Duration(milliseconds: 150);

  /// La duración de trabajo: cascadas de entrada, cross-fade de pestañas,
  /// aparición de elementos.
  static const base = Duration(milliseconds: 250);

  /// Transiciones de pantalla y desvanecidos de color de tarjeta.
  static const page = Duration(milliseconds: 300);

  /// Subida del modal de crear-solicitud. Historial de decisiones del PO
  /// viéndola en device: 300 → 600 ("reduce la velocidad al llegar al tope")
  /// → 900 ("todavía muy rápida, +300ms") → 2000 ("pongámosle 2 segundos").
  static const modalRise = Duration(milliseconds: 2000);

  /// Deslizado de pantalla entre secciones (PO 2026-07-19: "con un frenado
  /// de 2 segundos"): junto con [brake], casi todo el recorrido sucede al
  /// principio y el resto es una frenada larga y suave.
  static const screenSlide = Duration(milliseconds: 2000);

  /// La curva de ese frenado largo: quinta potencia — sale rápido y aterriza
  /// despacio, la mayor parte de la duración es deceleración.
  static const brake = Curves.easeOutQuint;

  /// 👉 LA PALANCA DEL SCROLL: cuánto tarda en detenerse un fling típico.
  ///
  /// Este es el número a tocar para que el scroll frene más o menos rápido —
  /// sube o baja los segundos y ya. Referencia: el default de Android
  /// equivale a ~1.0 s aquí. PO 2026-07-19 (5ª pasada, pidiendo el
  /// equivalente de un `decelerationRate` cercano a 1): 2 s → 4 s.
  static const scrollBrake = Duration(milliseconds: 4000);

  /// El fling con el que se calibra [scrollBrake] (px/s). Un envión normal
  /// del pulgar ronda esta cifra; flings más suaves frenan antes y más
  /// bruscos después, proporcionalmente.
  static const flingReference = 3000.0;

  /// Fricción derivada de [scrollBrake] — no se escribe a mano.
  static final double scrollFriction =
      frictionForBrake(scrollBrake, velocity: flingReference);

  /// Subida del modal: arranque suave y frenada MUY marcada al llegar al
  /// tope (la variante enfatizada de Material de easeInOutCubic).
  static const rise = Curves.easeInOutCubicEmphasized;

  /// Entrada: desacelera al llegar (el estándar de la app).
  static const enter = Curves.easeOutCubic;

  /// Salida / reversa: acelera al irse.
  static const exit = Curves.easeInCubic;

  /// Movimientos que van y vuelven en el mismo gesto (steppers, énfasis).
  static const emphasized = Curves.easeInOutCubic;

  /// Escala de una superficie mientras está presionada.
  static const pressedScale = .98;

  /// Mantener presionado para confirmar una decisión definitiva (aceptar una
  /// oferta, desbloquear un contacto). PO 2026-07-21: 3.5 s — barrera
  /// deliberada pero no eterna; evita aceptaciones/cobros por reflejo.
  static const holdConfirm = Duration(milliseconds: 3500);

  /// Accesibilidad: con "reducir animaciones" del sistema el movimiento se
  /// apaga (mismo criterio que JayaloLoader).
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
