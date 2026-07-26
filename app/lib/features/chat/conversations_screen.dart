import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/violet_header.dart';
import 'funnel_status_store.dart';
import 'opened_conversations.dart';

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
    this.loadConversations = conversationsList,
  });

  final Widget leading;
  final List<Widget> actions;

  /// Inyectable para el test de regresión del refresh al volver del chat —
  /// el real toca Supabase, que no se inicializa en los widget-tests.
  final Future<List<Map<String, dynamic>>> Function() loadConversations;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, dynamic>>? _all;
  bool _error = false;
  String _tab = 'abierto';
  String _q = '';

  /// Refresh al VOLVER a esta pantalla (badges/último mensaje). No puede
  /// depender del future de `context.push`: el atrás del chat hace
  /// `go('/messages')` (pedido PO 2026-07-21) y en go_router un `go` REMUEVE
  /// la ruta apilada SIN completar su future (solo `pop` lo completa) — el
  /// `await push` de antes se quedaba colgado y la lista nunca refrescaba
  /// (bug PO: "el contador de pendientes no desaparece al entrar"). En su
  /// lugar se escucha el `routeInformationProvider` del router (el delegate
  /// NO sirve: su uri no se mueve con pushes imperativos): cuando la lista
  /// vuelve a ser la ruta actual (por pop O por go), se recarga.
  GoRouter? _router;
  bool _wasCurrent = false;

  /// Mi user id (para saber en qué conversaciones soy el PROVEEDOR: el estado
  /// de embudo es solo mío y solo aplica a esas). En los widget-tests Supabase
  /// no está inicializado → guarda en try/catch (queda null, sin funnel).
  String? _uid;

  @override
  void initState() {
    super.initState();
    try {
      _uid = supa.auth.currentUser?.id;
    } catch (_) {}
    _load();
    // Estado de embudo (local): repintar la lista cuando cambie desde el chat.
    funnelStatusStore.ensureLoaded();
    funnelStatusStore.addListener(_onStoreChanged);
    // "Nueva" = conversación no abierta: la lista se repinta al instante cuando
    // el chat marca una conversación abierta (sin depender del reload por ruta).
    openedConversationsStore.ensureLoaded();
    openedConversationsStore.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // maybeOf: los widget-tests del header montan la pantalla sin router.
    final router = GoRouter.maybeOf(context);
    if (router != null && !identical(router, _router)) {
      _router?.routeInformationProvider.removeListener(_onRouteChanged);
      _router = router..routeInformationProvider.addListener(_onRouteChanged);
      _wasCurrent = _isCurrent;
    }
  }

  bool get _isCurrent =>
      _router?.routeInformationProvider.value.uri.path == '/messages';

  void _onRouteChanged() {
    final now = _isCurrent;
    if (now && !_wasCurrent && mounted) _load();
    _wasCurrent = now;
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_onRouteChanged);
    funnelStatusStore.removeListener(_onStoreChanged);
    openedConversationsStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final rows = await widget.loadConversations();
      // Contador EXACTO del badge de la barra: aquí ya tenemos el unread real
      // de cada conversación, sin un fetch extra.
      messagesBadge.set(
          rows.fold<int>(0, (s, c) => s + ((c['unread_count'] as int?) ?? 0)));
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
                  itemBuilder: (context, i) => _ConversationRow(
                        c: filtered[i],
                        onOpen: _open,
                        isNew: !openedConversationsStore
                            .contains(filtered[i]['id'] as String),
                        // Estado de embudo SOLO en las conversaciones donde soy
                        // el proveedor (es mi herramienta privada).
                        funnel: filtered[i]['provider_user_id'] == _uid
                            ? funnelStatusByKey(
                                funnelStatusStore.statusKey(filtered[i]['id'] as String))
                            : null,
                      ).cascadeIn(i),
                ),
              ),
      ),
    ]);
  }

  void _open(Map<String, dynamic> c) {
    // Task I-2: pasa peer_name/avatar ya resueltos en esta lista para que
    // ChatScreen no tenga que llamar de nuevo al RPC agregado
    // `conversationsList()` solo para esos dos campos.
    // El refresh al volver lo hace el listener del router (_onRouteChanged):
    // aquí NO se puede esperar el future del push — con el atrás del chat en
    // `go('/messages')` ese future no se completa nunca.
    context.push('/messages/${c['id']}', extra: {
      'peer_name': c['peer_name'],
      'peer_avatar_url': c['peer_avatar_url'],
    });
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
  const _ConversationRow(
      {required this.c, required this.onOpen, this.isNew = false, this.funnel});
  final Map<String, dynamic> c;
  final void Function(Map<String, dynamic>) onOpen;

  /// "Nueva": el usuario todavía no ha ABIERTO esta conversación.
  final bool isNew;

  /// Estado de embudo (privado del proveedor) o null. Tiene prioridad sobre
  /// el chip "Nueva".
  final FunnelStatus? funnel;

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
                    ? jayaloAvatarImage(c['peer_avatar_url'] as String, 46, context)
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
                      // Estado de embudo (privado del proveedor) tiene
                      // prioridad; si no, "Nueva" = nunca has hablado aquí.
                      if (funnel != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: funnel!.color.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: funnel!.color.withValues(alpha: .55)),
                          ),
                          child: Text('${funnel!.emoji} ${funnel!.label}',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: funnel!.color)),
                        ),
                      ] else if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('Nueva',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
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
