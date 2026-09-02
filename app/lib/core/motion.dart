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

/// Coeficiente de arrastre que hace que un fling de [velocity] px/s tarde
/// [target] en detenerse del todo.
///
/// Flutter NO tiene la prop `decelerationRate` de React Native (allí es un
/// float de 0 a 1 donde acercarse a 1 frena más lento). El equivalente aquí es
/// el arrastre de `FrictionSimulation`, pero como número suelto no dice nada —
/// así que se despeja al revés: se pide la DURACIÓN del frenado y de ahí sale
/// el arrastre.
///
/// ## Por qué decaimiento EXPONENCIAL y no la spline de Android
///
/// Hasta el 2026-08-03 esto devolvía la fricción de `ClampingScrollSimulation`
/// (la curva nativa de Android). Su problema, medido: la duración va como
/// `T ∝ v^0.736`, así que entre el fling más suave y el más brusco del uso real
/// había **6.3× de diferencia** — un swipe moderado frenaba en 0.7-1.3 s y se
/// leía como un frenazo, mientras el brusco planeaba 4.5 s. Y la fricción es un
/// MULTIPLICADOR sobre todas las velocidades a la vez, así que subir
/// [JayaloMotion.scrollBrake] no podía arreglarlo: el reparto entre suave y
/// brusco es una constante de ese modelo.
///
/// El decaimiento exponencial (`v(t) = v₀·drag^t`, el modelo de iOS) hace la
/// duración LOGARÍTMICA en la velocidad, que es justo lo que aplana el reparto:
/// el mismo uso real pasa de 6.3× a 1.7×. Ese es el motivo por el que iOS se
/// siente consistente entre un roce y un envión.
///
/// Se despeja de `FrictionSimulation.isDone`, que para cuando
/// `|v₀·drag^t| < toleranceVelocity`:
///   t = ln(v/tol) / (−ln drag)   →   drag = exp(−ln(v/tol) / t)
///
/// [toleranceVelocity] NO es un número fijo: `ScrollPhysics.toleranceFor` lo
/// calcula como `1/(0.05·devicePixelRatio)`, así que depende del device (6.36
/// px/s en el teléfono del PO, dpr 3.14). Por eso se recibe como parámetro y se
/// resuelve en el momento del fling — así los segundos de [target] se cumplen
/// en cualquier pantalla, en vez de solo en aquella donde se calibró.
double dragForBrake(
  Duration target, {
  required double velocity,
  required double toleranceVelocity,
}) {
  final t = target.inMicroseconds / Duration.microsecondsPerSecond;
  return math.exp(-math.log(velocity / toleranceVelocity) / t);
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
  ///
  /// Se mantiene en 4 s al cambiar a decaimiento exponencial (2026-08-03): lo
  /// que se arregló no fue la duración del fling típico, sino que TODOS los
  /// demás se parecieran a él. Ver [dragForBrake].
  static const scrollBrake = Duration(milliseconds: 4000);

  /// El fling con el que se calibra [scrollBrake] (px/s): la velocidad a la que
  /// los segundos de la palanca se cumplen exactamente.
  ///
  /// MEDIDO, no supuesto (2026-08-03). Una sonda en
  /// `JayaloScrollPhysics.createBallisticSimulation` registró 615 flings reales
  /// del PO usando la app en su teléfono. La mediana salió **1372 px/s**; aquí
  /// se redondea a 1400.
  ///
  /// El valor anterior era 3000, que nadie había medido y que resultó estar en
  /// el **p90-p95** del uso real: los 4 s aprobados solo se materializaban en el
  /// gesto que se hace una vez de cada diez, y el resto del tiempo la app
  /// frenaba en menos de la mitad. Eso, por sí solo, explicaba la queja del PO
  /// de que el scroll "solo se siente suave con un swipe muy brusco".
  ///
  /// El histograma salió BIMODAL — dos gestos distintos, con un valle claro
  /// entre ellos:
  ///   - leer   → 400-1000 px/s
  ///   - buscar → 1900-3650 px/s
  /// Con el modelo exponencial el ancla es poco sensible (mover esta cifra
  /// entre 630 y 1400 cambia las duraciones un ~11-17%), así que se toma la
  /// mediana global en vez de arbitrar entre los dos regímenes.
  static const flingReference = 1400.0;

  /// Arrastre derivado de [scrollBrake] — no se escribe a mano.
  ///
  /// Es función y no constante porque la tolerancia de parada depende del
  /// `devicePixelRatio` de la pantalla (ver [dragForBrake]); se resuelve en el
  /// momento del fling con la del `ScrollMetrics` real.
  static double scrollDragFor(double toleranceVelocity) => dragForBrake(
        scrollBrake,
        velocity: flingReference,
        toleranceVelocity: toleranceVelocity,
      );

  /// Entrada de las VENTANAS que se deslizan desde la derecha (el chat).
  /// Mismo carácter que [sheetRise]: 1.5s con la curva [brake] — el recorrido
  /// se hace casi todo al principio y el resto es la frenada larga llegando
  /// al tope (pedido PO 2026-08-11: "no se ve la animación del chat" — a
  /// 300ms el deslizado no se percibía junto a las hojas frenadas).
  static const windowRise = Duration(milliseconds: 1500);

  /// La salida de esas ventanas se queda corta a propósito, igual que en
  /// [sheetRise]: cerrar es "quítate".
  static const windowExit = Duration(milliseconds: 260);

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

  // ── El SALUDO del borde de "sin ver" (PO 2026-08-19/20) ───────────────
  //
  // El borde violeta que marca una oferta/solicitud que aún no has abierto
  // ya no aparece de golpe: RESPIRA unas cuantas veces y se detiene en el
  // borde lleno, que es la marca de siempre. El movimiento saluda; el borde
  // quieto es el estado — por eso lo PERMANENTE (una oferta aceptada) lleva
  // su borde de estado sin animar, y nunca este.
  //
  // Es finito A PROPÓSITO. Un latido perpetuo habría sido la primera
  // animación en bucle de la app —todo lo demás aquí es de una sola pasada—
  // y habría costado repintar la tarjeta mientras estuviera en pantalla, en
  // una LISTA. Con un número de respiros el controlador corre unos segundos
  // y se apaga.
  //
  // CUÁNDO saluda (decisión PO: opción "a"): cada vez que la tarjeta se
  // CONSTRUYE, más la vez en que pasa a estar "sin ver" sin cambiar de sitio.
  // En un `ListView.builder` eso significa que saluda otra vez al volver a
  // entrar en pantalla; se aceptó ese parpadeo a cambio de no llevar
  // contabilidad de qué tarjeta ya saludó. Lo que NO hace es re-saludar en
  // cada reconstrucción del padre: eso sería un parpadeo en cada `setState`
  // de la lista, que es bastante peor que lo que se aceptó.

  /// Cuánto dura UN respiro. 👉 LA PALANCA de la velocidad del saludo.
  static const pulseCycle = Duration(milliseconds: 1600);

  /// Cuántos respiros da antes de quedarse quieto. Con [pulseCycle] en 1600
  /// el saludo completo dura 4.8 s.
  static const pulseBreaths = 3;

  /// Opacidad del borde en lo más hondo del PRIMER respiro.
  static const pulseDepth = .30;

  /// Y en lo más hondo del ÚLTIMO. Que no sea 1 es lo que hace que el último
  /// respiro se note apenas, en vez de no existir.
  static const pulseDepthLast = .92;

  /// Opacidad del borde en el instante [t] (0..1 del saludo completo).
  ///
  /// Cada respiro es un valle de coseno —suave en los dos extremos, sin
  /// esquinas— y cada uno se apaga MENOS que el anterior, así el saludo se
  /// asienta en vez de cortarse. En t=0 y en t=1 vale exactamente 1: la
  /// tarjeta entra y se queda con el borde lleno.
  ///
  /// Vive aquí y no en el widget porque es la CURVA del movimiento, y en
  /// este archivo es donde viven las curvas.
  static double pulseOpacity(double t) {
    if (pulseBreaths <= 0) return 1;
    final u = t.clamp(0.0, 1.0) * pulseBreaths;
    final i = math.min(u.floor(), pulseBreaths - 1); // respiro en curso
    final valle = (1 - math.cos(2 * math.pi * (u - i))) / 2; // 0 → 1 → 0
    final fondo = pulseBreaths == 1
        ? pulseDepth
        : pulseDepth +
            (pulseDepthLast - pulseDepth) * (i / (pulseBreaths - 1));
    return 1 - valle * (1 - fondo);
  }

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

  /// Se CONSUMÓ algo que importa: una oferta aceptada, un contacto desbloqueado,
  /// unos créditos acreditados. Va por encima de [sent] a propósito — un envío
  /// es rutina y esto es un hito, casi siempre con dinero o una decisión detrás.
  ///
  /// Acompaña a los sonidos de celebración de `Sfx`, que hasta ahora sonaban
  /// SOLOS: el audio se pierde con el móvil en silencio, que es como anda medio
  /// mundo, y entonces la celebración no llegaba por ningún sentido.
  ///
  /// Es el mismo `mediumImpact` del "¡PUM!" del hold-to-confirm, y no es
  /// casualidad: los dos marcan que algo deliberado se consumó.
  static void success() => HapticFeedback.mediumImpact();

  /// La acción NO se hizo: saldo insuficiente, rechazo del servidor, fallo de
  /// red. El pulso más pesado, y el único que no celebra nada.
  ///
  /// La razón de que exista: un fallo tiene que sentirse DISTINTO de un acierto
  /// sin necesidad de mirar la pantalla. Sin él, desbloquear un contacto y que
  /// te lo rechacen por saldo se sienten igual en la mano.
  static void error() => HapticFeedback.heavyImpact();
}
