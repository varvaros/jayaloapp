import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show PeerBadges;
import 'network_image.dart' show jayaloAvatarImage;

/// Ficha del CLIENTE que hay al otro lado. Identidad ANÓNIMA hasta el
/// desbloqueo (pedido PO 2026-07-22): foto blureada + alias "Cliente NNNN"
/// derivado del id, y debajo su reputación. El proveedor la mira para decidir
/// si le conviene pagar. No expone contacto.
///
/// Desde el mockup aprobado 2026-08-11 la ficha es además una PUERTA: con
/// [onTap] muestra chevron + «Ver perfil» y navega al perfil del cliente. Y
/// con el contacto YA desbloqueado ([realName] no nulo) muestra el nombre y
/// la foto reales (decisión PO 2026-08-11) — el gate de esa identidad vive en
/// la RPC `get_customer_public_profile`, nunca aquí.
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
    this.onTap,
    this.realName,
    this.realAvatarUrl,
  });

  /// `null` = aún no se sabe quién es → no se dibuja nada (mismo criterio que
  /// tenía inline: sin id no hay ni alias que enseñar).
  final String? customerId;

  /// Lo que devuelve `customerReputation`. `null` mientras carga o si falló:
  /// la tarjeta se pinta igual, con "Cliente nuevo — aún sin historial".
  final Map<String, dynamic>? reputation;

  final PeerBadges? badges;

  /// Abre el perfil del cliente. `null` = ficha sin puerta (sin chevron).
  final VoidCallback? onTap;

  /// Nombre REAL del cliente cuando el contacto ya se desbloqueó (viene de
  /// `customerPublicProfile`, gateado server-side). `null` = anónimo.
  final String? realName;

  /// Foto real del cliente (misma condición que [realName]). Puede ser null
  /// aunque esté desbloqueado: no todo el mundo tiene avatar.
  final String? realAvatarUrl;

  static String aliasFor(String customerId) =>
      'Cliente ${1000 + (customerId.hashCode.abs() % 9000)}';

  bool get _revealed => realName != null && realName!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cid = customerId;
    if (cid == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rep = reputation;
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

    final green =
        dark ? JayaloColors.dSuccess : JayaloColors.success;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      // Tarjeta lila (mockup aprobado 2026-08-11): la ficha del cliente se
      // distingue del resto de la hoja porque es una puerta, no un dato más.
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: dark ? .16 : .07),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CustomerAvatar(
                  revealed: _revealed,
                  avatarUrl: realAvatarUrl,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_revealed ? realName! : aliasFor(cid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: jayaloHead(context))),
                      Text(
                          _revealed
                              ? 'Contacto desbloqueado'
                              : 'Nombre y foto al desbloquear',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: _revealed ? green : cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                // La puerta al perfil (mockup 2026-08-11): chevron + rótulo.
                if (onTap != null)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_right, size: 20, color: cs.primary),
                    Text('Ver perfil',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.primary)),
                  ]),
              ]),
              if (badges != null &&
                  (badges!.idVerified || badges!.whatsappVerified)) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (badges!.idVerified)
                    _verifyPill(context, cs, 'Id verificado'),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
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
                            style:
                                TextStyle(fontSize: 12.5, color: cs.onSurface)),
                      ]),
                    ),
                ]),
            ]),
          ),
        ),
      ),
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

/// Avatar del cliente en sus dos estados. ANÓNIMO = placeholder con blur
/// fuerte (no hay foto real hasta desbloquear; la identidad queda "casi
/// imperceptible"). REVELADO = la foto llena su contenedor (doctrina), o un
/// ícono de persona nítido sobre relleno cálido si el cliente no tiene foto.
/// Público y aparte para que el perfil del cliente use EXACTAMENTE el mismo
/// avatar a otro tamaño — dos dibujos distintos divergirían solos.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({
    super.key,
    required this.revealed,
    this.avatarUrl,
    this.size = 48,
  });

  final bool revealed;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!revealed) {
      return ClipOval(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            width: size,
            height: size,
            color: cs.primary.withValues(alpha: .35),
            child: Icon(Icons.person, size: size * .55, color: cs.primary),
          ),
        ),
      );
    }
    final url = avatarUrl;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: cs.primary.withValues(alpha: .14),
        child: url != null && url.isNotEmpty
            ? Image(
                image: jayaloAvatarImage(url, size, context),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(Icons.person,
                    size: size * .55, color: cs.primary),
              )
            : Icon(Icons.person, size: size * .55, color: cs.primary),
      ),
    );
  }
}
