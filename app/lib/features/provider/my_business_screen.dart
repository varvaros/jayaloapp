import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/editor_link_client.dart';
import '../../core/secure_web_launch.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/business_cover_hero.dart';
import '../shared/business_details_card.dart';
import '../shared/product_list_card.dart';
import '../shared/violet_header.dart';

/// Perfil del negocio para "Mi tienda" (espejo del record que devuelve
/// `myBusinessProfile()` en `repos.dart`): cabecera + detalles.
typedef StoreProfile = ({
  String id,
  String name,
  String? logoUrl,

  /// Portada del negocio. La app NO la leía en ningún sitio hasta el
  /// 2026-08-01, que es la mitad de por qué la tienda no se parecía a la web.
  String? coverUrl,
  bool verified,
  String? categoryId,
  String? city,
  bool wholesale,
  String? description,

  /// Sellos ya resueltos a etiqueta ("Identidad verificada", "RNC
  /// verificado", "WhatsApp verificado") para la portada.
  List<String> seals,

  /// La fila cruda de `provider_businesses`, para `BusinessDetailsCard`: las
  /// columnas de detalle son de lectura pública y la ficha decide sola qué
  /// enseñar.
  Map<String, dynamic> raw,
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
    required this.trabajos,
    required this.reviews,
    required this.rating,
  });
  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<Map<String, dynamic>> trabajos;
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
        trabajos: [],
        reviews: [],
        rating: null,
      );
    }
    final results = await Future.wait([
      myStoreProducts(business.id),
      myPortfolioItems(business.id),
      businessReviews(business.id),
      businessRatings([business.id]),
    ]);
    final (productos, servicios) =
        partitionStoreItems(results[0] as List<Map<String, dynamic>>);
    final ratings = results[3] as Map<String, BusinessRating>;
    return _StoreData(
      business: business,
      productos: productos,
      servicios: servicios,
      trabajos: results[1] as List<Map<String, dynamic>>,
      reviews: results[2] as List<BusinessReview>,
      rating: ratings[business.id],
    );
  }

  /// Abre el alta rápida del agregador y refresca al volver si hubo alta.
  Future<void> _openAdd(String businessId, String kind) async {
    final changed =
        await context.push<bool>('/provider/business/add?kind=$kind&bid=$businessId');
    if (changed == true) _refetch();
  }

  // Bloque para que setState no devuelva un Future (leer inbox_screen.dart).
  void _refetch() => setState(() {
        _load = _fetch();
      });

  /// Pide el magic link a la web y lo abre en el navegador externo (ya
  /// logueado, redirige a /provider/business/:id). NO usa WebView (el CAPTCHA
  /// se quemó con MIUI, ADR-0032). La edición vive en la web (V2).
  Future<void> _openEditor(String businessId) async {
    final token = supa.auth.currentSession?.accessToken;
    if (token == null) {
      _toast('Inicia sesión de nuevo para editar.');
      return;
    }
    try {
      final url = await EditorLinkClient()
          .fetchEditorUrl(businessId: businessId, accessToken: token);
      // Custom Tabs, NO intent público: este URL también lleva un token de
      // sesión de un solo uso (ver `core/secure_web_launch.dart`).
      final ok = await launchAuthenticatedUrl(Uri.parse(url));
      if (!ok) _toast('No pudimos abrir el navegador.');
    } catch (_) {
      _toast('No se pudo abrir el editor. Intenta de nuevo.');
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

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
                  trabajos: data.trabajos,
                  reviews: data.reviews,
                  rating: data.rating,
                  onEditWeb: data.business == null
                      ? null
                      : () => _openEditor(data.business!.id),
                  onAddItem: data.business == null
                      ? null
                      : (kind) => _openAdd(data.business!.id, kind),
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
    this.trabajos = const [],
    required this.reviews,
    required this.rating,
    this.onEditWeb,
    this.onAddItem,
  });

  final StoreProfile? business;
  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> servicios;
  final List<Map<String, dynamic>> trabajos;
  final List<BusinessReview> reviews;
  final BusinessRating? rating;

  /// Abre el editor en la web (magic-link SSO, Task 6). Nulo → el botón no se
  /// dibuja (p. ej. sin negocio). Inyectable para probar sin red.
  final Future<void> Function()? onEditWeb;

  /// Alta rápida del agregador (PO 2026-08-05): recibe el kind elegido en el
  /// chooser ('producto' | 'servicio' | 'trabajo'). Nulo → la tarjeta no se
  /// dibuja. Inyectable para probar sin router.
  final Future<void> Function(String kind)? onAddItem;

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
        // Portada editorial + ficha de detalles: las dos piezas del diseño web
        // que nunca se portaron (pedido PO 2026-08-01). Antes esto era una
        // tarjeta con logo y nombre, y tres chips sueltos.
        BusinessCoverHero(
          name: b.name,
          coverUrl: b.coverUrl,
          logoUrl: b.logoUrl,
          subtitle: _subtitleFor(b),
          seals: b.seals,
        ).cascadeIn(0),
        BusinessDetailsCard(business: b.raw).cascadeIn(1),
        if (widget.onEditWeb != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: FilledButton.icon(
              onPressed: () => widget.onEditWeb!.call(),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Editar en la web'),
            ),
          ),
        // El agregador (PO 2026-08-05): tarjeta vacía con ＋ que abre el
        // chooser producto/servicio/trabajo. Rompe a propósito el "solo
        // lectura" del spec 2026-07-20, decisión del PO: el alta mínima vive
        // en la app porque alimenta ofertas más rápidas.
        if (widget.onAddItem != null)
          _AddToStoreCard(onChoose: _chooseKind).cascadeIn(2),
        const SectionHeader(text: 'PRODUCTOS'),
        ..._itemsOrEmpty(widget.productos, 'Aún no tienes productos.'),
        const SectionHeader(text: 'SERVICIOS'),
        ..._itemsOrEmpty(widget.servicios, 'Aún no tienes servicios.'),
        const SectionHeader(text: 'TRABAJOS'),
        if (widget.trabajos.isEmpty)
          const _EmptyLine(text: 'Aún no tienes trabajos en tu portafolio.')
        else
          for (final t in widget.trabajos) _PortfolioTile(item: t),
        const SectionHeader(text: 'OPINIONES'),
        _ReviewsBlock(reviews: widget.reviews, rating: widget.rating),
      ],
    );
  }

  /// Chooser del agregador: hoja con las tres variantes del alta rápida.
  Future<void> _chooseKind() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Producto'),
            subtitle: const Text('Algo que vendes en tu tienda'),
            onTap: () => Navigator.pop(c, 'producto'),
          ),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: const Text('Servicio'),
            subtitle: const Text('Algo que ofreces hacer'),
            onTap: () => Navigator.pop(c, 'servicio'),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('Trabajo realizado'),
            subtitle: const Text('Para tu portafolio'),
            onTap: () => Navigator.pop(c, 'trabajo'),
          ),
        ]),
      ),
    );
    if (kind == null) return;
    await widget.onAddItem?.call(kind);
  }

  List<Widget> _itemsOrEmpty(List<Map<String, dynamic>> items, String empty) {
    if (items.isEmpty) return [_EmptyLine(text: empty)];
    return [for (final i in items) ProductListCard(item: i)];
  }

  /// Categoría y ciudad en UNA línea bajo el nombre, como la web en móvil.
  /// Antes eran dos chips sueltos junto al de "Mayorista"; el mayorista pasó a
  /// ser una fila de la ficha de detalles ("Ventas: Al por mayor").
  static String? _subtitleFor(StoreProfile b) {
    final partes = [
      if (categoryNameById(b.categoryId) != null)
        categoryNameById(b.categoryId)!,
      if (b.city != null) b.city!,
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }
}

/// La tarjeta del agregador (PO 2026-08-05): "tarjeta vacía con un signo de
/// ＋". El ＋ va en un aro punteado-suave del color primario para leerse como
/// hueco por llenar, no como contenido.
class _AddToStoreCard extends StatelessWidget {
  const _AddToStoreCard({required this.onChoose});
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      onTap: onChoose,
      child: Column(children: [
        const SizedBox(height: 6),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary, width: 2),
          ),
          child: Icon(Icons.add, size: 28, color: cs.primary),
        ),
        const SizedBox(height: 10),
        Text(
          'Haz ofertas más rápidas con tus productos en tus tiendas',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

/// Trabajo del portafolio en el escaparate propio: miniatura + título. Más
/// simple que el carrusel de la tienda pública — aquí solo confirma al dueño
/// que su alta quedó.
class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    final img = images.isEmpty ? null : images.first;
    return JayaloCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: img == null || img.isEmpty
              ? Container(
                  width: 56,
                  height: 56,
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.photo_outlined,
                      color: cs.onSurfaceVariant, size: 22),
                )
              : Image.network(img, width: 56, height: 56, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(item['title'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
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
