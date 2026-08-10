import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../../domain/money.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/collapsing_photo_panel.dart';
import 'product_detail_screen.dart' show productBackFab, productBackButton;

/// Detalle de un PAQUETE de la tienda pública (pedido PO 2026-08-09: "El
/// paquete no abre nada" — las tarjetas de PAQUETES en
/// `provider_store_screen.dart` no abrían ninguna vista).
///
/// Mismo modelo que `product_detail_screen.dart`: pantalla con fetch propio
/// (`PackageDetailScreen`) + vista pura (`PackageDetailView`), AppBar sin
/// campana/avatar (pantalla de detalle, no pestaña raíz del shell) y el mismo
/// atrás flotante (`productBackFab`/`productBackButton`, reusados tal cual).
///
/// ⚠️ DECISIÓN DE INVESTIGACIÓN (ver informe): el CTA "Solicitar" NO reusa el
/// formulario largo de "Me interesa" del producto (cantidad/color/dirección
/// no tienen sentido para un paquete) — reusa la MISMA RPC
/// `create_product_interest` ([sendProductInterest]/[productInterestExists],
/// `data/repos.dart`), que desde la migración `20260718150000` ya resuelve
/// server-side contra `provider_products` **o** `provider_packages` — no
/// hizo falta ni esquema ni migración nueva. El flujo se reduce a un
/// `AlertDialog` de confirmación con el mensaje fijo
/// `"Solicitud por paquete: <nombre>"`, EXACTA paridad con
/// `PackageInterestButton` de la web (`business.$id.tsx`, que ya hace
/// precisamente esto — la web nunca usó el formulario largo para paquetes).
class PackageDetailScreen extends StatefulWidget {
  const PackageDetailScreen({super.key, required this.packageId});
  final String packageId;

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

/// Todo lo que la pantalla necesita en un solo viaje.
class PackageDetailData {
  const PackageDetailData({
    required this.package,
    required this.hasInterest,
    required this.isOwner,
  });

  final Map<String, dynamic> package;

  /// Ya existe una fila de interés del cliente actual para este paquete
  /// (idempotente — alimenta el botón "Solicitud enviada").
  final bool hasInterest;

  /// El usuario actual es el dueño del paquete (nunca se le ofrece
  /// solicitar el suyo).
  final bool isOwner;
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  late Future<PackageDetailData?> _load = _fetch();

  Future<PackageDetailData?> _fetch() async {
    final pkg = await packageDetail(widget.packageId);
    if (pkg == null) return null;
    final ownerUserId = pkg['user_id'] as String?;
    final uid = supa.auth.currentUser?.id;
    final isOwner = uid != null && uid == ownerUserId;
    final hasInterest =
        isOwner ? false : await productInterestExists(widget.packageId);
    return PackageDetailData(
        package: pkg, hasInterest: hasInterest, isOwner: isOwner);
  }

  // Bloque, no expresión (mismo gotcha de `product_detail_screen.dart`):
  // `setState(() => _load = future)` haría que la closure DEVUELVA el Future.
  void _refetch() {
    setState(() => _load = _fetch());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageDetailData?>(
        future: _load,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done &&
              !snap.hasError &&
              snap.data != null) {
            return Scaffold(
              body: PackageDetailView(
                  data: snap.data!, onInterestSent: _refetch),
            );
          }
          final Widget content = switch (snap.connectionState) {
            ConnectionState.done => snap.hasError
                ? ErrorRetry(onRetry: () async => _refetch())
                : const EmptyState(
                    message: 'No encontramos este paquete.\n\n'
                        'Puede que ya no esté disponible.',
                  ),
            _ => const JayaloLoaderBlock(),
          };
          return Scaffold(
            body: Stack(children: [
              content,
              SafeArea(child: productBackFab(context)),
            ]),
          );
        },
      );
}

/// Solo dibuja — recibe los datos ya resueltos. `sendInterest` inyectable
/// (mismo patrón que `ProductDetailView`) para probar sin tocar Supabase.
class PackageDetailView extends StatefulWidget {
  const PackageDetailView({
    super.key,
    required this.data,
    required this.onInterestSent,
    this.sendInterest = sendProductInterest,
  });

  final PackageDetailData data;

  /// Se llama tras enviar la solicitud con éxito, para que el padre
  /// refresque `hasInterest` (idempotencia) sin recargar toda la pantalla.
  final VoidCallback onInterestSent;

  final Future<({bool ok, bool alreadyExists, String? id})> Function(
      String productId, String message) sendInterest;

  @override
  State<PackageDetailView> createState() => _PackageDetailViewState();
}

class _PackageDetailViewState extends State<PackageDetailView> {
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.data.package;
    final name = p['name'] as String? ?? '';
    final description = p['description'] as String?;
    final imageUrl = p['image_url'] as String?;
    final images =
        imageUrl != null && imageUrl.isNotEmpty ? [imageUrl] : const <String>[];
    final price = p['price'] as num?;
    // (price == null || price == 0): misma regla que `PackageTile`
    // (`shared/tile_carril.dart`) — `provider_packages.price` es NOT NULL
    // DEFAULT 0, un precio en blanco se guarda como 0, no como null.
    final priceLabel =
        (price == null || price == 0) ? 'Consultar precio' : fmtRD(price);
    final items = (p['items'] as List?)?.cast<String>() ?? const [];

    return CustomScrollView(controller: _scroll, slivers: [
      // Mismo panel plegable que el detalle de producto — un paquete tiene
      // una sola foto (`image_url`), así que la miniatura-espía de la 2ª
      // foto simplemente no aparece (el panel ya maneja `images.length<=1`).
      CollapsingPhotoPanel(
        images: images,
        fallbackIcon: Icons.inventory_2_outlined,
        leading: productBackButton(context),
        onOpenViewer: (i) => showPhotoViewer(context, images, initialIndex: i),
      ),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              22, 22, 22, 24 + navBarReservedSpace(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
              const SizedBox(height: 6),
              Text(priceLabel,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(description,
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Qué incluye',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: jayaloHead(context))),
                const SizedBox(height: 10),
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(it, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              _CtaArea(data: widget.data, busy: _busy, onTap: _onSolicitar),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _onSolicitar() async {
    if (_busy) return;
    final id = widget.data.package['id'] as String;
    final name = widget.data.package['name'] as String? ?? 'este paquete';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Enviar solicitud?'),
        content: Text(
            'Le enviarás al proveedor una solicitud por el paquete "$name". '
            'Te contactará pronto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Sí, enviar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final res =
          await widget.sendInterest(id, 'Solicitud por paquete: $name');
      if (!mounted) return;
      widget.onInterestSent();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.alreadyExists
              ? 'Ya enviaste tu solicitud por este paquete.'
              : '¡Solicitud enviada! El proveedor te contactará pronto.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo enviar tu solicitud.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Botón de acción según quién mira: dueño (nada que solicitar), ya
/// interesado (estado amable, idempotente) o CTA. Mismo copy/ícono que
/// `_CtaArea` del detalle de producto ("Solicitar" / "Solicitud enviada",
/// `ShoppingBag`).
class _CtaArea extends StatelessWidget {
  const _CtaArea({required this.data, required this.busy, required this.onTap});
  final PackageDetailData data;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.isOwner) {
      return Text('Este es tu paquete.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant));
    }
    if (data.hasInterest) {
      return Column(children: [
        FilledButton(
          onPressed: null,
          child: const Text('Solicitud enviada'),
        ),
        const SizedBox(height: 8),
        Text('Te avisaremos si el proveedor te escribe.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : () => onTap(),
        icon: busy
            ? const JayaloSpinner(size: 16)
            : const Icon(Icons.shopping_bag_outlined),
        label: const Text('Solicitar'),
      ),
    );
  }
}
