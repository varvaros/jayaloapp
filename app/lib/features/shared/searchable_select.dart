import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../domain/locations.dart' show normalizeLoose;

/// Selector de UNA opción con buscador — equivalente del `SearchableSelect` de
/// jayalo-main (wizard de proveedor), con dos diferencias deliberadas:
///
/// * **Sin la opción "todos"**: allá el selector define la ZONA DE COBERTURA de
///   un negocio, que puede ser "todas las provincias"; aquí define DÓNDE VIVE
///   una persona, que es un solo lugar. "Todos los sectores" no sería una
///   dirección.
/// * **Selección única** en vez de múltiple, por lo mismo.
///
/// Con muchas opciones (32 provincias) un `DropdownButton` obliga a un scroll
/// largo a ciegas, así que la lista se abre en una hoja con buscador. La
/// búsqueda ignora tildes y mayúsculas: "banica" encuentra "Bánica".
class SearchableSelectField extends StatelessWidget {
  const SearchableSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.disabledHint,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  /// Texto cuando no hay nada elegido y SÍ se puede elegir.
  final String? placeholder;

  /// Texto cuando no hay opciones todavía (p. ej. sector sin ciudad elegida).
  /// Que el campo explique por qué está apagado evita el "no me deja tocar".
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final off = options.isEmpty;
    final shown = value ?? (off ? disabledHint : placeholder) ?? '';
    final isPlaceholder = value == null;

    return Semantics(
      button: true,
      enabled: !off,
      label: label,
      value: value,
      child: InkWell(
        onTap: off ? null : () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          isEmpty: false,
          // Sin decoración propia: hereda el relleno sin línea del tema global
          // (`app.dart`), que es lo que usan el resto de los campos del alta.
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(Icons.expand_more,
                color: off ? cs.onSurfaceVariant.withValues(alpha: .4) : null),
          ),
          child: Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: isPlaceholder
                  ? cs.onSurfaceVariant.withValues(alpha: off ? .5 : .8)
                  : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: JayaloMotion.sheetRise,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SearchSheet(title: label, options: options, selected: value),
    );
    if (picked != null) onChanged(picked);
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String? selected;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = normalizeLoose(_query.text);
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) => normalizeLoose(o).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _filtered;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        // La hoja ocupa como mucho 3/4 de la pantalla: con el teclado abierto
        // deja ver la lista, y con pocas opciones no se estira en vacío.
        height: MediaQuery.of(context).size.height * .75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Buscar',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Limpiar',
                          onPressed: () => setState(_query.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Sin resultados para "${_query.text.trim()}".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  )
                : ListView.builder(
                    // Con el teclado cerrado, el último ítem quedaba pegado al
                    // borde, debajo de la barra de gestos.
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final o = list[i];
                      final isSel = o == widget.selected;
                      return ListTile(
                        title: Text(o),
                        trailing: isSel
                            ? Icon(Icons.check, color: cs.primary)
                            : null,
                        selected: isSel,
                        onTap: () => Navigator.pop(context, o),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
