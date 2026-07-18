/// Kit compartido de la línea gráfica "tarjetas que respiran".
///
/// TODO el estilo sale de la pantalla `/notifications` aprobada por el PO
/// (ver `docs/superpowers/plans/2026-07-18-uiux-resto-pantallas.md` §1):
/// estos widgets consolidan esos números exactos (radius 16, padding 12,
/// transición 300ms, cascada 250ms/40ms…) para que el resto de pantallas
/// no los re-derive ni los desafine.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/brand.dart';
import '../../domain/phase.dart';
import 'jayalo_loader.dart';

/// Tono de estado por fase de solicitud — el mismo mapa que usa la web con
/// sus `--status-*` (y que notificaciones usa por familia). Única fuente:
/// nada de `Colors.amber`/`green` sueltos para pintar fases.
StatusTone toneFor(BuildContext context, RequestPhase phase) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (phase) {
    RequestPhase.waiting =>
      dark ? JayaloStatus.pendingDark : JayaloStatus.pendingLight,
    RequestPhase.withOffers =>
      dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight,
    RequestPhase.accepted =>
      dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
    RequestPhase.unlocked =>
      dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight,
    RequestPhase.completed =>
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
  };
}

/// La tarjeta que respira: radius 16, margen 16×4, transición de color de
/// 300ms (así el paso de "viva" a neutra se desvanece, nunca salta).
/// [tint] nulo = tarjeta neutra sobre la superficie de card.
class JayaloCard extends StatelessWidget {
  const JayaloCard({
    super.key,
    required this.child,
    this.onTap,
    this.tint,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? tint;
  final EdgeInsetsGeometry padding;

  /// Margen exterior estándar de lista; pásalo en cero cuando la tarjeta vive
  /// dentro de un contenedor que ya trae su propio padding.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: padding,
            decoration: BoxDecoration(
              color: tint ?? cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Píldora de estado: fondo teñido + tinta del mismo tono, radius 99.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: tone.ink),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tone.ink)),
          ],
        ),
      );
}

/// Encabezado de sección — el mismo estilo de los títulos de día de
/// notificaciones ("Hoy", "Ayer").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

/// Estado vacío con la mascota "buscando algo que no encontró". Va dentro de
/// un ListView para que el pull-to-refresh funcione también en vacío; en las
/// pestañas raíz pásale el `homeScrollController` como [controller].
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.ctaLabel,
    this.onCta,
    this.controller,
  });

  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ListView(
        controller: controller,
        children: [
          const SizedBox(height: 100),
          const Center(child: JayaloMascot(size: 76)),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (ctaLabel != null)
            Center(
              child: FilledButton(
                onPressed: onCta,
                child: Text(ctaLabel!),
              ),
            ),
        ],
      );
}

/// Error amable + Reintentar — patrón único de error de la app.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.onRetry,
    this.message = 'No se pudo cargar',
  });

  final Future<void> Function() onRetry;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}

/// Cascada de entrada de listas: fade + slide 10% hacia arriba con stagger de
/// 40ms por ítem, tope en 14 para no eternizar listas largas. Respeta
/// "reducir animaciones" vía flutter_animate (Animate.restartOnHotReload no
/// aplica; disableAnimations lo corta el propio framework en tests).
extension CascadeIn on Widget {
  Widget cascadeIn(int index, {Key? key}) => animate(key: key)
      .fadeIn(duration: 250.ms, delay: (40 * min(index, 14)).ms)
      .slideY(
          begin: .10,
          end: 0,
          duration: 250.ms,
          delay: (40 * min(index, 14)).ms,
          curve: Curves.easeOutCubic);
}
