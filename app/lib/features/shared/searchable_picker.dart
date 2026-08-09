import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../domain/search_fold.dart';

/// Opción de un [SearchablePickerField]: `value` es lo que viaja al `onPick`
/// (un id o el propio nombre), `label` lo que se pinta y por lo que se busca.
class PickerItem {
  const PickerItem(this.value, this.label);
  final String value;
  final String label;
}

/// Campo "adder" con hoja de búsqueda — sustituye a los
/// `DropdownButtonFormField` de listas largas (rubros, provincias, sectores).
///
/// Pedido PO 2026-08-08: todo dropdown largo lleva buscador y orden
/// alfabético. El orden se garantiza AQUÍ y no en la fuente: el
/// `.order('name')` de Postgres depende de la collation de la BD (puede
/// mandar «Ébano» al final) y el catálogo de ubicaciones viene en orden
/// editorial. [pinned] queda arriba, fuera del orden (p. ej. «🗺️ Todos los
/// sectores», que es una acción, no una opción más de la T).
///
/// Semántica de "adder" (la misma que tenían los dropdowns que sustituye):
/// no retiene selección — al elegir emite [onPick] y el elegido desaparece
/// de las opciones en el siguiente build del padre. Por eso no hay `value`.
class SearchablePickerField extends StatelessWidget {
  const SearchablePickerField({
    super.key,
    required this.hint,
    required this.items,
    required this.onPick,
    this.pinned = const [],
    this.enabled = true,
    this.decoration,
  });

  final String hint;
  final List<PickerItem> items;
  final List<PickerItem> pinned;
  final bool enabled;
  final ValueChanged<String> onPick;

  /// Por defecto imita al `DropdownButtonFormField` que sustituye; los sitios
  /// con contenedor propio pueden pasar una decoración sin borde.
  final InputDecoration? decoration;

  bool get _off => !enabled || (items.isEmpty && pinned.isEmpty);

  Future<void> _open(BuildContext context) async {
    final v = await showSearchablePicker(
      context,
      title: hint,
      items: items,
      pinned: pinned,
    );
    if (v != null) onPick(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deco = decoration ??
        InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: const Icon(Icons.expand_more),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _off ? null : () => _open(context),
      child: InputDecorator(
        decoration: deco,
        // `isEmpty: true` mantiene el label como placeholder (semántica de
        // "adder": nunca hay selección retenida). Si la decoración ya trae
        // `labelText`, el hijo sobraría: se pintaría el texto dos veces.
        isEmpty: true,
        child: deco.labelText != null
            ? null
            : Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: _off
                      ? cs.onSurfaceVariant.withValues(alpha: .5)
                      : cs.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// Hoja modal con buscador. Devuelve el `value` elegido o `null` si se cerró.
Future<String?> showSearchablePicker(
  BuildContext context, {
  required String title,
  required List<PickerItem> items,
  List<PickerItem> pinned = const [],
}) {
  final sorted = [...items]..sort((a, b) => compareFolded(a.label, b.label));
  return showModalBottomSheet<String>(
    context: context,
    sheetAnimationStyle: JayaloMotion.sheetRise,
    isScrollControlled: true,
    builder: (ctx) => _PickerSheet(title: title, pinned: pinned, sorted: sorted),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.pinned,
    required this.sorted,
  });

  final String title;
  final List<PickerItem> pinned;
  final List<PickerItem> sorted;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = searchFold(_query.trim());
    // El buscador también filtra lo fijado: quien teclea está buscando.
    final pinned = q.isEmpty
        ? widget.pinned
        : widget.pinned
            .where((o) => searchFold(o.label).contains(q))
            .toList();
    final visibles = q.isEmpty
        ? widget.sorted
        : widget.sorted
            .where((o) => searchFold(o.label).contains(q))
            .toList();

    // 70% de pantalla: deja ver el contexto de atrás y le cabe el teclado.
    final alto = MediaQuery.sizeOf(context).height * .7;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: alto,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                // Sin autofocus: abrir el teclado encima de la lista antes de
                // que el usuario decida buscar tapa justo lo que vino a ver.
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: (pinned.isEmpty && visibles.isEmpty)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Sin resultados para esa búsqueda.'),
                      ),
                    )
                  : ListView(
                      // El teclado no debe taparle el final a la lista.
                      padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.viewInsetsOf(context).bottom + 12),
                      children: [
                        for (final o in pinned)
                          ListTile(
                            title: Text(o.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            onTap: () => Navigator.of(context).pop(o.value),
                          ),
                        if (pinned.isNotEmpty && visibles.isNotEmpty)
                          const Divider(height: 1),
                        for (final o in visibles)
                          ListTile(
                            title: Text(o.label),
                            onTap: () => Navigator.of(context).pop(o.value),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
