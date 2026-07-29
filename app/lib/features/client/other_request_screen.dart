import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import '../../core/brand.dart';
import '../../core/create_request_nav.dart';
import '../../data/repos.dart';
import '../shared/brand_kit.dart';

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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitud')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _load,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: JayaloLoaderBlock());
          }
          final r = snap.data;
          if (r == null) {
            return const Center(child: Text('No se pudo cargar la solicitud.'));
          }
          final imgs = _images(r);
          final bullets = (r['bullets'] as List?)?.cast<String>() ?? const [];
          final desc = (r['description'] as String?) ?? '';
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text(r['title'] as String? ?? 'Solicitud',
                  style: TextStyle(
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
              if (r['is_wholesale'] == true) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: 'Al por mayor',
                    icon: Icons.inventory_2_outlined,
                    tone: dark
                        ? JayaloStatus.respondedDark
                        : JayaloStatus.respondedLight,
                  ),
                ),
              ],
              if (imgs.isNotEmpty) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: JayaloNetworkImage(imgs.first,
                      height: 200, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox()),
                ),
              ],
              if (bullets.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final b in bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(b)),
                        ]),
                  ),
              ] else if (desc.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(desc, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _confirmSeed,
                icon: const Icon(Icons.add),
                label: const Text('También busco esto'),
              ),
            ],
          );
        },
      ),
    );
  }
}
