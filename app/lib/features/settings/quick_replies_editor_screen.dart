import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_state.dart';
import '../../domain/chat.dart';
import '../chat/quick_replies_store.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Editor de las RESPUESTAS RÁPIDAS del chat (pedido PO: cada usuario edita
/// partiendo de los defaults). Edita la lista del ROL del usuario: un cliente
/// edita las preguntas que él envía; un proveedor, las suyas. Se puede cambiar
/// el texto, agregar, borrar, reordenar y restaurar los predeterminados. Las
/// que traen botones de respuesta conservan sus botones (solo se edita el
/// texto); agregar una nueva crea un mensaje simple.
class QuickRepliesEditorScreen extends StatefulWidget {
  const QuickRepliesEditorScreen({super.key});

  @override
  State<QuickRepliesEditorScreen> createState() =>
      _QuickRepliesEditorScreenState();
}

/// Fila en edición: el controlador del texto + los botones/confirmaciones que
/// se conservan tal cual (no editables en esta versión) + una key estable para
/// el reordenamiento.
class _EditItem {
  _EditItem(this.ctrl, this.options, this.replies) : key = UniqueKey();
  final TextEditingController ctrl;
  final List<String> options;
  final Map<String, String> replies;
  final Key key;

  factory _EditItem.from(QuickItem q) =>
      _EditItem(TextEditingController(text: q.question), List.of(q.options),
          Map.of(q.replies));

  QuickItem toQuickItem() => QuickItem(ctrl.text.trim(), options, replies);
}

class _QuickRepliesEditorScreenState extends State<QuickRepliesEditorScreen> {
  late final bool _provider = roleStore.value == RoleState.provider;
  final List<_EditItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    await quickRepliesStore.ensureLoaded();
    _fill(quickRepliesStore.forProvider(_provider));
    if (mounted) setState(() => _loading = false);
  }

  void _fill(List<QuickItem> list) {
    for (final it in _items) {
      it.ctrl.dispose();
    }
    _items
      ..clear()
      ..addAll(list.map(_EditItem.from));
  }

  void _add() {
    setState(() => _items.add(_EditItem(TextEditingController(), const [], const {})));
  }

  void _removeAt(int i) {
    final it = _items.removeAt(i);
    it.ctrl.dispose();
    setState(() {});
  }

  // `onReorderItem` entrega el newIndex YA ajustado para el hueco del ítem que
  // se saca (a diferencia del viejo `onReorder`, que había que corregir a mano).
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final it = _items.removeAt(oldIndex);
      _items.insert(newIndex, it);
    });
  }

  Future<void> _save() async {
    final items = _items
        .map((e) => e.toQuickItem())
        .where((q) => q.question.isNotEmpty)
        .toList();
    setState(() => _saving = true);
    try {
      await quickRepliesStore.save(provider: _provider, items: items);
      if (!mounted) return;
      showJayaloToast(context, 'Respuestas guardadas');
      context.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showJayaloToast(context, 'No se pudo guardar. Intenta de nuevo.');
      }
    }
  }

  Future<void> _restoreDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar predeterminados?'),
        content: const Text(
            'Se descartarán tus cambios y volverán las respuestas rápidas originales.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await quickRepliesStore.resetToDefaults(provider: _provider);
      if (!mounted) return;
      setState(() {
        _fill(quickRepliesStore.forProvider(_provider));
        _saving = false;
      });
      showJayaloToast(context, 'Predeterminados restaurados');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showJayaloToast(context, 'No se pudo restaurar. Intenta de nuevo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () => context.pop(),
          ),
          title: 'Respuestas rápidas',
          subtitle: _provider
              ? 'Las preguntas que envías a tus clientes'
              : 'Las preguntas que envías a los proveedores',
          titleAlign: HeaderTitleAlign.center,
          actions: [
            HeaderCircleButton(
              icon: Icons.restore,
              tooltip: 'Restaurar predeterminados',
              onTap: () {
                if (!_saving) _restoreDefaults();
              },
            ),
          ],
        ),
        if (_loading)
          const Expanded(child: JayaloLoaderBlock())
        else
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 12 + navBarReservedSpace(context)),
              itemCount: _items.length,
              onReorderItem: _onReorder,
              header: Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                child: Text(
                  'Edita el texto, reordénalas arrastrando, borra las que no uses '
                  'o agrega las tuyas. Las que muestran botones conservan sus '
                  'opciones de respuesta.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
              footer: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar respuesta'),
                ),
              ),
              itemBuilder: (context, i) => _buildRow(i),
            ),
          ),
        _bottomBar(),
      ]),
    );
  }

  Widget _buildRow(int i) {
    final it = _items[i];
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: it.key,
      padding: const EdgeInsets.only(bottom: 10),
      child: JayaloCard(
        margin: EdgeInsets.zero,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Asa de arrastre para reordenar.
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Icon(Icons.drag_handle, size: 20, color: cs.outline),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: it.ctrl,
                minLines: 1,
                maxLines: 3,
                maxLength: maxMessageLen,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                decoration: filledField(context, 'Mensaje'),
              ),
              if (it.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in it.options)
                    Chip(
                      label: Text(o, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('El cliente responde con estos botones.',
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ),
              ],
            ]),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: Icon(Icons.delete_outline, color: cs.error),
            onPressed: () => _removeAt(i),
          ),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const JayaloSpinner(size: 16, color: Colors.white)
                : const Text('Guardar cambios'),
          ),
        ),
      ),
    );
  }
}
