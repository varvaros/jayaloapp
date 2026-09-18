// Revelaciones del intro: fade + subida con retardo, palabra a palabra, y el
// contador de créditos. Todas respetan «reducir animaciones» pintando el
// estado FINAL desde el primer frame (no el instante 0).
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
        alignment: Alignment.centerLeft,
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
    final words = text.split(' ');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: style.fontSize! * .28,
      runSpacing: 0,
      children: [
        for (var i = 0; i < words.length; i++)
          IntroReveal(
            delay: delay + step * i,
            child: Text(words[i], style: style),
          ),
      ],
    );
  }
}

/// Cuenta de 0 a [to] a 120 ms por cifra; cada cifra entra a 122 % y baja.
class IntroCounter extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (JayaloMotion.reduced(context) || to <= 0)
      return Text('$to', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: to.toDouble()),
      duration: stepPerDigit * to,
      curve: Curves.linear,
      builder: (_, v, __) {
        final shown = v.ceil();
        final frac = v - v.floorToDouble();
        final scale = (shown == 0 || frac == 0) ? 1.0 : 1.22 - .22 * frac;
        return Transform.scale(
          scale: scale,
          child: Text('$shown', style: style),
        );
      },
    ).animate(delay: delay).fadeIn(duration: JayaloMotion.fast);
  }
}
