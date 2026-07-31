/// Pull-to-refresh con la mascota de Jáyalo en vez del anillo de Material.
///
/// Por dentro es un `RefreshIndicator.noSpinner`: se conserva ENTERA la
/// maquinaria de Material — detección de borde, umbral de armado, el
/// `triggerMode`, el ciclo de vida del `Future` de refresco y su semántica de
/// accesibilidad — y solo se reemplaza lo que dibuja. Reimplementar el gesto a
/// mano habría obligado a duplicar esa lógica y, peor, a pelear con
/// `JayaloScrollPhysics`, que es de donde sale el frenado largo de la app.
///
/// ⚠️ LO QUE `noSpinner` NO DA: el progreso continuo del tirón (0-1). La API
/// pública solo expone [RefreshIndicatorStatus] — `drag`, `armed`, `snap`,
/// `refresh`, `done`, `canceled`. Así que la mascota no baja pegada al dedo:
/// aparece en un punto fijo y entra/sale animada según el ESTADO. Es a
/// propósito, no una limitación pendiente de arreglar: el precio de tener el
/// progreso continuo sería replicar el cálculo de arrastre de
/// `RefreshIndicator` y quedar expuesto a que divergiera en cada upgrade de
/// Flutter.
///
/// 📌 SOBRE LA MASCOTA LOTTIE: hoy dibuja [JayaloMascotFace] (CustomPainter),
/// que es la mascota canónica de carga de la app. Los dos únicos Lottie que
/// existen son `jayi_celebrando.json` y su variante blanca, y una mascota
/// CELEBRANDO mientras se recargan datos cuenta la historia equivocada. Cuando
/// el PO exporte un Lottie de "trabajando/idle", el cambio es un solo sitio:
/// [_MascotIndicator.build].
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'brand_kit.dart' show jayaloCardShadow;
import 'jayalo_loader.dart';

/// Diámetro de la pastilla que sostiene a la mascota.
const _pillSize = 46.0;

/// Cuánto baja del borde superior. Alineado con el `displacement` de 40 que usa
/// `RefreshIndicator` por defecto, para que el indicador aterrice donde el
/// usuario de Android ya lo espera.
const _pillDrop = 40.0;

class JayaloRefresh extends StatefulWidget {
  const JayaloRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  /// Igual que `RefreshIndicator.onRefresh`: se completa cuando el refresco
  /// terminó, y hasta entonces la mascota sigue en pantalla.
  final Future<void> Function() onRefresh;

  final Widget child;

  /// Desplaza el indicador hacia abajo cuando algo fijo (un header) tapa el
  /// borde superior del scrollable.
  final double edgeOffset;

  @override
  State<JayaloRefresh> createState() => _JayaloRefreshState();
}

class _JayaloRefreshState extends State<JayaloRefresh> {
  RefreshIndicatorStatus? _status;

  /// ¿Se está viendo la mascota?
  ///
  /// ⚠️ `drag` NO cuenta, y esa es la diferencia entre un indicador y un
  /// estorbo. `RefreshIndicator` entra en `drag` con el PRIMER píxel de
  /// sobre-scroll: al llegar al tope de una lista y seguir el dedo un poco, o
  /// al rebotar contra el borde, la mascota aparecía de golpe a tamaño
  /// completo — el usuario lo lee como "sale mientras hago scroll" (bug PO
  /// 2026-07-30). Material se salva de esto porque escala su anillo con el
  /// avance del tirón; acá no hay avance continuo que leer (ver la nota de
  /// arriba sobre `noSpinner`), así que la alternativa honesta es esperar a
  /// `armed`: el punto en el que el tirón YA es suficiente y soltar va a
  /// refrescar de verdad.
  ///
  /// `canceled` y `done` son las fases de desvanecido: ahí el estado ya no es
  /// null pero el indicador tiene que estar yéndose, así que cuentan como
  /// invisible y la animación de salida hace el resto.
  bool get _visible => switch (_status) {
        RefreshIndicatorStatus.armed ||
        RefreshIndicatorStatus.snap ||
        RefreshIndicatorStatus.refresh =>
          true,
        RefreshIndicatorStatus.drag ||
        RefreshIndicatorStatus.done ||
        RefreshIndicatorStatus.canceled ||
        null =>
          false,
      };

  /// El tirón ya alcanzó el umbral y el dedo sigue abajo: la mascota se
  /// sorprende y se estira — "¡uy, me estás jalando!" (pedido PO 2026-07-30).
  /// Al soltar (`snap` → `refresh`) vuelve a su cara de trabajo: respira,
  /// parpadea y escanea con la pupila, la misma del loader de la app.
  ///
  /// Solo `armed`, nunca `drag`: ver la nota de [_visible].
  bool get _pulling => _status == RefreshIndicatorStatus.armed;

  MascotMood get _mood =>
      _pulling ? MascotMood.surprised : MascotMood.idle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) {
            if (!mounted) return;
            setState(() => _status = status);
          },
          child: widget.child,
        ),
        // `IgnorePointer` es imprescindible: la pastilla se dibuja ENCIMA del
        // scrollable y sin esto se comería el arrastre justo en la franja donde
        // el usuario está tirando para refrescar.
        Positioned(
          top: widget.edgeOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: _MascotIndicator(
                visible: _visible, mood: _mood, stretched: _pulling),
          ),
        ),
      ],
    );
  }
}

class _MascotIndicator extends StatelessWidget {
  const _MascotIndicator({
    required this.visible,
    required this.mood,
    required this.stretched,
  });

  final bool visible;
  final MascotMood mood;

  /// El usuario está TIRANDO ahora mismo: la mascota se estira un poco, como
  /// si el dedo la jalara hacia abajo.
  final bool stretched;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);

    final pill = Padding(
      padding: const EdgeInsets.only(top: _pillDrop),
      child: Center(
        child: Container(
          width: _pillSize,
          height: _pillSize,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            shape: BoxShape.circle,
            boxShadow: jayaloCardShadow(context),
          ),
          alignment: Alignment.center,
          // El ESTIRÓN del tirón: se alarga en vertical y adelgaza un pelín en
          // horizontal — conservar el área es lo que lo hace leer como algo
          // elástico y no como un simple "se hizo más grande". El ancla es
          // ARRIBA (`alignment: topCenter`): la mascota cuelga del borde del
          // que viene, así que crece hacia el dedo que la jala.
          //
          // Va por fuera del `AnimatedSwitcher` de más abajo a propósito: ese
          // maneja entrar/salir, este el estado del gesto MIENTRAS está
          // visible, y mezclarlos haría que soltar el dedo remontara la
          // mascota entera (perdiendo el parpadeo y su ciclo).
          child: TweenAnimationBuilder<double>(
            // Con reduce-motion el estirón no ocurre: la cara de sorpresa sola
            // ya cuenta que la estás jalando.
            tween: Tween<double>(end: stretched && !reduced ? 1 : 0),
            duration: JayaloMotion.fast,
            curve: JayaloMotion.enter,
            builder: (context, k, child) => Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.diagonal3Values(1 - .07 * k, 1 + .14 * k, 1),
              child: child,
            ),
            // 👉 EL PUNTO DE CAMBIO si algún día hay un Lottie de
            // "trabajando": reemplazar este widget por su `Lottie.asset(...)`.
            // Todo lo demás (posición, entrada, salida, estados) queda igual.
            child: JayaloMascotFace(
              size: 34,
              mood: mood,
              semanticsLabel: 'Actualizando',
            ),
          ),
        ),
      ),
    );

    // Sin movimiento: aparece y desaparece, sin fundido ni escala.
    if (reduced) return visible ? pill : const SizedBox.shrink();

    // ⚠️ AnimatedSwitcher y NO AnimatedOpacity/AnimatedScale: la mascota tiene
    // un ticker en `repeat()` que no se detiene nunca, así que dejarla MONTADA
    // en opacidad 0 mientras no se refresca le pediría a la app un frame por
    // vsync, para siempre, en las 6 pantallas que usan este widget (y de paso
    // cuelga cualquier `pumpAndSettle` de sus tests). El switcher la
    // DESMONTA al terminar la transición de salida, y así en reposo no hay
    // ningún ticker vivo.
    //
    // Hace falta desmontar a mano porque `onStatusChange` no avisa el estado
    // final: `RefreshIndicator._dismiss` pone `_status = null` SIN invocar el
    // callback (refresh_indicator.dart), así que "ya no hay refresco" no llega
    // nunca como evento — se deduce de que el estado sea `done`/`canceled`.
    return AnimatedSwitcher(
      // La SALIDA es más corta que la entrada (150 vs 250ms): ya terminó de
      // refrescar y el usuario quiere ver sus datos, no ver irse al indicador.
      duration: JayaloMotion.base,
      reverseDuration: JayaloMotion.fast,
      switchInCurve: JayaloMotion.enter,
      switchOutCurve: JayaloMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        // Entra deslizándose desde arriba: viene de FUERA de la pantalla, que
        // es de donde el usuario la está jalando — gesto y movimiento apuntan
        // al mismo lado.
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -.5), end: Offset.zero)
              .animate(animation),
          child: ScaleTransition(
            // Nunca desde 0: una escala naciendo de la nada se lee sintética.
            scale: Tween<double>(begin: .92, end: 1).animate(animation),
            child: child,
          ),
        ),
      ),
      child: visible ? pill : const SizedBox.shrink(),
    );
  }
}
