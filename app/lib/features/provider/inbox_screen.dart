import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shell/floating_nav_bar.dart';
import '../shell/home_scroll.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shared/profile_avatar_button.dart';

/// Signature de las fuentes de datos del inbox: `providerInbox` (Para ti,
/// filtra por rubro del proveedor) y `allOpenRequests` (Todas, cualquier
/// rubro). Inyectada en [ProviderInboxView] para que la pantalla se pueda
/// probar sin red.
typedef InboxFetch = Future<List<Map<String, dynamic>>> Function(
    {String? kind, required bool todas});

class ProviderInboxScreen extends StatelessWidget {
  const ProviderInboxScreen({super.key});

  static Future<List<Map<String, dynamic>>> _fetch(
          {String? kind, required bool todas}) =>
      todas ? allOpenRequests(kind: kind) : providerInbox(kind: kind);

  @override
  Widget build(BuildContext context) =>
      const ProviderInboxView(fetch: _fetch);
}

/// Dibuja el toggle "Para ti/Todas", el filtro de tipo y la lista.
///
/// StatefulWidget porque el toggle y el filtro son estado de UI que vive
/// junto al de carga (mismo espíritu que separar ReputationView/StatsView de
/// sus pantallas, extendido aquí: `fetch` se inyecta para poder montar este
/// widget en tests sin tocar la red). `actions` también es inyectable: por
/// defecto son la campana y el avatar reales, pero [NotificationBell] y
/// [ProfileAvatarButton] tocan `supa` en su `initState` (vía
/// `notifCountStore`/`profileStore`), que revienta si Supabase no está
/// inicializado — en los tests se pasa una lista vacía.
class ProviderInboxView extends StatefulWidget {
  const ProviderInboxView({
    super.key,
    required this.fetch,
    this.actions = const [NotificationBell(), ProfileAvatarButton()],
  });

  final InboxFetch fetch;
  final List<Widget> actions;

  @override
  State<ProviderInboxView> createState() => _ProviderInboxViewState();
}

class _ProviderInboxViewState extends State<ProviderInboxView> {
  String? _kind;

  /// false = "Para ti" (su rubro), true = "Todas" (cualquier rubro).
  /// NO persiste entre sesiones: al entrar siempre arranca en "Para ti", que
  /// es la vista con solicitudes relevantes para ofertar.
  bool _todas = false;

  late Future<List<Map<String, dynamic>>> _load =
      widget.fetch(kind: _kind, todas: _todas);

  // Bloque, no expresión: `setState(() => _load = future)` hace que la
  // closure DEVUELVA ese future (una asignación se evalúa al valor asignado)
  // y Flutter revienta con "setState() callback argument returned a
  // Future." en cuanto se llama (lo descubrió el test del toggle). El mismo
  // patrón roto vive en my_requests_screen.dart, reputation_screen.dart y
  // stats_screen.dart, pero tocar esos archivos queda fuera de esta tarea.
  void _refetch() {
    final next = widget.fetch(kind: _kind, todas: _todas);
    setState(() {
      _load = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(_todas ? 'Todas las solicitudes' : 'Solicitudes para ti'),
          actions: widget.actions),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Para ti')),
              ButtonSegment(value: true, label: Text('Todas')),
            ],
            selected: {_todas},
            onSelectionChanged: (s) {
              _todas = s.first;
              _refetch();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('Todo')),
              ButtonSegment(value: 'producto', label: Text('Productos')),
              ButtonSegment(value: 'servicio', label: Text('Servicios')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              _kind = s.first;
              _refetch();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refetch(),
            child: FutureBuilder(
              future: _load,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const JayaloLoaderBlock();
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return EmptyState(
                    controller: homeScrollController,
                    message: _todas
                        ? 'Ahora mismo no hay solicitudes abiertas.\n'
                            'Vuelve más tarde: entran nuevas todos los días.'
                        : 'Aquí verás las solicitudes que coinciden con tu negocio.\n'
                            'Te avisaremos cuando llegue una nueva.',
                  );
                }
                return ListView.builder(
                  controller: homeScrollController,
                  padding: EdgeInsets.only(
                      top: 8, bottom: 8 + navBarReservedSpace(context)),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return _InboxCard(
                      title: r['title'] as String? ?? '',
                      description: r['description'] as String? ?? '',
                      kind: r['kind'] as String?,
                      createdAt: DateTime.parse(r['created_at'] as String),
                      onTap: () => context.go('/provider/request/${r['id']}'),
                    ).cascadeIn(i);
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Variante "I2 · Con ícono de tipo" (elegida por el PO): tarjeta neutra con
/// el ícono de producto/servicio en contenedor redondeado, como una
/// notificación. El acento usa el primario del tema (violeta claro / azul
/// oscuro).
class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.title,
    required this.description,
    required this.kind,
    required this.createdAt,
    required this.onTap,
  });

  final String title;
  final String description;
  final String? kind;
  final DateTime createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                kind == 'producto'
                    ? Icons.inventory_2_outlined
                    : Icons.handyman_outlined,
                size: 20,
                color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
