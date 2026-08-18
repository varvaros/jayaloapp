import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import '../shared/brand_kit.dart';
import '../shared/star_score.dart';
import '../shared/customer_rep_card.dart'
    show CustomerAvatar, CustomerRepCard;
import '../shared/section_heading.dart';
import '../shell/floating_nav_bar.dart';

/// Perfil del CLIENTE visto por el proveedor (mockup aprobado 2026-08-11).
///
/// ANTES del desbloqueo es anónimo: foto blureada + alias "Cliente NNNN" +
/// agregados de reputación. TRAS pagar un desbloqueo con ese cliente, muestra
/// el nombre y la foto reales (decisión PO 2026-08-11) — quién está
/// desbloqueado lo decide la RPC `get_customer_public_profile` server-side,
/// nunca esta pantalla.
///
/// Las reseñas vienen de `get_customer_reviews`, que EXCLUYE las de los
/// negocios del que mira (regla PO 2026-08-11: reconocer tu propio comentario
/// desanonimiza al cliente). Por eso "0 reseñas listadas" NO contradice al
/// contador agregado: tu propia reseña cuenta en el promedio pero no se lista.
///
/// Sin CTA: es informativa; desbloquear sigue viviendo en la solicitud.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({
    super.key,
    required this.customerId,
    this.requestId,
    this.offerId,
    this.interestId,
    this.fetchProfile = customerPublicProfile,
    this.fetchReputation = customerReputation,
    this.fetchReviews = customerReviews,
    this.fetchBadges = peerVerificationBadges,
  });

  final String customerId;

  /// Contexto desde el que se llega (gate POR SOLICITUD, PO 2026-08-11): la
  /// RPC solo revela identidad si ESTE contexto está pagado por el llamador.
  /// Todos null = perfil siempre anónimo (default seguro).
  final String? requestId;
  final String? offerId;
  final String? interestId;

  /// Inyectables (mismo patrón que `MyOffersScreen.fetchOffers`): el default
  /// es la implementación real de `repos.dart`; los tests pasan dobles para
  /// no tocar Supabase.
  final Future<
          ({bool unlocked, String? firstName, String? lastName, String? avatarUrl})>
      Function(String,
          {String? requestId, String? offerId, String? interestId}) fetchProfile;
  final Future<Map<String, dynamic>?> Function([String?]) fetchReputation;
  final Future<List<Map<String, dynamic>>> Function(String, {int limit})
      fetchReviews;
  final Future<Map<String, PeerBadges>> Function(List<String>) fetchBadges;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  ({bool unlocked, String? firstName, String? lastName, String? avatarUrl})?
      _profile;
  Map<String, dynamic>? _rep;
  List<Map<String, dynamic>> _reviews = const [];
  PeerBadges? _badges;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Todo en paralelo y CADA pieza best-effort: si una consulta falla, el
  /// perfil se pinta con lo que sí llegó — nunca una pantalla rota por una
  /// sección opcional.
  Future<void> _load() async {
    final cid = widget.customerId;
    final results = await Future.wait<Object?>([
      widget
          .fetchProfile(cid,
              requestId: widget.requestId,
              offerId: widget.offerId,
              interestId: widget.interestId)
          .then<Object?>((v) => v)
          .catchError((_) => null),
      widget.fetchReputation(cid).catchError((_) => null),
      widget
          .fetchReviews(cid)
          .catchError((_) => const <Map<String, dynamic>>[]),
      widget
          .fetchBadges([cid])
          .then<Object?>((m) => m[cid])
          .catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as ({
        bool unlocked,
        String? firstName,
        String? lastName,
        String? avatarUrl
      })?;
      _rep = results[1] as Map<String, dynamic>?;
      _reviews = results[2] as List<Map<String, dynamic>>;
      _badges = results[3] as PeerBadges?;
      _loading = false;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/provider');
    }
  }

  String get _displayName {
    final p = _profile;
    if (p != null && p.unlocked) {
      final full = [p.firstName, p.lastName]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      if (full.isNotEmpty) return full;
    }
    return CustomerRepCard.aliasFor(widget.customerId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unlocked = _profile?.unlocked == true;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(children: [
              Material(
                color: cs.surfaceContainerLowest,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: 1,
                child: InkWell(
                  onTap: _goBack,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.arrow_back_ios_new,
                        size: 16, color: jayaloHead(context)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('Perfil del cliente',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: jayaloHead(context))),
            ]),
          ),
          Expanded(
            child: _loading
                ? const JayaloLoaderBlock()
                : ListView(
                    padding: EdgeInsets.only(
                        top: 10, bottom: 16 + navBarReservedSpace(context)),
                    children: [
                      _hero(context, unlocked),
                      _tiles(context),
                      if (_reviews.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                          child: sectionHeading(
                              context, 'Lo que dicen los proveedores'),
                        ),
                        _reviewList(context),
                      ],
                      if (!unlocked) _anonNote(context),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  /// Héroe centrado sobre el fondo (sin tarjeta, mockup): así el perfil se
  /// reconoce sin leer — ninguna otra pantalla abre con un avatar centrado.
  Widget _hero(BuildContext context, bool unlocked) {
    final cs = Theme.of(context).colorScheme;
    final badges = _badges;
    return Column(children: [
      CustomerAvatar(
        revealed: unlocked,
        avatarUrl: _profile?.avatarUrl,
        size: 86,
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(_displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context))),
      ),
      const SizedBox(height: 3),
      Text(
          unlocked
              ? 'Contacto desbloqueado'
              : 'Nombre y foto al desbloquear el contacto',
          style: TextStyle(
              fontSize: 12,
              color: unlocked
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? JayaloColors.dSuccess
                      : JayaloColors.success)
                  : cs.onSurfaceVariant)),
      if (badges != null &&
          (badges.idVerified || badges.whatsappVerified)) ...[
        const SizedBox(height: 11),
        Wrap(spacing: 7, runSpacing: 6, alignment: WrapAlignment.center,
            children: [
              if (badges.whatsappVerified) _sello(context, 'WS verificado'),
              if (badges.idVerified) _sello(context, 'Id verificado'),
            ]),
      ],
    ]);
  }

  Widget _sello(BuildContext context, String label) {
    final green = Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dSuccess
        : JayaloColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified, size: 13, color: green),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: green)),
      ]),
    );
  }

  /// Tiles 2×2. El tiempo de respuesta va en la tile LILA destacada (mockup):
  /// es el dato que más le importa a un proveedor antes de gastar créditos.
  Widget _tiles(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rep = _rep;
    final avg = (rep?['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (rep?['reviews_count'] as num?)?.toInt() ?? 0;
    final completed = (rep?['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (rep?['requests_count'] as num?)?.toInt() ?? 0;
    final respMin = (rep?['median_response_minutes'] as num?)?.toDouble();
    final samples = (rep?['response_samples'] as num?)?.toInt() ?? 0;

    String resp() {
      if (respMin == null || samples < 3) return '—';
      if (respMin < 60) return '~${respMin.round()} min';
      if (respMin < 1440) return '~${(respMin / 60).round()} h';
      return '~${(respMin / 1440).round()} d';
    }

    Widget tile(IconData icon, String value, String label,
            {bool destacado = false}) =>
        Expanded(
          child: JayaloCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            tint: destacado
                ? cs.primary.withValues(alpha:
                    Theme.of(context).brightness == Brightness.dark
                        ? .18
                        : .08)
                : null,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon,
                    size: 15,
                    color: icon == Icons.star_rounded
                        ? const Color(0xFFF2B705)
                        : cs.primary),
                const SizedBox(width: 6),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: jayaloHead(context))),
              ]),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(children: [
        Row(children: [
          tile(Icons.schedule_outlined, resp(), 'Tiempo de respuesta',
              destacado: true),
          const SizedBox(width: 10),
          tile(
              Icons.star_rounded,
              // El promedio es sobre 10 (ver `_stars`): sin el "/10" se lee como /5.
              count > 0 ? '${avg.toStringAsFixed(1)}/10' : '—',
              count == 1 ? '1 reseña de proveedor' : '$count reseñas de proveedores'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.receipt_long_outlined, '$requests',
              'Solicitud${requests == 1 ? '' : 'es'} publicada${requests == 1 ? '' : 's'}'),
          const SizedBox(width: 10),
          tile(Icons.check_circle_outline, '$completed',
              'Compra${completed == 1 ? '' : 's'} cerrada${completed == 1 ? '' : 's'}'),
        ]),
      ]),
    );
  }

  /// Reseñas de OTROS proveedores en filas planas con línea fina (doctrina:
  /// así las listas se reconocen sin leer). Nunca incluye las del que mira —
  /// eso lo garantiza la RPC.
  Widget _reviewList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: JayaloCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < _reviews.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stars((_reviews[i]['rating'] as num?)?.toInt() ?? 0),
                    if ((_reviews[i]['comment'] as String? ?? '')
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(_reviews[i]['comment'] as String,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: cs.onSurface)),
                    ],
                    const SizedBox(height: 3),
                    Text(_reviewMeta(_reviews[i]),
                        style: TextStyle(
                            fontSize: 10.5, color: cs.onSurfaceVariant)),
                  ]),
            ),
          ],
        ]),
      ),
    );
  }

  String _reviewMeta(Map<String, dynamic> r) {
    final biz = (r['business_name'] as String? ?? '').trim();
    final createdRaw = r['created_at'] as String?;
    final created =
        createdRaw == null ? null : DateTime.tryParse(createdRaw)?.toLocal();
    final when = created == null ? '' : timeAgo(created);
    if (biz.isEmpty) return when;
    return when.isEmpty ? biz : '$biz · $when';
  }

  /// La nota es **1-10** (`customer_reviews.rating`, CHECK 1..10), no 1-5. Se
  /// pinta sobre 5 estrellas dividiendo entre 2 —el mismo patrón que la web en
  /// `provider/business.$id.tsx`— y se escribe el número al lado.
  ///
  /// ⚠️ Antes recorría `i <= rating` con 5 iconos: un 6, un 8 y un 10 salían
  /// IDÉNTICOS (cinco estrellas llenas). Se veía coherente solo mientras el
  /// formulario escribía 1-5, que era el bug arreglado el 2026-08-17.
  Widget _stars(int rating) => StarScore(score: rating.toDouble(), size: 14);

  Widget _anonNote(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 26, 40, 0),
      child: Column(children: [
        Text('🔒', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(
            'Este perfil es anónimo. La identidad se revela solo al proveedor '
            'que desbloquea el contacto.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, height: 1.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
