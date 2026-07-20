import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/brand.dart';
import '../shared/brand_kit.dart';

/// Éxito al publicar una solicitud (spec 2026-07-19-solicitud-gamificada):
/// mascota celebrando + confeti breve + botón para ver la solicitud ya en la
/// lista. Reemplaza al SnackBar que la navbar tapaba.
class RequestPublishedView extends StatelessWidget {
  const RequestPublishedView({super.key, required this.onSeeRequests});
  final VoidCallback onSeeRequests;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // La mascota CELEBRANDO (ojo feliz "∩", sonrisón, saltitos y
            // antenas vibrando) — entra con un pop y sigue de fiesta mientras
            // cae el confeti.
            const JayaloMascotFace(size: 96, mood: MascotMood.celebrate)
                .animate()
                .scale(
                    begin: const Offset(.7, .7),
                    end: const Offset(1, 1),
                    duration: 250.ms,
                    curve: Curves.easeOutBack),
            const SizedBox(height: 20),
            Text('¡Tu solicitud está publicada!',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: jayaloHead(context))),
            const SizedBox(height: 8),
            Text('Los proveedores empezarán a enviarte ofertas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: onSeeRequests,
                child: const Text('Ver mis solicitudes')),
          ]),
        ),
      ),
    ]);
  }
}

/// Confeti propio (sin dependencias): ~40 partículas de la paleta cayendo con
/// giro, entrada escalonada y fundido, una sola vez, ~1.8 s (el de 900 ms se
/// perdía — feedback PO). Nada queda animando después.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
                _c.value, Theme.of(context).colorScheme.primary),
            size: Size.infinite),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.primary);
  final double t;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    // Semilla fija: la misma lluvia en cada frame (solo avanza `t`).
    final rnd = Random(7);
    final colors = [
      primary,
      const Color(0xFFEF9F27),
      const Color(0xFFD4537E),
      const Color(0xFF1D9E75),
    ];
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final drift = (rnd.nextDouble() - .5) * 90;
      final y0 = size.height * (.02 + rnd.nextDouble() * .2);
      final dist = size.height * (.35 + rnd.nextDouble() * .35);
      final spinSeed = rnd.nextDouble() * 6.3;
      final spinDir = rnd.nextBool() ? 6 : -6;
      final s = 6.0 + rnd.nextDouble() * 6;
      // Entrada escalonada: cada partícula arranca con su propio retraso y
      // vive su [0,1] local — la lluvia se siente continua, no un golpe único.
      final delay = rnd.nextDouble() * .35;
      final tl = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (tl <= 0) continue;
      final fall = Curves.easeIn.transform(tl);
      final fade = (1 - Curves.easeIn.transform(tl)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x + drift * tl, y0 + dist * fall);
      canvas.rotate(spinSeed + tl * spinDir);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: s, height: s * .6),
              const Radius.circular(2)),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
