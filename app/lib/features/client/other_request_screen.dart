import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/create_request_nav.dart';
import '../../data/repos.dart';
import '../../domain/request_requirements.dart';
import '../shared/brand_kit.dart';
import '../shared/collapsing_photo_panel.dart';
import '../shared/detail_tiles.dart';
import '../shared/request_bullet_tiles.dart';
import '../shared/request_requirement_badges.dart';
import '../shell/floating_nav_bar.dart';
import 'product_detail_screen.dart' show productBackButton;
import '../../domain/share_links.dart';
import '../shared/share_button.dart';

/// Detalle READ-ONLY de una solicitud de OTRO usuario (pestaña "De otros" de
/// Tus solicitudes). No muestra estado/ofertas (eso es de las propias) ni
/// permite ofertar (eso vive del lado proveedor). Su única acción es "También
/// busco esto" → siembra el creador con foto + título (PO 2026-07-22).
class OtherRequestScreen extends StatefulWidget {
  const OtherRequestScreen({super.key, required this.requestId, this.fetch});
  final String requestId;

  /// Inyectable para tests (por defecto lee de la BD por id).
  final Future<Map<String, dynamic>?> Function()? fetch;

  @override
  State<OtherRequestScreen> createState() => _OtherRequestScreenState();
}

class _OtherRequestScreenState extends State<OtherRequestScreen> {
  late Future<Map<String, dynamic>?> _load;

  @override
  void initState() {
    super.initState();
    _load = (widget.fetch ?? () => requestById(widget.requestId))();
  }

  List<String> _images(Map<String, dynamic> r) {
    final urls = (r['image_urls'] as List?)?.cast<String>() ?? const <String>[];
    final primary = r['image_url'] as String?;
    return [
      if (primary != null && primary.isNotEmpty) primary,
      ...urls.where((u) => u.isNotEmpty && u != primary),
    ];
  }

  Future<void> _confirmSeed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Busco esto mismo'),
        content: const Text(
            'Vamos a crear tu propia solicitud a partir de esta. Te haremos '
            'unas preguntas para ajustarla a lo que necesitas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, busco lo mismo')),
        ],
      ),
    );
    if (ok == true && mounted) {
      pushCreateRequestOnce(context, seedFrom: widget.requestId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _load,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Scaffold(
              appBar: AppBar(title: const Text('Solicitud')),
              body: const Center(child: JayaloLoaderBlock()),
            );
          }
          final r = snap.data;
          if (r == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Solicitud')),
              body: const Center(
                  child: Text('No se pudo cargar la solicitud.')),
            );
          }
          final imgs = _images(r);
          // CON foto entra el panel plegable (la foto se ESCONDE al scrollear
          // — pedido PO 2026-08-11, la fija de 200 no lo hacía) con el atrás
          // flotante encima, misma anatomía que los otros detalles. SIN foto
          // se conserva el header «Solicitud» de siempre.
          if (imgs.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Solicitud')),
              body: ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, 24 + navBarReservedSpace(context)),
                children: _content(context, r),
              ),
            );
          }
          final isServicio = (r['kind'] as String?) == 'servicio';
          return Scaffold(
            body: CustomScrollView(slivers: [
              CollapsingPhotoPanel(
                images: imgs,
                fallbackIcon: isServicio
                    ? Icons.handyman_outlined
                    : Icons.inventory_2_outlined,
                leading: productBackButton(context),
                actions: [
                  SharePhotoAction(
                    texto: ShareLinks.requestText(r['title'] as String?),
                    url: ShareLinks.request(widget.requestId),
                  ),
                ],
                onOpenViewer: (i) =>
                    showPhotoViewer(context, imgs, initialIndex: i),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                      20, 22, 20, 24 + navBarReservedSpace(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _content(context, r),
                  ),
                ),
              ),
            ]),
          );
        },
      );

  /// El cuerpo es el mismo con o sin foto: plantilla aprobada PO 2026-08-11 —
  /// chip titular, título, tarjetas de detalle (los bullets «Etiqueta: valor»
  /// de la IA), requisitos en teal y el CTA al final.
  List<Widget> _content(BuildContext context, Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    final bullets = (r['bullets'] as List?)?.cast<String>() ?? const [];
    final desc = (r['description'] as String?) ?? '';
    final parsed = requestBulletRows(bullets);
    return [
      if (r['is_wholesale'] == true) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text('AL POR MAYOR',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
          ),
        ),
        const SizedBox(height: 10),
      ],
      Text(r['title'] as String? ?? 'Solicitud',
          style: TextStyle(
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: jayaloHead(context))),
      const SizedBox(height: 16),
      ...detailTileBlock(context,
          eyebrow: 'DETALLES DE LA SOLICITUD', rows: parsed.rows),
      // Lo que no encajó como «Etiqueta: valor» sobrevive como texto libre;
      // sin bullets, la descripción cruda hace ese papel.
      if (parsed.freeText.isNotEmpty) ...[
        SizedBox(height: parsed.rows.isEmpty ? 0 : 12),
        for (final b in parsed.freeText)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(b,
                style: TextStyle(height: 1.4, color: cs.onSurfaceVariant)),
          ),
      ] else if (bullets.isEmpty && desc.isNotEmpty) ...[
        Text(desc,
            style: TextStyle(height: 1.4, color: cs.onSurfaceVariant)),
      ],
      RequestRequirementBadges(
        req: requirementsFromRow(r),
        variant: RequirementBadgeVariant.tiles,
        padding: const EdgeInsets.only(top: 16),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        onPressed: _confirmSeed,
        icon: const Icon(Icons.add),
        label: const Text('También busco esto'),
      ),
    ];
  }
}
