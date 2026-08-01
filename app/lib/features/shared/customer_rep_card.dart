import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show PeerBadges;

/// Ficha del CLIENTE que hay al otro lado, con identidad ANÓNIMA hasta el
/// desbloqueo (pedido PO 2026-07-22): foto blureada + alias "Cliente NNNN"
/// derivado del id, y debajo su reputación. El proveedor la mira para decidir
/// si le conviene pagar. No expone contacto.
///
/// Vivía inline en `request_detail_screen.dart`; se extrajo el 2026-08-01
/// porque el detalle del interés de producto necesita exactamente la misma
/// sección — el PO pidió esa ventana "igual que las demás solicitudes", y
/// "datos del cliente" es justo esto.
class CustomerRepCard extends StatelessWidget {
  const CustomerRepCard({
    super.key,
    required this.customerId,
    this.reputation,
    this.badges,
  });

  /// `null` = aún no se sabe quién es → no se dibuja nada (mismo criterio que
  /// tenía inline: sin id no hay ni alias que enseñar).
  final String? customerId;

  /// Lo que devuelve `customerReputation`. `null` mientras carga o si falló:
  /// la tarjeta se pinta igual, con "Cliente nuevo — aún sin historial".
  final Map<String, dynamic>? reputation;

  final PeerBadges? badges;

  static String aliasFor(String customerId) =>
      'Cliente ${1000 + (customerId.hashCode.abs() % 9000)}';

  @override
  Widget build(BuildContext context) {
    final cid = customerId;
    if (cid == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final rep = reputation;
    final alias = aliasFor(cid);
    final avg = (rep?['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (rep?['reviews_count'] as num?)?.toInt() ?? 0;
    final completed = (rep?['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (rep?['requests_count'] as num?)?.toInt() ?? 0;
    final respMin = (rep?['median_response_minutes'] as num?)?.toDouble();
    final samples = (rep?['response_samples'] as num?)?.toInt() ?? 0;

    String respLabel(double m) {
      if (m < 60) return 'Responde en ~${m.round()} min';
      if (m < 1440) return 'Responde en ~${(m / 60).round()} h';
      return 'Responde en ~${(m / 1440).round()} d';
    }

    final chips = <(IconData, String)>[
      if (count > 0)
        (Icons.star_rounded, '${avg.toStringAsFixed(1)} ($count)'),
      if (requests > 0)
        (Icons.receipt_long_outlined,
            '$requests solicitud${requests == 1 ? '' : 'es'}'),
      if (completed > 0)
        (Icons.check_circle_outline,
            '$completed compra${completed == 1 ? '' : 's'} cerrada${completed == 1 ? '' : 's'}'),
      if (respMin != null && samples >= 3)
        (Icons.schedule_outlined, respLabel(respMin)),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Foto blureada: placeholder con blur fuerte (no hay foto real hasta
          // desbloquear; la identidad queda "casi imperceptible").
          ClipOval(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                width: 44,
                height: 44,
                color: cs.primary.withValues(alpha: .35),
                child: Icon(Icons.person, size: 26, color: cs.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alias,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: jayaloHead(context))),
                Text('Nombre y foto al desbloquear',
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
        if (badges != null &&
            (badges!.idVerified || badges!.whatsappVerified)) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (badges!.idVerified) _verifyPill(context, cs, 'Id verificado'),
            if (badges!.whatsappVerified)
              _verifyPill(context, cs, 'WS verificado'),
          ]),
        ],
        const SizedBox(height: 12),
        if (chips.isEmpty)
          Text('Cliente nuevo — aún sin historial.',
              style: TextStyle(fontSize: 13, color: cs.onSurface))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (icon, txt) in chips)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 14,
                      color: icon == Icons.star_rounded
                          ? const Color(0xFFF2B705)
                          : cs.primary),
                  const SizedBox(width: 5),
                  Text(txt,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
                ]),
              ),
          ]),
      ]),
    );
  }

  Widget _verifyPill(BuildContext context, ColorScheme cs, String label) {
    final green = Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dSuccess
        : JayaloColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified, size: 13, color: green),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: green)),
      ]),
    );
  }
}
