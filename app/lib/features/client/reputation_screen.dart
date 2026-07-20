import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

/// Umbral de la web (`src/lib/responseTime.ts`): con menos de 5 respuestas
/// medidas la mediana no representa nada y se omite por completo.
const kMinResponseSamples = 5;

class ReputationScreen extends StatefulWidget {
  const ReputationScreen({super.key});
  @override
  State<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends State<ReputationScreen> {
  late Future<Map<String, dynamic>?> _load = customerReputation();

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
    _load = customerReputation();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          const VioletHeader(
            leading: HeaderAvatar(),
            title: 'Mi reputación',
            actions: [HeaderBell()],
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData &&
                    snap.connectionState != ConnectionState.done) {
                  return const JayaloLoaderBlock();
                }
                return ReputationView(data: snap.data ?? const {});
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja. Recibe el mapa crudo de `get_customer_reputation`.
///
/// StatefulWidget solo para poseer su propio ScrollController (con dispose
/// correcto): esta pantalla NO es la home, así que no debe compartir
/// `homeScrollController` con `MyRequestsScreen` — el `AnimatedSwitcher` del
/// shell mantiene ambas pestañas montadas ~250ms durante el cambio, y dos
/// `ScrollPosition` adjuntas al mismo controller hacen que `BackGuard` lance
/// `StateError` al leer `c.offset` en cualquier ATRÁS.
class ReputationView extends StatefulWidget {
  const ReputationView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<ReputationView> createState() => _ReputationViewState();
}

class _ReputationViewState extends State<ReputationView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;
    final purchases = (data['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (data['requests_count'] as num?)?.toInt() ?? 0;
    final samples = (data['response_samples'] as num?)?.toInt() ?? 0;
    final minutes = (data['median_response_minutes'] as num?)?.toInt();
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;

    if (reviews == 0 && purchases == 0 && requests == 0) {
      return EmptyState(
        controller: _scrollController,
        message: 'Todavía no tienes reputación.\n\n'
            'Se construye sola: pide lo que necesitas, completa tus compras '
            'y califica a quien te atendió. Los proveedores la verán y te '
            'responderán con más confianza.',
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        const SectionHeader(text: 'CÓMO TE VEN'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    label: reviews == 1 ? '1 reseña' : '$reviews reseñas')),
            Expanded(
                child: MetricTile(
                    icon: Icons.shopping_bag_outlined,
                    value: '$purchases',
                    label: 'compras completadas')),
          ]),
        ).cascadeIn(0),
        const SectionHeader(text: 'TU ACTIVIDAD'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.receipt_long_outlined,
                    value: '$requests',
                    label: 'solicitudes hechas')),
          ]),
        ).cascadeIn(1),
        if (samples >= kMinResponseSamples && minutes != null)
          JayaloCard(
            child: Row(children: [
              Icon(Icons.schedule,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Regularmente respondes en ${_humanMinutes(minutes)}')),
            ]),
          ).cascadeIn(2),
      ],
    );
  }
}

/// "45 minutos" / "unas 2 horas" / "1 día" — nunca "min" ni "h" abreviados:
/// el público de la app lee palabras, no unidades.
String _humanMinutes(int m) {
  if (m < 60) return '$m minutos';
  final horas = (m / 60).round();
  if (horas < 24) return horas == 1 ? 'una hora' : 'unas $horas horas';
  final dias = (horas / 24).round();
  return dias == 1 ? 'un día' : '$dias días';
}
