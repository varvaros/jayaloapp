import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/phase.dart';
import '../domain/profile_address.dart';

final supa = Supabase.instance.client;

/// Se incrementa cada vez que el usuario publica una solicitud, para que las
/// pantallas ya montadas (pestañas vivas del shell) refresquen su lista sin
/// pull-to-refresh. Escuchar con addListener y re-lanzar el fetch.
final requestsChanged = ValueNotifier<int>(0);

// ── Cliente: mis solicitudes y ofertas ──────────────────────────────────────

Future<List<Map<String, dynamic>>> myRequests() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select(
          'id,title,kind,status,is_wholesale,created_at,image_url,image_urls',
        )
        .eq('user_id', uid)
        // Las canceladas (soft-delete de "Eliminar") desaparecen del listado; la
        // fila sigue en la BD (auditable / no se borra un lead pagado).
        .neq('status', 'cancelled')
        .order('created_at', ascending: false),
  );
}

const offerCols =
    'id,request_id,business_id,user_id,price,price_min,price_max,pricing_mode,'
    'hourly_rate,estimated_hours,message,status,unlocked_at,created_at';

Future<List<Map<String, dynamic>>> offersForRequest(String requestId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_offers')
          .select(offerCols)
          .eq('request_id', requestId)
          .order('created_at', ascending: false),
    );

Stream<List<Map<String, dynamic>>> offersStream(String requestId) => supa
    .from('provider_offers')
    .stream(primaryKey: ['id'])
    .eq('request_id', requestId);

OfferLite offerLite(Map<String, dynamic> o) => OfferLite(
  status: o['status'] as String,
  unlockedAt: o['unlocked_at'] == null
      ? null
      : DateTime.parse(o['unlocked_at'] as String),
);

/// Nombres visibles de rubros por id (para el paso "rubros sugeridos" del
/// formulario final de crear solicitud).
Future<Map<String, String>> rubroNames(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.from('rubros').select('id,name').inFilter('id', ids),
  );
  return {for (final r in rows) r['id'] as String: r['name'] as String};
}

/// Insert de solicitud — campos y gates EXACTOS del form final de la web
/// (requests/new.tsx `submit()` L586-608). Lo del turno `routing` viaja en
/// `categories`/`rubros`; el resto viene del FORMULARIO final:
/// - `condition` 'nuevo'|'usado'|'ambos'|'' (vacío en servicios);
/// - `withShipping`/`withInstallation` solo aplican a producto;
/// - `requiresEvaluation` aplica a ambos (la web no lo capa por kind);
/// - `urgency` = string de URGENCY_OPTIONS (producto);
/// - `serviceModality`/`urgencyLevel`/`serviceEventDate` solo servicios.
Future<void> submitRequest({
  required String title,
  required List<String> bullets,
  required String kind, // 'producto' | 'servicio'
  required bool wholesale,
  required List<String> categories,
  required List<String> rubros,
  List<String> imageUrls = const [],
  String condition = '',
  String urgency = 'Normal - 24 horas',
  bool withShipping = false,
  bool withInstallation = false,
  bool requiresEvaluation = false,
  String serviceModality = '',
  String urgencyLevel = '',
  DateTime? serviceEventDate,
}) async {
  final uid = supa.auth.currentUser!.id;
  final isService = kind == 'servicio';
  await supa.from('customer_requests').insert({
    'user_id': uid,
    'kind': kind,
    'title': title,
    'description': bullets.join(' • '),
    'bullets': bullets,
    // image_url = primaria (paridad web requests/new.tsx L570); image_urls = todas.
    'image_url': imageUrls.isEmpty ? '' : imageUrls.first,
    'image_urls': imageUrls,
    'image_thumb_url': null,
    'with_shipping': isService ? false : withShipping,
    'with_installation': isService ? false : withInstallation,
    'requires_evaluation': requiresEvaluation,
    'condition': isService ? '' : condition,
    'urgency': urgency,
    'status': 'open',
    'target_categories': categories,
    'target_rubros': rubros,
    'service_modality': isService ? serviceModality : '',
    'service_event_date':
        isService && serviceModality == 'event' && serviceEventDate != null
        ? serviceEventDate.toUtc().toIso8601String()
        : null,
    'urgency_level': isService ? urgencyLevel : '',
    'budget_min': null,
    'budget_max': null,
    'is_recurring': false,
    'recurrence_note': '',
    'is_wholesale': !isService && wholesale,
    'target_business_id': null,
  });
  requestsChanged.value++;
}

/// Cancela (retira) una solicitud del marketplace. La regla dura la impone la
/// RPC `cancel_customer_request` (SECURITY DEFINER, migración 20260717120000),
/// NO el cliente: solo el dueño, solo si está `open`, y NUNCA si un proveedor
/// ya pagó por desbloquear el contacto — en ese caso la RPC lanza
/// `unlocked_offer_exists` (el llamador lo detecta en el mensaje del error).
Future<void> cancelCustomerRequest(String requestId) async {
  await supa.rpc('cancel_customer_request', params: {'_request_id': requestId});
  requestsChanged.value++;
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

Future<void> rejectOffer({
  required String offerId,
  required String reason,
}) async {
  await supa
      .from('provider_offers')
      .update({'status': 'rejected', 'rejection_reason': reason})
      .eq('id', offerId);
}

Future<void> submitReview({
  required String businessId,
  required int rating,
  String comment = '',
}) async {
  await supa.from('business_reviews').insert({
    'business_id': businessId,
    'reviewer_id': supa.auth.currentUser!.id,
    'rating': rating,
    'comment': comment,
  });
}

// ── Proveedor: bandeja, ofertas, wallet y desbloqueo ────────────────────────

/// Llamada real a `get_provider_inbox_unified` — inyectable en `providerInbox`
/// (mismo patrón que `ProfileStore.loader` en `profile_avatar_button.dart`)
/// para que un test pueda alimentar filas falsas sin red.
Future<dynamic> _fetchProviderInboxRows(String? kind) => supa.rpc(
  'get_provider_inbox_unified',
  params: {'p_limit': 100, 'p_offset': 0, 'p_kind': kind},
);

/// Bug arreglado 2026-07-19 — `providerInbox()` descartaba las filas
/// `source == 'store'` (intereses de producto) que la RPC YA devuelve junto a
/// 'marketplace' (solicitudes), así que el proveedor nunca veía quién tocó
/// "Me interesa" en su catálogo. NO debe volver a filtrar por `source` aquí
/// ni en quien lo llame — `repos_test.dart` inyecta [fetcher] con filas
/// mezcladas de ambos orígenes y revienta si el filtro reaparece.
Future<List<Map<String, dynamic>>> providerInbox({
  String? kind,
  Future<dynamic> Function(String?) fetcher = _fetchProviderInboxRows,
}) async => List<Map<String, dynamic>>.from(await fetcher(kind));

Future<Map<String, dynamic>?> requestById(String id) async => await supa
    .from('customer_requests')
    .select(
      'id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at',
    )
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
  List<String> imageUrls = const [],
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
    'image_urls': imageUrls,
    'offers_shipping': false,
    'offers_installation': false,
    'requires_evaluation': false,
    'pricing_mode': price != null ? 'fixed' : 'range',
    'hourly_rate': null,
  });
}

Future<List<Map<String, dynamic>>> myOffers() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select('$offerCols,request_title,points_charged,purchase_completed')
        .eq('user_id', uid)
        .order('created_at', ascending: false),
  );
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
  String offerId,
  int estimatedCost,
) async {
  final res =
      await supa.rpc(
            'try_unlock_offer',
            params: {'_offer_id': offerId, '_cost': estimatedCost},
          )
          as Map<String, dynamic>;
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: (res['new_balance'] as num?)?.toInt(),
  );
}

Future<({String? firstName, String? phone})> unlockedContact(
  String offerId,
) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_unlocked_offer_contact',
      params: {'_offer_id': offerId},
    ),
  );
  final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
  return (firstName: r['first_name'] as String?, phone: r['phone'] as String?);
}

// ── Proveedor: intereses de producto (Task 9) ───────────────────────────────
// Mismo molde que unlockOffer/unlockedContact de arriba — solo cambia la RPC.

/// RPC atómica; el `_cost` enviado se IGNORA server-side (el costo real lo
/// calcula la RPC, siempre `productInterestUnlockCost`). `already == true`
/// es un ÉXITO idempotente (el contacto ya estaba pagado), no un error —
/// quien llame debe seguir tratando `ok == true` como el único gate.
Future<({bool ok, bool already, int charged, int? newBalance})>
unlockProductInterest(String interestId, int estimatedCost) async {
  final res =
      await supa.rpc(
            'try_unlock_product_interest',
            params: {'_interest_id': interestId, '_cost': estimatedCost},
          )
          as Map<String, dynamic>;
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: (res['new_balance'] as num?)?.toInt(),
  );
}

Future<({String? firstName, String? phone})> productInterestContact(
  String interestId,
) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_unlocked_product_interest_contact',
      params: {'_interest_id': interestId},
    ),
  );
  final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
  return (firstName: r['first_name'] as String?, phone: r['phone'] as String?);
}

/// Abre (o crea) la conversación ligada a un interés de producto — paridad
/// con la web (`ProviderInterestsSection.tsx`): `_kind: 'product_interest'`,
/// `_source_id` = id del INTERÉS (no del producto). El RPC puede devolver el
/// id envuelto en una fila (`rpc` de PostgREST) o el escalar directo, según
/// cómo lo declare Postgres — se cubren ambos.
Future<String?> getOrCreateConversation({
  required String kind,
  required String sourceId,
}) async {
  final res = await supa.rpc(
    'get_or_create_conversation',
    params: {'_kind': kind, '_source_id': sourceId},
  );
  if (res is List) {
    if (res.isEmpty) return null;
    final first = res.first;
    return first is Map ? first.values.first as String? : first as String?;
  }
  return res as String?;
}

Future<void> markPurchaseCompleted(String offerId) async {
  await supa
      .from('provider_offers')
      .update({
        'purchase_completed': true,
        'purchase_completed_at': DateTime.now().toIso8601String(),
        'status': 'completed',
      })
      .eq('id', offerId);
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

// ── Onboarding y verificación (spec 2026-07-16-onboarding-nativo) ───────────

Future<Map<String, dynamic>?> myProfile() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  return await supa
      .from('profiles')
      .select('account_type,first_name,last_name,phone,avatar_url')
      .eq('user_id', uid)
      .maybeSingle();
}

/// ¿La fila PERSONAL (business_id NULL) está sellada? Es el gate del revelado.
Future<bool> whatsappVerified() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('account_verifications')
      .select('whatsapp_verified_at')
      .eq('user_id', uid)
      .isFilter('business_id', null)
      .maybeSingle();
  return row?['whatsapp_verified_at'] != null;
}

Future<bool> isWhatsappTakenRemote(String digits) async =>
    await supa.rpc(
      'is_whatsapp_taken',
      params: {'_whatsapp': digits, '_exclude_user': supa.auth.currentUser!.id},
    ) ==
    true;

/// Alta de consumidor — payload idéntico a choose-role.tsx L88-104 de la web.
Future<void> completeConsumerProfile({
  required String firstName,
  required String lastName,
  required String whatsapp, // E.164
  required String address,
  double? lat,
  double? lng,
  required String termsVersion,
}) async {
  final u = supa.auth.currentUser!;
  await supa.from('profiles').upsert({
    'user_id': u.id,
    'email': u.email,
    'first_name': firstName.isEmpty ? null : firstName,
    'last_name': lastName.isEmpty ? null : lastName,
    'phone': whatsapp,
    'whatsapp': whatsapp,
    'address': address,
    'lat': lat,
    'lng': lng,
    'location_captured_at': (lat != null && lng != null)
        ? DateTime.now().toIso8601String()
        : null,
    'account_type': 'consumer',
    'terms_accepted_at': DateTime.now().toIso8601String(),
    'terms_version': termsVersion,
  }, onConflict: 'user_id');
}

/// Alta de proveedor — RPC atómica (ADR-0029). Lanza con slug estable
/// (whatsapp_taken/phone_taken/rnc_taken/…) que mapea onboardingErrorCopy.
Future<String> completeProviderOnboarding({
  required String firstName,
  required String lastName,
  required String phone, // E.164
  required Map<String, dynamic> business, // shape pending_business
  required String termsVersion,
}) async {
  final res =
      await supa.rpc(
            'complete_provider_onboarding',
            params: {
              '_first_name': firstName,
              '_last_name': lastName,
              '_phone': phone,
              '_business': business,
              '_terms_version': termsVersion,
            },
          )
          as Map<String, dynamic>;
  return res['business_id'] as String;
}

/// Los EF devuelven { error } con copy en español en 4xx; FunctionException
/// trae ese body en `details` — re-lanzar siempre el mensaje humano.
Never _throwFunctionError(FunctionException e) {
  final details = e.details;
  final msg = details is Map ? details['error'] : null;
  throw Exception(msg ?? 'Error de conexión. Intenta de nuevo.');
}

/// Devuelve el canal REAL por el que salió el código ('sms' | 'whatsapp') para
/// que el copy no mienta si `app_settings.otp_channel` cambia.
Future<String> sendOtp({required String phone, String? businessId}) async {
  try {
    final res = await supa.functions.invoke(
      'send-otp',
      body: {'phone': phone, 'business_id': ?businessId},
    );
    final data = res.data as Map<String, dynamic>?;
    if (data?['ok'] != true) {
      throw Exception(data?['error'] ?? 'No se pudo enviar el código');
    }
    return (data?['channel'] as String?) ?? 'sms';
  } on FunctionException catch (e) {
    _throwFunctionError(e);
  }
}

Future<({bool ok, bool businessBadgeVerified})> verifyOtp({
  required String code,
  String? businessId,
}) async {
  try {
    final res = await supa.functions.invoke(
      'verify-otp',
      body: {'code': code, 'business_id': ?businessId},
    );
    final data = res.data as Map<String, dynamic>?;
    if (data?['ok'] != true) {
      throw Exception(data?['error'] ?? 'No se pudo verificar el código');
    }
    return (
      ok: true,
      businessBadgeVerified: data?['business_badge_verified'] == true,
    );
  } on FunctionException catch (e) {
    _throwFunctionError(e);
  }
}

/// Magic link autenticado hacia /provider/wallet (ADR-0031): evita que el
/// proveedor tenga que loguearse a mano en el navegador al recargar. El pago
/// sigue ocurriendo 100% en la web — esto es solo un handoff de sesión.
Future<String> createWalletLoginLink() async {
  try {
    final res = await supa.functions.invoke('create-wallet-login-link');
    final data = res.data as Map<String, dynamic>?;
    final url = data?['url'] as String?;
    if (data?['ok'] != true || url == null) {
      throw Exception(data?['error'] ?? 'No se pudo generar el enlace');
    }
    return url;
  } on FunctionException catch (e) {
    _throwFunctionError(e);
  }
}

/// Chequeo liviano PRE-cobro (paridad web ProviderOffersSection.tsx:670):
/// nunca desbloquear si el contacto no es revelable.
Future<bool> canRevealOffer(String offerId) async =>
    await supa.rpc(
      'can_reveal_offer_whatsapp',
      params: {'_offer_id': offerId},
    ) ==
    true;

Future<List<Map<String, dynamic>>> rubrosForCategories(
  List<String> categoryIds,
) async => List<Map<String, dynamic>>.from(
  await supa
      .from('rubros')
      .select('id,name,category_id')
      .inFilter('category_id', categoryIds)
      .order('name'),
);

Future<String?> uploadBusinessLogo(String filePath) async {
  final uid = supa.auth.currentUser!.id;
  final path = '$uid/logo-${DateTime.now().millisecondsSinceEpoch}.jpg';
  await supa.storage.from('business-logos').upload(path, File(filePath));
  return supa.storage.from('business-logos').getPublicUrl(path);
}

// ── Fotos de solicitudes y ofertas ──────────────────────────────────────────
// Espejan `src/lib/image/uploadRequestImage.ts` de la web: se sube al bucket
// `business-logos` (reusado, público) con prefijo de ruta distinto y se guarda
// la URL pública — NUNCA base64 en la BD.

/// Foto de una solicitud del cliente → `{uid}/requests/<ts>-<rand>.<ext>`.
Future<String> uploadRequestImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'requests');

/// Foto de una oferta del proveedor → `{uid}/offers/<ts>-<rand>.<ext>`.
Future<String> uploadOfferImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'offers');

final _rand = Random();

Future<String> _uploadMarketplaceImage(String filePath, String kind) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext =
      (dot == -1 ? '' : filePath.substring(dot + 1).toLowerCase()).isEmpty
      ? 'jpg'
      : filePath.substring(dot + 1).toLowerCase();
  final rand = _rand.nextInt(1 << 31).toRadixString(16);
  final path = '$uid/$kind/${DateTime.now().millisecondsSinceEpoch}-$rand.$ext';
  await supa.storage
      .from('business-logos')
      .upload(
        path,
        File(filePath),
        fileOptions: FileOptions(contentType: _imageContentType(ext)),
      );
  return supa.storage.from('business-logos').getPublicUrl(path);
}

String _imageContentType(String ext) => switch (ext) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

// ── Chat (spec 2026-07-17-chat-app-design.md) ───────────────────────────────

const chatMsgCols = 'id,sender_id,kind,body,created_at';

Future<List<Map<String, dynamic>>> conversationsList() async =>
    List<Map<String, dynamic>>.from(
      await supa.rpc('get_my_conversations_list'),
    );

Future<Map<String, dynamic>?> fetchConversation(String id) async => await supa
    .from('conversations')
    .select(
      'id,kind,source_id,customer_id,provider_user_id,product_name,'
      'agreed_price,agreed_hourly_rate,agreed_estimated_hours,'
      'product_image_url,request_title,status,created_at',
    )
    .eq('id', id)
    .maybeSingle();

/// Página de historial, más recientes primero. Cursor COMPUESTO (created_at,id)
/// — un cursor de una sola columna salta filas con timestamps iguales.
Future<List<Map<String, dynamic>>> messagesPage(
  String convId, {
  String? beforeCreatedAt,
  String? beforeId,
  int limit = 50,
}) async {
  var q = supa
      .from('conversation_messages')
      .select(chatMsgCols)
      .eq('conversation_id', convId);
  if (beforeCreatedAt != null && beforeId != null) {
    q = q.or(
      'created_at.lt.$beforeCreatedAt,'
      'and(created_at.eq.$beforeCreatedAt,id.lt.$beforeId)',
    );
  }
  return List<Map<String, dynamic>>.from(
    await q
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit),
  );
}

/// Gap al volver de background: solo lo nuevo desde el último visto.
Future<List<Map<String, dynamic>>> messagesSince(
  String convId,
  String afterCreatedAt,
) async => List<Map<String, dynamic>>.from(
  await supa
      .from('conversation_messages')
      .select(chatMsgCols)
      .eq('conversation_id', convId)
      .gt('created_at', afterCreatedAt)
      .order('created_at', ascending: true),
);

Future<Map<String, dynamic>> insertChatMessage({
  required String convId,
  required String? senderId,
  required String kind,
  required String body,
}) async => Map<String, dynamic>.from(
  await supa
      .from('conversation_messages')
      .insert({
        'conversation_id': convId,
        'sender_id': senderId,
        'kind': kind,
        'body': body,
      })
      .select(chatMsgCols)
      .single(),
);

Future<void> updateQuickBody(String messageId, String body) async => supa
    .from('conversation_messages')
    .update({'body': body})
    .eq('id', messageId);

Future<void> markConversationCompleted(String convId) async => supa.rpc(
  'mark_conversation_completed',
  params: {'_conversation_id': convId},
);

Future<void> markConversationLost(String convId) async =>
    supa.from('conversations').update({'status': 'perdido'}).eq('id', convId);

Future<void> improveOfferPrice(String convId, num newPrice) async => supa
    .from('conversations')
    .update({'agreed_price': newPrice})
    .eq('id', convId);

Future<bool> hasConversationRating(String convId) async =>
    (await supa
        .from('conversation_ratings')
        .select('id')
        .eq('conversation_id', convId)
        .maybeSingle()) !=
    null;

/// ¿Ya existe un mensaje de auditoría en esta conversación? Query dedicada:
/// mirar los 50 cargados no basta (la auditoría puede estar más atrás).
Future<bool> hasAuditMessage(String convId) async =>
    (await supa
        .from('conversation_messages')
        .select('id')
        .eq('conversation_id', convId)
        .eq('kind', 'audit')
        .limit(1)
        .maybeSingle()) !=
    null;

Future<void> submitConversationRating({
  required String convId,
  required String customerId,
  required String providerUserId,
  required int overall,
  required bool quality,
  required bool fulfillment,
  required bool service,
  required bool condition,
  String? comment,
}) async => supa.from('conversation_ratings').insert({
  'conversation_id': convId,
  'customer_id': customerId,
  'provider_user_id': providerUserId,
  'overall': overall,
  'quality_ok': quality,
  'fulfillment_ok': fulfillment,
  'service_ok': service,
  'condition_ok': condition,
  'comment': (comment == null || comment.trim().isEmpty)
      ? null
      : comment.trim(),
});

Future<void> reportAccount({
  required String reporterId,
  required String reportedUserId,
  String? convId,
  required String reason,
  String? details,
}) async => supa.from('account_reports').insert({
  'reporter_id': reporterId,
  'reported_user_id': reportedUserId,
  'conversation_id': convId,
  'reason': reason,
  'details': (details == null || details.trim().isEmpty)
      ? null
      : details.trim(),
});

/// Gotcha #14: matchear por LINK (formato actual + legado), nunca entity_id.
Future<void> markChatNotificationsRead(String convId) async {
  final uid = supa.auth.currentUser!.id;
  final readAt = DateTime.now().toUtc().toIso8601String();
  await Future.wait([
    supa
        .from('notifications')
        .update({'read_at': readAt})
        .eq('user_id', uid)
        .eq('kind', 'message_new')
        .eq('link', '/messages?c=$convId')
        .isFilter('read_at', null),
    supa
        .from('notifications')
        .update({'read_at': readAt})
        .eq('user_id', uid)
        .eq('kind', 'message_new')
        .eq('link', '/messages/$convId')
        .isFilter('read_at', null),
  ]);
}

/// Foto del chat → `{uid}/chat/<ts>-<rand>.<ext>` (mismo bucket público).
Future<String> uploadChatImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'chat');

Future<String?> myBusinessAddressBody() async {
  final uid = supa.auth.currentUser!.id;
  final biz = await supa
      .from('provider_businesses')
      .select('id,name,city,sector')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (biz == null) return null;
  final address = await supa.rpc(
    'get_business_address',
    params: {'_business_id': biz['id']},
  );
  if (address == null || (address as String).isEmpty) return null;
  final cityLine = [
    biz['sector'],
    biz['city'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  return [
    biz['name'],
    address,
    cityLine,
  ].whereType<String>().where((s) => s.isNotEmpty).join('\n');
}

Future<String?> myContactBody() async {
  final uid = supa.auth.currentUser!.id;
  final p = await supa
      .from('profiles')
      .select('first_name,last_name,phone,whatsapp')
      .eq('user_id', uid)
      .maybeSingle();
  if (p == null) return null;
  final fullName = [
    p['first_name'],
    p['last_name'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim();
  final lines = <String>[
    if (fullName.isNotEmpty) 'Nombre: $fullName',
    if (p['phone'] is String && (p['phone'] as String).isNotEmpty)
      'Teléfono: ${p['phone']}',
    if (p['whatsapp'] is String &&
        (p['whatsapp'] as String).isNotEmpty &&
        p['whatsapp'] != p['phone'])
      'WhatsApp: ${p['whatsapp']}',
  ];
  return lines.isEmpty ? null : '📇 Mis datos de contacto\n${lines.join('\n')}';
}

Future<String?> myLocationBody() async {
  final uid = supa.auth.currentUser!.id;
  final p = await supa
      .from('profiles')
      .select('address,address_reference,sector,city')
      .eq('user_id', uid)
      .maybeSingle();
  if (p == null) return null;
  final cityLine = [
    p['sector'],
    p['city'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  final parts = <String>[
    if (p['address'] is String && (p['address'] as String).isNotEmpty)
      p['address'] as String,
    if (cityLine.isNotEmpty) cityLine,
    if (p['address_reference'] is String &&
        (p['address_reference'] as String).isNotEmpty)
      'Referencia: ${p['address_reference']}',
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

/// Defaults idénticos a DEFAULT_CHAT_WELCOME de la web + override de app_settings.
const defaultChatWelcome = <String, String>{
  'provider_title': 'Aviso de seguridad antes de vender',
  'provider_body':
      'Jayalo te conecta con clientes, pero no participa en pagos, entregas ni garantías.\n\nAntes de entregar un producto o servicio, verifica la identidad del cliente y confirma que el pago haya sido recibido. Evita confiar únicamente en comprobantes de pago.\n\nCualquier acuerdo, pago o entrega es responsabilidad exclusiva del proveedor y del cliente. Jayalo no se hace responsable por fraudes, incumplimientos o disputas entre las partes.',
  'customer_title': 'Aviso de seguridad antes de comprar',
  'customer_body':
      'Jayalo te conecta con el proveedor, pero no participa en el pago, la entrega ni la garantía del producto o servicio.\n\nAntes de pagar: confirma el producto/servicio, el precio total y la forma de entrega por este chat. Si es posible, verifica el producto en persona antes de pagar.\n\nEvita transferir dinero por adelantado a cuentas que no puedas verificar. Cualquier acuerdo es responsabilidad tuya y del proveedor.',
  'button_label': 'Entiendo y acepto',
  'auto_greeting_template':
      '¡Hola, {first_name}! Gracias por elegir {business}. Confirmo que el acuerdo es: {product}{price}. Estoy listo para concretar la entrega.',
};

Future<Map<String, dynamic>> chatWelcomeConfig() async {
  try {
    final row = await supa
        .from('app_settings')
        .select('value')
        .eq('key', 'chat_welcome_messages')
        .maybeSingle();
    final v = row?['value'];
    return {
      ...defaultChatWelcome,
      if (v is Map) ...Map<String, dynamic>.from(v),
    };
  } catch (_) {
    return Map<String, dynamic>.from(
      defaultChatWelcome,
    ); // best-effort, nunca bloquea
  }
}

Future<String?> conversationCustomerFirstName(String convId) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_conversation_customer_name',
      params: {'_conversation_id': convId},
    ),
  );
  if (rows.isEmpty) return null;
  final full = [
    rows.first['first_name'],
    rows.first['last_name'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim();
  return full.isEmpty ? null : full;
}

Future<String?> myBusinessName() async {
  final uid = supa.auth.currentUser!.id;
  final biz = await supa
      .from('provider_businesses')
      .select('name')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  final n = biz?['name'];
  return (n is String && n.isNotEmpty) ? n : null;
}

// ── Métricas: reputación del cliente y estadísticas del proveedor ───────────

/// Reputación del usuario actual como CLIENTE.
///
/// La RPC `get_customer_reputation` SIEMPRE devuelve exactamente una fila
/// (select de subconsultas escalares sin FROM ni GROUP BY). Para un usuario
/// sin actividad, devuelve ceros o NULL en cada campo, nunca cero filas.
/// El `rows.isEmpty ? null` es solo defensivo por si la RPC cambiara de forma
/// en el futuro. Quien consuma esto debe decidir "sin actividad" mirando los
/// CEROS de los campos, no el null.
///
/// Campos: avg_rating, reviews_count, completed_purchases, requests_count,
/// median_response_minutes, response_samples.
Future<Map<String, dynamic>?> customerReputation() async {
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('get_customer_reputation', params: {'_customer_id': uid}),
  );
  return rows.isEmpty ? null : rows.first;
}

/// Estadísticas del usuario actual como PROVEEDOR: fusiona las dos RPCs en un
/// solo mapa porque la pantalla las muestra juntas y ninguna tiene sentido
/// sola. Las claves ausentes quedan en 0 (proveedor sin actividad todavía).
///
/// Las RPCs `get_provider_stats` y `get_provider_reviews_summary` SIEMPRE
/// devuelven exactamente una fila cada una (select de subconsultas escalares
/// con COALESCE a 0, sin FROM ni GROUP BY). Para un proveedor sin actividad,
/// devuelven ceros en los campos. El `isEmpty` es solo defensivo por si esas
/// RPCs cambiaran de forma en el futuro.
///
/// Campos: clients_count, completed_count, points_invested, revenue_total,
/// avg_rating, reviews_count.
Future<Map<String, dynamic>> providerStats() async {
  final uid = supa.auth.currentUser!.id;
  final results = await Future.wait([
    supa.rpc('get_provider_stats', params: {'_user_id': uid}),
    supa.rpc('get_provider_reviews_summary', params: {'_user_id': uid}),
  ]);
  final stats = List<Map<String, dynamic>>.from(results[0] as List);
  final reviews = List<Map<String, dynamic>>.from(results[1] as List);
  return {
    ...(stats.isEmpty ? const <String, dynamic>{} : stats.first),
    ...(reviews.isEmpty ? const <String, dynamic>{} : reviews.first),
  };
}

/// Cuántos productos y cuántos servicios tiene publicados el proveedor.
/// Solo la CIFRA — el catálogo navegable es un spec aparte.
Future<({int productos, int servicios})> providerCatalogCounts() async {
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa.from('provider_products').select('kind').eq('user_id', uid),
  );
  return (
    productos: rows.where((r) => r['kind'] == 'producto').length,
    servicios: rows.where((r) => r['kind'] == 'servicio').length,
  );
}

/// Solo `completed_count` de `get_provider_stats`, para "Mi negocio" (Task 4):
/// esa pantalla no necesita reseñas ni el resto de KPIs de Estadísticas, así
/// que no vale la pena traer las dos RPCs que fusiona `providerStats()`.
Future<int> providerCompletedCount() async {
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('get_provider_stats', params: {'_user_id': uid}),
  );
  return (rows.isEmpty
          ? 0
          : (rows.first['completed_count'] as num?)?.toInt()) ??
      0;
}

/// SOLO `business_verified_at` (RNC del negocio, revisado por un admin)
/// cuenta como "Negocio verificado" — espejo exacto de la web
/// (`business.$id.tsx`, el chip violeta con `Building2` separado del chip
/// verde de `whatsapp_verified_at`). Extraída como función pura para que un
/// futuro regreso a `whatsapp_verified_at` (el bug original de este mismo
/// campo) rompa un test sin necesitar mockear Supabase.
bool businessVerifiedFrom(Map<String, dynamic> businessRow) =>
    businessRow['business_verified_at'] != null;

/// Cabecera del negocio para "Mi negocio" (Task 4): nombre, logo y si el
/// sello de "Negocio verificado" está confirmado.
///
/// Fix (revisión de Task 4): antes este booleano leía
/// `account_verifications.whatsapp_verified_at` por `business_id`, así que la
/// cabecera mostraba "Negocio verificado" con solo el WhatsApp confirmado —
/// una credencial distinta a la del RNC que la web exige para ese mismo
/// texto. `business_verified_at` vive en la MISMA fila de
/// `provider_businesses` que ya se trae para nombre/logo, así que además se
/// ahorra el viaje a `account_verifications`. Decisión de alcance: el sello
/// de WhatsApp del negocio NO se agrega aquí como chip aparte (sería una
/// pieza de UI nueva, fuera del hallazgo puntual) — el proveedor ya lo ve en
/// Ajustes ("Sello de WhatsApp del negocio").
/// `null` si el proveedor todavía no tiene negocio creado (no debería pasar
/// en esta pantalla, pero la ruta no lo garantiza).
Future<({String id, String name, String? logoUrl, bool verified})?>
myBusinessProfile() async {
  final uid = supa.auth.currentUser!.id;
  final biz = await supa
      .from('provider_businesses')
      .select('id,name,logo_url,business_verified_at')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (biz == null) return null;
  final logo = biz['logo_url'] as String?;
  return (
    id: biz['id'] as String,
    name: (biz['name'] as String?) ?? '',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    verified: businessVerifiedFrom(biz),
  );
}

/// TODAS las solicitudes abiertas, de cualquier rubro, excluyendo las propias.
///
/// Decisión PO 2026-07-17: esta vista existe para que el marketplace no se vea
/// vacío, así que NUNCA filtra por rubro ni categoría del proveedor. Antes la
/// web aplicaba las preferencias por defecto y dejaba la pestaña en "0
/// resultados" aunque hubiera solicitudes abiertas de otros rubros.
Future<List<Map<String, dynamic>>> allOpenRequests({String? kind}) async {
  final uid = supa.auth.currentUser!.id;
  var q = supa
      .from('customer_requests')
      .select('id,title,description,kind,urgency,zone,created_at')
      .eq('status', 'open')
      .neq('user_id', uid);
  if (kind != null) q = q.eq('kind', kind);
  return List<Map<String, dynamic>>.from(
    await q.order('created_at', ascending: false).limit(100),
  );
}

// ── Catálogo (Task 6): listado de productos/servicios publicados ───────────

const catalogProductCols =
    'id,user_id,business_id,name,description,price,'
    'price_min,price_max,image_urls,category_id,rubro,kind';

/// Quita `%`/`,` de un término de búsqueda antes de meterlo en un patrón
/// `ilike`/`or` de PostgREST — mismo saneo que `requests/index.tsx` de la web
/// (`term.replace(/[%,]/g, " ")`): sin esto, un usuario que escribe una coma
/// rompe el separador de `.or(...)` y un `%` cambia el propio patrón ilike.
String sanitizeCatalogSearchTerm(String term) =>
    term.replaceAll(RegExp(r'[%,]'), ' ');

/// Paridad con `productHitsQ` de la web (`requests/index.tsx`): catálogo
/// público de productos/servicios de CUALQUIER proveedor, sin paginación por
/// cursor (la web tampoco la tiene en esta vista — `limit(60)` alcanza).
///
/// Task 4 (2026-07-20): además de `kind` + búsqueda por texto, ya soporta los
/// filtros de categoría/rubro/mayoreo de la web.
Future<List<Map<String, dynamic>>> catalogProducts({
  required String kind,
  String? search,
  String? categoryId,
  String? rubro,
  bool wholesale = false,
}) async {
  // En mayoreo se une el negocio (inner) para poder exigir is_wholesale, igual
  // que `productHitsQ` de la web. El objeto embebido `provider_businesses` que
  // vuelve en cada fila es inofensivo (la tarjeta no lo lee).
  final cols = wholesale
      ? '$catalogProductCols,provider_businesses!inner(is_wholesale)'
      : catalogProductCols;
  var q = supa.from('provider_products').select(cols).eq('kind', kind);
  if (wholesale) q = q.eq('provider_businesses.is_wholesale', true);
  if (categoryId != null) q = q.eq('category_id', categoryId);
  if (rubro != null) q = q.ilike('rubro', rubro);
  final term = search?.trim();
  if (term != null && term.isNotEmpty) {
    final safe = sanitizeCatalogSearchTerm(term);
    q = q.or(
      'name.ilike.%$safe%,description.ilike.%$safe%,rubro.ilike.%$safe%',
    );
  }
  return List<Map<String, dynamic>>.from(
    await q.order('created_at', ascending: false).limit(60),
  );
}

// ── Catálogo (Task 7): detalle del producto + "Me interesa" ────────────────

/// Columnas del detalle — paridad con el `select` de
/// `src/routes/products.$productId.tsx` (web) + `condition`, que trae aparte
/// `InterestConfirmDialog.tsx` para el chip Nuevo/Usado.
const productDetailCols =
    'id,user_id,business_id,name,description,color,'
    'price,price_min,price_max,image_urls,category_id,rubro,condition,'
    'offers_shipping,offers_installation,kind';

Future<Map<String, dynamic>?> productDetail(String id) async => await supa
    .from('provider_products')
    .select(productDetailCols)
    .eq('id', id)
    .maybeSingle();

// ── Reputación del proveedor por lote (catálogo) ──────────────────────────

/// avg/count de reseñas de un negocio. Interfaz ESTABLE a propósito: hoy la
/// respalda la RPC por lote `get_business_ratings`; si mañana se denormaliza en
/// `provider_businesses`, esta firma y la UI que la consume no cambian.
typedef BusinessRating = ({double avg, int count});

/// Trae la reputación de varios negocios en UNA llamada. De-duplica ids y no
/// llama a la red con lista vacía.
Future<Map<String, BusinessRating>> businessRatings(
    List<String> businessIds) async {
  final ids = businessIds.toSet().toList();
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('get_business_ratings', params: {'_business_ids': ids}),
  );
  return {
    for (final r in rows)
      r['business_id'] as String: (
        avg: (r['avg_rating'] as num?)?.toDouble() ?? 0,
        count: (r['reviews_count'] as num?)?.toInt() ?? 0,
      ),
  };
}

/// Fusiona la reputación en cada item del catálogo por su `business_id`. Pura y
/// sin mutar la entrada: un negocio sin reseñas queda sin `avg_rating` (la
/// tarjeta oculta la estrella).
List<Map<String, dynamic>> mergeCatalogRatings(
    List<Map<String, dynamic>> items, Map<String, BusinessRating> ratings) {
  return [
    for (final it in items)
      if (it['business_id'] is String && ratings[it['business_id']] != null)
        {
          ...it,
          'avg_rating': ratings[it['business_id']]!.avg,
          'reviews_count': ratings[it['business_id']]!.count,
        }
      else
        it,
  ];
}

/// Entrada de PRODUCCIÓN del catálogo: trae los productos y les fusiona la
/// reputación de su negocio en una segunda llamada por lote. La `CatalogView`
/// consume esto; los tests/harness inyectan su propio `fetch` con el rating ya
/// horneado, así que no tocan la red.
Future<List<Map<String, dynamic>>> catalogProductsWithRatings({
  required String kind,
  String? search,
  String? categoryId,
  String? rubro,
  bool wholesale = false,
}) async {
  final items = await catalogProducts(
      kind: kind,
      search: search,
      categoryId: categoryId,
      rubro: rubro,
      wholesale: wholesale);
  final ids = <String>{
    for (final it in items)
      if (it['business_id'] is String) it['business_id'] as String,
  }.toList();
  // La reputación es un adorno (spec §2): si la RPC por lote falla, se ocultan
  // las estrellas — NO se tira todo el catálogo a la pantalla de error.
  final ratings = await businessRatings(ids)
      .catchError((_) => <String, BusinessRating>{});
  return mergeCatalogRatings(items, ratings);
}

/// Cabecera pública de un negocio (nombre/logo/sello) — mismo shape que
/// `BusinessProfile` de `my_business_screen.dart`, redefinido aquí (capa de
/// datos, sin importar entre features de cliente/proveedor).
typedef BusinessLite = ({
  String id,
  String name,
  String? logoUrl,
  bool verified,
});

BusinessLite? _mapBusinessLite(Map<String, dynamic>? b) {
  if (b == null) return null;
  final logo = b['logo_url'] as String?;
  return (
    id: b['id'] as String,
    name: (b['name'] as String?) ?? '',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    verified: businessVerifiedFrom(b),
  );
}

const _businessLiteCols = 'id,name,logo_url,business_verified_at';

Future<BusinessLite?> businessLite(String businessId) async => _mapBusinessLite(
  await supa
      .from('provider_businesses')
      .select(_businessLiteCols)
      .eq('id', businessId)
      .maybeSingle(),
);

/// Fallback cuando el producto no tiene `business_id` (paridad web: busca el
/// negocio del proveedor por `user_id`).
Future<BusinessLite?> businessLiteByOwner(String userId) async =>
    _mapBusinessLite(
      await supa
          .from('provider_businesses')
          .select(_businessLiteCols)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle(),
    );

/// Estado de interés del cliente actual sobre un producto: `exists` alimenta
/// el estado idempotente "ya enviaste tu interés" (el SELECT sigue permitido
/// tras la migración 20260718150000, que solo revocó INSERT/UPDATE de tabla);
/// `unlocked` es el gate de identidad del negocio (paridad
/// `products.$productId.tsx`: el negocio se muestra genérico hasta que algún
/// proveedor pagó por desbloquear el interés de este cliente en este
/// producto — nunca se revela gratis por adelantado).
Future<({bool exists, bool unlocked})> productInterestStatus(
  String productId,
) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return (exists: false, unlocked: false);
  final row = await supa
      .from('product_interests')
      .select('id,unlocked_at')
      .eq('product_id', productId)
      .eq('customer_id', uid)
      .limit(1)
      .maybeSingle();
  if (row == null) return (exists: false, unlocked: false);
  return (exists: true, unlocked: row['unlocked_at'] != null);
}

/// Registra el interés vía la RPC SECURITY DEFINER `create_product_interest`
/// (migración `20260718150000` de jayalo-main, AÚN NO aplicada a prod al
/// escribir esto): deriva provider_user_id/business_id/product_name
/// server-side (resuelve contra `provider_products` o `provider_packages`);
/// el INSERT directo a `product_interests` está revocado. `already_exists`
/// distingue el reintento idempotente sin round-trip extra.
Future<({bool ok, bool alreadyExists, String? id})> sendProductInterest(
  String productId,
  String message,
) async {
  final res =
      await supa.rpc(
            'create_product_interest',
            params: {'_product_id': productId, '_message': message},
          )
          as Map<String, dynamic>;
  return (
    ok: res['ok'] == true,
    alreadyExists: res['already_exists'] == true,
    id: res['id'] as String?,
  );
}

/// Dirección compuesta del perfil del cliente — paridad con el `useEffect`
/// de `InterestConfirmDialog.tsx`: `address` completo gana; si no existe se
/// arma con `street street_number, sector, city` ([composeProfileAddress]).
Future<String?> myDeliveryAddress() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  final p = await supa
      .from('profiles')
      .select('address,street,street_number,sector,city')
      .eq('user_id', uid)
      .maybeSingle();
  if (p == null) return null;
  return composeProfileAddress(
    address: p['address'] as String?,
    street: p['street'] as String?,
    streetNumber: p['street_number'] as String?,
    sector: p['sector'] as String?,
    city: p['city'] as String?,
  );
}

/// Foto de referencia de un interés (solo servicio) →
/// `{uid}/interest/<ts>-<rand>.<ext>`. Kind más cercano al
/// `persistRequestImage(..., 'interest')` de la web (mismo bucket público
/// `business-logos`, reusado por todas las fotos de marketplace de la app).
Future<String> uploadInterestImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'interest');
