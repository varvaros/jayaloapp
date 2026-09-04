import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/money.dart';
import '../../domain/response_time.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/star_score.dart';
import '../shared/violet_header.dart';
import '../shared/moneda.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<Map<String, dynamic>> _load = providerStats();

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
    _load = providerStats();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        // Pantalla de detalle: se llega por `context.push` desde el menú del
        // avatar (Task 8, vive en `_excludedFromNav`), así que su header lleva
        // atrás y título centrado — no campana/avatar. El atrás hace `pop`
        // sobre el Navigator anidado del shell, devolviendo al proveedor a la
        // pestaña que estaba debajo (misma salida que resolvía BackGuard).
        body: Column(children: [
          VioletHeader(
            leading: HeaderCircleButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              onTap: () => context.pop(),
            ),
            title: 'Mis estadísticas',
            titleAlign: HeaderTitleAlign.center,
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData) return const JayaloLoaderBlock();
                return StatsView(data: snap.data!);
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja.
///
/// Es Stateful solo para alojar su propio `ScrollController`: usar el
/// singleton `homeScrollController` aquí tumbaría la app (ver el comentario
/// del `ListView` de abajo). Misma solución que `ReputationView`.
///
/// Task 4 (2026-07-18): el catálogo ("LO QUE OFRECES") y "trabajos
/// realizados" SALIERON de aquí hacia `/provider/business` ("Mi negocio",
/// decisión PO §0.2) — no se duplican. `completed_count` se sigue leyendo
/// (internamente) porque el estado vacío de esta pantalla lo necesita para
/// decidir si el proveedor tiene algo de actividad.
class StatsView extends StatefulWidget {
  const StatsView({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  /// UN solo reloj para los tres íconos de las cabeceras: así el titileo, la
  /// respiración y el meceo van sincronizados. Mismo patrón y misma duración
  /// que los Jayi de la app (4,8 s por vuelta).
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800));

  /// Un mando por sección. Los pulsa la tarjeta que se toca y responde la
  /// pastilla de SU cabecera — nada más: no navegan (decisión PO 2026-09-04).
  final _pulseCalifican = SectionPulse();
  final _pulseNegocio = SectionPulse();
  final _pulseComprador = SectionPulse();

  /// Ver el gotcha de `_SectionGlyphPill`: bajo `flutter test` el bucle no
  /// arranca, o el ticker en repeat deja la prueba esperando para siempre.
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _idle.dispose();
    _pulseCalifican.dispose();
    _pulseNegocio.dispose();
    _pulseComprador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final completed = (data['completed_count'] as num?)?.toInt() ?? 0;
    final clients = (data['clients_count'] as num?)?.toInt() ?? 0;
    final points = (data['points_invested'] as num?)?.toInt() ?? 0;
    final revenue = (data['revenue_total'] as num?) ?? 0;
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;

    // ── El mismo usuario, del otro lado del mostrador ───────────────────
    // `kStatsBuyerKey` viene ANIDADO desde `providerStats()`: sus
    // `avg_rating`/`reviews_count` son la nota que le ponen como COMPRADOR y
    // no deben confundirse con las de arriba, que son las de su negocio.
    final buyer = data[kStatsBuyerKey] as Map<String, dynamic>?;
    final bRating = (buyer?['avg_rating'] as num?)?.toDouble() ?? 0;
    final bReviews = (buyer?['reviews_count'] as num?)?.toInt() ?? 0;
    final bPurchases = (buyer?['completed_purchases'] as num?)?.toInt() ?? 0;
    final bRequests = (buyer?['requests_count'] as num?)?.toInt() ?? 0;
    final bFrase = responseTimeCopy(
      (buyer?['median_response_minutes'] as num?)?.toInt(),
      (buyer?['response_samples'] as num?)?.toInt() ?? 0,
    );

    final hayNegocio = completed > 0 || reviews > 0;
    final hayCompras = bRequests > 0 || bPurchases > 0 || bReviews > 0;

    // El vacío total solo cuando NINGUNO de los dos lados tiene nada. Antes
    // bastaba con no haber vendido para cortar la pantalla entera; desde que
    // el proveedor perdió el ítem "Reputación" de su menú (PO 2026-09-04),
    // eso lo dejaría sin ver JAMÁS sus datos de comprador.
    if (!hayNegocio && !hayCompras) {
      return EmptyState(
        controller: _scroll,
        message: 'Todavía no has completado ningún trabajo.\n\n'
            'Cuando cierres el primero verás aquí cuántos clientes has '
            'atendido, cuánto has facturado y cómo te califican.',
      );
    }

    return ListView(
      // Controlador PROPIO, no `homeScrollController`. Ese singleton lo lee
      // `BackGuard._handleBack` con `c.offset`, que lanza "Too many elements"
      // si hay más de una posición adjunta — y el AnimatedSwitcher del shell
      // mantiene dos pestañas montadas durante los 250 ms del cambio.
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        // ── Lo del negocio. Solo si ha vendido algo; si no, un aviso corto
        //    y la pantalla sigue con lo de comprador.
        if (!hayNegocio)
          JayaloCard(
            child: Row(children: [
              Icon(Icons.storefront_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Todavía no has completado ningún trabajo. '
                    'Cuando cierres el primero verás aquí tus clientes, lo '
                    'facturado y cómo te califican.'),
              ),
            ]),
          ).cascadeIn(0),
        if (hayNegocio) ...[
        SectionHeader(
            text: 'CÓMO TE CALIFICAN',
            glyph: SectionGlyph.estrella,
            idle: _idle,
            pulse: _pulseCalifican),
        JayaloCard(
          onTap: _pulseCalifican.pop,
          child: Row(children: [
            // Task 4: antes esta tarjeta emparejaba calificación+reseñas con
            // "trabajos realizados" en un solo MetricTile combinado. Al salir
            // "trabajos realizados" hacia Mi negocio, se separan calificación
            // y reseñas en dos MetricTile propios para no dejar la fila coja
            // de una sola columna.
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    // La nota es sobre 10: sin el sufijo, pegada a una estrella se
                    // lee como si fuera sobre 5 y un proveedor mediocre parece bueno.
                    value:
                        rating > 0 ? '${StarScore.formatScore(rating)}/10' : '—',
                    extra: rating > 0
                        ? StarScore(score: rating, size: 13, showNumber: false)
                        : null,
                    label: 'calificación')),
            Expanded(
                child: MetricTile(
                    icon: Icons.rate_review_outlined,
                    value: '$reviews',
                    label: reviews == 1 ? 'reseña' : 'reseñas')),
          ]),
        ).cascadeIn(0),
        SectionHeader(
            text: 'TU NEGOCIO',
            glyph: SectionGlyph.tienda,
            idle: _idle,
            pulse: _pulseNegocio),
        JayaloCard(
          onTap: _pulseNegocio.pop,
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.people_alt_outlined,
                    value: '$clients',
                    label: 'clientes atendidos')),
            Expanded(
                child: MetricTile(
                    icon: Icons.payments_outlined,
                    value: fmtRD(revenue),
                    label: 'facturado')),
          ]),
        ).cascadeIn(1),
        JayaloCard(
          onTap: _pulseNegocio.pop,
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.toll_outlined,
                    leading: const MonedaJayalo(size: 22),
                    value: '$points',
                    label: 'créditos invertidos')),
          ]),
        ).cascadeIn(2),
        ],

        // ── El mismo usuario, comprando ────────────────────────────────────
        // Estos cinco datos vivían SOLO en `/client/reputation`, que el
        // proveedor alcanzaba por su menú del avatar. Al quitarse ese ítem
        // (PO 2026-09-04), esta es su única superficie. El cliente conserva
        // su pantalla entera intacta.
        if (hayCompras) ...[
          SectionHeader(
              text: 'COMO COMPRADOR',
              glyph: SectionGlyph.bolsa,
              idle: _idle,
              pulse: _pulseComprador),
          JayaloCard(
            onTap: _pulseComprador.pop,
            child: Row(children: [
              Expanded(
                  child: MetricTile(
                      icon: Icons.star_rounded,
                      value: bRating > 0
                          ? '${StarScore.formatScore(bRating)}/10'
                          : '—',
                      extra: bRating > 0
                          ? StarScore(score: bRating, size: 13, showNumber: false)
                          : null,
                      // "te califican" y no "calificación" a secas: en la misma
                      // pantalla ya hay una calificación (la del negocio) y dos
                      // etiquetas iguales con números distintos se leen como un
                      // error.
                      label: 'te califican')),
              Expanded(
                  child: MetricTile(
                      icon: Icons.rate_review_outlined,
                      value: '$bReviews',
                      label: bReviews == 1 ? 'reseña' : 'reseñas')),
            ]),
          ).cascadeIn(3),
          JayaloCard(
            onTap: _pulseComprador.pop,
            child: Row(children: [
              Expanded(
                  child: MetricTile(
                      icon: Icons.shopping_bag_outlined,
                      value: '$bPurchases',
                      label: 'compras completadas')),
              Expanded(
                  child: MetricTile(
                      icon: Icons.receipt_long_outlined,
                      value: '$bRequests',
                      label: 'solicitudes hechas')),
            ]),
          ).cascadeIn(4),
          if (bFrase != null)
            JayaloCard(
              onTap: _pulseComprador.pop,
              child: Row(children: [
                Icon(Icons.schedule,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(bFrase)),
              ]),
            ).cascadeIn(5),
        ],
      ],
    );
  }
}
