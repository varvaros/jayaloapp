import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shell/home_scroll.dart';

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

  void _refetch() => setState(() => _load = customerReputation());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Mi reputación'),
            actions: const [NotificationBell()]),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _load,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorRetry(onRetry: () async => _refetch());
            }
            if (!snap.hasData && snap.connectionState != ConnectionState.done) {
              return const JayaloLoaderBlock();
            }
            return ReputationView(data: snap.data ?? const {});
          },
        ),
      );
}

/// Solo dibuja. Recibe el mapa crudo de `get_customer_reputation`.
class ReputationView extends StatelessWidget {
  const ReputationView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;
    final purchases = (data['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (data['requests_count'] as num?)?.toInt() ?? 0;
    final samples = (data['response_samples'] as num?)?.toInt() ?? 0;
    final minutes = (data['median_response_minutes'] as num?)?.toInt();
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;

    if (reviews == 0 && purchases == 0 && requests == 0) {
      return EmptyState(
        controller: homeScrollController,
        message: 'Todavía no tienes reputación.\n\n'
            'Se construye sola: pide lo que necesitas, completa tus compras '
            'y califica a quien te atendió. Los proveedores la verán y te '
            'responderán con más confianza.',
      );
    }

    return ListView(
      controller: homeScrollController,
      padding: const EdgeInsets.only(bottom: 24),
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

/// Cifra grande + etiqueta. La reusan Reputación y Estadísticas.
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
                fontSize: 24, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
