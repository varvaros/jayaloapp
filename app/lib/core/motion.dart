/// Sistema central de movimiento (doctrina PO 2026-07-18): la app debe
/// sentirse premium — rápida, con respuesta inmediata al toque y transiciones
/// fluidas que nunca estorban. TODA duración y curva de animación sale de
/// aquí; no se escriben `Duration(milliseconds: …)` ni `Curves.…` sueltos en
/// las pantallas, para que la velocidad y el carácter del movimiento sean
/// idénticos en toda la app.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  /// oferta, desbloquear un contacto). PO 2026-07-22: 2.5 s — barrera
  /// deliberada pero no eterna; evita aceptaciones/cobros por reflejo.
  static const holdConfirm = Duration(milliseconds: 2500);

  /// El "¡PUM!" de la mascota al completar el hold de desbloqueo (pedido PO
  /// 2026-07-22): lo que dura la explosión ANTES de cerrar la hoja. Corre en
  /// paralelo con el RPC del cobro, así que no retrasa el acceso al contacto.
  static const mascotPum = Duration(milliseconds: 560);

  /// La subida frenada de las HOJAS que salen desde abajo.
  ///
  /// Estos números NO son nuevos: son exactamente los que el PO aprobó el
  /// 2026-07-21 para "ver ofertas" y la hoja de aceptar oferta ("que suba más
  /// lenta y desacelere al llegar al final"). Vivían copiados a mano en esas
  /// dos pantallas mientras las otras 18 hojas de la app seguían con la
  /// transición default de Material; el pedido del 2026-07-30 ("el efecto de
  /// frenado lento a las ventanas que se deslizan, COMO LAS DE VER OFERTAS")
  /// es extenderlo a todas. Se sube el valor aprobado a token en vez de
  /// inventar una curva nueva — la doctrina de este archivo es que la curva y
  /// la duración salgan de un solo sitio.
  ///
  /// Entrada de 1.5s con FRENADO (PO 2026-07-30: "agrégale 1.5 segundos, como
  /// la de crear solicitudes, que tenga un frenado"). La curva es [brake]
  /// (easeOutQuint), no [enter]: con quinta potencia el recorrido se hace casi
  /// todo al principio y el resto de la duración es una frenada larga: eso es
  /// lo que se percibe como "la ventana llegando despacio al tope" y no como
  /// "la ventana tardando". Es la misma familia que
  /// [modalRise], la del modal de crear solicitud.
  ///
  /// Los 520ms de easeOutCubic que tenían "ver ofertas" y "aceptar oferta"
  /// (aprobados el 2026-07-21) quedan reemplazados por esto en TODAS las
  /// hojas: la de 520 era una decisión local de dos pantallas mientras las
  /// otras 18 seguían con el default de Material.
  ///
  /// La SALIDA se queda corta (260ms, acelerando con [exit]) a propósito, y no
  /// sube a 1.5s: cerrar es "quítate" — hacer esperar un segundo y medio por
  /// algo que el usuario ya descartó se siente trabado por más linda que sea
  /// la entrada.
  ///
  /// No se usa un `AnimationController` propio (que en su momento rompió el
  /// arrastre-para-cerrar): `sheetAnimationStyle` solo ajusta curva y duración
  /// de la transición estándar y deja el gesto intacto.
  ///
  /// 👉 LA PALANCA: los 1500. Va como `sheetAnimationStyle` en cada
  /// `showModalBottomSheet` porque `BottomSheetThemeData` no expone animación —
  /// no hay manera de ponerlo una sola vez en el tema.
  static final sheetRise = AnimationStyle(
    curve: brake,
    duration: const Duration(milliseconds: 1500),
    reverseCurve: exit,
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// El hermano RÁPIDO de [sheetRise], para los MENÚS: listas cortas de acción
  /// que se abren, se tocan y se cierran ("tomar foto / elegir de la galería",
  /// emojis, respuestas rápidas, el ＋ del chat).
  ///
  /// LA REGLA para elegir entre los dos: ¿el usuario viene a LEER o a ELEGIR?
  /// Una hoja de contenido (ver ofertas, aceptar, desbloquear, detalle de
  /// producto, un formulario) es una pantalla — ahí el frenado largo se lee
  /// como algo importante llegando a su sitio. Un menú de tres filas es un
  /// trámite: el usuario ya sabe qué va a tocar antes de que termine de subir,
  /// y 1.5s lo dejan esperando a que la app le permita actuar. Se siente como
  /// que la app no responde (PO 2026-07-30, tras verlo en device).
  ///
  /// Conserva la MISMA curva [brake] a propósito: el carácter del movimiento
  /// de la app es uno solo, lo que cambia es cuánto dura. Y la salida es la
  /// misma que la de [sheetRise], que ya era corta.
  static final sheetMenu = AnimationStyle(
    curve: brake,
    duration: const Duration(milliseconds: 400),
    reverseCurve: exit,
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Accesibilidad: con "reducir animaciones" del sistema el movimiento se
  /// apaga (mismo criterio que JayaloLoader).
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Feedback TÁCTIL. Igual que las duraciones y las curvas, los pulsos salen de
/// un solo sitio: así el vocabulario háptico de la app es uno solo y se puede
/// recalibrar o apagar sin ir a buscar llamadas sueltas por las pantallas.
///
/// ⚠️ A diferencia de todo lo demás de este archivo, esto NO se apaga con
/// [JayaloMotion.reduced]: "reducir animaciones" es una preferencia de
/// MOVIMIENTO (vértigo, mareo con el movimiento en pantalla), no de vibración.
/// Android e iOS tienen su propio ajuste de respuesta táctil y la plataforma ya
/// lo respeta por debajo de `HapticFeedback` — silenciarlo acá le quitaría al
/// usuario que apagó las animaciones justamente la confirmación que le queda.
abstract final class JayaloHaptics {
  /// Algo SALIÓ del dispositivo por decisión del usuario: un mensaje de chat,
  /// una solicitud, una oferta. Frecuencia media y un único golpe seco — el
  /// pulso más liviano que de verdad se siente en la mano.
  ///
  /// El "¡PUM!" del hold-to-confirm es otra cosa y vive aparte
  /// (`mediumImpact` en `celebration.dart`): ahí el golpe fuerte marca el
  /// final de una barrera deliberada, no un envío.
  static void sent() => HapticFeedback.lightImpact();

  /// Cambió la SELECCIÓN: pestaña de la barra flotante, segmentado. Es la
  /// interacción más frecuente de la app, así que va con el pulso más tenue
  /// que existe (el mismo tic que hace un picker al pasar de valor). Se
  /// dispara solo cuando el índice CAMBIA de verdad — re-tocar la pestaña en
  /// la que ya estás no vibra.
  static void tabChange() => HapticFeedback.selectionClick();
}
