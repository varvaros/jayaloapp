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

// Re-exporta el loader para que cualquier pantalla que ya importa el kit pueda
// usar `JayaloLoaderBlock` (la mascota) en sus estados de carga sin un import
// extra — decisión PO: el skeleton solo se queda en Notificaciones.
export 'jayalo_loader.dart';

/// Tono de estado por fase de solicitud — el mismo mapa que usa la web con
/// sus `--status-*` (y que notificaciones usa por familia). Única fuente:
/// nada de `Colors.amber`/`green` sueltos para pintar fases.
/// Sombra cálida de las tarjetas que flotan (doctrina mockups: "elevación solo
/// por sombra suave cálida", `0 8px 26px rgba(93,72,38,.09)`). En oscuro la
/// receta cálida se apaga sobre fondo oscuro, así que se cae a una sombra
/// neutra tenue del propio esquema.
List<BoxShadow> jayaloCardShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: dark
          ? Theme.of(context).colorScheme.shadow.withValues(alpha: .18)
          : JayaloColors.warmShadow,
      blurRadius: 26,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Radio de las tarjetas de la app (mockups aprobados usan 24 en las tarjetas
/// de lista; se adopta 20 como el redondeo premium de la línea gráfica, un pelo
/// más contenido que el del lienzo por el padding menor de la app).
const double kCardRadius = 20;

/// Color del badge de estado de una OFERTA del proveedor (pedido PO
/// 2026-07-21): `pending` ("Ya ofertaste") = ÁMBAR (esperando decisión);
/// `accepted` ("Aceptada") = VERDE (te eligieron); `unlocked`/`completed`
/// ("Desbloqueado") = VIOLETA (ya pagaste y tienes el contacto). Un solo lugar
/// para que la bandeja y Mis ofertas usen exactamente los mismos tonos.
StatusTone offerBadgeTone(BuildContext context, String state) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (state) {
    'accepted' => dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight,
    'unlocked' ||
    'completed' =>
      dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight,
    'rejected' =>
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    _ => dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
  };
}

StatusTone toneFor(BuildContext context, RequestPhase phase) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (phase) {
    RequestPhase.waiting =>
      dark ? JayaloStatus.pendingDark : JayaloStatus.pendingLight,
    RequestPhase.withOffers =>
      dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight,
    // "Oferta aceptada" en AZUL claro (pedido PO 2026-07-21; el ámbar queda
    // para espera/dinero).
    RequestPhase.accepted =>
      dark ? JayaloStatus.offerAcceptedDark : JayaloStatus.offerAcceptedLight,
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
            borderRadius: BorderRadius.circular(kCardRadius),
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
                borderRadius: BorderRadius.circular(kCardRadius),
                // Sin borde: la tarjeta flota solo por la sombra cálida.
                boxShadow: jayaloCardShadow(context),
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
                    fontWeight: FontWeight.w600,
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
          // Eyebrow en versalitas con tracking, como los `.shead` del mockup
          // ("CÓMO TE CALIFICAN", "TU NEGOCIO").
          text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

/// Cifra grande + etiqueta. La reusan Reputación y Estadísticas — movida
/// aquí desde `reputation_screen.dart` (I3): una pantalla de proveedor
/// (`stats_screen.dart`) no debe importar una de cliente
/// (`reputation_screen.dart`), y este archivo es el sitio único de los
/// widgets compartidos entre pantallas.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: cs.primary, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context),
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
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
/// líneas), con un brillo que recorre en loop. Decisión PO 2026-07-19 (3ª
/// pasada estética, REVIERTE la del 07-18 "solo /notifications"): los
/// skeletons son el estado de carga de TODAS las pantallas con datos — la
/// mascota [JayaloLoaderBlock] hacía sentir la carga lenta. La mascota
/// sigue viva como identidad en los demás usos de [JayaloLoader].
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
          borderRadius: BorderRadius.circular(kCardRadius),
          boxShadow: jayaloCardShadow(context),
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

/// El gesto "mantener presionado" cubre las DOS confirmaciones deliberadas de
/// la app; el TONO las separa visualmente (doctrina PO 2026-07-20 "hold en
/// ambos, con distinción visual"):
///
///   • [paid] — desbloquear contacto: GASTA créditos → violeta de acción + 🔒.
///   • [free] — aceptar una oferta: es GRATIS → verde de éxito + ✓.
///
/// El default es [paid] para no tocar los desbloqueos ya existentes.
enum HoldToConfirmTone { paid, free }

/// Confirmación deliberada mantenida (equivalente nativo del hold-to-confirm
/// de la web). Extraída de `my_offers_screen.dart` (Task 9) para reusarla en
/// el desbloqueo de intereses de producto y, con [HoldToConfirmTone.free], en
/// la aceptación de ofertas.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton(
      {super.key,
      required this.onConfirmed,
      this.tone = HoldToConfirmTone.paid,
      this.label});

  final Future<void> Function() onConfirmed;
  final HoldToConfirmTone tone;

  /// Copy del botón; si es null cae al texto por defecto del [tone].
  final String? label;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: JayaloMotion.holdConfirm)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onConfirmed();
        });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final free = widget.tone == HoldToConfirmTone.free;
    // El color separa lo pagado (violeta de acción) de lo gratis (verde de
    // éxito). El texto y el icono lo refuerzan.
    // Botón GRANDE de color sólido (violeta pagado / verde gratis) que se
    // RELLENA con una versión CLARA del mismo color al mantener presionado
    // (pedido PO 2026-07-22): base = color fuerte, progreso = color claro,
    // texto e ícono SIEMPRE en blanco. La barra clara crece de izq. a der.
    final fill = free
        ? (dark ? JayaloColors.dSuccess : JayaloColors.success)
        : cs.primary;
    final light = Color.lerp(fill, Colors.white, .5)!;
    final icon = free ? Icons.check_rounded : Icons.lock_outline_rounded;
    final label = widget.label ??
        (free
            ? 'Mantén presionado para aceptar'
            : 'Mantén presionado para desbloquear');
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value.clamp(0.0, 1.0);
          // Aro de progreso ALREDEDOR del botón (pedido PO 2026-07-21): se
          // pinta fuera del ClipRRect y recorre el perímetro al ritmo del
          // relleno; el Padding deja el hueco para que respire.
          return CustomPaint(
            foregroundPainter:
                _HoldRingPainter(progress: t, color: fill),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  Container(height: 58, color: fill), // base sólida
                  // ANCLADO a la izquierda (pedido PO): antes el Stack con
                  // alignment center centraba la caja que crece y el relleno
                  // parecía expandirse del centro hacia los lados.
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: t,
                        heightFactor: 1,
                        child: Container(color: light), // se llena claro
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 19, color: Colors.white),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Borde de progreso del [HoldToConfirmButton]: traza el perímetro redondeado
/// (arranca arriba a la izquierda, en sentido horario) en proporción al hold.
/// Vive FUERA del botón — el Padding del botón le deja un hueco de 4px.
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const stroke = 2.5;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2),
      const Radius.circular(20),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Segmentado CÁLIDO a ancho completo (estilo `.seg` del mockup): pista arena
/// (`#F1ECE1`), segmento activo = tarjeta blanca con sombra suave, texto activo
/// en el tinta de la marca. Es la versión "sobre el cuerpo cálido" del
/// [HeaderSegmented] (que vive sobre el violeta): se usa para pestañas que
/// están BAJO el header (p. ej. Abierto/Completado/No concretado en Mensajes),
/// donde el `SegmentedButton` de Material se veía frío y ajeno a la línea.
class PillSegmented extends StatelessWidget {
  const PillSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Pista = neutro de la marca (`secondary`, hoy gris frío) en claro; en
    // oscuro cae a la superficie más contenida del esquema. Antes clavaba el
    // arena `#F1ECE1` a mano — ahora sale del token para seguir la paleta.
    final track = dark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : JayaloColors.secondary;
    final activeBg = dark
        ? Theme.of(context).colorScheme.surfaceContainerLowest
        : Colors.white;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: i == index ? activeBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: i == index ? jayaloCardShadow(context) : null,
                  ),
                  child: Text(
                    options[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          i == index ? FontWeight.w600 : FontWeight.w500,
                      color: i == index
                          ? jayaloHead(context)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cinta diagonal "POR MAYOR" que cruza la esquina de la miniatura de una
/// solicitud (pedido PO 2026-07-21, referencia: ribbon "NEW" de esquina).
/// Reemplaza al sticker-pastilla anterior. Va DENTRO del `Stack` de la
/// miniatura y se recorta a su mismo radio; usa el [Banner] nativo de
/// Flutter (el del listón "DEBUG"), así que no hay geometría a mano.
class WholesaleRibbon extends StatelessWidget {
  const WholesaleRibbon({super.key, required this.radius});

  /// Radio de la miniatura sobre la que se posa (para que el recorte calce).
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: const Banner(
            message: 'POR MAYOR',
            // Esquina superior DERECHA del placeholder — el lado que da al
            // título (pedido PO 2026-07-22; antes topStart/izquierda).
            location: BannerLocation.topEnd,
            color: Color(0xFF6D28D9), // violeta pleno, alto contraste
            textStyle: TextStyle(
                color: Colors.white,
                fontSize: 6.5,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: .3),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Visor de fotos a pantalla completa: fondo negro, pellizco para zoom
/// (InteractiveViewer), desliza entre fotos si hay varias; se cierra con un
/// tap, con la X o con el atrás del sistema. Va por el navigator RAÍZ para
/// cubrir también la navbar del shell.
Future<void> showPhotoViewer(BuildContext context, List<String> urls,
        {int initialIndex = 0}) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) =>
          _PhotoViewer(urls: urls, initialIndex: initialIndex),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ));

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          PageView.builder(
            controller: _page,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.network(widget.urls[i],
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          size: 64,
                          color: Colors.white38)),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.white24,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child:
                          Icon(Icons.close, size: 22, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.urls.length; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                i == _index ? Colors.white : Colors.white38,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// SnackBar de marca visible por ENCIMA de la barra flotante.
///
/// El SnackBar estándar sale pegado al borde inferior y la navbar flotante lo
/// tapa (bug PO 2026-07-19: "no veo aviso de que fue enviado"). Flotante con
/// margen inferior = espacio reservado de la barra + respiro.
void showJayaloToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      margin:
          EdgeInsets.fromLTRB(16, 0, 16, navBarReservedSpace(context) + 12),
    ));
}
