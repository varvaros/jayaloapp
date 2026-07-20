import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';

/// Perfil del negocio para "Mi tienda" (espejo del record que devuelve
/// `myBusinessProfile()` en `repos.dart`): cabecera + detalles.
typedef StoreProfile = ({
  String id,
  String name,
  String? logoUrl,
  bool verified,
  String? categoryId,
  String? city,
  bool wholesale,
  String? description,
});

/// "Mi tienda" (spec 2026-07-20-mi-tienda-solo-lectura): *Mi negocio* muestra el
/// escaparate de SOLO LECTURA — detalles del negocio + productos + servicios +
/// opiniones. La edición NO vive en la app (V2): el botón "Editar en la web"
/// (Task 6) lleva a jayalo.com ya logueado. Antes esta pantalla era una tarjeta
/// de conteo inerte ("se administran desde jayalo.com").
class MyBusinessScreen extends StatefulWidget {
  const MyBusinessScreen({super.key});
  @override
  State<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

/// Todo lo que el escaparate necesita en un solo viaje.
class _StoreData {
  const _StoreData({
    required this.business,
    required this.productos,
    required this.servicios,
    required this.reviews,
    required this.rating,
  });
  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;
}

class _MyBusinessScreenState extends State<MyBusinessScreen> {
  late Future<_StoreData> _load = _fetch();

  Future<_StoreData> _fetch() async {
    final business = await myBusinessProfile();
    if (business == null) {
      return const _StoreData(
        business: null,
        productos: [],
        servicios: [],
        reviews: [],
        rating: null,
      );
    }
    final results = await Future.wait([
      myStoreProducts(business.id),
      businessReviews(business.id),
      businessRatings([business.id]),
    ]);
    final (productos, servicios) =
        partitionStoreItems(results[0] as List<Map<String, dynamic>>);
    final ratings = results[2] as Map<String, BusinessRating>;
    return _StoreData(
      business: business,
      productos: productos,
      servicios: servicios,
      reviews: results[1] as List<BusinessReview>,
      rating: ratings[business.id],
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
            child: FutureBuilder<_StoreData>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData) return const JayaloLoaderBlock();
                final data = snap.data!;
                return MyBusinessView(
                  business: data.business,
                  productos: data.productos,
                  servicios: data.servicios,
                  reviews: data.reviews,
                  rating: data.rating,
                );
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja. Stateful solo por su `ScrollController` propio (nunca el
/// singleton `homeScrollController` — mismo motivo que `StatsView`/
/// `ReputationView`: `BackGuard` revienta con dos posiciones adjuntas).
class MyBusinessView extends StatefulWidget {
  const MyBusinessView({
    super.key,
    required this.business,
    required this.productos,
    required this.servicios,
    required this.reviews,
    required this.rating,
  });

  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

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
    final b = widget.business;
    if (b == null) {
      return EmptyState(
        controller: _scroll,
        message: 'No encontramos tu negocio.\n\n'
            'Si el problema sigue, escríbenos desde Ajustes.',
      );
    }

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + navBarReservedSpace(context)),
      children: [
        _BusinessHeaderCard(business: b).cascadeIn(0),
        _DetailsRow(business: b).cascadeIn(1),
        const SectionHeader(text: 'PRODUCTOS'),
        ..._itemsOrEmpty(widget.productos, 'Aún no tienes productos.'),
        const SectionHeader(text: 'SERVICIOS'),
        ..._itemsOrEmpty(widget.servicios, 'Aún no tienes servicios.'),
        const SectionHeader(text: 'OPINIONES'),
        _ReviewsBlock(reviews: widget.reviews, rating: widget.rating),
      ],
    );
  }

  List<Widget> _itemsOrEmpty(List<Map<String, dynamic>> items, String empty) {
    if (items.isEmpty) return [_EmptyLine(text: empty)];
    return [for (final i in items) ProductListCard(item: i)];
  }
}

/// Fila de detalles bajo la cabecera: categoría, zona y chip mayorista.
/// Espejo de lo principal que muestra `BusinessDetailsCard` de la web.
class _DetailsRow extends StatelessWidget {
  const _DetailsRow({required this.business});
  final StoreProfile business;

  @override
  Widget build(BuildContext context) {
    final catName = categoryNameById(business.categoryId);
    final chips = <Widget>[
      if (catName != null)
        _MetaChip(icon: Icons.category_outlined, label: catName),
      if (business.city != null)
        _MetaChip(icon: Icons.place_outlined, label: business.city!),
      if (business.wholesale)
        _MetaChip(icon: Icons.inventory_2_outlined, label: 'Mayorista'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

/// Aviso discreto para una sección vacía (sin CTA de crear: eso es V2/web).
class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child:
          Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

/// Promedio + conteo (encabezado) y la lista de reseñas anónimas.
class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.reviews, required this.rating});
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (reviews.isEmpty) {
      return const _EmptyLine(text: 'Aún no tienes opiniones.');
    }
    final r = rating;
    return Column(children: [
      if (r != null && r.count > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5A623)),
            const SizedBox(width: 4),
            Text(r.avg.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('(${r.count} ${r.count == 1 ? 'reseña' : 'reseñas'})',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        ),
      for (final rev in reviews) _ReviewCard(review: rev),
    ]);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final BusinessReview review;

  @override
  Widget build(BuildContext context) {
    return JayaloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            for (var i = 0; i < 5; i++)
              Icon(
                  i < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFF5A623)),
          ]),
          if (review.comment != null) ...[
            const SizedBox(height: 6),
            Text(review.comment!, style: const TextStyle(fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}

/// Cabecera: logo (o ícono genérico), nombre y el sello "Negocio verificado"
/// si el RNC está aprobado. Mismo tono verde que Ajustes para "confirmado".
class _BusinessHeaderCard extends StatelessWidget {
  const _BusinessHeaderCard({required this.business});
  final StoreProfile business;

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
