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

  /// Subida del modal de crear-solicitud. 3ª pasada PO: 300→600 ms ("cuando
  /// esté llegando a su tope reduce su velocidad"). 4ª pasada, viéndolo en
  /// device: "todavía se siente muy rápida, agrégale 300ms más" → 900 ms.
  static const modalRise = Duration(milliseconds: 900);

  /// Deslizado de pantalla entre secciones (PO 2026-07-19: "con un frenado
  /// de 2 segundos"): junto con [brake], casi todo el recorrido sucede al
  /// principio y el resto es una frenada larga y suave.
  static const screenSlide = Duration(milliseconds: 2000);

  /// La curva de ese frenado largo: quinta potencia — sale rápido y aterriza
  /// despacio, la mayor parte de la duración es deceleración.
  static const brake = Curves.easeOutQuint;

  /// Fricción del fling de scroll (PO 2026-07-19, 4ª pasada: "el scroll de la
  /// pantalla ponle 2 segundos de frenado"). Android/Flutter usan 0.015 por
  /// defecto, que para un fling típico (~3000 px/s) frena en ~1.0 s.
  ///
  /// La duración del fling sale de `ClampingScrollSimulation._flingDuration`:
  ///   t = 0.8256 · (v / (friction · 51890.6 / 0.35))^0.7359
  /// Duplicar t exige dividir la fricción por 2^(1/0.7359) ≈ 2.57, de ahí
  /// 0.015 / 2.57 ≈ 0.0058 → ~2.07 s de frenado para ese mismo fling. Menos
  /// fricción = el dedo suelta y el contenido sigue planeando más tiempo,
  /// que es justo la sensación pedida.
  static const scrollFriction = 0.0058;

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

  /// Mantener presionado para confirmar un cobro (equivalente nativo del
  /// hold-to-confirm de la web). Deliberadamente más largo que `fast`/`base`:
  /// es una confirmación de dinero, no feedback táctil.
  static const holdConfirm = Duration(milliseconds: 900);

  /// Accesibilidad: con "reducir animaciones" del sistema el movimiento se
  /// apaga (mismo criterio que JayaloLoader).
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
