import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../../domain/money.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/profile_avatar_button.dart';
import '../shell/floating_nav_bar.dart';

/// Signature de la fuente de datos del catálogo (paridad `productHitsQ` de la
/// web). Inyectada en [CatalogView] para poder probar la pantalla sin red —
/// mismo patrón que `InboxFetch` en `provider/inbox_screen.dart`.
typedef CatalogFetch = Future<List<Map<String, dynamic>>> Function(
    {required String kind, String? search});

/// Task 6 (2026-07-18): SOLO el listado. El detalle del producto y el botón
/// "Me interesa" son la tarea siguiente — por eso las tarjetas de esta
/// pantalla no navegan a ningún lado todavía. El cableado de la pestaña en la
/// barra flotante es posterior (no se toca `nav_destinations.dart`); hoy se
/// llega aquí navegando a `/catalog` a mano, como `/provider/business`.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => const CatalogView(fetch: catalogProducts);
}

/// Dibuja el toggle Producto/Servicio, la búsqueda y la rejilla. StatefulWidget
/// con su propio [ScrollController] (nunca `homeScrollController`: esta
/// pantalla todavía no es una pestaña raíz del shell, mismo motivo que
/// `ReputationView`/`StatsView` — el `AnimatedSwitcher` del shell y `BackGuard`
/// revientan si dos pantallas comparten un único controller).
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.fetch,
    this.actions = const [NotificationBell(), ProfileAvatarButton()],
  });

  final CatalogFetch fetch;
  final List<Widget> actions;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String _kind = 'producto';
  String? _search;
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  late Future<List<Map<String, dynamic>>> _load =
      widget.fetch(kind: _kind, search: _search);

  // Bloque, no expresión: el mismo gotcha documentado en inbox_screen.dart —
  // `setState(() => _load = future)` hace que la closure DEVUELVA el Future.
  //
  // `.ignore()`: `setState` no reconstruye sincrónicamente (recién en el
  // próximo frame `FutureBuilder` reengancha su listener sobre el `Future`
  // nuevo), así que si `next` se resuelve en error ANTES de ese frame, la
  // zona de Dart lo reporta como "no manejado" aunque `FutureBuilder` sí lo
  // vaya a mostrar bien vía `snapshot.hasError` un instante después. Marca
  // el `Future` como atendido sin tocar su valor — `FutureBuilder` sigue
  // escuchando la MISMA instancia por su cuenta.
  void _refetch() {
    final next = widget.fetch(kind: _kind, search: _search)..ignore();
    setState(() {
      _load = next;
    });
  }

  void _applySearch() {
    final term = _searchCtrl.text.trim();
    setState(() => _search = term.isEmpty ? null : term);
    _refetch();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _search = null);
    _refetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: const Text('Catálogo'), actions: widget.actions),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'producto', label: Text('Producto')),
                ButtonSegment(value: 'servicio', label: Text('Servicio')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                setState(() => _kind = s.first);
                _refetch();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
              decoration: filledField(context, 'Buscar en el catálogo',
                      hint: 'Ej. taladro, instalación eléctrica…')
                  .copyWith(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refetch(),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _load,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SkeletonList();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(onRetry: () async => _refetch());
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return EmptyState(
                      controller: _scrollController,
                      message: _search != null
                          ? 'No hay artículos que coincidan con tu búsqueda.'
                          : 'Aún no hay artículos publicados en esta '
                              'categoría.\n\nVuelve más tarde: los '
                              'proveedores publican todos los días.',
                      ctaLabel: _search != null ? 'Quitar búsqueda' : null,
                      onCta: _search != null ? _clearSearch : null,
                    );
                  }
                  return GridView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                        12, 8, 12, 12 + navBarReservedSpace(context)),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      // .62, no .72: con la imagen cuadrada + 2 líneas de
                      // nombre + precio, un ratio más ajustado desborda por
                      // unos px en anchos de teléfono típicos (~360-390dp) —
                      // verificado con el ratio anterior en ese ancho.
                      childAspectRatio: .62,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _CatalogCard(item: items[i]).cascadeIn(i),
                  );
                },
              ),
            ),
          ),
        ]),
      );
}

/// Tarjeta del catálogo: foto (con placeholder/error, nunca ícono roto),
/// nombre y precio (`catalogPriceLabel`, fijo o rango — paridad
/// `ProductHitCard.tsx`). Task 7 (2026-07-19): ya navega al detalle
/// (`/catalog/:id`) — antes (Task 6) no tenía `onTap` porque el detalle no
/// existía todavía.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    final priceLabel = catalogPriceLabel(
      price: item['price'] as num?,
      priceMin: item['price_min'] as num?,
      priceMax: item['price_max'] as num?,
    );
    return JayaloCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      onTap: () => context.push('/catalog/${item['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: img == null
                  ? _imagePlaceholder(cs)
                  : Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imagePlaceholder(cs),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(priceLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
      );
}
