import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/brand.dart';
import '../shared/brand_kit.dart';
import '../shared/celebration.dart' show ConfettiBurst;

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

// ConfettiBurst se movió a `../shared/celebration.dart` (se reusa también en la
// oferta enviada). Se importa arriba.
