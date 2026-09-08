import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Píldora compartida por las tiras de filtro del catálogo: blanca con
/// sombra cálida en reposo; activa según `dark` — clara (`cs.primaryContainer`
/// + `cs.onPrimaryContainer`, la de siempre en categorías) u oscura
/// (`cs.onPrimaryContainer` + blanco, como la píldora «Filtrar»; la usa
/// `CatalogTipoStrip`). Pesos 500-600: los filtros son discretos, las
/// tarjetas mandan (doctrina).
///
/// Extraída de `client/catalog_chip_strip.dart` (Task 4, 2026-09-07) al
/// aparecer el segundo consumidor (`CatalogTipoStrip`), para no duplicarla.
class CatalogChip extends StatelessWidget {
  const CatalogChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.leading,
    this.dark = false,
    this.fontSize = 11.5,
    this.trailing,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? leading;

  /// `true` ⇒ el estado activo pinta oscuro (fondo `cs.onPrimaryContainer`,
  /// texto blanco) en vez del claro de siempre.
  final bool dark;
  final double fontSize;

  /// Contenido opcional tras la etiqueta (p. ej. el conteo de
  /// `CatalogTipoStrip`), en su propio `Text` para que los tests lo hallen.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active
        ? (dark ? cs.onPrimaryContainer : cs.primaryContainer)
        : cs.surface;
    final fg = active
        ? (dark ? Colors.white : cs.onPrimaryContainer)
        : cs.onSurface;
    // MergeSemantics: un solo nodo (botón + etiqueta + seleccionado) para el
    // lector de pantalla, en vez de InkWell y Text por separado.
    return MergeSemantics(
      child: Semantics(
        selected: active,
        child: Material(
          color: bg,
          elevation: active ? 0 : 2,
          shadowColor: JayaloColors.warmShadow,
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    Icon(leading, size: 14, color: fg),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
