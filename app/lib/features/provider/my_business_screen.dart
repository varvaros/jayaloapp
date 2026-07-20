import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

/// Tipo de la cabecera del negocio (espejo del record que devuelve
/// `myBusinessProfile()` en `repos.dart`).
typedef BusinessProfile = ({String id, String name, String? logoUrl, bool verified});

/// "Mi negocio" (Task 4, spec iteración 2 §0.2): cabecera del negocio +
/// productos + servicios + trabajos realizados. Estas dos últimas piezas SE
/// MUEVEN aquí desde `/provider/stats` — decisión PO verbatim: "ahí pondremos
/// productos, servicios y trabajos realizados (los tenemos en estadísticas
/// actualmente, lo movemos aquí)". `stats_screen.dart` ya NO las dibuja.
///
/// NO hay edición en v1: el negocio se administra desde jayalo.com (mismo
/// copy que ya traía `CatalogCard`). El cableado de la pestaña en la barra
/// flotante es una tarea posterior — hoy se llega navegando a
/// `/provider/business`.
class MyBusinessScreen extends StatefulWidget {
  const MyBusinessScreen({super.key});
  @override
  State<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

class _MyBusinessScreenState extends State<MyBusinessScreen> {
  late Future<(BusinessProfile?, ({int productos, int servicios}), int)> _load =
      _fetch();

  Future<(BusinessProfile?, ({int productos, int servicios}), int)>
      _fetch() async {
    final r = await Future.wait([
      myBusinessProfile(),
      providerCatalogCounts(),
      providerCompletedCount(),
    ]);
    return (
      r[0] as BusinessProfile?,
      r[1] as ({int productos, int servicios}),
      r[2] as int,
    );
  }

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
    _load = _fetch();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          const VioletHeader(
            leading: HeaderAvatar(),
            title: 'Mi negocio',
            actions: [HeaderBell()],
          ),
          Expanded(
            child: FutureBuilder<
                (BusinessProfile?, ({int productos, int servicios}), int)>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData) return const JayaloLoaderBlock();
                final (business, catalogo, completados) = snap.data!;
                return MyBusinessView(
                    business: business,
                    productos: catalogo.productos,
                    servicios: catalogo.servicios,
                    completados: completados);
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja. Stateful solo por su `ScrollController` propio (nunca el
/// singleton `homeScrollController` — ver el comentario del `ListView` de
/// abajo; mismo motivo que `StatsView`/`ReputationView`).
class MyBusinessView extends StatefulWidget {
  const MyBusinessView({
    super.key,
    required this.business,
    required this.productos,
    required this.servicios,
    required this.completados,
  });

  final BusinessProfile? business;
  final int productos;
  final int servicios;
  final int completados;

  @override
  State<MyBusinessView> createState() => _MyBusinessViewState();
}

class _MyBusinessViewState extends State<MyBusinessView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final business = widget.business;
    if (business == null) {
      return EmptyState(
        controller: _scroll,
        message: 'No encontramos tu negocio.\n\n'
            'Si el problema sigue, escríbenos desde Ajustes.',
      );
    }

    return ListView(
      // Controlador PROPIO, no `homeScrollController`. Ese singleton lo lee
      // `BackGuard._handleBack` con `c.offset`, que lanza "Too many elements"
      // si hay más de una posición adjunta — y el AnimatedSwitcher del shell
      // mantiene dos pestañas montadas durante los 250 ms del cambio.
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        _BusinessHeaderCard(business: business).cascadeIn(0),
        const SectionHeader(text: 'LO QUE OFRECES'),
        CatalogCard(productos: widget.productos, servicios: widget.servicios)
            .cascadeIn(1),
        const SectionHeader(text: 'TRABAJOS REALIZADOS'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.handshake_outlined,
                    value: '${widget.completados}',
                    label: 'trabajos realizados')),
          ]),
        ).cascadeIn(2),
      ],
    );
  }
}

/// Conteo del catálogo. INERTE a propósito: `onTap` es nulo hasta que exista
/// el spec del catálogo navegable (decisión PO 2026-07-18). Cuando llegue, se
/// le pasa el `onTap` y nada más cambia.
///
/// Task 4 (2026-07-18): vivía en `stats_screen.dart`; se mueve aquí completa
/// porque la pieza entera (dato + UI) sale de Estadísticas hacia Mi negocio.
class CatalogCard extends StatelessWidget {
  const CatalogCard({
    super.key,
    required this.productos,
    required this.servicios,
    this.onTap,
  });

  final int productos;
  final int servicios;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = productos == 1 ? '1 producto' : '$productos productos';
    final s = servicios == 1 ? '1 servicio' : '$servicios servicios';
    return JayaloCard(
      onTap: onTap,
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$p · $s',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Se administran desde jayalo.com por ahora',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Cabecera: logo (o ícono genérico si no tiene), nombre y el sello de
/// WhatsApp del negocio si está confirmado. Mismo tono verde que ya usa
/// `settings_screen.dart` para "WhatsApp confirmado" (`JayaloStatus.unlocked*`,
/// reutilizado aquí como el tono "positivo/confirmado" de la app).
class _BusinessHeaderCard extends StatelessWidget {
  const _BusinessHeaderCard({required this.business});
  final BusinessProfile business;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight;
    final logoUrl = business.logoUrl;
    return JayaloCard(
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: cs.surfaceContainerHighest,
          backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
          child: logoUrl == null
              ? Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(business.name.isEmpty ? 'Tu negocio' : business.name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
              if (business.verified) ...[
                const SizedBox(height: 6),
                StatusChip(
                    label: 'Negocio verificado',
                    icon: Icons.verified,
                    tone: tone),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}
