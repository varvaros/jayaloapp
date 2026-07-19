import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

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
                if (!snap.hasData) return const SkeletonList();
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

class _StatsViewState extends State<StatsView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
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

    if (completed == 0 && reviews == 0) {
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
        const SectionHeader(text: 'CÓMO TE CALIFICAN'),
        JayaloCard(
          child: Row(children: [
            // Task 4: antes esta tarjeta emparejaba calificación+reseñas con
            // "trabajos realizados" en un solo MetricTile combinado. Al salir
            // "trabajos realizados" hacia Mi negocio, se separan calificación
            // y reseñas en dos MetricTile propios para no dejar la fila coja
            // de una sola columna.
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    label: 'calificación')),
            Expanded(
                child: MetricTile(
                    icon: Icons.rate_review_outlined,
                    value: '$reviews',
                    label: reviews == 1 ? 'reseña' : 'reseñas')),
          ]),
        ).cascadeIn(0),
        const SectionHeader(text: 'TU NEGOCIO'),
        JayaloCard(
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
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.toll_outlined,
                    value: '$points',
                    label: 'créditos invertidos')),
          ]),
        ).cascadeIn(2),
      ],
    );
  }
}
