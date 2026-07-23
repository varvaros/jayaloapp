import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
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
  // Bloque de confianza bajo el nombre (adorno, no bloquea la tienda si falla):
  // rating, trabajos completados, tiempo de respuesta, miembro-desde y sellos.
  BusinessStorefrontStats? _stats;
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
      // Bloque de confianza: adorno bajo el nombre. Si la RPC falla, el bloque
      // simplemente no aparece — nunca se tira la tienda a la pantalla de error.
      final statsF = businessStorefrontStats(widget.businessId)
          .catchError((_) => null);
      final results = await Future.wait([
        myStoreProducts(widget.businessId),
        myPortfolioItems(widget.businessId),
      ]);
      final (prod, serv) = partitionStoreItems(results[0]);
      final portfolio = results[1];
      final type = await typeF;
      final stats = await statsF;
      // Perfil de servicios: técnico, o (heurística de respaldo) sin productos
      // pero con servicios/trabajos publicados.
      final servicesFirst = type == 'tecnico' ||
          (prod.isEmpty && (serv.isNotEmpty || portfolio.isNotEmpty));
      if (!mounted) return;
      setState(() {
        _productos = prod;
        _servicios = serv;
        _portfolio = portfolio;
        _stats = stats;
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

  String _fmtResp(double minutes) {
    final m = minutes.round();
    if (m < 60) return '~$m min';
    final h = (m / 60).round();
    if (h < 24) return '~$h h';
    final d = (h / 24).round();
    return '~$d ${d == 1 ? 'día' : 'días'}';
  }

  /// Bloque de confianza bajo el nombre (paridad con la tienda web): avatar
  /// BLUREADO del proveedor (identidad anónima hasta desbloquear) + grid de
  /// rating / trabajos completados / tiempo de respuesta / miembro-desde +
  /// sellos de verificación. `null` mientras carga o si no hay datos.
  Widget? _repCard() {
    final s = _stats;
    if (s == null) return null;
    final cs = Theme.of(context).colorScheme;
    final hasRating = s.avgRating != null && s.reviewsCount > 0;
    final badges = <(IconData, String)>[
      if (s.identityVerified || s.businessVerified || s.whatsappVerified)
        (Icons.verified_outlined, 'Proveedor verificado'),
      if (s.identityVerified) (Icons.badge_outlined, 'Identidad verificada'),
      if (s.businessVerified) (Icons.apartment_outlined, 'RNC verificado'),
      if (s.whatsappVerified) (Icons.chat_outlined, 'WhatsApp verificado'),
    ];
    return JayaloCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Avatar BLUREADO: placeholder casi imperceptible (no hay foto real
          // hasta desbloquear), mismo trato que el avatar del cliente.
          ClipOval(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                width: 46,
                height: 46,
                color: cs.primary.withValues(alpha: .35),
                child: Icon(Icons.person, size: 28, color: cs.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.alias,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: jayaloHead(context))),
                Text('Nombre y foto al desbloquear',
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _statCell(
              hasRating ? s.avgRating!.toStringAsFixed(1) : 'Nuevo',
              hasRating
                  ? '${s.reviewsCount} reseña${s.reviewsCount == 1 ? '' : 's'}'
                  : 'sin reseñas aún',
              star: hasRating,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCell('${s.completedJobs}',
                s.completedJobs == 1 ? 'trabajo completado' : 'trabajos completados'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _statCell(
              s.medianResponseMinutes != null
                  ? _fmtResp(s.medianResponseMinutes!)
                  : '—',
              'tiempo de respuesta',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCell(
              s.memberSinceYear?.toString() ?? '—',
              'miembro desde',
            ),
          ),
        ]),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final (icon, label) in badges)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 15, color: JayaloColors.success),
                  const SizedBox(width: 5),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JayaloColors.success)),
                ]),
            ],
          ),
        ],
      ]),
    );
  }

  /// Celda de un indicador del grid: cifra grande (con estrella opcional) + una
  /// etiqueta corta debajo, sobre una píldora tenue.
  Widget _statCell(String value, String label, {bool star = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (star) ...[
            const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5A623)),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: jayaloHead(context))),
          ),
        ]),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = _sections[_tab];
    final repCard = _repCard();
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
          below: HeaderSegmented(
            options: [for (final s in _sections) _sectionLabel(s)],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        ?repCard,
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
