/// El vuelo de monedas de la acreditacion, sacado de `credit_shop_screen.dart`
/// el 2026-09-21 para que lo use tambien el intro de primera apertura (la
/// lamina del bono de bienvenida). La coreografia no cambio ni un milisegundo
/// en la mudanza: es la misma que el PO aprobo el 2026-08-23.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/sfx.dart';
import 'moneda.dart';

/// El vuelo de monedas de la acreditación (mockup «enjambre cometa», PO
/// 2026-08-23): cinco monedas estallan a la vez sobre la pila de la tarjeta
/// comprada, flotan un instante y salen disparadas UNA A UNA, con estela
/// dorada y un arco propio cada una, hasta el contador del AppBar.
///
/// Como el Jayi de la banda: UN SOLO controller para toda la coreografía —
/// estallido, tirones, estelas, aterrizajes, destello y el sonido salen de la
/// misma línea de tiempo, que es lo que la mantiene articulada (feedback PO
/// sobre el mockup: «se ve desarticulada» — aquí nada corre por su cuenta).
/// Público solo para los widget tests de la pantalla.
class VueloMonedas extends StatefulWidget {
  const VueloMonedas({
    super.key,
    required this.origen,
    required this.destino,
    required this.onAterrizaje,
    required this.onFin,
  });

  /// Centro de la pila de la tarjeta comprada, en coordenadas globales.
  final Offset origen;

  /// Centro del contador del AppBar, en coordenadas globales.
  final Offset destino;

  /// Una llamada por moneda que llega (0..4), EN el instante del impacto: la
  /// pantalla sube el saldo con cada una y el contador pulsa al recibirla.
  final void Function(int moneda) onAterrizaje;

  /// El vuelo terminó: quien lo montó retira el overlay.
  final VoidCallback onFin;

  @override
  State<VueloMonedas> createState() => _VueloMonedasState();
}

class _VueloMonedasState extends State<VueloMonedas>
    with SingleTickerProviderStateMixin {
  /// 1 240 ms en total: estallido 322, respiro, y cinco tiros de 384 cada
  /// 90 ms. Duración propia (no un token de `motion.dart`): es la coreografía
  /// de UNA celebración, como el ciclo de 4,2 s del Jayi.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1240));

  int _aterrizadas = 0;
  bool _sono = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_avanza);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onFin();
    });
    _c.forward();
  }

  void _avanza() {
    final t = _c.value;
    // El ting-ting-ting arranca un pelín antes del primer impacto (.71) para
    // que los tintineos caigan sobre los aterrizajes, no detrás de ellos.
    if (!_sono && t >= .56) {
      _sono = true;
      // El sonido se pierde con el móvil en silencio, que es como anda medio
      // mundo: sin esto la recarga acreditada no llegaba por ningún sentido.
      JayaloHaptics.success();
      unawaited(playSfx(Sfx.coinsCredited));
    }
    while (_aterrizadas < 5 &&
        t >= _VueloPainter.aterrizajes[_aterrizadas]) {
      widget.onAterrizaje(_aterrizadas);
      _aterrizadas++;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _VueloPainter(
              t: _c.value,
              origen: widget.origen,
              destino: widget.destino,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _VueloPainter extends CustomPainter {
  _VueloPainter({required this.t, required this.origen, required this.destino});

  final double t;
  final Offset origen;
  final Offset destino;

  // ── La línea de tiempo (fracciones de los 1 240 ms) ────────────────────────
  /// Fin del estallido conjunto.
  static const _finEstallido = .26;

  /// Salida del tiro de cada moneda (cada 90 ms desde los 496 ms)…
  static const _salidas = [.40, .4725, .545, .6175, .69];

  /// …y su impacto en el contador, 384 ms después. La última cierra el vuelo.
  static const aterrizajes = [.71, .7825, .855, .9275, 1.0];

  // ── La geometría (relativa a la pila) ─────────────────────────────────────
  /// De dónde despega cada moneda: las posiciones de la pila de 5.
  static const _cunas = [
    Offset(-40, 18), Offset(-20, -10), Offset(0, 18),
    Offset(20, -10), Offset(40, 18),
  ];

  /// Hasta dónde estalla cada una: un abanico sobre la tarjeta.
  static const _abanico = [
    Offset(-66, -64), Offset(-34, -88), Offset(6, -99),
    Offset(44, -85), Offset(74, -52),
  ];

  /// Comba del arco de cada tiro, alternando el lado: cinco trayectorias
  /// hermanas pero no clónicas, que es lo que se lee como "orgánico".
  static const _combas = [-30.0, 24.0, -18.0, 26.0, -22.0];

  /// El acelerón del tiro. El mockup usaba u³ y en los fotogramas se vio el
  /// defecto: la moneda pasa medio tiro pegada al enjambre (a mitad de tiempo
  /// solo lleva el 15 % del camino) y luego cruza la pantalla en un
  /// parpadeo — teletransporte, no vuelo. u² (easeInQuad) sigue llegando
  /// lanzada pero despega a tiempo de leerse.
  static const _acelera = Curves.easeInQuad;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 5; i++) {
      _moneda(canvas, i);
      _impacto(canvas, i);
    }
  }

  void _moneda(Canvas canvas, int i) {
    final cuna = origen + _cunas[i];
    final flote = origen + _abanico[i];

    if (t < _finEstallido) {
      // Estallido conjunto: de la pila al abanico con un puntito de rebote
      // (easeOutBack) y apareciendo en los primeros metros.
      final u = (t / _finEstallido).clamp(0.0, 1.0);
      final e = Curves.easeOutBack.transform(u);
      final pos = Offset.lerp(cuna, flote, e)!;
      final escala = .35 + .65 * Curves.easeOutCubic.transform(u);
      pintarMoneda(canvas, pos, 15 * escala,
          alpha: (u * 3.5).clamp(0.0, 1.0));
      return;
    }

    final salida = _salidas[i];
    // Flote: sube 7 px y respira 2 px, CONGELADO en el instante de la salida
    // para que el tiro arranque exactamente donde la moneda estaba — sin ese
    // empalme el tiro "teletransporta" y se ve desarticulado.
    final tf = math.min(t, salida);
    final flotePos = flote +
        Offset(
            0,
            -7 * Curves.easeOutCubic.transform(
                    ((tf - _finEstallido) / .10).clamp(0.0, 1.0)) -
                2 * math.sin(9 * (tf - _finEstallido) + i * 1.7));

    if (t < salida) {
      pintarMoneda(canvas, flotePos, 15);
      return;
    }

    final u = ((t - salida) / (aterrizajes[i] - salida)).clamp(0.0, 1.0);
    if (u >= 1) return; // ya aterrizó: la pinta el impacto, no la moneda.

    final e = _acelera.transform(u);
    // Arco cuadrático: el punto de control se sale de la recta hacia el lado
    // de su comba.
    final medio = Offset.lerp(flotePos, destino, .5)!;
    final dir = destino - flotePos;
    final largo = dir.distance;
    final perp = largo == 0
        ? Offset.zero
        : Offset(-dir.dy / largo, dir.dx / largo) * _combas[i];
    final control = medio + perp;
    Offset punto(double k) =>
        flotePos * (1 - k) * (1 - k) + control * 2 * k * (1 - k) + destino * k * k;

    // Estela: cuatro tramos por donde la moneda acaba de pasar, afinándose.
    // En el ORO de la moneda y no en crema: el vuelo cruza la tarjeta blanca
    // y una estela pálida desaparecía contra ella (visto en los fotogramas).
    for (var k = 4; k >= 1; k--) {
      final a = (e - .055 * k).clamp(0.0, 1.0);
      final b = (e - .055 * (k - 1)).clamp(0.0, 1.0);
      if (a >= b) continue;
      canvas.drawLine(
        punto(a),
        punto(b),
        Paint()
          ..color = kOroMoneda
              .withValues(alpha: (.58 - .12 * k) * (1 - u * .3))
          ..strokeWidth = 8.5 - 1.6 * k
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.save();
    final pos = punto(e);
    pintarMoneda(canvas, pos, 15 * (1 - .62 * e),
        rot: _combas[i].sign * 1.1 * e);
    canvas.restore();
  }

  /// El golpe en el contador: anillo que se abre + dos chispas; la última
  /// moneda trae además el halo grande del "ya está".
  void _impacto(Canvas canvas, int i) {
    final u = ((t - aterrizajes[i]) / .15).clamp(0.0, 1.0);
    if (t < aterrizajes[i] || u >= 1) return;
    final abre = Curves.easeOutCubic.transform(u);
    final ultimo = i == 4;

    if (ultimo) {
      canvas.drawCircle(
          destino,
          12 + 26 * abre,
          Paint()
            ..color = kOroMoneda.withValues(alpha: .35 * (1 - u))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawCircle(
        destino,
        (ultimo ? 10 : 8) + (ultimo ? 34 : 24) * abre,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - u)
          ..color = kOroMoneda.withValues(alpha: .55 * (1 - u)));

    final k = math.sin(math.pi * u);
    _estrella(canvas, destino + const Offset(-11, -7), 7 * k, k);
    _estrella(canvas, destino + const Offset(9, -4), 5 * k, k);
  }

  void _estrella(Canvas canvas, Offset c, double r, double alpha) {
    if (r <= .1 || alpha <= .01) return;
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * .28, c.dy - r * .28)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + r * .28, c.dy + r * .28)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * .28, c.dy + r * .28)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - r * .28, c.dy - r * .28)
      ..close();
    canvas.drawPath(p, Paint()..color = kOroMoneda.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_VueloPainter old) =>
      old.t != t || old.origen != origen || old.destino != destino;
}
