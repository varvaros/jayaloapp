import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../shared/catalog_chip.dart';

/// Tira de chips del catálogo (PO 2026-09-05, camino 3): «Al por mayor» como
/// toggle discreto al inicio (solo Producto), un separador, «Todo» y un chip
/// por categoría navegable. Pura: recibe las listas y avisa por callbacks —
/// quién filtra y qué cuerpo se pinta lo decide `CatalogView`.
///
/// Un solo chip activo a la vez. Tocar el activo NO lo apaga: para volver a
/// la portada se toca «Todo» (regla de la spec §2.2).
///
/// Con categoría activa y rubros disponibles (Task 4, 2026-09-07), pinta
/// debajo una segunda fila de sub-chips: «Todo `<categoría>`» + un chip por
/// rubro — espejo del filtro que hoy solo vivía en la hoja de filtros.
class CatalogChipStrip extends StatelessWidget {
  const CatalogChipStrip({
    super.key,
    required this.categorias,
    required this.categoryId,
    required this.onCategory,
    required this.onTodo,
    required this.rubros,
    required this.rubro,
    required this.onRubro,
    this.wholesale,
    this.onWholesale,
  });

  final List<Category> categorias;

  /// Categoría activa; `null` ⇒ «Todo» activo.
  final String? categoryId;
  final ValueChanged<String> onCategory;
  final VoidCallback onTodo;

  /// Rubros de la categoría activa (vacío ⇒ sin fila de rubros).
  final List<String> rubros;

  /// Rubro activo; `null` ⇒ «Todo `<categoría>`» activo.
  final String? rubro;
  final ValueChanged<String?> onRubro;

  /// Estado del chip de mayoreo; `null` ⇒ el chip no existe (Servicio).
  final bool? wholesale;

  /// Recibe el NUEVO valor (ya alternado).
  final ValueChanged<bool>? onWholesale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mayoreo = wholesale;
    final mostrarRubros = categoryId != null && rubros.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Row(
            children: [
              if (mayoreo != null) ...[
                CatalogChip(
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
              CatalogChip(
                label: 'Todo',
                active: categoryId == null,
                onTap: onTodo,
              ),
              for (final c in categorias) ...[
                const SizedBox(width: 8),
                CatalogChip(
                  label: c.name,
                  active: categoryId == c.id,
                  onTap: () => onCategory(c.id),
                ),
              ],
            ],
          ),
        ),
        if (mostrarRubros)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CatalogChip(
                    label: 'Todo ${categoryNameById(categoryId) ?? ''}',
                    active: rubro == null,
                    fontSize: 11,
                    onTap: () => onRubro(null),
                  ),
                  for (final r in rubros) ...[
                    const SizedBox(width: 8),
                    CatalogChip(
                      label: r,
                      active: rubro == r,
                      fontSize: 11,
                      onTap: () => onRubro(rubro == r ? null : r),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
