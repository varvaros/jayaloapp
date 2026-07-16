import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/phase.dart';

final supa = Supabase.instance.client;

// ── Cliente: mis solicitudes y ofertas ──────────────────────────────────────

Future<List<Map<String, dynamic>>> myRequests() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('customer_requests')
      .select('id,title,kind,status,is_wholesale,created_at')
      .eq('user_id', uid)
      .order('created_at', ascending: false));
}

const offerCols =
    'id,request_id,business_id,user_id,price,price_min,price_max,pricing_mode,'
    'hourly_rate,estimated_hours,message,status,unlocked_at,created_at';

Future<List<Map<String, dynamic>>> offersForRequest(String requestId) async =>
    List<Map<String, dynamic>>.from(await supa
        .from('provider_offers')
        .select(offerCols)
        .eq('request_id', requestId)
        .order('created_at', ascending: false));

Stream<List<Map<String, dynamic>>> offersStream(String requestId) => supa
    .from('provider_offers')
    .stream(primaryKey: ['id']).eq('request_id', requestId);

OfferLite offerLite(Map<String, dynamic> o) => OfferLite(
    status: o['status'] as String,
    unlockedAt: o['unlocked_at'] == null
        ? null
        : DateTime.parse(o['unlocked_at'] as String));

/// Insert de solicitud — campos EXACTOS de la web (requests/new.tsx L541-570),
/// camino sin fotos (v1). `categories`/`rubros` vienen del turno `routing`.
Future<void> submitRequest({
  required String title,
  required List<String> bullets,
  required String kind, // 'producto' | 'servicio'
  required bool wholesale,
  required List<String> categories,
  required List<String> rubros,
}) async {
  final uid = supa.auth.currentUser!.id;
  final isService = kind == 'servicio';
  await supa.from('customer_requests').insert({
    'user_id': uid,
    'kind': kind,
    'title': title,
    'description': bullets.join(' • '),
    'bullets': bullets,
    'image_url': '',
    'image_urls': <String>[],
    'image_thumb_url': null,
    'with_shipping': false,
    'with_installation': false,
    'requires_evaluation': false,
    'condition': '',
    'urgency': 'normal',
    'status': 'open',
    'target_categories': categories,
    'target_rubros': rubros,
    'service_modality': '',
    'service_event_date': null,
    'urgency_level': '',
    'budget_min': null,
    'budget_max': null,
    'is_recurring': false,
    'recurrence_note': '',
    'is_wholesale': !isService && wholesale,
    'target_business_id': null,
  });
}

Future<bool> acceptOffer({required String offerId}) async {
  final uid = supa.auth.currentUser!.id;
  // Guard anti-doble-aceptación: mismo patrón que la web ($requestId.tsx L707-713).
  final rows = await supa
      .from('provider_offers')
      .update({'status': 'accepted', 'customer_id': uid})
      .eq('id', offerId)
      .eq('status', 'pending')
      .select('id');
  return rows.isNotEmpty;
}

Future<void> rejectOffer({required String offerId, required String reason}) async {
  await supa
      .from('provider_offers')
      .update({'status': 'rejected', 'rejection_reason': reason})
      .eq('id', offerId);
}

Future<void> submitReview(
    {required String businessId, required int rating, String comment = ''}) async {
  await supa.from('business_reviews').insert({
    'business_id': businessId,
    'reviewer_id': supa.auth.currentUser!.id,
    'rating': rating,
    'comment': comment,
  });
}

// ── Proveedor: bandeja, ofertas, wallet y desbloqueo ────────────────────────

Future<List<Map<String, dynamic>>> providerInbox({String? kind}) async {
  final rows = List<Map<String, dynamic>>.from(await supa.rpc(
      'get_provider_inbox_unified',
      params: {'p_limit': 100, 'p_offset': 0, 'p_kind': kind}));
  return rows.where((r) => r['source'] == 'marketplace').toList();
}

Future<Map<String, dynamic>?> requestById(String id) async => await supa
    .from('customer_requests')
    .select(
        'id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at')
    .eq('id', id)
    .maybeSingle();

Future<String?> myBusinessId() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_businesses')
      .select('id')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  return row?['id'] as String?;
}

/// Ofertar es GRATIS. Campos idénticos al insert de la web
/// (RequestRespondSection.tsx L940-954, camino precio fijo/rango).
Future<void> makeOffer({
  required Map<String, dynamic> request,
  required String businessId,
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_offers').insert({
    'user_id': uid,
    'business_id': businessId,
    'request_id': request['id'],
    'request_title': request['title'],
    'price': price,
    'price_min': priceMin,
    'price_max': priceMax,
    'message': message,
    'status': 'pending',
    'image_urls': <String>[],
    'offers_shipping': false,
    'offers_installation': false,
    'requires_evaluation': false,
    'pricing_mode': price != null ? 'fixed' : 'range',
    'hourly_rate': null,
  });
}

Future<List<Map<String, dynamic>>> myOffers() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('provider_offers')
      .select('$offerCols,request_title,points_charged,purchase_completed')
      .eq('user_id', uid)
      .order('created_at', ascending: false));
}

Future<int?> walletBalance() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_wallets')
      .select('balance')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['balance'] as int?;
}

/// RPC atómica; el `_cost` enviado se IGNORA server-side (el costo real lo
/// calcula la RPC — regla de seguridad del proyecto).
Future<({bool ok, bool already, int charged, int? newBalance})> unlockOffer(
    String offerId, int estimatedCost) async {
  final res = await supa.rpc('try_unlock_offer',
      params: {'_offer_id': offerId, '_cost': estimatedCost}) as Map<String, dynamic>;
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: (res['new_balance'] as num?)?.toInt(),
  );
}

Future<({String? firstName, String? phone})> unlockedContact(String offerId) async {
  final rows = List<Map<String, dynamic>>.from(
      await supa.rpc('get_unlocked_offer_contact', params: {'_offer_id': offerId}));
  final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
  return (firstName: r['first_name'] as String?, phone: r['phone'] as String?);
}

Future<void> markPurchaseCompleted(String offerId) async {
  await supa.from('provider_offers').update({
    'purchase_completed': true,
    'purchase_completed_at': DateTime.now().toIso8601String(),
    'status': 'completed',
  }).eq('id', offerId);
}

Future<bool> isProviderAccount() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supa
      .from('profiles')
      .select('account_type')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['account_type'] == 'provider';
}
