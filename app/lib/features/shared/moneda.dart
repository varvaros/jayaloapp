/// La moneda de Jayalo, dibujada — no un asset.
///
/// Nació dentro de la lluvia de monedas que rebota en la cabeza del Jayi en la
/// tienda de créditos y se sacó aquí cuando empezó a hacer falta en tres sitios
/// más: las pilas de las tarjetas de paquetes y el contador de saldo de los
/// headers. Es la MISMA moneda en todos: eso es lo que hace que el número del
/// header y el paquete que compras se lean como la misma cosa.
library;

import 'package:flutter/material.dart';

/// Oro de la moneda. Un solo tono para la lluvia, las pilas y los sellos.
const kOroMoneda = Color(0xFFF2B705);

/// Tinta sobre el oro (sellos y píldoras doradas). Más oscura que la 'J' de la
/// moneda a propósito: ahí es un grabado, aquí tiene que LEERSE.
const kTintaOro = Color(0xFF5C3A00);

/// Dibuja UNA moneda de radio [r] centrada en [c].
///
/// Todas las medidas van en proporción a [r], así que la moneda de 10 px del
/// contador es exactamente la misma que la de 17 px de una pila.
void pintarMoneda(Canvas canvas, Offset c, double r,
    {double rot = 0, double alpha = 1}) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  if (rot != 0) canvas.rotate(rot);
  canvas.drawCircle(
      Offset.zero,
      r * 1.17,
      Paint()
        ..color = kOroMoneda.withValues(alpha: .38 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .42));
  canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.24, -.36),
          colors: [
            const Color(0xFFFFEDB0).withValues(alpha: alpha),
            kOroMoneda.withValues(alpha: alpha),
            const Color(0xFFC98A00).withValues(alpha: alpha),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
  canvas.drawCircle(
      Offset.zero,
      r * .717,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .133
        ..color = const Color(0xFFFFE9A8).withValues(alpha: alpha));
  final j = TextPainter(
    text: TextSpan(
        text: 'J',
        style: TextStyle(
            fontSize: r,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF8A5E00).withValues(alpha: alpha))),
    textDirection: TextDirection.ltr,
  )..layout();
  j.paint(canvas, -Offset(j.width / 2, j.height / 2 + r * .04));
  canvas.restore();
}

/// Una moneda suelta, del tamaño que se le pida.
class MonedaJayalo extends StatelessWidget {
  const MonedaJayalo({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _MonedaPainter(),
      );
}

class _MonedaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => pintarMoneda(
      canvas, Offset(size.width / 2, size.height / 2), size.width / 2 - 1);

  @override
  bool shouldRepaint(_MonedaPainter old) => false;
}
