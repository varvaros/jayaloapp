import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'network_image.dart';

/// Portada editorial del negocio — la pieza del diseño web que nunca se portó
/// a la app (`cover_url` no se leía en NINGÚN sitio de `lib/`).
///
/// Sigue el tratamiento MÓVIL de la web (`provider/business.$id.tsx`, dos
/// pasadas el 2026-07-21): la portada va de fondo y el bloque de identidad en
/// flujo normal encima del scrim, de modo que la caja crece con el contenido y
/// nada se desborda. El overlay absoluto de la web es solo para desktop, y en
/// un teléfono no aplica.
///
/// Sin portada se pinta un degradado de marca en vez de un hueco gris.
class BusinessCoverHero extends StatelessWidget {
  const BusinessCoverHero({
    super.key,
    required this.name,
    this.coverUrl,
    this.logoUrl,
    this.subtitle,
    this.seals = const [],
    this.trailing,
  });

  final String name;
  final String? coverUrl;
  final String? logoUrl;

  /// Una línea con lo esencial: categoría, ciudad… Nulo = no se dibuja.
  final String? subtitle;

  /// Sellos de verificación ya resueltos a etiqueta ("Identidad verificada").
  final List<String> seals;

  /// Hueco para lo que cada pantalla quiera colgar bajo la identidad (la
  /// tienda pública mete ahí su bloque de confianza).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cover = coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    // Sin nombre la portada se quedaba muda; "Tu negocio" es el mismo respaldo
    // que ya usaba la cabecera vieja de Mi negocio.
    final displayName = name.trim().isEmpty ? 'Tu negocio' : name.trim();

    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: [
          Positioned.fill(
            child: hasCover
                ? JayaloNetworkImage(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallbackBackdrop(cs),
                  )
                : _fallbackBackdrop(cs),
          ),
          // Scrim: sin él el nombre blanco se pierde sobre una portada clara.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: hasCover ? .25 : .10),
                    Colors.black.withValues(alpha: hasCover ? .78 : .45),
                  ],
                ),
              ),
            ),
          ),
          // Contenido en FLUJO NORMAL (no `Positioned`): la caja crece con él.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 64, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _logoCard(cs),
                const SizedBox(height: 14),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: .88),
                    ),
                  ),
                ],
                if (seals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final s in seals) _seal(s)],
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 14),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackBackdrop(ColorScheme cs) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, JayaloColors.head],
          ),
        ),
      );

  /// Tarjeta del logo: fondo claro y esquinas redondeadas, como la web.
  Widget _logoCard(ColorScheme cs) {
    final logo = logoUrl;
    Widget placeholder() => Container(
          color: cs.primary.withValues(alpha: .12),
          child: Icon(Icons.storefront_outlined, size: 32, color: cs.primary),
        );
    return Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: (logo == null || logo.isEmpty)
            ? placeholder()
            : JayaloNetworkImage(
                logo,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder(),
              ),
      ),
    );
  }

  Widget _seal(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              )),
        ]),
      );
}
