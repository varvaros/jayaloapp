import 'package:flutter/material.dart';

import '../shared/catalog_chip.dart';

/// Fila de tipo del catálogo (Task 4, 2026-09-07): «Todos · Productos ·
/// Servicios · Paquetes · Proveedores», cada uno con su conteo del conjunto
/// cargado y filtrado. Pura: recibe `conteos` y avisa por `onTipo` con la
/// CLAVE del tipo (no la etiqueta) — quién filtra lo decide `CatalogView`.
class CatalogTipoStrip extends StatelessWidget {
  const CatalogTipoStrip({
    super.key,
    required this.tipo,
    required this.conteos,
    required this.onTipo,
  });

  /// Tipo activo: una de las claves de [_tipos].
  final String tipo;

  /// Conteos por clave: `todos|producto|servicio|paquete|proveedor`.
  final Map<String, int> conteos;

  /// Recibe la CLAVE del tipo tocado (p. ej. `'paquete'`, no «Paquetes»).
  final ValueChanged<String> onTipo;

  static const _tipos = [
    (key: 'todos', label: 'Todos'),
    (key: 'producto', label: 'Productos'),
    (key: 'servicio', label: 'Servicios'),
    (key: 'paquete', label: 'Paquetes'),
    (key: 'proveedor', label: 'Proveedores'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < _tipos.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            CatalogChip(
              label: _tipos[i].label,
              active: tipo == _tipos[i].key,
              dark: true,
              onTap: () => onTipo(_tipos[i].key),
              trailing: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '${conteos[_tipos[i].key] ?? 0}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: (tipo == _tipos[i].key ? Colors.white : cs.onSurface)
                        .withValues(alpha: .7),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
