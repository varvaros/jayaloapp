import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../core/brand.dart';
import '../../data/repos.dart'
    show categoriasConCatalogoTodas, rubrosForCategories;
import '../../domain/catalog.dart';
import '../shared/brand_kit.dart';
import '../../core/motion.dart';
import 'catalog_articulos.dart' show FiltrosLateral;

/// Resultado de la hoja: categoría (+ rubro) y filtros elegidos. `null` como
/// retorno de `showCatalogFilterSheet` = el usuario cerró sin cambiar.
/// `CatalogFilterResult.limpio()` apaga todo (categoría, rubro y los
/// bloques de Ubicación/Precio/Proveedor).
class CatalogFilterResult {
  const CatalogFilterResult(
    this.categoryId,
    this.rubro, {
    this.ciudad,
    this.precioMin = 0,
    this.precioMax = 0,
    this.soloVerificados = false,
    this.conLocal = false,
  });

  const CatalogFilterResult.limpio()
    : categoryId = null,
      rubro = null,
      ciudad = null,
      precioMin = 0,
      precioMax = 0,
      soloVerificados = false,
      conLocal = false;

  final String? categoryId;
  final String? rubro;
  final String? ciudad;

  /// 0 = sin filtro.
  final int precioMin;
  final int precioMax;
  final bool soloVerificados;
  final bool conLocal;
}

Future<CatalogFilterResult?> showCatalogFilterSheet(
  BuildContext context, {
  String? categoryId,
  String? rubro,
  required List<String> ciudades,
  required FiltrosLateral filtros,
  Future<Set<String>?> Function() categoriasVivas = categoriasConCatalogoTodas,
}) => showModalBottomSheet<CatalogFilterResult>(
  sheetAnimationStyle: JayaloMotion.sheetRise,
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: .85,
    child: _CatalogFilterSheet(
      categoryId: categoryId,
      rubro: rubro,
      ciudades: ciudades,
      filtros: filtros,
      categoriasVivas: categoriasVivas,
    ),
  ),
);

class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({
    this.categoryId,
    this.rubro,
    required this.ciudades,
    required this.filtros,
    required this.categoriasVivas,
  });
  final String? categoryId;
  final String? rubro;
  final List<String> ciudades;
  final FiltrosLateral filtros;
  final Future<Set<String>?> Function() categoriasVivas;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  final _searchCtrl = TextEditingController();
  late final TextEditingController _precioMinCtrl;
  late final TextEditingController _precioMaxCtrl;
  String _query = '';
  String? _expanded; // categoría desplegada (acordeón)
  List<Map<String, dynamic>>? _rubros; // rubros de _expanded (lazy)
  // Categorías con artículos publicados. `null` mientras no llega (o si la
  // RPC falla): en ese hueco NO se filtra — igual que la web, un flash de
  // lista completa es mejor que una hoja vacía.
  Set<String>? _vivas;

  late String? _ciudad;
  late bool _soloVerificados;
  late bool _conLocal;

  @override
  void initState() {
    super.initState();
    _ciudad = widget.filtros.ciudad;
    _soloVerificados = widget.filtros.soloVerificados;
    _conLocal = widget.filtros.conLocal;
    _precioMinCtrl = TextEditingController(
      text: widget.filtros.precioMin == 0 ? '' : '${widget.filtros.precioMin}',
    );
    _precioMaxCtrl = TextEditingController(
      text: widget.filtros.precioMax == 0 ? '' : '${widget.filtros.precioMax}',
    );
    widget.categoriasVivas().then((v) {
      if (mounted) setState(() => _vivas = v);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _precioMinCtrl.dispose();
    _precioMaxCtrl.dispose();
    super.dispose();
  }

  List<Category> get _filtered {
    // Solo categorías navegables (decisión PO 2026-08-31, paridad web); la
    // seleccionada nunca se oculta. La búsqueda corre SOBRE las navegables.
    final base = categoriasNavegables(
      kCategories,
      _vivas,
      seleccionada: widget.categoryId,
    );
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((c) => c.name.toLowerCase().contains(q)).toList();
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

  int get _precioMin => int.tryParse(_precioMinCtrl.text) ?? 0;
  int get _precioMax => int.tryParse(_precioMaxCtrl.text) ?? 0;

  /// La ciudad SELECCIONADA nunca se oculta: si desapareciera de
  /// `widget.ciudades`, el filtro seguiría aplicado sin control visible para
  /// quitarlo (misma regla que la web).
  List<String> get _opcionesCiudad {
    final opciones = [...widget.ciudades];
    if (_ciudad != null && !opciones.contains(_ciudad)) {
      opciones.add(_ciudad!);
    }
    opciones.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return opciones;
  }

  /// Resultado con los filtros vigentes de esta hoja (Ubicación/Precio/
  /// Proveedor) para la categoría/rubro dados — usado tanto por «Aplicar»
  /// (categoría/rubro sin tocar) como por un tap en el acordeón (categoría/
  /// rubro nuevos).
  CatalogFilterResult _resultado(String? categoryId, String? rubro) =>
      CatalogFilterResult(
        categoryId,
        rubro,
        ciudad: _ciudad,
        precioMin: _precioMin,
        precioMax: _precioMax,
        soloVerificados: _soloVerificados,
        conLocal: _conLocal,
      );

  @override
  Widget build(BuildContext context) {
    // Estado EN VIVO, no el filtros con el que se abrió la hoja: si el
    // usuario escribe un precio o toca "Solo verificados" sin haber entrado
    // con filtros, "Limpiar" debe aparecer igual.
    final hasFilter =
        widget.categoryId != null ||
        widget.rubro != null ||
        _ciudad != null ||
        _precioMin > 0 ||
        _precioMax > 0 ||
        _soloVerificados ||
        _conLocal;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Text(
                  'Filtrar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: jayaloHead(context),
                  ),
                ),
                const Spacer(),
                if (hasFilter)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const CatalogFilterResult.limpio(),
                    ),
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                const SectionHeader(text: 'Ubicación'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _ciudad,
                    decoration: filledField(context, 'Ciudad'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las ciudades'),
                      ),
                      for (final c in _opcionesCiudad)
                        DropdownMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _ciudad = v),
                  ),
                ),
                const SectionHeader(text: 'Precio'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _precioMinCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: filledField(context, 'Desde RD\$'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _precioMaxCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: filledField(context, 'Hasta RD\$'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(text: 'Proveedor'),
                SwitchListTile(
                  title: const Text('Solo verificados'),
                  value: _soloVerificados,
                  onChanged: (v) => setState(() => _soloVerificados = v),
                ),
                SwitchListTile(
                  title: const Text('Con local'),
                  value: _conLocal,
                  onChanged: (v) => setState(() => _conLocal = v),
                ),
                const SectionHeader(text: 'Categorías'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: filledField(context, 'Buscar categoría…'),
                  ),
                ),
                for (final c in _filtered) ...[
                  ListTile(
                    title: Text(c.name),
                    trailing: Icon(
                      _expanded == c.id ? Icons.expand_less : Icons.expand_more,
                    ),
                    selected: widget.categoryId == c.id,
                    onTap: () => _expand(c.id),
                  ),
                  if (_expanded == c.id)
                    _RubroList(
                      categoryName: c.name,
                      rubros: _rubros,
                      selectedRubro: widget.categoryId == c.id
                          ? widget.rubro
                          : null,
                      onAll: () =>
                          Navigator.pop(context, _resultado(c.id, null)),
                      onRubro: (r) =>
                          Navigator.pop(context, _resultado(c.id, r)),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _resultado(widget.categoryId, widget.rubro),
                  ),
                  child: const Text('Aplicar'),
                ),
              ),
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
    return Column(
      children: [
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
      ],
    );
  }
}
