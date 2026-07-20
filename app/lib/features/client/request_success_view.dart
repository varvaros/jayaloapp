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
            const JayaloMascot(size: 96).animate().scale(
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

/// Confeti propio (sin dependencias): ~26 partículas de la paleta cayendo con
/// giro y fundido, una sola vez, ~900 ms. Nada queda animando después.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
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
    final fade = (1 - t).clamp(0.0, 1.0);
    final fall = Curves.easeIn.transform(t);
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * size.width;
      final drift = (rnd.nextDouble() - .5) * 70;
      final y0 = size.height * (.08 + rnd.nextDouble() * .18);
      final dist = size.height * (.3 + rnd.nextDouble() * .3);
      final spin = rnd.nextDouble() * 6.3 + t * (rnd.nextBool() ? 5 : -5);
      final s = 5 + rnd.nextDouble() * 5;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x + drift * t, y0 + dist * fall);
      canvas.rotate(spin);
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
