import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show rubrosForCategories;
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../../core/motion.dart';

/// Resultado de la hoja: categoría (+ rubro) elegidos. `null` como retorno de
/// `showCatalogFilterSheet` = el usuario cerró sin cambiar. Un resultado con
/// ambos en null = "Limpiar".
class CatalogFilterResult {
  const CatalogFilterResult(this.categoryId, this.rubro);
  final String? categoryId;
  final String? rubro;
}

Future<CatalogFilterResult?> showCatalogFilterSheet(BuildContext context,
        {String? categoryId, String? rubro}) =>
    showModalBottomSheet<CatalogFilterResult>(
      sheetAnimationStyle: JayaloMotion.sheetRise,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .85,
        child: _CatalogFilterSheet(categoryId: categoryId, rubro: rubro),
      ),
    );

class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({this.categoryId, this.rubro});
  final String? categoryId;
  final String? rubro;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _expanded; // categoría desplegada (acordeón)
  List<Map<String, dynamic>>? _rubros; // rubros de _expanded (lazy)

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Category> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kCategories;
    return kCategories.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _expand(String catId) async {
    setState(() {
      _expanded = _expanded == catId ? null : catId;
      _rubros = null;
    });
    if (_expanded != catId) return;
    final rows = await rubrosForCategories([catId]);
    if (mounted && _expanded == catId) setState(() => _rubros = rows);
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = widget.categoryId != null || widget.rubro != null;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(children: [
              Text('Filtrar',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: jayaloHead(context))),
              const Spacer(),
              if (hasFilter)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, const CatalogFilterResult(null, null)),
                  child: const Text('Limpiar'),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: filledField(context, 'Buscar categoría…'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in _filtered) ...[
                  ListTile(
                    title: Text(c.name),
                    trailing: Icon(_expanded == c.id
                        ? Icons.expand_less
                        : Icons.expand_more),
                    selected: widget.categoryId == c.id,
                    onTap: () => _expand(c.id),
                  ),
                  if (_expanded == c.id)
                    _RubroList(
                      categoryName: c.name,
                      rubros: _rubros,
                      selectedRubro:
                          widget.categoryId == c.id ? widget.rubro : null,
                      onAll: () =>
                          Navigator.pop(context, CatalogFilterResult(c.id, null)),
                      onRubro: (r) =>
                          Navigator.pop(context, CatalogFilterResult(c.id, r)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RubroList extends StatelessWidget {
  const _RubroList({
    required this.categoryName,
    required this.rubros,
    required this.selectedRubro,
    required this.onAll,
    required this.onRubro,
  });
  final String categoryName;
  final List<Map<String, dynamic>>? rubros;
  final String? selectedRubro;
  final VoidCallback onAll;
  final ValueChanged<String> onRubro;

  @override
  Widget build(BuildContext context) {
    if (rubros == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: JayaloSpinner(size: 18),
        ),
      );
    }
    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        title: Text('Todo $categoryName'),
        selected: selectedRubro == null,
        onTap: onAll,
      ),
      for (final r in rubros!)
        ListTile(
          contentPadding: const EdgeInsets.only(left: 32, right: 16),
          title: Text(r['name'] as String),
          selected: selectedRubro == r['name'],
          onTap: () => onRubro(r['name'] as String),
        ),
    ]);
  }
}
