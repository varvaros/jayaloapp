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
    this.onCoverTap,
    this.onLogoTap,
    this.onCoverLongPress,
    this.onLogoLongPress,
    this.coverBusy = false,
    this.logoBusy = false,
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

  /// Edición desde "Mi negocio" (2026-08-09): con callback nulo (el default)
  /// el hero se comporta EXACTO como antes — la tienda pública, que no pasa
  /// ninguno de estos parámetros, no cambia un píxel.
  final VoidCallback? onCoverTap;
  final VoidCallback? onLogoTap;
  final VoidCallback? onCoverLongPress;
  final VoidCallback? onLogoLongPress;

  /// Sube un spinner pequeño superpuesto mientras la portada/logo se está
  /// subiendo o quitando.
  final bool coverBusy;
  final bool logoBusy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cover = coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    // Sin nombre la portada se quedaba muda; "Tu negocio" es el mismo respaldo
    // que ya usaba la cabecera vieja de Mi negocio.
    final displayName = name.trim().isEmpty ? 'Tu negocio' : name.trim();
    final coverEditable = onCoverTap != null || onCoverLongPress != null;

    Widget stack = Stack(
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
        // "+ Añadir portada": solo sin portada, editable y no ocupado — con
        // portada ya puesta, tocar para CAMBIARLA no necesita esta pista.
        if (!hasCover && onCoverTap != null && !coverBusy)
          const Positioned.fill(child: Center(child: _AddPill())),
        if (coverBusy) const Positioned.fill(child: Center(child: _BusySpinner())),
      ],
    );

    // El GestureDetector envuelve TODO el Stack (portada) — el logo, más
    // adentro, tiene el suyo propio (`_logoCard`) que gana la arena de gestos
    // dentro de sus límites.
    if (coverEditable) {
      stack = GestureDetector(
        onTap: onCoverTap,
        onLongPress: onCoverLongPress,
        child: stack,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28)),
      child: stack,
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
    final hasLogo = logo != null && logo.isNotEmpty;
    final logoEditable = onLogoTap != null || onLogoLongPress != null;
    Widget placeholder() => Container(
          color: cs.primary.withValues(alpha: .12),
          child: Icon(Icons.storefront_outlined, size: 32, color: cs.primary),
        );
    Widget card = Container(
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: hasLogo
                ? JayaloNetworkImage(
                    logo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder(),
                  )
                : placeholder(),
          ),
          // Badge circular "+" en la esquina: solo logo vacío y editable —
          // con logo puesto tocar para CAMBIARLO no necesita esta pista.
          if (!hasLogo && onLogoTap != null && !logoBusy)
            const Positioned(right: -4, bottom: -4, child: _AddBadge()),
          if (logoBusy)
            const Positioned.fill(
              child: Center(child: _BusySpinner(small: true)),
            ),
        ],
      ),
    );
    if (logoEditable) {
      card = GestureDetector(
        onTap: onLogoTap,
        onLongPress: onLogoLongPress,
        child: card,
      );
    }
    return card;
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

/// Píldora centrada "+ Añadir portada": la única pista de que la portada
/// vacía es editable.
class _AddPill extends StatelessWidget {
  const _AddPill();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: JayaloColors.primary.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .4)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 18, color: Colors.white),
          SizedBox(width: 6),
          Text('Añadir portada',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              )),
        ]),
      );
}

/// Badge circular "+" en la esquina del logo vacío editable — el equivalente
/// compacto de [_AddPill] cuando no hay espacio para texto.
class _AddBadge extends StatelessWidget {
  const _AddBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: JayaloColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(Icons.add, size: 14, color: Colors.white),
      );
}

/// Spinner pequeño superpuesto mientras la portada/logo sube o se quita.
class _BusySpinner extends StatelessWidget {
  const _BusySpinner({this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 22.0 : 30.0;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(small ? 3 : 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .45),
        shape: BoxShape.circle,
      ),
      child: const CircularProgressIndicator(
        strokeWidth: 2.4,
        valueColor: AlwaysStoppedAnimation(Colors.white),
      ),
    );
  }
}
