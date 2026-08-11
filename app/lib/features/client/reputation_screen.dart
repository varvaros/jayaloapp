import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

/// Umbral de la web (`src/lib/responseTime.ts`): con menos de 5 respuestas
/// medidas la mediana no representa nada y se omite por completo.
const kMinResponseSamples = 5;

class ReputationScreen extends StatefulWidget {
  const ReputationScreen({super.key});
  @override
  State<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends State<ReputationScreen> {
  late Future<Map<String, dynamic>?> _load = customerReputation();

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
    _load = customerReputation();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const VioletHeader(
          leading: HeaderLeading(),
          title: 'Mi reputación',
          actions: [HeaderBell()],
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _load,
            builder: (context, snap) {
              if (snap.hasError) {
                return ErrorRetry(onRetry: () async => _refetch());
              }
              if (!snap.hasData &&
                  snap.connectionState != ConnectionState.done) {
                return const JayaloLoaderBlock();
              }
              return ReputationView(data: snap.data ?? const {});
            },
          ),
        ),
      ],
    ),
  );
}

/// Solo dibuja. Recibe el mapa crudo de `get_customer_reputation`.
///
/// StatefulWidget solo para poseer su propio ScrollController (con dispose
/// correcto): esta pantalla NO es la home, así que no debe compartir
/// `homeScrollController` con `MyRequestsScreen` — el `AnimatedSwitcher` del
/// shell mantiene ambas pestañas montadas ~250ms durante el cambio, y dos
/// `ScrollPosition` adjuntas al mismo controller hacen que `BackGuard` lance
/// `StateError` al leer `c.offset` en cualquier ATRÁS.
class ReputationView extends StatefulWidget {
  const ReputationView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<ReputationView> createState() => _ReputationViewState();
}

class _ReputationViewState extends State<ReputationView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;
    final purchases = (data['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (data['requests_count'] as num?)?.toInt() ?? 0;
    final samples = (data['response_samples'] as num?)?.toInt() ?? 0;
    final minutes = (data['median_response_minutes'] as num?)?.toInt();
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;

    if (reviews == 0 && purchases == 0 && requests == 0) {
      return EmptyState(
        controller: _scrollController,
        message:
            'Todavía no tienes reputación.\n\n'
            'Se construye sola: pide lo que necesitas, completa tus compras '
            'y califica a quien te atendió. Los proveedores la verán y te '
            'responderán con más confianza.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    // Mockup aprobado PO 2026-08-11: una tarjeta de la plantilla por dato
    // (pastilla de ícono, etiqueta arriba, número protagonista), la
    // calificación enseña sus estrellas de una vez, "Ver" lleva a la lista de
    // solicitudes, y el vacío de abajo lo llena Jayi abrazando la estrella.
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        const SectionHeader(text: 'TU CALIFICACIÓN'),
        _StatTile(
          icon: Icons.star_rounded,
          label: 'CALIFICACIÓN',
          value: rating > 0 ? rating.toStringAsFixed(1) : '—',
          suffix: reviews == 1 ? ' · 1 reseña' : ' · $reviews reseñas',
          trailing: rating > 0 ? _Stars(rating: rating) : null,
        ).cascadeIn(0),
        _StatTile(
          icon: Icons.shopping_bag_outlined,
          label: 'COMPRAS COMPLETADAS',
          value: '$purchases',
        ).cascadeIn(1),
        const SectionHeader(text: 'TU ACTIVIDAD'),
        _StatTile(
          icon: Icons.receipt_long_outlined,
          label: 'SOLICITUDES HECHAS',
          value: '$requests',
          trailing: _VerPill(onTap: () => context.go('/client')),
        ).cascadeIn(2),
        if (samples >= kMinResponseSamples && minutes != null)
          JayaloCard(
            child: Row(
              children: [
                Icon(Icons.schedule, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Regularmente respondes en ${_humanMinutes(minutes)}',
                  ),
                ),
              ],
            ),
          ).cascadeIn(3),
        // Jayi abrazando la estrella (mockup aprobado): el hueco muerto bajo
        // las tarjetas se vuelve la explicación de cómo crece la reputación.
        const SizedBox(height: 22),
        const Center(child: _JayiEstrella()),
        const SizedBox(height: 10),
        Center(
          child: Text('Tu reputación crece con cada compra',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
        ),
        const SizedBox(height: 5),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              'Completa una solicitud y califica al proveedor: los '
              'proveedores confían más en clientes con historial.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de estadística con el molde de la plantilla (pastilla de ícono,
/// etiqueta tenue arriba, valor protagonista debajo). `suffix` va pegado al
/// valor en tono tenue («· 1 reseña»).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    this.value,
    this.suffix,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? suffix;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: value ?? ''),
                  if (suffix != null)
                    TextSpan(
                        text: suffix,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurfaceVariant)),
                ]),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context)),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// Las cinco estrellas de la calificación, llenas según el redondeo.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = rating.round().clamp(0, 5);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 5; i++)
        Icon(Icons.star_rounded,
            size: 15,
            color: i < filled ? const Color(0xFFF2B705) : cs.outlineVariant),
    ]);
  }
}

class _VerPill extends StatelessWidget {
  const _VerPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text('Ver',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: cs.primary)),
      ),
    );
  }
}

/// Jayi abrazando una estrella (mockup aprobado PO 2026-08-11, v4): se mece
/// con ella, la APRIETA —la estrella se achucha y saltan tres chispas en
/// escalera— y el ojo único pestañea dos veces. Anatomía canónica de
/// `mascot.png`: cuerpo cuadrado redondeado, UN ojo con la pupila
/// abajo-derecha, dos antenas cortas; los bracitos con codo son el accesorio
/// de esta escena. Mismo patrón que los otros Jayi: UN controller de 4,8 s
/// (sincronía gratis) y frame fijo en tests / «reducir movimiento».
class _JayiEstrella extends StatefulWidget {
  const _JayiEstrella();

  @override
  State<_JayiEstrella> createState() => _JayiEstrellaState();
}

class _JayiEstrellaState extends State<_JayiEstrella>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800));

  /// `Platform.environment` y no `bool.fromEnvironment`: ese dart-define NO
  /// está definido bajo `flutter test` (gotcha documentado en
  /// `conversations_screen.dart`).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _fx.stop();
    } else if (!_fx.isAnimating) {
      _fx.repeat();
    }
  }

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estatico = _enTest || JayaloMotion.reduced(context);
    return AnimatedBuilder(
      animation: _fx,
      builder: (_, _) => CustomPaint(
        key: const ValueKey('jayi_estrella'),
        size: const Size(156, 152),
        painter: _JayiEstrellaPainter(t: _fx.value, estatico: estatico),
      ),
    );
  }
}

class _JayiEstrellaPainter extends CustomPainter {
  _JayiEstrellaPainter({required this.t, required this.estatico});

  /// 0..1 del ciclo de 4,8 s.
  final double t;

  /// Frame fijo: abrazo a medio apretón con las chispas visibles.
  final bool estatico;

  static const _cuerpoA = Color(0xFF7E56F5);
  static const _cuerpoB = Color(0xFF6438E8);
  static const _estrella = Color(0xFFFFC93C);
  static const _estrellaBorde = Color(0xFFE8A814);

  /// Vaivén del mockup (grados en los hitos 0/.2/.4/.62/.8/1).
  static const _swayT = [0.0, .2, .4, .62, .8, 1.0];
  static const _swayV = [0.0, -2.5, 2.0, -1.5, 1.0, 0.0];

  double get _sway {
    if (estatico) return 0;
    for (var i = 1; i < _swayT.length; i++) {
      if (t <= _swayT[i]) {
        final u = (t - _swayT[i - 1]) / (_swayT[i] - _swayT[i - 1]);
        final s = u * u * (3 - 2 * u); // smoothstep
        return _swayV[i - 1] + (_swayV[i] - _swayV[i - 1]) * s;
      }
    }
    return 0;
  }

  /// El APRETÓN (0..1): sube .32→.42, sostiene hasta .55, baja a .68.
  double get _apreton {
    if (estatico) return .55;
    double ramp(double a, double b) {
      final u = ((t - a) / (b - a)).clamp(0.0, 1.0);
      return u * u * (3 - 2 * u);
    }

    if (t < .32 || t > .68) return 0;
    if (t < .42) return ramp(.32, .42);
    if (t <= .55) return 1;
    return 1 - ramp(.55, .68);
  }

  /// Escala vertical del ojo: doble pestañeo en .83 y .91.
  double get _ojo {
    if (estatico) return 1;
    var sy = 1.0;
    for (final b in [.83, .91]) {
      final u = (t - b).abs() / .02;
      if (u < 1) sy = math.min(sy, .08 + .92 * u);
    }
    return sy;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 150, size.height / 152);
    final s = _apreton;

    // Vaivén de toda la escena, anclado a los pies.
    canvas.translate(75, 128);
    canvas.rotate(_sway * math.pi / 180);
    canvas.translate(-75, -128);

    // Sombra (fuera del apretón: los pies no se mueven).
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(75, 140), width: 72, height: 12),
        Paint()..color = const Color(0xFF3E3560).withValues(alpha: .08));

    // Apretón: cuerpo + estrella + brazos se comprimen juntos.
    canvas.save();
    canvas.translate(75, 92);
    canvas.scale(1 + .05 * s, 1 - .05 * s);
    canvas.translate(-75, -92);

    final violeta = Paint()..color = _cuerpoB;

    // Antenas cortas.
    final antena = Paint()
      ..color = _cuerpoB
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(66, 42)
          ..quadraticBezierTo(64, 34, 57, 30),
        antena);
    canvas.drawPath(
        Path()
          ..moveTo(84, 42)
          ..quadraticBezierTo(86, 34, 93, 30),
        antena);

    // Cuerpo: cuadrado redondeado con el degradado de marca.
    const cuerpo = Rect.fromLTWH(37, 40, 76, 76);
    canvas.drawRRect(
        RRect.fromRectAndRadius(cuerpo, const Radius.circular(26)),
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_cuerpoA, _cuerpoB])
              .createShader(cuerpo));

    // Ojo único (pestañea): blanco grande, pupila abajo-derecha.
    canvas.save();
    canvas.translate(62, 72);
    canvas.scale(1, _ojo);
    canvas.translate(-62, -72);
    canvas.drawCircle(const Offset(62, 72), 16, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(68, 77), 6, violeta);
    canvas.restore();

    // Estrella grande abrazada al frente: rota y se achucha con el apretón.
    canvas.save();
    canvas.translate(75, 108);
    canvas.rotate((-8 - 5 * s) * math.pi / 180);
    canvas.scale(1 - .13 * s);
    canvas.translate(-75, -108);
    final star = Path()
      ..moveTo(75, 78)
      ..lineTo(81.7, 92.3)
      ..lineTo(97.4, 94.2)
      ..lineTo(85.8, 105)
      ..lineTo(88.9, 120.4)
      ..lineTo(75, 112.7)
      ..lineTo(61.1, 120.4)
      ..lineTo(64.2, 105)
      ..lineTo(52.6, 94.2)
      ..lineTo(68.3, 92.3)
      ..close();
    canvas.drawPath(star, Paint()..color = _estrella);
    canvas.drawPath(
        star,
        Paint()
          ..color = _estrellaBorde
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();

    // Brazos CON CODO por delante de la estrella: bajan rectos del hombro,
    // quiebran y la envuelven. Aprietan rotando desde el hombro.
    final brazo = Paint()
      ..color = _cuerpoB
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void arm(Offset hombro, double dir) {
      canvas.save();
      canvas.translate(hombro.dx, hombro.dy);
      canvas.rotate(dir * 8 * s * math.pi / 180);
      canvas.translate(-hombro.dx, -hombro.dy);
      final p = Path()
        ..moveTo(hombro.dx, hombro.dy)
        ..lineTo(hombro.dx + dir * 8, 106)
        ..quadraticBezierTo(
            hombro.dx + dir * 14, 114, 75 - dir * 5, 116);
      canvas.drawPath(p, brazo);
      canvas.restore();
    }

    arm(const Offset(38, 88), 1);
    arm(const Offset(112, 88), -1);

    canvas.restore(); // fin del apretón

    // Chispas del apretón, en escalera (.12 s y .22 s de retardo).
    for (final (i, c) in const [
      (0, Offset(34, 72)),
      (1, Offset(122, 62)),
      (2, Offset(120, 108)),
    ]) {
      final (op, esc) = _chispa(i * .025);
      if (op <= 0) continue;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(esc);
      final d = Path()
        ..moveTo(0, -6)
        ..lineTo(1.7, -1.7)
        ..lineTo(6, 0)
        ..lineTo(1.7, 1.7)
        ..lineTo(0, 6)
        ..lineTo(-1.7, 1.7)
        ..lineTo(-6, 0)
        ..lineTo(-1.7, -1.7)
        ..close();
      canvas.drawPath(
          d, Paint()..color = _estrella.withValues(alpha: op));
      canvas.restore();
    }
  }

  /// Opacidad y escala de una chispa con su retardo: nace al arrancar el
  /// apretón (.38), pica a un tercio y se apaga.
  (double, double) _chispa(double delay) {
    if (estatico) return (.9, 1);
    final u = (t - .38 - delay) / .18;
    if (u < 0 || u > 1) return (0, 0);
    if (u < .33) {
      final v = u / .33;
      return (v, .2 + .95 * v);
    }
    final v = (u - .33) / .67;
    return (1 - v, 1.15 - .75 * v);
  }

  @override
  bool shouldRepaint(_JayiEstrellaPainter old) =>
      old.t != t || old.estatico != estatico;
}

/// "45 minutos" / "unas 2 horas" / "1 día" — nunca "min" ni "h" abreviados:
/// el público de la app lee palabras, no unidades.
String _humanMinutes(int m) {
  if (m < 60) return '$m minutos';
  final horas = (m / 60).round();
  if (horas < 24) return horas == 1 ? 'una hora' : 'unas $horas horas';
  final dias = (horas / 24).round();
  return dias == 1 ? 'un día' : '$dias días';
}
