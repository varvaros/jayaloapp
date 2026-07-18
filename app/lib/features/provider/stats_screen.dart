import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../../domain/money.dart';
import '../client/reputation_screen.dart' show MetricTile;
import '../shell/floating_nav_bar.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<(Map<String, dynamic>, ({int productos, int servicios}))> _load =
      _fetch();

  Future<(Map<String, dynamic>, ({int productos, int servicios}))>
      _fetch() async {
    final r = await Future.wait([providerStats(), providerCatalogCounts()]);
    return (
      r[0] as Map<String, dynamic>,
      r[1] as ({int productos, int servicios}),
    );
  }

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
    _load = _fetch();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Mis estadísticas'),
            actions: const [NotificationBell()]),
        body: FutureBuilder<
            (Map<String, dynamic>, ({int productos, int servicios}))>(
          future: _load,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorRetry(onRetry: () async => _refetch());
            }
            if (!snap.hasData) return const JayaloLoaderBlock();
            final (data, catalogo) = snap.data!;
            return StatsView(
                data: data,
                productos: catalogo.productos,
                servicios: catalogo.servicios);
          },
        ),
      );
}

/// Solo dibuja.
///
/// Es Stateful solo para alojar su propio `ScrollController`: usar el
/// singleton `homeScrollController` aquí tumbaría la app (ver el comentario
/// del `ListView` de abajo). Misma solución que `ReputationView`.
class StatsView extends StatefulWidget {
  const StatsView({
    super.key,
    required this.data,
    required this.productos,
    required this.servicios,
  });

  final Map<String, dynamic> data;
  final int productos;
  final int servicios;

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
    final productos = widget.productos;
    final servicios = widget.servicios;
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
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    label: reviews == 1 ? '1 reseña' : '$reviews reseñas')),
            Expanded(
                child: MetricTile(
                    icon: Icons.handshake_outlined,
                    value: '$completed',
                    label: 'trabajos realizados')),
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
        const SectionHeader(text: 'LO QUE OFRECES'),
        CatalogCard(productos: productos, servicios: servicios).cascadeIn(3),
      ],
    );
  }
}

/// Conteo del catálogo. INERTE a propósito: `onTap` es nulo hasta que exista
/// el spec del catálogo navegable (decisión PO 2026-07-18). Cuando llegue, se
/// le pasa el `onTap` y nada más cambia.
class CatalogCard extends StatelessWidget {
  const CatalogCard({
    super.key,
    required this.productos,
    required this.servicios,
    this.onTap,
  });

  final int productos;
  final int servicios;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = productos == 1 ? '1 producto' : '$productos productos';
    final s = servicios == 1 ? '1 servicio' : '$servicios servicios';
    return JayaloCard(
      onTap: onTap,
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$p · $s',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Se administran desde jayalo.com por ahora',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}
