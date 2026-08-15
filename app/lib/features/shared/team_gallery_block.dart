import 'package:flutter/material.dart';

import 'network_image.dart';
import 'portfolio_gallery_viewer.dart';

/// Galería del equipo (PO 2026-08-14, Task 9 — paridad del perfil
/// diferenciado técnico vs. tienda). Espejo del bloque "El equipo" de
/// `business.$id.tsx` (web): fotos del personal, en `provider_businesses
/// .team_photos` (`text[]`, lectura pública).
///
/// Se pinta SOLO si el negocio es `tecnico` Y el array no está vacío — un
/// `informal` (emprendedor individual) NO tiene equipo (decisión PO
/// 2026-08-14: "un emprendedor individual no tiene equipo"), y un `formal`
/// ya cuenta su identidad por RNC/fundación/número de empleados.
class TeamGalleryBlock extends StatelessWidget {
  const TeamGalleryBlock({super.key, required this.teamPhotos});

  final List<String> teamPhotos;

  /// `null` si no corresponde pintar nada — mismo patrón que
  /// `_physicalLocationBadge`/`_servicesBlock` de `provider_store_screen
  /// .dart`: construir solo si hay algo que mostrar, para no ensuciar el
  /// árbol de widgets con un bloque vacío.
  static Widget? maybe({
    required String? businessType,
    required List<String>? teamPhotos,
  }) {
    if (businessType != 'tecnico') return null;
    final photos = teamPhotos ?? const [];
    if (photos.isEmpty) return null;
    return TeamGalleryBlock(teamPhotos: photos);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.groups_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text('EL EQUIPO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: cs.onSurfaceVariant,
                )),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in teamPhotos)
                GestureDetector(
                  onTap: () => showPortfolioGallery(
                    context,
                    images: teamPhotos,
                    title: 'El equipo',
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: JayaloNetworkImage(
                      url,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 88,
                        height: 88,
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.person_outline,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
