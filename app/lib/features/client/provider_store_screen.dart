import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/response_time.dart';
import '../shared/brand_kit.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Tienda ANÓNIMA de un proveedor (pedido PO 2026-07-22): al tocar
/// "enviado por Proveedor 2820" en una oferta, el cliente ve los productos,
/// servicios y trabajos anteriores del negocio SIN saber quién es (el nombre
/// real solo se revela al desbloquear). `provider_products` y
/// `provider_portfolio_items` tienen lectura pública, así que se leen por
/// `business_id` sin exponer datos de contacto.
class ProviderStoreScreen extends StatefulWidget {
  const ProviderStoreScreen({
    super.key,
    required this.businessId,
    this.alias = 'Proveedor',
  });

  final String businessId;

  /// Etiqueta anónima que traía la oferta ("Proveedor 2820").
  final String alias;

  @override
  State<ProviderStoreScreen> createState() => _ProviderStoreScreenState();
}

/// Secciones de la tienda. Su ORDEN depende del perfil del negocio (PO
/// 2026-07-21): negocio de productos → productos primero; negocio de servicios
/// (técnico) → servicios y trabajos primero.
enum _Section { productos, servicios, trabajos }

class _ProviderStoreScreenState extends State<ProviderStoreScreen> {
  int _tab = 0; // índice dentro de _sections
  bool _loading = true;
  List<Map<String, dynamic>> _productos = const [];
  List<Map<String, dynamic>> _servicios = const [];
  List<Map<String, dynamic>> _portfolio = const [];
  // Reputación bajo el nombre (adornos, no bloquean la tienda si fallan):
  // rating del negocio + copy de tiempo de respuesta (null si <5 muestras).
  BusinessRating? _rating;
  String? _responseCopy;
  // Orden por defecto (productos primero); se recalcula tras cargar según el
  // tipo de negocio.
  List<_Section> _sections = const [
    _Section.productos,
    _Section.servicios,
    _Section.trabajos,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // El tipo de negocio se pide en paralelo; su fallo no rompe la tienda
      // (sin él se cae al orden por defecto).
      final typeF =
          providerBusinessType(widget.businessId).catchError((_) => null);
      // Reputación: adornos bajo el nombre. Si la RPC falla, la línea
      // simplemente no aparece — nunca se tira la tienda a la pantalla de error.
      final ratingF = businessRatings([widget.businessId])
          .catchError((_) => <String, BusinessRating>{});
      final responseF = businessResponseTimes([widget.businessId])
          .catchError((_) => <String, BusinessResponseTime>{});
      final results = await Future.wait([
        myStoreProducts(widget.businessId),
        myPortfolioItems(widget.businessId),
      ]);
      final (prod, serv) = partitionStoreItems(results[0]);
      final portfolio = results[1];
      final type = await typeF;
      final rating = (await ratingF)[widget.businessId];
      final rt = (await responseF)[widget.businessId];
      final responseCopy =
          rt == null ? null : responseTimeCopy(rt.medianMinutes, rt.samples);
      // Perfil de servicios: técnico, o (heurística de respaldo) sin productos
      // pero con servicios/trabajos publicados.
      final servicesFirst = type == 'tecnico' ||
          (prod.isEmpty && (serv.isNotEmpty || portfolio.isNotEmpty));
      if (!mounted) return;
      setState(() {
        _productos = prod;
        _servicios = serv;
        _portfolio = portfolio;
        _rating = rating;
        _responseCopy = responseCopy;
        _sections = servicesFirst
            ? const [_Section.servicios, _Section.trabajos, _Section.productos]
            : const [_Section.productos, _Section.servicios, _Section.trabajos];
        _tab = 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sectionLabel(_Section s) => switch (s) {
        _Section.productos => 'Productos',
        _Section.servicios => 'Servicios',
        _Section.trabajos => 'Trabajos',
      };

  /// Fila de reputación bajo el nombre: estrella + nota (si hay reseñas) y/o
  /// "Regularmente responde en ~X" (si supera el umbral de muestras). Devuelve
  /// `null` si no hay nada que mostrar — un proveedor nuevo no enseña un "0.0"
  /// ni una promesa de respuesta sin datos. Va sobre el header violeta, así que
  /// el texto es blanco (la estrella conserva su ámbar de marca).
  Widget? _reputationStrip() {
    final r = _rating;
    final hasRating = r != null && r.avg > 0 && r.count > 0;
    final copy = _responseCopy;
    if (!hasRating && copy == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (hasRating) ...[
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5C542)),
          const SizedBox(width: 3),
          Text(r.avg.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(width: 4),
          Text('(${r.count})',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: .78))),
        ],
        if (hasRating && copy != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('·',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: .55))),
          ),
        if (copy != null) ...[
          Icon(Icons.schedule_rounded,
              size: 13, color: Colors.white.withValues(alpha: .85)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(copy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: Colors.white.withValues(alpha: .85))),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = _sections[_tab];
    final reputation = _reputationStrip();
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back,
            tooltip: 'Atrás',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          title: widget.alias,
          subtitle: 'Tienda del proveedor',
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reputation != null) ...[
                reputation,
                const SizedBox(height: 12),
              ],
              HeaderSegmented(
                options: [for (final s in _sections) _sectionLabel(s)],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const JayaloLoaderBlock()
              : switch (section) {
                  _Section.productos => _itemsList(_productos, section),
                  _Section.servicios => _itemsList(_servicios, section),
                  _Section.trabajos => _portfolioList(),
                },
        ),
      ]),
    );
  }

  Widget _itemsList(List<Map<String, dynamic>> items, _Section section) {
    if (items.isEmpty) {
      return _empty(section == _Section.productos
          ? 'Este proveedor aún no publica productos.'
          : 'Este proveedor aún no publica servicios.');
    }
    return ListView.builder(
      padding:
          EdgeInsets.only(top: 8, bottom: 12 + navBarReservedSpace(context)),
      itemCount: items.length,
      // Anónimo: la tarjeta NO navega a un detalle que revele el negocio.
      itemBuilder: (_, i) => ProductListCard(item: items[i]).cascadeIn(i),
    );
  }

  Widget _portfolioList() {
    if (_portfolio.isEmpty) {
      return _empty('Este proveedor aún no muestra trabajos anteriores.');
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding:
          EdgeInsets.only(top: 12, bottom: 12 + navBarReservedSpace(context)),
      itemCount: _portfolio.length,
      itemBuilder: (_, i) {
        final it = _portfolio[i];
        final urls =
            ((it['image_urls'] as List?)?.cast<String>() ?? const <String>[])
                .where((u) => u.isNotEmpty)
                .toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: JayaloCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it['title'] as String? ?? 'Trabajo realizado',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: jayaloHead(context))),
                if (urls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: urls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, j) => GestureDetector(
                        onTap: () => showPhotoViewer(context, urls, initialIndex: j),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(urls[j],
                              width: 200,
                              height: 140,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                  width: 200,
                                  height: 140,
                                  color: cs.surfaceContainerHighest)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
