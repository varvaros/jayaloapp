// Revelaciones del intro: fade + subida con retardo, palabra a palabra, y el
// contador de créditos. Todas respetan «reducir animaciones» pintando el
// estado FINAL desde el primer frame (no el instante 0).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/motion.dart';

/// Aparece con fundido y una subida corta, tras [delay].
class IntroReveal extends StatelessWidget {
  const IntroReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = JayaloMotion.intro,
    this.dy = 10,
    this.curve = JayaloMotion.brake,
    this.scaleFrom,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double dy;
  final Curve curve;

  /// Si se da, además crece desde este factor (el grito: .72 con `bounce`).
  final double? scaleFrom;

  @override
  Widget build(BuildContext context) {
    if (JayaloMotion.reduced(context)) return child;
    var a = child
        .animate(delay: delay)
        .fadeIn(duration: duration, curve: curve)
        .moveY(begin: dy, end: 0, duration: duration, curve: curve);
    if (scaleFrom != null) {
      a = a.scale(
        begin: Offset(scaleFrom!, scaleFrom!),
        end: const Offset(1, 1),
        duration: duration,
        curve: curve,
        // El grito crece desde su centro: va centrado (PO 2026-09-18).
        alignment: Alignment.center,
      );
    }
    return a;
  }
}

/// El titular palabra a palabra: cada una sube 10 px, escalonadas [step].
class IntroWords extends StatelessWidget {
  const IntroWords({
    super.key,
    required this.text,
    required this.style,
    this.delay = const Duration(milliseconds: 120),
    this.step = const Duration(milliseconds: 38),
  });

  final String text;
  final TextStyle style;
  final Duration delay;
  final Duration step;

  @override
  Widget build(BuildContext context) {
    assert(
      style.fontSize != null,
      'IntroWords calcula el espaciado con el fontSize del titular',
    );
    final size = style.fontSize ?? 16;
    final words = text.split(' ');
    // El titular es UNA frase, no seis palabras sueltas: sin esto TalkBack
    // pedía un gesto por `Text` para oír la primera pantalla de la app (era
    // un solo nodo cuando el titular era un `Text.rich`).
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: size * .28,
        runSpacing: 0,
        children: [
          for (var i = 0; i < words.length; i++)
            IntroReveal(
              delay: delay + step * i,
              child: Text(words[i], style: style),
            ),
        ],
      ),
    );
  }
}

/// Cuenta de 0 a [to] a 120 ms por cifra; cada cifra entra a 122 % y baja.
///
/// El tween NACE al vencer [delay], no al montarse. Con el tween arrancando en
/// el montaje y el fundido esperando el retardo, las cifras que el usuario
/// alcanzaba a VER eran las dos últimas: para cuando el número se hacía
/// visible la cuenta ya iba por 4 y parecía que el «5» simplemente aparecía.
class IntroCounter extends StatefulWidget {
  const IntroCounter({
    super.key,
    required this.to,
    required this.style,
    this.delay = const Duration(milliseconds: 360),
  });

  final int to;
  final TextStyle style;
  final Duration delay;

  /// 120 ms por cifra, o sea `JayaloMotion.fast` menos 30: el ritmo de un
  /// contador, no el de un toque.
  static const stepPerDigit = Duration(milliseconds: 120);

  @override
  State<IntroCounter> createState() => _IntroCounterState();
}

class _IntroCounterState extends State<IntroCounter> {
  /// El retardo, como temporizador cancelable. Un `Future.delayed` no se
  /// cancela al desmontar y en los tests de widgets eso sale como «A Timer is
  /// still pending» apuntando a cualquier otro sitio.
  Timer? _arranque;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _arranque = Timer(widget.delay, () {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  void dispose() {
    _arranque?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.to;
    if (JayaloMotion.reduced(context) || to <= 0) {
      return Text('$to', style: widget.style);
    }
    if (!_started) {
      // Invisible pero OCUPANDO el sitio del número FINAL (una o dos cifras):
      // si el titular midiera sin él, se recolocaría entero durante la cuenta.
      return Opacity(
        opacity: 0,
        child: Text('0' * '$to'.length, style: widget.style),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: to.toDouble()),
      duration: IntroCounter.stepPerDigit * to,
      curve: JayaloMotion.linear,
      builder: (_, v, _) {
        final shown = v.ceil();
        final frac = v - v.floorToDouble();
        final scale = (shown == 0 || frac == 0) ? 1.0 : 1.22 - .22 * frac;
        return Transform.scale(
          scale: scale,
          child: Text('$shown', style: widget.style),
        );
      },
    ).animate().fadeIn(duration: JayaloMotion.fast);
  }
}
