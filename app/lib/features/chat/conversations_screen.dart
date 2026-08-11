import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/chat_time.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/swipe_to_actions.dart';
import '../shared/verified_badges.dart';
import '../shared/violet_header.dart';
import 'funnel_status_store.dart';
import 'opened_conversations.dart';
import 'widgets/conversation_actions.dart';

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

  /// Un solo row de swipe abierto a la vez (mismo patrón que Solicitudes).
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);

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

  /// Sellos de verificación de la contraparte, por peer user id (PO
  /// 2026-07-28: "deberían aparecer... sobre el avatar"). Best-effort: si la
  /// RPC falla, queda vacío y la lista se pinta igual, sin ✓.
  Map<String, PeerBadges> _badges = const {};

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
    _openRow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final rows = await widget.loadConversations();
      // Sellos de la contraparte (RPC de la migración 20260728120000).
      // Best-effort: si falla (o si alguna fila viniera sin los ids esperados),
      // la lista se pinta igual, sin ✓ — nunca debe tumbar la carga de la
      // lista. Va en un viaje aparte a propósito: los ids del peer salen de
      // `rows`, así que no puede ir en paralelo con la carga de la lista.
      try {
        final uid = supa.auth.currentUser?.id;
        final peerIds = <String>{
          for (final r in rows)
            if ((r['customer_id'] == uid
                    ? r['provider_user_id']
                    : r['customer_id'])
                case final String id)
              id,
        }.toList();
        _badges = await peerVerificationBadges(peerIds);
      } catch (_) {
        _badges = const {};
      }
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
                  : JayaloRefresh(onRefresh: _load, child: _body(all)),
        ),
      ]),
    );
  }

  Widget _body(List<Map<String, dynamic>> all) {
    // Los archivados salen de las tres pestañas normales y de sus conteos:
    // archivar es "quítamelo de la bandeja".
    final archived = all.where(conversationArchived).toList();
    final live = all.where((c) => !conversationArchived(c)).toList();
    final counts = <String, int>{};
    for (final c in live) {
      counts[c['status'] as String] = (counts[c['status'] as String] ?? 0) + 1;
    }
    // La cuarta píldora solo existe si hay algo que mostrar en ella.
    final tabs = [
      ..._tabs,
      if (archived.isNotEmpty) ('archivados', 'Archivados'),
    ];
    // Si la píldora desaparece (se desarchivó el último), el estado efectivo
    // vuelve a Abierto — NO solo el índice pintado. Se resuelve como variable
    // local derivada (nunca `setState` durante `build`): si `_tab` sigue
    // siendo 'archivados' cuando esa pestaña ya no existe, todo lo que lee
    // `effectiveTab` (contenido, resaltado de la píldora, acciones del swipe,
    // mensaje vacío) cae a 'abierto' de forma consistente, en vez de dejar la
    // píldora pintada como "Abierto" mientras el contenido sigue filtrando
    // por archivados (lista vacía y píldora mintiendo).
    final tabIndex = tabs.indexWhere((t) => t.$1 == _tab);
    final effectiveTab = tabIndex == -1 ? 'abierto' : _tab;
    final safeIndex = tabIndex == -1 ? 0 : tabIndex;
    final term = _q.trim().toLowerCase();
    final source = effectiveTab == 'archivados'
        ? archived
        : live.where((c) => c['status'] == effectiveTab);
    final filtered = source
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
            for (final (v, label) in tabs)
              v == 'archivados'
                  ? '$label ${archived.length}'
                  : counts[v] == null
                      ? label
                      : '$label ${counts[v]}',
          ],
          index: safeIndex,
          onChanged: (i) => setState(() => _tab = tabs[i].$1),
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
                // Jayi con su celular recibiendo mensajes (mockup aprobado
                // PO 08-10, burbujas verdes): SOLO en el vacío de Mensajes,
                // los demás EmptyState de la app siguen con la mascota.
                illustration: const Center(child: _JayiCelular()),
                message: effectiveTab == 'archivados'
                    ? 'Sin conversaciones archivadas.'
                    : effectiveTab == 'abierto'
                        ? 'Sin conversaciones abiertas.\nLas conversaciones empiezan cuando contactas a un proveedor.'
                        : effectiveTab == 'cerrado'
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
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final peerId = (c['customer_id'] == _uid
                        ? c['provider_user_id']
                        : c['customer_id']) as String?;
                    final convId = c['id'] as String;
                    final asProvider = c['provider_user_id'] == _uid;
                    final row = _ConversationRow(
                      c: c,
                      onOpen: _open,
                      isNew: !openedConversationsStore.contains(convId),
                      // Estado de embudo SOLO en las conversaciones donde soy
                      // el proveedor (es mi herramienta privada).
                      funnel: c['provider_user_id'] == _uid
                          ? funnelStatusByKey(
                              funnelStatusStore.statusKey(convId))
                          : null,
                      badge: peerId != null ? _badges[peerId] : null,
                    );
                    return SwipeToActions(
                      id: convId,
                      group: _openRow,
                      // La lista de chats es PLANA (filas con divisor, no
                      // tarjetas): sin radio ni margen propio.
                      radius: 0,
                      margin: EdgeInsets.zero,
                      actions: [
                        // "No concretado" solo tiene sentido en un chat vivo.
                        if (effectiveTab == 'abierto')
                          SwipeAction(
                            icon: Icons.cancel_outlined,
                            // "Marcar no concretado", no "No concretado" a
                            // secas: la PÍLDORA del filtro ya usa ese literal
                            // exacto, y la ambigüedad era tal que el propio
                            // test tuvo que acotar el finder para distinguir
                            // los dos (revisión final, 2026-08-01). Si el test
                            // necesita desambiguar, el usuario también.
                            label: 'Marcar no concretado',
                            color: Theme.of(context).colorScheme.error,
                            onTap: () => _markLost(convId),
                          ),
                        SwipeAction(
                          icon: effectiveTab == 'archivados'
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          label: effectiveTab == 'archivados'
                              ? 'Desarchivar'
                              : 'Archivar',
                          color: Theme.of(context).colorScheme.outline,
                          onTap: () => _setArchived(
                            convId,
                            effectiveTab != 'archivados',
                            asProvider,
                          ),
                        ),
                      ],
                      child: row,
                    ).cascadeIn(i);
                  },
                ),
              ),
      ),
    ]);
  }

  /// Marcar no concretado: IRREVERSIBLE, así que siempre pasa por confirmación.
  Future<void> _markLost(String convId) async {
    if (!await confirmMarkLost(context)) return;
    try {
      await markConversationLost(convId);
    } catch (_) {
      if (mounted) {
        showJayaloToast(context, 'No se pudo marcar. Intenta de nuevo.');
      }
      return;
    }
    // Acuse explícito: el ⋮ del chat sí lo daba y la lista no. Sin él, una
    // acción que el usuario acaba de confirmar como IRREVERSIBLE no producía
    // ninguna señal y invitaba a repetirla (revisión final, 2026-08-01).
    if (mounted) showJayaloToast(context, 'Marcado como no concretado.');
    if (mounted) await _load();
  }

  Future<void> _setArchived(
      String convId, bool archived, bool asProvider) async {
    try {
      await setConversationArchived(convId, archived, asProvider: asProvider);
    } catch (_) {
      if (mounted) {
        showJayaloToast(context, 'No se pudo archivar. Intenta de nuevo.');
      }
      return;
    }
    if (mounted) {
      showJayaloToast(
          context, archived ? 'Conversación archivada.' : 'Conversación restaurada.');
    }
    if (mounted) await _load();
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
      {required this.c,
      required this.onOpen,
      this.isNew = false,
      this.funnel,
      this.badge});
  final Map<String, dynamic> c;
  final void Function(Map<String, dynamic>) onOpen;

  /// "Nueva": el usuario todavía no ha ABIERTO esta conversación.
  final bool isNew;

  /// Estado de embudo (privado del proveedor) o null. Tiene prioridad sobre
  /// el chip "Nueva".
  final FunnelStatus? funnel;

  /// Sellos de verificación de la contraparte (o null si no hay relación
  /// registrada / la RPC falló). Pasado explícito desde `_ConversationsScreenState`
  /// — nunca leído de un `static` ni de una global.
  final PeerBadges? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = (c['unread_count'] as int?) ?? 0;
    final tinted = unread > 0;
    final fg = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final lastAt = c['last_created_at'] ?? c['updated_at'];
    // Asunto del chat: para las conversaciones de OFERTA, `product_name` ES el
    // título de la solicitud (lo fija `get_or_create_conversation` desde
    // `provider_offers.request_title`); para las de producto, el nombre del
    // producto. En ambos casos es "qué se está negociando".
    final subject = (c['product_name'] as String?)?.trim() ?? '';
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
              Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(
                  radius: 23,
                  backgroundImage: c['peer_avatar_url'] != null
                      ? jayaloAvatarImage(
                          c['peer_avatar_url'] as String, 46, context)
                      : null,
                  child: c['peer_avatar_url'] == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: VerifiedTick(
                    whatsappVerified: badge?.whatsappVerified ?? false,
                    idVerified: badge?.idVerified ?? false,
                  ),
                ),
              ]),
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
                                  fontWeight: FontWeight.bold,
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
                    // El asunto va en su PROPIA línea (pedido PO 2026-07-28:
                    // "el chat solo tiene los nombres, debo entrar para saber
                    // qué se está negociando"). Antes iba pegado al FINAL del
                    // último mensaje, así que el ellipsis se lo comía casi
                    // siempre. Jerarquía: nombre > asunto > mensaje.
                    if (subject.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // Asunto · precio EN VIOLETA (mockup aprobado PO
                      // 2026-08-10): la segunda línea entera es "qué se
                      // negocia", el precio solo sube el peso.
                      Text.rich(
                          TextSpan(children: [
                            TextSpan(text: subject),
                            if (price.isNotEmpty)
                              TextSpan(
                                  text: price,
                                  style:
                                      const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.primary)),
                    ],
                    const SizedBox(height: 2),
                    // El aviso del cron de inactividad NO es un preview: va
                    // como chip ámbar compacto y deja de comerse el último
                    // mensaje real (mockup aprobado PO 2026-08-10).
                    if (c['last_kind'] != null &&
                        isInactivityWarning(c['last_body'] as String? ?? ''))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB47A1D)
                                .withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('⏳ Se cierra pronto por inactividad',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB47A1D))),
                        ),
                      )
                    else
                      Text(
                          c['last_kind'] == null
                              ? 'Sin mensajes aún'
                              : messagePreview(c['last_kind'] as String,
                                  c['last_body'] as String? ?? ''),
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

/// Jayi con su celular recibiendo mensajes (mockup aprobado PO 2026-08-10,
/// «burbujas verdes y un poco más lentas»): painter propio, cero assets
/// nuevos. Cada ~1,9 s entra un mensaje — el celular zumba y su pantallita
/// destella, una burbujita VERDE hace pop y sube flotando hasta apagarse
/// alternando el lado, y Jayi pestañea. Mismo patrón que los Jayi de
/// Mis ofertas y Recargar créditos: frame fijo en tests y con «reducir
/// movimiento».
class _JayiCelular extends StatefulWidget {
  const _JayiCelular();

  @override
  State<_JayiCelular> createState() => _JayiCelularState();
}

class _JayiCelularState extends State<_JayiCelular>
    with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));

  /// La línea de tiempo de los mensajes: zumbido, destello, burbuja y
  /// pestañeo comparten controller (impactos en .15/.45/.75) y quedan
  /// sincronizados gratis, como en el mockup CSS.
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5600));

  /// En widget-tests el bucle infinito rompe TODO `pumpAndSettle` de la
  /// pantalla (nunca "asienta"): frame fijo. `Platform.environment` y no
  /// `bool.fromEnvironment` (ese dart-define NO está definido bajo
  /// `flutter test` y el gate no gateaba).
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enTest || JayaloMotion.reduced(context)) {
      _bob.stop();
      _fx.stop();
    } else {
      if (!_bob.isAnimating) _bob.repeat(reverse: true);
      if (!_fx.isAnimating) _fx.repeat();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estatico = _enTest || JayaloMotion.reduced(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_bob, _fx]),
      builder: (_, _) => CustomPaint(
        key: const ValueKey('jayi_celular'),
        size: const Size(190, 190),
        painter: _JayiCelularPainter(
            bob: _bob.value, fx: _fx.value, estatico: estatico),
      ),
    );
  }
}

class _JayiCelularPainter extends CustomPainter {
  _JayiCelularPainter(
      {required this.bob, required this.fx, required this.estatico});

  /// 0..1 con repeat(reverse): el flote de toda la escena.
  final double bob;

  /// 0..1 en bucle de 5,6 s: mensajes en .15, .45 y .75.
  final double fx;

  /// Frame fijo (tests / «reducir movimiento»): Jayi quieto con una burbuja
  /// visible a media subida.
  final bool estatico;

  static const _violetaTubo = Color(0xFF6B40EE);
  static const _cuerpoA = Color(0xFF7E56F5);
  static const _cuerpoB = Color(0xFF6438E8);
  static const _verde = Color(0xFF2E9E6B);
  static const _lila = Color(0xFFF1ECFE);

  /// Origen del sistema local de Jayi (118×112) dentro del lienzo 190×190.
  static const _jayiX = 36.0;
  static const _jayiY = 78.0;

  /// De dónde nacen las burbujas: justo sobre el celular.
  static const _nido = Offset(_jayiX + 58, _jayiY + 62);

  /// Instantes de mensaje y hacia qué lado sube cada burbuja.
  static const _impactos = [.15, .45, .75];
  static const _lados = [1.0, -1.0, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(0, -5 * bob);
    _jayi(canvas);
    if (estatico) {
      _globo(canvas, _nido + const Offset(10, -30), 1, 1, puntos: true);
      return;
    }
    for (var i = 0; i < _impactos.length; i++) {
      _globoEnVuelo(canvas, i);
    }
  }

  /// Zumbido del celular: giro amortiguado de ~280 ms tras cada mensaje.
  double get _zumbido {
    if (estatico) return 0;
    for (final ti in _impactos) {
      final u = (fx - ti) / .05;
      if (u >= 0 && u <= 1) {
        return -.09 * math.sin(3 * math.pi * u) * (1 - u);
      }
    }
    return 0;
  }

  /// Destello de la pantallita (0..1) al recibir.
  double get _destello {
    if (estatico) return 0;
    for (final ti in _impactos) {
      final u = (fx - ti - .01) / .07;
      if (u >= 0 && u <= 1) return math.sin(math.pi * u);
    }
    return 0;
  }

  /// Párpado (1 = ojo abierto): pestañeo con cada mensaje.
  double get _ojo {
    if (estatico) return 1;
    for (final ti in _impactos) {
      final u = (fx - ti) / .05;
      if (u >= 0 && u <= 1) return 1 - .88 * math.sin(math.pi * u);
    }
    return 1;
  }

  void _jayi(Canvas canvas) {
    canvas.save();
    canvas.translate(_jayiX, _jayiY);

    final tubo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _violetaTubo;

    // Antenas.
    tubo.strokeWidth = 5;
    canvas.drawPath(
        Path()
          ..moveTo(47, 16)
          ..cubicTo(43, 8, 35, 5, 30, 8),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(65, 15)
          ..cubicTo(69, 7, 77, 4, 82, 7),
        tubo);

    // Cuerpo "tele".
    const bodyRect = Rect.fromLTWH(22, 14, 70, 66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cuerpoA, _cuerpoB],
        ).createShader(bodyRect),
    );

    // Ojo mirando al celular (pupila abajo), con pestañeo por mensaje.
    canvas.save();
    canvas.translate(45, 40);
    canvas.scale(1, _ojo.clamp(.12, 1.0));
    canvas.drawCircle(Offset.zero, 14, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(2, 6), 5.2, Paint()..color = _cuerpoB);
    canvas.restore();

    // Bracitos sujetando el celular.
    tubo.strokeWidth = 7;
    canvas.drawPath(
        Path()
          ..moveTo(27, 62)
          ..cubicTo(18, 70, 22, 82, 34, 86),
        tubo);
    canvas.drawPath(
        Path()
          ..moveTo(88, 62)
          ..cubicTo(97, 70, 93, 82, 81, 86),
        tubo);

    // Celular, con zumbido alrededor de su centro.
    canvas.save();
    const centroCelu = Offset(58, 81);
    canvas.translate(centroCelu.dx, centroCelu.dy);
    canvas.rotate(_zumbido);
    canvas.translate(-centroCelu.dx, -centroCelu.dy);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(43, 58, 30, 46), const Radius.circular(7)),
        Paint()..color = const Color(0xFF3E3560));
    const pantallita = Rect.fromLTWH(46.5, 63, 23, 36);
    canvas.drawRRect(
        RRect.fromRectAndRadius(pantallita, const Radius.circular(4)),
        Paint()..color = _lila);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(53, 60, 10, 2.4), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFF6B5F82));
    // Mini-conversación en la pantallita.
    final burbujita = Paint()..color = const Color(0xFFC9BCF5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(49.5, 68, 13, 4), const Radius.circular(2)),
        burbujita);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(53.5, 75, 13, 4), const Radius.circular(2)),
        Paint()..color = _verde);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(49.5, 82, 10, 4), const Radius.circular(2)),
        burbujita);
    final flash = _destello;
    if (flash > .01) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(pantallita, const Radius.circular(4)),
          Paint()..color = Colors.white.withValues(alpha: .8 * flash));
    }
    canvas.restore();

    // Manitas por delante del celular.
    final mano = Paint()..color = _cuerpoA;
    canvas.drawCircle(const Offset(38, 87), 5.5, mano);
    canvas.drawCircle(const Offset(78, 87), 5.5, mano);

    canvas.restore();
  }

  /// Una burbuja: pop con rebasito, sube en diagonal y se apaga.
  void _globoEnVuelo(Canvas canvas, int i) {
    final ti = _impactos[i];
    // La tercera ventana se recorta al final del ciclo (.75 + .25 = 1.0).
    final ventana = i == 2 ? .25 : .30;
    final u = (fx - ti) / ventana;
    if (u < 0 || u > 1) return;

    double s;
    if (u < .1) {
      final e = u / .1;
      s = .3 + .78 * (1 - (1 - e) * (1 - e)); // ease-out hasta 1.08
    } else if (u < .2) {
      s = 1.08 - .08 * (u - .1) / .1;
    } else {
      s = 1;
    }
    final alpha = u < .08
        ? u / .08
        : u > .85
            ? (1 - u) / .15
            : 1.0;
    final pos = _nido + Offset(_lados[i] * 19 * u, -64 * u);
    _globo(canvas, pos, s, alpha.clamp(0.0, 1.0), puntos: i != 1);
  }

  /// Burbuja verde de chat (46×24 + rabito) centrada en [c]. Con [puntos],
  /// los tres puntitos de «escribiendo...» titilando; si no, renglones.
  void _globo(Canvas canvas, Offset c, double s, double alpha,
      {required bool puntos}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s);

    final cuerpo = Paint()..color = _verde.withValues(alpha: alpha);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 46, height: 24),
            const Radius.circular(7)),
        cuerpo);
    // Rabito hacia el celular.
    canvas.drawPath(
        Path()
          ..moveTo(-14, 10)
          ..lineTo(-20, 18)
          ..lineTo(-8, 11)
          ..close(),
        cuerpo);

    if (puntos) {
      for (var d = 0; d < 3; d++) {
        // Titileo desfasado de los puntitos «escribiendo...».
        final k = estatico
            ? (d == 1 ? 1.0 : .55)
            : .45 +
                .55 * (.5 + .5 * math.sin(2 * math.pi * (fx * 5.3 - d * .17)));
        canvas.drawCircle(Offset(-9 + 9.0 * d, 0), 3,
            Paint()..color = Colors.white.withValues(alpha: alpha * k));
      }
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -5, 22, 3.2),
              const Radius.circular(1.6)),
          Paint()..color = Colors.white.withValues(alpha: alpha * .9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-11, 2, 14, 3.2), const Radius.circular(1.6)),
          Paint()..color = Colors.white.withValues(alpha: alpha * .55));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JayiCelularPainter old) =>
      old.bob != bob || old.fx != fx || old.estatico != estatico;
}
