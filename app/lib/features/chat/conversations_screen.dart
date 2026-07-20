import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

const _tabs = [
  ('abierto', 'Abierto'),
  ('cerrado', 'Completado'),
  ('perdido', 'No concretado'),
];

Color _statusColor(BuildContext c, String s) => switch (s) {
      'abierto' => Theme.of(c).colorScheme.primary,
      'cerrado' => Theme.of(c).brightness == Brightness.dark
          ? JayaloColors.dSuccess
          : JayaloColors.success,
      _ => Theme.of(c).colorScheme.outline,
    };

class ConversationsScreen extends StatefulWidget {
  /// [leading] y [actions] son inyectables (mismo patrón que `CatalogView`/
  /// `ProviderInboxView`) para poder probar el contrato del header sin montar
  /// `HeaderAvatar`/`HeaderBell` de verdad — ambos tocan Supabase en su
  /// `initState` (perfil/conteo) y esta app no inicializa Supabase en los tests
  /// de widgets.
  ///
  /// I1 (invariante que se preserva del AppBar viejo): Mensajes es la única
  /// pestaña raíz sin acceso propio a Notificaciones y al menú de perfil
  /// (Ajustes/Estadísticas) si el header no los trae — por eso el avatar
  /// (→ menú) va de leading y la campana (→ notificaciones) de acción.
  const ConversationsScreen({
    super.key,
    this.leading = const HeaderAvatar(),
    this.actions = const [HeaderBell()],
  });

  final Widget leading;
  final List<Widget> actions;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, dynamic>>? _all;
  bool _error = false;
  String _tab = 'abierto';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final rows = await conversationsList();
      if (mounted) setState(() => _all = rows);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: widget.leading,
          title: 'Mensajes',
          actions: widget.actions,
        ),
        Expanded(
          child: _error
              ? ErrorRetry(
                  onRetry: _load, message: 'No pudimos cargar tus mensajes')
              : all == null
                  ? const JayaloLoaderBlock()
                  : RefreshIndicator(onRefresh: _load, child: _body(all)),
        ),
      ]),
    );
  }

  Widget _body(List<Map<String, dynamic>> all) {
    final counts = <String, int>{};
    for (final c in all) {
      counts[c['status'] as String] = (counts[c['status'] as String] ?? 0) + 1;
    }
    final term = _q.trim().toLowerCase();
    final filtered = all
        .where((c) => c['status'] == _tab)
        .where((c) =>
            term.isEmpty ||
            ((c['product_name'] as String?) ?? '').toLowerCase().contains(term) ||
            ((c['peer_name'] as String?) ?? '').toLowerCase().contains(term))
        .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: PillSegmented(
          options: [
            for (final (v, label) in _tabs)
              counts[v] == null ? label : '$label ${counts[v]}',
          ],
          index: _tabs.indexWhere((t) => t.$1 == _tab),
          onChanged: (i) => setState(() => _tab = _tabs[i].$1),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: _SearchPill(
          hint: 'Buscar conversación',
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      // Contenedor blanco a sangre con filas PLANAS separadas por línea fina
      // (doctrina: la lista de conversaciones se reconoce por ser plana, no una
      // pila de tarjetas flotantes).
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                message: _tab == 'abierto'
                    ? 'Sin conversaciones abiertas.\nLas conversaciones empiezan cuando contactas a un proveedor.'
                    : _tab == 'cerrado'
                        ? 'Sin conversaciones completadas.'
                        : 'Sin conversaciones no concretadas.',
              )
            : Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  padding: EdgeInsets.only(
                      top: 6, bottom: 6 + navBarReservedSpace(context)),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      indent: 22,
                      endIndent: 22,
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: .5)),
                  itemBuilder: (context, i) =>
                      _ConversationRow(c: filtered[i], onOpen: _open)
                          .cascadeIn(i),
                ),
              ),
      ),
    ]);
  }

  Future<void> _open(Map<String, dynamic> c) async {
    // Task I-2: pasa peer_name/avatar ya resueltos en esta lista para que
    // ChatScreen no tenga que llamar de nuevo al RPC agregado
    // `conversationsList()` solo para esos dos campos.
    await context.push('/messages/${c['id']}', extra: {
      'peer_name': c['peer_name'],
      'peer_avatar_url': c['peer_avatar_url'],
    });
    _load(); // refresh al volver del chat (badges/último mensaje)
  }
}

/// Buscador blanco redondeado (píldora) — reemplaza el TextField gris; sigue
/// filtrando de verdad (a diferencia del buscador del home, que es un hueco).
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        boxShadow: jayaloCardShadow(context),
      ),
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(children: [
        Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
              filled: false,
              border: InputBorder.none,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Fila PLANA de conversación (doctrina: la lista de conversaciones se
/// reconoce por ser plana, no una pila de tarjetas). Con no-leídos respira un
/// tinte tenue y suma el badge violeta; al día, va limpia sobre el blanco.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.c, required this.onOpen});
  final Map<String, dynamic> c;
  final Future<void> Function(Map<String, dynamic>) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = (c['unread_count'] as int?) ?? 0;
    final tinted = unread > 0;
    final fg = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final lastAt = c['last_created_at'] ?? c['updated_at'];
    final price = c['agreed_price'] != null
        ? ' · ${fmtRD(c['agreed_price'] as num)}'
        : c['agreed_hourly_rate'] != null
            ? ' · ${fmtRD(c['agreed_hourly_rate'] as num)}/h'
            : '';
    return Material(
      color: tinted ? cs.primaryContainer.withValues(alpha: .35) : Colors.transparent,
      child: InkWell(
        onTap: () => onOpen(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundImage: c['peer_avatar_url'] != null
                    ? NetworkImage(c['peer_avatar_url'] as String)
                    : null,
                child: c['peer_avatar_url'] == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor(
                                  context, c['status'] as String))),
                      Expanded(
                          child: Text(c['peer_name'] as String? ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: tinted
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontSize: 14,
                                  color: tinted ? jayaloHead(context) : fg))),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                        c['last_kind'] == null
                            ? 'Sin mensajes aún'
                            : '${messagePreview(c['last_kind'] as String, c['last_body'] as String? ?? '')}'
                                '${(c['product_name'] as String?)?.isNotEmpty == true ? ' · ${c['product_name']}$price' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            fontWeight:
                                tinted ? FontWeight.w500 : FontWeight.normal)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                      lastAt == null
                          ? ''
                          : formatListTime(
                              DateTime.parse(lastAt as String).toLocal()),
                      style: TextStyle(fontSize: 10.5, color: muted)),
                  if (unread > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('$unread',
                            style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
