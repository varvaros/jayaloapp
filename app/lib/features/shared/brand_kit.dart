/// Kit compartido de la línea gráfica "tarjetas que respiran".
///
/// TODO el estilo sale de la pantalla `/notifications` aprobada por el PO
/// (ver `docs/superpowers/plans/2026-07-18-uiux-resto-pantallas.md` §1):
/// estos widgets consolidan esos números exactos (radius 16, padding 12,
/// transición 300ms, cascada 250ms/40ms…) para que el resto de pantallas
/// no los re-derive ni los desafine.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../domain/phase.dart';
import '../shell/floating_nav_bar.dart';
import 'onboarding_store.dart';
import 'jayalo_loader.dart';

// Re-exporta el loader para que cualquier pantalla que ya importa el kit pueda
// usar `JayaloLoaderBlock` (la mascota) en sus estados de carga sin un import
// extra — decisión PO: el skeleton solo se queda en Notificaciones.
export 'jayalo_loader.dart';

// Misma razón para el pull-to-refresh: las 6 pantallas que lo usan ya importan
// el kit, así que `JayaloRefresh` entra por acá y ninguna necesita un import
// nuevo. (`jayalo_refresh.dart` importa de vuelta `jayaloCardShadow` de este
// archivo; el ciclo es legal en Dart y no hay nombres en conflicto.)
export 'jayalo_refresh.dart';

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
    // "Cerrada" comparte el gris de la completada a propósito (pedido PO
    // 2026-08-03): las dos están terminadas. Lo que las distingue es la banda
    // violeta, que solo lleva la completada.
    RequestPhase.closed =>
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
    this.onLongPress,
    this.tint,
    this.border,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Opcional (Task 6, "Mi negocio"): "mantener presionada → Eliminar de tu
  /// tienda" en las tarjetas de producto/servicio propias. `null` en el resto
  /// de usos — sin gesto de más, la tarjeta se comporta exactamente igual.
  final VoidCallback? onLongPress;
  final Color? tint;

  /// Borde opcional. Por defecto la tarjeta va SIN borde (flota solo por la
  /// sombra cálida); se pasa uno para destacarla — p. ej. una solicitud con
  /// ofertas nuevas sin ver, que va con borde grueso oscuro + punto rojo.
  final BoxBorder? border;
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
            onLongPress: widget.onLongPress,
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
                // Por defecto sin borde (flota solo por la sombra cálida); con
                // `border` se destaca (solicitud con ofertas nuevas sin ver).
                border: widget.border,
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
            // `Flexible` + `overflow: ellipsis` (antes el `Text` no tenía
            // ninguno de los dos): un `Row` con `mainAxisSize: min` da ancho
            // INFINITO a un hijo que no sea `Flexible`/`Expanded`, así que
            // sin esto un contenedor angosto (p. ej. una fila con un ícono al
            // lado) revienta en overflow en vez de truncar con "…". Nunca
            // recorta en el uso normal — un chip con espacio de sobra se ve
            // exactamente igual que antes.
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tone.ink)),
            ),
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
        // Los números aparecen ya en su valor. Hubo un conteo animado
        // (`CountUpText`, 2026-07-30) y el PO lo retiró tras verlo en device:
        // "se siente confuso y no añade estética" — un número que sube solo
        // parece que el dato está cambiando, no que está llegando.
        // `tabularFigures` se queda: alinea las cifras entre las dos columnas
        // de métricas.
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
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key, this.index = 0});

  /// Posición en la lista. Solo desfasa el barrido de luz: la tarjeta `i`
  /// empieza su brillo [_shimmerStagger] después que la `i-1`, y así la luz se
  /// lee como UNA que baja por la lista en vez de N destellos simultáneos.
  final int index;

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

/// Ciclo completo del barrido. El brillo cruza durante [_shimmerSweep] y el
/// resto del ciclo la banda queda FUERA de la tarjeta: sin esa pausa el
/// skeleton estrobea, que es lo que separa un shimmer premium de un GIF de
/// carga. La banda viaja a velocidad CONSTANTE (`linear`, sin curva): es una
/// animación de tiempo, y cualquier easing la haría parecer que titubea a
/// mitad de camino.
const _shimmerCycle = Duration(milliseconds: 1800);
const _shimmerSweep = Duration(milliseconds: 1200);

/// Cuánto se atrasa cada tarjeta respecto de la anterior.
const _shimmerStagger = Duration(milliseconds: 90);

/// Semiancho de la banda de luz en unidades de [Alignment] (1 = medio ancho de
/// la tarjeta). Una banda ancha y tenue lee como reflejo; una angosta y fuerte,
/// como un escáner.
const _shimmerBand = .55;

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  // Un ticker por tarjeta, pero TODOS con la misma duración y arrancados en el
  // mismo frame (SkeletonList construye sus hijos de una sola pasada, no con
  // `.builder`), así que sus `value` van en fase y el desfase sale solo del
  // índice. Si en vez de eso el desfase viviera en la duración de cada
  // controller, los barridos se irían despegando ciclo a ciclo.
  //
  // ⚠️ Se crea en `initState`, NO como `late final … = AnimationController(…)`.
  // Con "reducir animaciones" el `build` retorna antes de tocar el campo, así
  // que un `late final` quedaría sin inicializar hasta que `dispose()` lo
  // leyera — y ahí `createTicker` va a buscar el `TickerMode` de un elemento ya
  // desactivado ("Looking up a deactivated widget's ancestor is unsafe").
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _shimmerCycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // El ticker se DETIENE con reduce-motion, no se ignora: un controller en
    // `repeat()` cuyo valor nadie lee le sigue pidiendo un frame por vsync a
    // toda la app. Corre acá (no en `initState`) porque leer el MediaQuery es
    // una dependencia, y así también reacciona si el ajuste cambia en vivo.
    if (JayaloMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Gradiente de la banda para la fase `t` (0-1 del ciclo). Devuelve null
  /// cuando la banda está fuera de la tarjeta: ahí no hay que pintar nada.
  LinearGradient? _sweep(double t, Color glint) {
    final staggered =
        (t - widget.index * (_shimmerStagger.inMilliseconds / _shimmerCycle.inMilliseconds)) % 1.0;
    // Reparte el ciclo: el barrido ocupa `_shimmerSweep`, el resto es pausa.
    final sweepFraction =
        _shimmerSweep.inMilliseconds / _shimmerCycle.inMilliseconds;
    if (staggered > sweepFraction) return null;
    final p = staggered / sweepFraction;
    // El CENTRO de la banda entra por la izquierda fuera de cuadro y sale por
    // la derecha fuera de cuadro, así que nunca se ve aparecer ni cortarse.
    final center = -(1 + _shimmerBand) + p * 2 * (1 + _shimmerBand);
    // `begin`/`end` admiten coordenadas fuera de [-1,1] y el TileMode.clamp de
    // los extremos transparentes deja el resto limpio — por eso se desliza el
    // TRAMO del gradiente en vez de mover los `stops` (mover stops obliga a
    // recortarlos a 0-1, y ahí la banda se achata contra los bordes).
    // El desnivel en Y la inclina: una banda diagonal lee como reflejo, una
    // perfectamente vertical lee como barra de progreso.
    return LinearGradient(
      begin: Alignment(center - _shimmerBand, -.6),
      end: Alignment(center + _shimmerBand, .6),
      colors: [glint.withValues(alpha: 0), glint, glint.withValues(alpha: 0)],
    );
  }

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
    // Solo los bloques grises: el barrido se aplica ACÁ y no sobre la tarjeta
    // entera a propósito. Con `srcATop` el ShaderMask tiñe todo lo que su hijo
    // pinte, y eso incluiría la superficie de la tarjeta y su `boxShadow` — la
    // sombra aclarándose al pasar la luz se veía como un halo sucio.
    final blocks = Row(children: [
      block(width: 40, height: 40, radius: 12),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(height: 14),
            const SizedBox(height: 6),
            FractionallySizedBox(widthFactor: .6, child: block(height: 12)),
          ],
        ),
      ),
    ]);

    Widget shell(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(kCardRadius),
              boxShadow: jayaloCardShadow(context),
            ),
            child: child,
          ),
        );

    if (JayaloMotion.reduced(context)) return shell(blocks);

    // El brillo es BLANCO en ambos temas: un glint tiene que ser más CLARO que
    // el bloque que cruza. El shimmer anterior usaba `onSurface`, que en tema
    // claro es casi negro — la banda oscurecía la tarjeta y se leía como una
    // sombra pasando, justo lo contrario de un destello. En claro el bloque ya
    // es gris pálido y hace falta bastante alpha para que el brillo se note;
    // en oscuro el bloque es casi negro y con poco alcanza.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glint = Colors.white.withValues(alpha: dark ? .16 : .70);

    return shell(AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final gradient = _sweep(_c.value, glint);
        if (gradient == null) return child!;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: gradient.createShader,
          child: child,
        );
      },
      child: blocks,
    ));
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
        // `children` (no `.builder`) a propósito: construir las N tarjetas en
        // el MISMO frame es lo que mantiene sus tickers en fase, y es de donde
        // el desfase por índice saca su coherencia.
        children: [for (var i = 0; i < count; i++) SkeletonCard(index: i)],
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
      this.label,
      this.progress});

  final Future<void> Function() onConfirmed;
  final HoldToConfirmTone tone;

  /// Copy del botón; si es null cae al texto por defecto del [tone].
  final String? label;

  /// Espejo OPCIONAL del progreso REAL del hold (0→1): el botón escribe aquí
  /// el valor de su propio AnimationController en cada tick (avance Y
  /// reversa al soltar). Permite capas visuales sincronizadas — la mascota
  /// que se infla del desbloqueo — sin un segundo timer ni doble conteo.
  final ValueNotifier<double>? progress;

  /// Alto total del botón renderizado (Container 58 + Padding.all(4)*2 = 66).
  /// Lo consume [HoldCoachMark] para dimensionar el hueco del spotlight sin
  /// medir el botón real (que vive en el overlay).
  static const double kHeight = 66;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: JayaloMotion.holdConfirm)
        ..addListener(() => widget.progress?.value = _c.value)
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
                // Tic de selección solo al cambiar de verdad de segmento
                // (mismo criterio que la barra flotante).
                onTap: () {
                  if (i != index) JayaloHaptics.tabChange();
                  onChanged(i);
                },
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
                  child: JayaloNetworkImage(widget.urls[i],
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

/// Tutorial coach-mark para el gesto "mantén presionado".
///
/// Envuelve un [HoldToConfirmButton]. Mientras el gesto ([gesture]) no se haya
/// logrado ni descartado, monta un overlay a pantalla completa: velo oscuro
/// (spotlight), el botón reubicado BRILLANTE encima del velo (vía
/// [CompositedTransformFollower], único origen del botón — el sitio en el flujo
/// queda como hueco que reserva el tamaño), un recuadro guía sobre el botón y
/// una demo animada (barra clara que barre + "dedito" pulsante) que enseña el
/// gesto. La demo se pausa cuando el usuario presiona de verdad ([progress] >
/// 0). Al primer hold exitoso ([progress] llega a 1.0) marca el gesto en
/// [onboardingStore] y el tutorial desaparece para siempre. Un toque en el
/// velo lo descarta en esta apertura (sin marcar), y reaparecerá la próxima vez.
class HoldCoachMark extends StatefulWidget {
  const HoldCoachMark({
    super.key,
    required this.gesture,
    required this.message,
    required this.tone,
    required this.progress,
    required this.child,
  });

  final String gesture;
  final String message;
  final HoldToConfirmTone tone;
  final ValueListenable<double> progress;
  final Widget child;

  @override
  State<HoldCoachMark> createState() => _HoldCoachMarkState();
}

class _HoldCoachMarkState extends State<HoldCoachMark>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchorKey = GlobalKey();

  // Loop de la demo (barre 0→1 y sostiene lleno un instante antes de reiniciar).
  late final AnimationController _demo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));

  Size? _anchorSize;
  bool _dismissed = false;
  bool _marked = false;

  /// Se enciende cuando NI la medición inicial NI el reintento único logran
  /// un tamaño del ancla — invariante: el botón nunca debe quedar
  /// inalcanzable, así que [build] cae al botón real en línea en vez del
  /// hueco vacío.
  bool _measureFailed = false;

  String get _guideKey => 'gesture.${widget.gesture}.v1';

  bool get _shouldShow =>
      !_dismissed && !onboardingStore.isDone(_guideKey);

  @override
  void initState() {
    super.initState();
    onboardingStore.addListener(_onStore);
    widget.progress.addListener(_onProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
  }

  @override
  void dispose() {
    onboardingStore.removeListener(_onStore);
    widget.progress.removeListener(_onProgress);
    _demo.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
    if (!_shouldShow && _portal.isShowing) _portal.hide();
  }

  void _onProgress() {
    // Éxito del gesto: el hold real llegó al tope → marcar y cerrar el tutorial.
    if (!_marked && widget.progress.value >= 1.0) {
      _marked = true;
      onboardingStore.markDone(_guideKey);
    }
    // Pausar/reanudar la demo según el usuario esté presionando de verdad.
    if (mounted) setState(() {});
  }

  void _measureAndMaybeShow() {
    if (!mounted) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      setState(() => _anchorSize = box.size);
    } else {
      // La medición falló en este frame (RenderBox nulo o sin tamaño aún) —
      // reintenta UNA vez en el próximo frame antes de resignarse al
      // fallback en línea.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retryBox =
            _anchorKey.currentContext?.findRenderObject() as RenderBox?;
        if (retryBox != null && retryBox.hasSize) {
          setState(() => _anchorSize = retryBox.size);
          _showPortalIfReady();
        } else {
          setState(() => _measureFailed = true);
        }
      });
      return;
    }
    _showPortalIfReady();
  }

  void _showPortalIfReady() {
    if (!mounted) return;
    if (_shouldShow && _anchorSize != null) {
      _portal.show();
      if (!_demo.isAnimating && !JayaloMotion.reduced(context)) {
        _demo.repeat();
      }
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    // Ya logrado o descartado → botón normal en su sitio, sin overlay.
    if (!_shouldShow) return widget.child;

    // Fallback (invariante: el botón nunca debe quedar inalcanzable): si la
    // medición del ancla falló incluso tras el reintento, el overlay no
    // puede mostrarse — el botón real queda en línea, interactivo, en vez
    // del hueco vacío sin acción posible.
    if (_measureFailed) return widget.child;

    // El sitio en el flujo reserva el tamaño del botón (hueco). El botón real
    // vive en el overlay, brillante sobre el velo.
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: SizedBox(
          key: _anchorKey,
          width: double.infinity,
          height: HoldToConfirmButton.kHeight,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final size = _anchorSize;
    if (size == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final pressing = widget.progress.value > 0;

    return Stack(
      children: [
        // Velo oscuro a pantalla completa: atenúa todo y descarta al tocarlo.
        Positioned.fill(
          child: GestureDetector(
            key: const Key('holdCoachScrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Color(0x8C000000)),
          ),
        ),
        // Botón real, reubicado BRILLANTE sobre el velo (spotlight).
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                widget.child,
                // Demo: solo cuando el usuario NO está presionando de verdad.
                if (!pressing)
                  Positioned.fill(
                    key: const Key('holdCoachDemo'),
                    child: IgnorePointer(
                      child: _DemoFill(listenable: _demo),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Recuadro guía, justo encima del botón.
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: _CoachCallout(
            message: widget.message,
            demo: _demo,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

/// Barra clara que barre de izq. a der. + "dedito" translúcido pulsante, sobre
/// el botón. Enseña el gesto sin tocar los internos del [HoldToConfirmButton].
class _DemoFill extends StatelessWidget {
  const _DemoFill({required this.listenable});
  final Animation<double> listenable;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (_, _) {
        // Barre durante el 70% del ciclo y sostiene lleno el resto.
        final t = (listenable.value / 0.7).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: t,
                    heightFactor: 1,
                    child: const ColoredBox(color: Color(0x47FFFFFF)),
                  ),
                ),
                // Dedito: círculo translúcido que avanza con la barra y late.
                Align(
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: Opacity(
                    opacity: (1 - (t - 0.85).abs() * 6).clamp(0.0, 1.0),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0x59FFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Recuadro flotante con el texto del gesto y una mini-barra de demo, con un
/// pico apuntando hacia abajo al botón.
class _CoachCallout extends StatelessWidget {
  const _CoachCallout(
      {required this.message, required this.demo, required this.color});
  final String message;
  final Animation<double> demo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: AnimatedBuilder(
                    animation: demo,
                    builder: (_, _) {
                      final t = (demo.value / 0.7).clamp(0.0, 1.0);
                      return Stack(
                        children: [
                          const Positioned.fill(
                              child: ColoredBox(color: Color(0x33FFFFFF))),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: t,
                              heightFactor: 1,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Pico del recuadro.
        Transform.translate(
          offset: const Offset(0, -1),
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
