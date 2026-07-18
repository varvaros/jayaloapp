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
import '../../core/motion.dart';
import '../../domain/phase.dart';
import '../shell/floating_nav_bar.dart';
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

/// La tarjeta que respira: radius 16, margen 16×4, transición de color suave
/// (así el paso de "viva" a neutra se desvanece, nunca salta).
/// [tint] nulo = tarjeta neutra sobre la superficie de card.
///
/// Doctrina de movimiento: si es tocable, responde al dedo AL INSTANTE —
/// se encoge levemente mientras está presionada (además del ripple) y vuelve
/// suave al soltar. Con "reducir animaciones" el feedback queda solo en el
/// ripple del sistema.
class JayaloCard extends StatefulWidget {
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
  State<JayaloCard> createState() => _JayaloCardState();
}

class _JayaloCardState extends State<JayaloCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pressable = widget.onTap != null && !JayaloMotion.reduced(context);
    return Padding(
      padding: widget.margin,
      child: AnimatedScale(
        scale: _pressed ? JayaloMotion.pressedScale : 1,
        duration: JayaloMotion.fast,
        curve: JayaloMotion.enter,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            // onHighlightChanged dispara al presionar/soltar/cancelar — es la
            // señal más temprana que da InkWell, sin retrasar el onTap.
            onHighlightChanged:
                pressable ? (v) => setState(() => _pressed = v) : null,
            child: AnimatedContainer(
              duration: JayaloMotion.page,
              curve: Curves.easeOut,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.tint ?? cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: widget.child,
            ),
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
        // Caso especial (spec navbar-flotante §Detalle): este ListView es
        // interno del widget y las 11 pantallas del shell que lo usan para
        // su estado vacío no pueden pasarle su propio padding — se reserva
        // aquí, una sola vez, para todas.
        padding: EdgeInsets.only(bottom: navBarReservedSpace(context)),
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

/// "F1 · Rellenos suaves" (elegida por el PO): campos sin borde con fondo
/// gris suave y radius 12. La receta única de TextField de la app.
InputDecoration filledField(BuildContext context, String label,
        {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

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
/// 40ms por ítem, tope en 14 para no eternizar listas largas. Con "reducir
/// animaciones" del sistema los ítems aparecen quietos.
extension CascadeIn on Widget {
  Widget cascadeIn(int index, {Key? key}) => Builder(
        key: key,
        builder: (context) {
          if (JayaloMotion.reduced(context)) return this;
          final delay = (40 * min(index, 14)).ms;
          return animate()
              .fadeIn(duration: JayaloMotion.base, delay: delay)
              .slideY(
                  begin: .10,
                  end: 0,
                  duration: JayaloMotion.base,
                  delay: delay,
                  curve: JayaloMotion.enter);
        },
      );
}

/// Skeleton con la silueta de la tarjeta que respira (ícono 40×40 + dos
/// líneas), con un brillo que recorre en loop. Decisión PO 2026-07-18: el
/// skeleton se usa SOLO en /notifications (su spec original lo pedía); el
/// resto de la app carga con la mascota [JayaloLoaderBlock].
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget block({double? width, required double height, double radius = 6}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          block(width: 40, height: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(height: 14),
                const SizedBox(height: 6),
                FractionallySizedBox(
                    widthFactor: .6, child: block(height: 12)),
              ],
            ),
          ),
        ]),
      ),
    );
    if (JayaloMotion.reduced(context)) return card;
    return card
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
            duration: 1200.ms,
            color: cs.onSurface.withValues(alpha: .08));
  }
}

/// Lista de skeletons para el estado de carga de una pantalla de lista.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [for (var i = 0; i < count; i++) const SkeletonCard()],
      );
}
