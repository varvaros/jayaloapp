import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/catalog.dart';

/// Tira de chips del catálogo (PO 2026-09-05, camino 3): «Al por mayor» como
/// toggle discreto al inicio (solo Producto), un separador, «Todo» y un chip
/// por categoría navegable. Pura: recibe las listas y avisa por callbacks —
/// quién filtra y qué cuerpo se pinta lo decide `CatalogView`.
///
/// Un solo chip activo a la vez. Tocar el activo NO lo apaga: para volver a
/// la portada se toca «Todo» (regla de la spec §2.2).
class CatalogChipStrip extends StatelessWidget {
  const CatalogChipStrip({
    super.key,
    required this.categorias,
    required this.categoryId,
    required this.onCategory,
    required this.onTodo,
    this.wholesale,
    this.onWholesale,
  });

  final List<Category> categorias;

  /// Categoría activa; `null` ⇒ «Todo» activo.
  final String? categoryId;
  final ValueChanged<String> onCategory;
  final VoidCallback onTodo;

  /// Estado del chip de mayoreo; `null` ⇒ el chip no existe (Servicio).
  final bool? wholesale;

  /// Recibe el NUEVO valor (ya alternado).
  final ValueChanged<bool>? onWholesale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mayoreo = wholesale;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(children: [
        if (mayoreo != null) ...[
          _Chip(
            label: 'Al por mayor',
            active: mayoreo,
            leading: mayoreo
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            onTap: () => onWholesale?.call(!mayoreo),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: cs.outlineVariant),
          const SizedBox(width: 8),
        ],
        _Chip(label: 'Todo', active: categoryId == null, onTap: onTodo),
        for (final c in categorias) ...[
          const SizedBox(width: 8),
          _Chip(
            label: c.name,
            active: categoryId == c.id,
            onTap: () => onCategory(c.id),
          ),
        ],
      ]),
    );
  }
}

/// Píldora: blanca con sombra cálida en reposo, lila de acento (`accent` /
/// `accentFg`, los mismos de la navbar) cuando está activa. Pesos 500-600,
/// fuente 11,5: los filtros son discretos, las tarjetas mandan (doctrina).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.leading,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active ? cs.primaryContainer : cs.surface;
    final fg = active ? cs.onPrimaryContainer : cs.onSurface;
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[
                Icon(leading, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: fg)),
            ]),
          ),
        ),
      ),
      ),
    );
  }
}
