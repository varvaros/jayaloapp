// «PORTADA JAYI» — port del mockup jayalo-main/portada-jayi.html (PO 2026-08-14).
// Fondo del login: gradiente líquido (3 masas que recorren rutas propias) +
// pattern del isotipo en marca de agua (2 capas en diagonales opuestas + vaivén)
// + cabecera (imagotipo, título, claim) + Jayi 3D (webp con alfa) que flota,
// se mece y pestañea. Reemplaza a FONDO PLAYA (portada_animada.dart), que se
// conserva intacto para reutilizarse.
//
// Los números (waypoints, periodos, alphas, posición del párpado) son copia del
// mockup, no invenciones: el ojo de la webp está medido por píxeles (centro
// 423,673 de 1024x1536, diámetro 244) y la imagen se muestra recortada a la
// franja vertical 18%–72%.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import 'jayalo_imagotipo.dart';

/// Waypoint de una masa líquida: instante (0..1), desplazamiento en fracciones
/// del propio diámetro y escala.
class _Wp {
  const _Wp(this.t, this.dx, this.dy, this.s);
  final double t, dx, dy, s;
}

/// Interpola la lista de waypoints en [phase] (0..1) con easing por tramo,
/// como los keyframes ease-in-out del mockup. La lista abre en t=0 y cierra en
/// t=1 con el mismo punto: loop perfecto por construcción.
(double, double, double) _sample(List<_Wp> wps, double phase) {
  for (var i = 0; i < wps.length - 1; i++) {
    final a = wps[i], b = wps[i + 1];
    if (phase <= b.t) {
      final span = b.t - a.t;
      final f = span <= 0 ? 1.0 : Curves.easeInOut.transform((phase - a.t) / span);
      return (
        a.dx + (b.dx - a.dx) * f,
        a.dy + (b.dy - a.dy) * f,
        a.s + (b.s - a.s) * f,
      );
    }
  }
  final last = wps.last;
  return (last.dx, last.dy, last.s);
}

/// Triángulo suavizado 0→1→0 (keyframes 0%/50%/100% con ease-in-out).
double _breathe(double phase) => phase < .5
    ? Curves.easeInOut.transform(phase * 2)
    : Curves.easeInOut.transform(2 - phase * 2);

class PortadaJayi extends StatefulWidget {
  const PortadaJayi({super.key, this.bottomReserve = 0});

  /// Alto (px lógicos) que los botones del login tapan por abajo: Jayi se
  /// centra en el espacio libre por encima. Mismo contrato que el mar limpio
  /// de FONDO PLAYA.
  final double bottomReserve;

  @override
  State<PortadaJayi> createState() => _PortadaJayiState();
}

class _PortadaJayiState extends State<PortadaJayi>
    with SingleTickerProviderStateMixin {
  /// Segundos transcurridos; todos los relojes (47/61/53/44/58/13/4.8/7.3/6.4 s)
  /// derivan de aquí, así que un solo ticker mueve toda la portada.
  final ValueNotifier<double> _t = ValueNotifier(0);
  Ticker? _ticker;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = JayaloMotion.reduced(context);
    if (reduced == _reduced && _ticker != null) return;
    _reduced = reduced;
    _ticker?.dispose();
    _ticker = null;
    if (!reduced) {
      _ticker = createTicker(
          (elapsed) => _t.value = elapsed.inMicroseconds / 1e6)
        ..start();
    } else {
      _t.value = 0; // frame estático, párpado abierto
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _FondoPainter(time: _t)),
        ),
        Column(
          children: [
            const _Cabecera(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.bottomReserve),
                child: Center(child: _Jayi(time: _t)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cabecera: imagotipo + título + claim (texto normal, no título de pantalla).
// ---------------------------------------------------------------------------

class _Cabecera extends StatelessWidget {
  const _Cabecera();
  @override
  Widget build(BuildContext context) {
    // Portada decorativa: la fuente del sistema en gigante no debe exprimir la
    // zona de Jayi (bug 4e8cff1 en las tarjetas del catálogo).
    return SafeArea(
      bottom: false,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
          child: LayoutBuilder(
            builder: (context, box) {
              final logoW = math.min(box.maxWidth * .46, 250.0);
              return Column(
                children: [
                  SizedBox(
                    width: logoW,
                    height: logoW *
                        kImagotipoSize.height /
                        kImagotipoSize.width,
                    child: const CustomPaint(painter: _LogoPainter()),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Todo comienza con una idea',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      // Colores literales del tema claro a propósito: la
                      // portada es arena fija también en modo oscuro.
                      color: JayaloColors.head,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Describe lo que necesitas y proveedores verificados '
                    'encontrarán la solución.',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      fontWeight: FontWeight.w400,
                      color: JayaloColors.foreground.withValues(alpha: .9),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();
  @override
  void paint(Canvas canvas, Size size) =>
      paintImagotipo(canvas, Offset.zero & size);
  @override
  bool shouldRepaint(covariant _LogoPainter old) => false;
}

// ---------------------------------------------------------------------------
// Jayi: la webp 3D recortada (franja 18%–72%), glow, flote, meceo y párpado.
// ---------------------------------------------------------------------------

class _Jayi extends StatelessWidget {
  const _Jayi({required this.time});
  final ValueNotifier<double> time;

  // Ojo medido por píxeles sobre la webp: centro (423,673) de 1024x1536.
  // En la ventana recortada (y de 18% a 72% del alto): x=41.3%, y=47.8%.
  static const _eyeX = 423 / 1024;
  static const _eyeY = (673 / 1536 - .18) / .54;
  static const _lidD = .27; // diámetro del párpado (ojo=23.8% + margen)

  /// Párpado del ciclo de 6.4 s: 0–40% abierto, cierra en 42%, se queda
  /// cerrado hasta 43.5%, abre en 46%. UN parpadeo por ciclo (pedido PO).
  static double _lidY(double phase) {
    const open = -1.05;
    if (phase < .40) return open;
    if (phase < .42) return open + (0 - open) * ((phase - .40) / .02);
    if (phase < .435) return 0;
    if (phase < .46) return 0 + (open - 0) * ((phase - .435) / .025);
    return open;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // Ventana del recorte: proporción 100/81 (1024 × el 54% de 1536).
      final w = math.min(box.maxWidth * .80, box.maxHeight / 0.95);
      final h = w * .81;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheW = math.min((w * dpr).round(), 1024);
      return AnimatedBuilder(
        animation: time,
        builder: (context, _) {
          final t = time.value;
          final float = -_breathe((t % 4.8) / 4.8) * h * .03;
          final tilt = _breathe((t % 7.3) / 7.3) * 1.3 * math.pi / 180;
          return Transform.rotate(
            angle: tilt,
            child: Transform.translate(
              offset: Offset(0, float),
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Glow blanco que despega a Jayi del pattern.
                    Positioned(
                      left: w * .5 - w * .6,
                      top: h * .52 - w * .6,
                      width: w * 1.2,
                      height: w * 1.2,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Color(0xF2FFFFFF),
                              Color(0x99FFFFFF),
                              Color(0x00FFFFFF),
                            ],
                            stops: [0, .45, .68],
                          ),
                        ),
                      ),
                    ),
                    ClipRect(
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: -w * .27, // franja 18%–72% de la imagen
                            width: w,
                            child: Image.asset(
                              'assets/images/jayi-hero.webp',
                              width: w,
                              cacheWidth: cacheW,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                          // Párpado: ventana circular sobre el ojo por la que
                          // baja y sube un degradado más oscuro que el cuerpo.
                          Positioned(
                            left: w * _eyeX - w * _lidD / 2,
                            top: h * _eyeY - w * _lidD / 2,
                            width: w * _lidD,
                            height: w * _lidD,
                            child: ClipOval(
                              child: FractionalTranslation(
                                translation:
                                    Offset(0, _lidY((t % 6.4) / 6.4)),
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF6233D8),
                                        Color(0xFF4E23BB),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Fondo: gradiente líquido + pattern del isotipo (2 capas) con vaivén.
// ---------------------------------------------------------------------------

class _FondoPainter extends CustomPainter {
  _FondoPainter({required this.time}) : super(repaint: time);
  final ValueNotifier<double> time;

  // Rutas del mockup (waypoints en fracciones del diámetro de cada masa).
  static const _ruta1 = [
    _Wp(0, 0, 0, 1),
    _Wp(.18, .52, .38, 1.14),
    _Wp(.38, .18, 1.12, .92),
    _Wp(.58, .68, .64, 1.08),
    _Wp(.78, .08, .26, .96),
    _Wp(1, 0, 0, 1),
  ];
  static const _ruta2 = [
    _Wp(0, 0, 0, 1),
    _Wp(.22, -.58, .42, 1.12),
    _Wp(.46, -.22, .95, .9),
    _Wp(.70, -.66, .12, 1.16),
    _Wp(.86, -.18, -.08, 1.02),
    _Wp(1, 0, 0, 1),
  ];
  static const _ruta3 = [
    _Wp(0, 0, 0, 1),
    _Wp(.26, .48, -.66, 1.1),
    _Wp(.50, .12, -1.24, .94),
    _Wp(.72, .62, -.36, 1.06),
    _Wp(1, 0, 0, 1),
  ];

  // Isotipo del imagotipo: cuerpo 74.4×91.4 con el ojo en (5.75,25.45) y el
  // iris en (24.05,35.9) (jayalo_imagotipo.dart). En el tile grande el iso
  // mide ~72 px de alto, como en el mockup.
  static final Rect _isoBounds = ImagotipoPaths.cuerpo.getBounds();

  void _blob(Canvas canvas, Size size, List<_Wp> ruta, double period,
      double t, Offset baseCenter, double d, Color color, double stop) {
    final (dx, dy, s) = _sample(ruta, (t % period) / period);
    final center = baseCenter + Offset(dx * d, dy * d);
    final r = d / 2 * s;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: [0, stop],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, paint);
  }

  void _iso(Canvas canvas, double x, double y, double rot, double scale,
      Paint cuerpo, Paint ojo, Paint iris) {
    canvas.save();
    canvas.translate(x, y);
    final cx = _isoBounds.width * scale / 2;
    final cy = _isoBounds.height * scale / 2;
    canvas.translate(cx, cy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-cx, -cy);
    canvas.scale(scale);
    canvas.translate(-_isoBounds.left, -_isoBounds.top);
    canvas.drawPath(ImagotipoPaths.cuerpo, cuerpo);
    canvas.save();
    canvas.translate(5.75, 25.45);
    canvas.drawPath(ImagotipoPaths.ojo, ojo);
    canvas.restore();
    canvas.save();
    canvas.translate(24.05, 35.9);
    canvas.drawPath(ImagotipoPaths.iris, iris);
    canvas.restore();
    canvas.restore();
  }

  void _patternLayer(Canvas canvas, Size size,
      {required double tile,
      required double offset,
      required double isoScale,
      required List<(double, double, double)> instances,
      required Paint cuerpo,
      required Paint ojo,
      required Paint iris}) {
    final o = offset % tile;
    for (var x = -tile + o; x < size.width + tile; x += tile) {
      for (var y = -tile + o; y < size.height + tile; y += tile) {
        for (final (ix, iy, rot) in instances) {
          _iso(canvas, x + ix, y + iy, rot, isoScale, cuerpo, ojo, iris);
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;

    // 1) Gradiente líquido (fuera del vaivén, como en el mockup).
    _blob(canvas, size, _ruta1, 47, t, Offset(.18 * w, .5 * w - .14 * h),
        1.00 * w, const Color(0x9EAC8EF4), .68); // rgba(172,142,244,.62)
    _blob(canvas, size, _ruta2, 61, t, Offset(.90 * w, .55 * w + .06 * h),
        1.10 * w, const Color(0x80ECC48E), .66); // rgba(236,196,142,.5)
    _blob(canvas, size, _ruta3, 53, t, Offset(.27 * w, 1.26 * h - .45 * w),
        0.90 * w, const Color(0x8CBEA0F8), .70); // rgba(190,160,248,.55)

    // 2) Pattern del isotipo con el vaivén de 13 s.
    final sway = _breathe((t % 13) / 13);
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(1 + .015 * sway);
    canvas.translate(-w / 2 + 12 * sway, -h / 2);

    const violeta = Color(0xFF7147F2);
    // Capa lejana (tile 150, deriva arriba-izquierda, 58 s; opacidad de capa
    // .55 ya multiplicada en las alphas).
    _patternLayer(
      canvas,
      size,
      tile: 150,
      offset: -((t % 58) / 58) * 150,
      isoScale: (72 / _isoBounds.height) * .62,
      instances: const [(16, 16, 9), (91, 91, -9)],
      cuerpo: Paint()..color = violeta.withValues(alpha: .04),
      ojo: Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .28),
      iris: Paint()..color = violeta.withValues(alpha: .06),
    );
    // Capa cercana (tile 230, deriva abajo-derecha, 44 s).
    _patternLayer(
      canvas,
      size,
      tile: 230,
      offset: ((t % 44) / 44) * 230,
      isoScale: 72 / _isoBounds.height,
      instances: const [(24, 24, -8), (139, 139, 8)],
      cuerpo: Paint()..color = violeta.withValues(alpha: .10),
      ojo: Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .55),
      iris: Paint()..color = violeta.withValues(alpha: .16),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FondoPainter old) => false; // repaint: time
}
