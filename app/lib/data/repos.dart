import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/chat.dart' show QuickItem;
import '../domain/phase.dart';
import '../domain/profile_address.dart';

final supa = Supabase.instance.client;

/// Se incrementa cada vez que el usuario publica una solicitud, para que las
/// pantallas ya montadas (pestañas vivas del shell) refresquen su lista sin
/// pull-to-refresh. Escuchar con addListener y re-lanzar el fetch.
final requestsChanged = ValueNotifier<int>(0);

/// Contador para el badge de la pestaña "Solicitudes" de la barra flotante.
/// Su significado depende del rol activo (solo hay uno por sesión): para el
/// CLIENTE = solicitudes con ofertas por revisar; para el PROVEEDOR = solicitudes
/// abiertas en su bandeja "Para ti". Cada pantalla lo actualiza tras su fetch;
/// la barra lo lee con un `ValueListenableBuilder`. 0 = sin badge.
final solicitudesBadge = ValueNotifier<int>(0);

/// Badge de MENSAJES sin leer para el ícono "Mensajes" de la barra flotante
/// (pedido PO 2026-07-21: "cuando haya mensajes nuevos en el chat, que aparezca
/// una notificación en el icono del navbar"). Suma `unread_count` de todas las
/// conversaciones. Se refresca al montar el shell y al volver del background
/// (mismo patrón sin-socket que [NotifCountStore]), y de forma EXACTA cuando la
/// lista de conversaciones o un chat ya tienen el dato fresco.
class MessagesBadgeStore extends ChangeNotifier {
  int count = 0;

  MessagesBadgeStore() {
    // Al cerrar sesión no arrastrar el conteo del usuario anterior. Va en
    // try/catch: este store es global y el shell lo referencia, pero en los
    // widget-tests de la barra Supabase no está inicializado (`Supabase.instance`
    // dispara un assert) — el badge simplemente arranca inerte ahí.
    try {
      supa.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.signedOut) set(0);
      });
    } catch (_) {}
  }

  void set(int n) {
    final next = n.clamp(0, 999);
    if (next != count) {
      count = next;
      notifyListeners();
    }
  }

  /// Recuenta desde el servidor (best-effort: nunca rompe la barra).
  Future<void> refresh() async {
    try {
      final rows = await conversationsList();
      final total = rows.fold<int>(
          0, (s, c) => s + ((c['unread_count'] as int?) ?? 0));
      set(total);
    } catch (_) {}
  }
}

final messagesBadge = MessagesBadgeStore();

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
    'hourly_rate,estimated_hours,message,status,unlocked_at,created_at,'
    // Fotos de la oferta (marquesina en la hoja de detalle) + logística de
    // envío (para sumar al precio en el badge "Más económica").
    'image_urls,offers_shipping,shipping_price,'
    // Detalles estructurados que la hoja de la oferta muestra si existen
    // (pedido PO: color, tiempo de entrega, garantía, etc. — no solo el
    // mensaje compuesto).
    'offers_installation,installation_price,requires_evaluation,'
    'evaluation_price,availability_note,estimated_duration,product_brand,'
    'product_colors,product_warranty,delivery_time';

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

/// De un lote de solicitudes, cuáles ya tienen una oferta de ESTE usuario
/// (proveedor) — para el badge "Ya ofertaste" en la bandeja. Filtra por
/// `user_id` (quien mira la bandeja), coherente con "una oferta por solicitud".
Future<Set<String>> myOfferedRequestIds(List<String> requestIds) async {
  if (requestIds.isEmpty) return {};
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select('request_id')
        .eq('user_id', uid)
        .inFilter('request_id', requestIds),
  );
  return {for (final r in rows) r['request_id'] as String};
}

/// Como [myOfferedRequestIds] pero con el ESTADO EFECTIVO de la oferta para el
/// badge de la bandeja: 'pending' ("Ya ofertaste"), 'accepted' ("Aceptada") y
/// **'unlocked'** ("Desbloqueado", cuando ya se pagó el contacto — pedido PO
/// 2026-07-22). `unlocked_at != null` gana sobre el status.
Future<Map<String, String>> myOfferedRequestStatuses(
    List<String> requestIds) async {
  if (requestIds.isEmpty) return {};
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select('request_id,status,unlocked_at')
        .eq('user_id', uid)
        .inFilter('request_id', requestIds),
  );
  return {
    for (final r in rows)
      r['request_id'] as String:
          (r['unlocked_at'] != null ? 'unlocked' : r['status'] as String),
  };
}

/// Cuántas ofertas ha recibido cada solicitud (FOMO para el proveedor, pedido
/// PO 2026-07-21): SOLO el número, nunca las ofertas — la RLS impide leer las
/// ofertas ajenas, así que se pasa por la RPC SECURITY DEFINER
/// `offer_counts_for_requests`, que devuelve únicamente el agregado. Devuelve
/// un mapa requestId→conteo; las solicitudes sin ofertas simplemente no
/// aparecen (se tratan como 0). Best-effort en quien llama.
Future<Map<String, int>> offerCountsForRequests(List<String> requestIds) async {
  if (requestIds.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('offer_counts_for_requests',
        params: {'p_request_ids': requestIds}),
  );
  return {
    for (final r in rows)
      r['request_id'] as String: (r['offer_count'] as num).toInt(),
  };
}

/// Solicitudes ABIERTAS (de otros) a las que este proveedor ya ofertó — para
/// que una oferta hecha en OTRO rubro también aparezca en "Para ti" (pedido
/// PO: "si alguien ofertó en otro rubro, esa oferta pasa a Para ti").
/// Mismas columnas que [allOpenRequests] para que la tarjeta pinte igual.
Future<List<Map<String, dynamic>>> myOfferedOpenRequests(
    {String? kind}) async {
  final uid = supa.auth.currentUser!.id;
  final offers = List<Map<String, dynamic>>.from(
    await supa.from('provider_offers').select('request_id').eq('user_id', uid),
  );
  final ids = {for (final o in offers) o['request_id'] as String}.toList();
  if (ids.isEmpty) return [];
  var q = supa
      .from('customer_requests')
      .select(
          'id,title,description,kind,urgency,zone,is_wholesale,created_at,image_url')
      .eq('status', 'open')
      .inFilter('id', ids);
  if (kind != null) q = q.eq('kind', kind);
  return List<Map<String, dynamic>>.from(
    await q.order('created_at', ascending: false).limit(100),
  );
}

/// La oferta que ESTE negocio ya envió a esta solicitud, o `null` si aún no ha
/// ofertado. Regla PO: **una sola oferta por solicitud por proveedor** — el
/// detalle usa esto para mostrar "Ya ofertaste" en vez del formulario. El
/// filtro por `business_id` (no `user_id`) hace la regla POR NEGOCIO, que es la
/// unidad que oferta. La RLS ya deja al dueño leer sus propias ofertas.
Future<Map<String, dynamic>?> myOfferForRequest(
    String requestId, String businessId) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select(offerCols)
        .eq('request_id', requestId)
        .eq('business_id', businessId)
        .limit(1),
  );
  return rows.isEmpty ? null : rows.first;
}

/// Bandera de verificación por negocio (RPC `businesses_verified`): el cliente
/// no puede leer las columnas de verificación (RLS), así que la señal pública
/// "verificado" viene por esta RPC. Devuelve business_id → bool.
Future<Map<String, bool>> businessesVerified(List<String> businessIds) async {
  if (businessIds.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('businesses_verified', params: {'_ids': businessIds}),
  );
  return {
    for (final r in rows) r['business_id'] as String: r['verified'] as bool,
  };
}

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
  // Presupuesto estimado del cliente (opcional, solo servicios — paridad web
  // requests/new.tsx). Se guarda solo si es > 0.
  num? budgetMin,
  num? budgetMax,
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
    'budget_min':
        isService && budgetMin != null && budgetMin > 0 ? budgetMin : null,
    'budget_max':
        isService && budgetMax != null && budgetMax > 0 ? budgetMax : null,
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
      // image_url/image_urls: el detalle del proveedor pinta la foto del
      // cliente en el panel ámbar (igual que el detalle del cliente). Sin
      // estas columnas el panel SIEMPRE caía al ícono — "llegan sin imágenes".
      'id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at,image_url,image_urls,budget_min,budget_max',
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
/// Campos compartidos entre CREAR ([makeOffer]) y EDITAR ([updateOffer]) una
/// oferta. Aísla la forma del payload en un solo lugar para no duplicar la
/// regla de "guardar el costo solo si el toggle está activo Y > 0 (0 = gratis)"
/// ni la de "por hora solo aplica en ese modo".
Map<String, dynamic> _offerFields({
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
  List<String> imageUrls = const [],
  String pricingMode = 'fixed',
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  double? hourlyRate,
  double? estimatedHours,
  String availabilityNote = '',
  String estimatedDuration = '',
  String productBrand = '',
  List<String> productColors = const [],
  String productWarranty = '',
  String deliveryTime = '',
}) => {
  'price': price,
  'price_min': priceMin,
  'price_max': priceMax,
  'message': message,
  'image_urls': imageUrls,
  // Logística de producto (paridad web RequestRespondSection.tsx:952-957): el
  // precio solo se guarda si el toggle está activo Y el costo > 0 (0 = gratis).
  'offers_shipping': offersShipping,
  'shipping_price':
      offersShipping && (shippingPrice ?? 0) > 0 ? shippingPrice : null,
  'offers_installation': offersInstallation,
  'installation_price':
      offersInstallation && (installationPrice ?? 0) > 0 ? installationPrice : null,
  'requires_evaluation': requiresEvaluation,
  'evaluation_price':
      requiresEvaluation && (evaluationPrice ?? 0) > 0 ? evaluationPrice : null,
  'pricing_mode': pricingMode,
  // Por hora (servicio): tarifa + horas solo aplican en ese modo.
  'hourly_rate': pricingMode == 'hourly' ? hourlyRate : null,
  'estimated_hours': pricingMode == 'hourly' ? estimatedHours : null,
  'availability_note': availabilityNote,
  'estimated_duration': estimatedDuration,
  // Detalles del producto (paridad web): solo se guardan si vienen.
  'product_brand': productBrand.trim().isEmpty ? null : productBrand.trim(),
  'product_colors': productColors.isEmpty ? null : productColors,
  'product_warranty':
      productWarranty.trim().isEmpty ? null : productWarranty.trim(),
  'delivery_time': deliveryTime.trim().isEmpty ? null : deliveryTime.trim(),
};

Future<void> makeOffer({
  required Map<String, dynamic> request,
  required String businessId,
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
  List<String> imageUrls = const [],
  String pricingMode = 'fixed',
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  double? hourlyRate,
  double? estimatedHours,
  String availabilityNote = '',
  String estimatedDuration = '',
  String productBrand = '',
  List<String> productColors = const [],
  String productWarranty = '',
  String deliveryTime = '',
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_offers').insert({
    'user_id': uid,
    'business_id': businessId,
    'request_id': request['id'],
    'request_title': request['title'],
    'status': 'pending',
    ..._offerFields(
      price: price,
      priceMin: priceMin,
      priceMax: priceMax,
      message: message,
      imageUrls: imageUrls,
      pricingMode: pricingMode,
      offersShipping: offersShipping,
      shippingPrice: shippingPrice,
      offersInstallation: offersInstallation,
      installationPrice: installationPrice,
      requiresEvaluation: requiresEvaluation,
      evaluationPrice: evaluationPrice,
      hourlyRate: hourlyRate,
      estimatedHours: estimatedHours,
      availabilityNote: availabilityNote,
      estimatedDuration: estimatedDuration,
      productBrand: productBrand,
      productColors: productColors,
      productWarranty: productWarranty,
      deliveryTime: deliveryTime,
    ),
  });
}

/// Edita una oferta PENDIENTE propia (RLS: dueño). No toca
/// request_id/business_id/status; misma forma de payload que [makeOffer].
Future<void> updateOffer({
  required String offerId,
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
  List<String> imageUrls = const [],
  String pricingMode = 'fixed',
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  double? hourlyRate,
  double? estimatedHours,
  String availabilityNote = '',
  String estimatedDuration = '',
  String productBrand = '',
  List<String> productColors = const [],
  String productWarranty = '',
  String deliveryTime = '',
}) async {
  await supa.from('provider_offers').update(_offerFields(
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    message: message,
    imageUrls: imageUrls,
    pricingMode: pricingMode,
    offersShipping: offersShipping,
    shippingPrice: shippingPrice,
    offersInstallation: offersInstallation,
    installationPrice: installationPrice,
    requiresEvaluation: requiresEvaluation,
    evaluationPrice: evaluationPrice,
    hourlyRate: hourlyRate,
    estimatedHours: estimatedHours,
    availabilityNote: availabilityNote,
    estimatedDuration: estimatedDuration,
    productBrand: productBrand,
    productColors: productColors,
    productWarranty: productWarranty,
    deliveryTime: deliveryTime,
  )).eq('id', offerId);
}

/// Fila COMPLETA de una oferta propia (todas las columnas) para prefijar el
/// formulario de edición — `offerCols` no trae los detalles de producto.
Future<Map<String, dynamic>?> offerForEdit(String offerId) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.from('provider_offers').select().eq('id', offerId).limit(1),
  );
  return rows.isEmpty ? null : rows.first;
}

/// Borra una oferta PENDIENTE propia (RLS: dueño). Solo se ofrece en la app
/// para ofertas SIN aceptar; una aceptada ya está en el flujo de dinero.
Future<void> deleteOffer(String offerId) =>
    supa.from('provider_offers').delete().eq('id', offerId);

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

/// Preferencia de contacto del usuario (pedido PO 2026-07-22): si prefiere que
/// lo contacten por WhatsApp (true) o SOLO por el chat de Jayalo (false).
/// Es la columna `profiles.whatsapp_reveal_enabled` que gatea
/// `can_reveal_offer_whatsapp` server-side. DEFAULT = DESACTIVADO (pedido PO
/// 2026-07-21, alineado con la doctrina "WhatsApp nunca es la conversación"):
/// quien lo quiera lo enciende en Ajustes.
Future<bool> whatsappRevealEnabled() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('profiles')
      .select('whatsapp_reveal_enabled')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['whatsapp_reveal_enabled'] as bool? ?? false;
}

Future<void> setWhatsappRevealEnabled(bool enabled) async {
  final uid = supa.auth.currentUser!.id;
  await supa
      .from('profiles')
      .update({'whatsapp_reveal_enabled': enabled}).eq('user_id', uid);
}

/// Respuestas rápidas del chat personalizadas por el usuario (jsonb
/// `{"customer":[...],"provider":[...]}`). NULL / clave ausente = defaults.
Future<Map<String, dynamic>?> fetchCustomQuickReplies() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('profiles')
      .select('custom_quick_replies')
      .eq('user_id', uid)
      .maybeSingle();
  final v = row?['custom_quick_replies'];
  return v is Map ? Map<String, dynamic>.from(v) : null;
}

/// Guarda la lista personalizada de un rol SIN pisar la del otro (read-modify-
/// write del jsonb). Una lista vacía deja el rol como personalizado-vacío; para
/// volver a los defaults se guarda la lista de defaults tal cual (el editor lo
/// hace con "Restaurar predeterminados").
Future<void> saveCustomQuickReplies({
  required bool provider,
  required List<QuickItem> items,
}) async {
  final uid = supa.auth.currentUser!.id;
  final current = await fetchCustomQuickReplies() ?? <String, dynamic>{};
  current[provider ? 'provider' : 'customer'] =
      items.map((e) => e.toJson()).toList();
  await supa
      .from('profiles')
      .update({'custom_quick_replies': current}).eq('user_id', uid);
}

/// Restaura los defaults de un rol quitando su clave del jsonb (así el usuario
/// vuelve a heredar los defaults VIVOS de la app, no una copia congelada).
Future<void> resetCustomQuickReplies({required bool provider}) async {
  final uid = supa.auth.currentUser!.id;
  final current = await fetchCustomQuickReplies();
  if (current == null) return; // nunca personalizó: ya está en defaults
  current.remove(provider ? 'provider' : 'customer');
  await supa
      .from('profiles')
      .update({'custom_quick_replies': current.isEmpty ? null : current})
      .eq('user_id', uid);
}

/// ¿El usuario actual es admin? (RLS de `user_roles`: cada quien lee su propia
/// fila). Para mostrar el "Registro rápido" del menú (pedido PO 2026-07-22).
Future<bool> isAdmin() async {
  try {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await supa
        .from('user_roles')
        .select('role')
        .eq('user_id', uid)
        .eq('role', 'admin')
        .maybeSingle();
    return row != null;
  } catch (_) {
    return false;
  }
}

/// Registro rápido de un proveedor por correo (solo admin). Llama a la edge
/// function `admin-invite-provider`, que reproduce el `inviteProvider` de la web
/// (invita por Auth Admin con `pending_business` en la metadata).
Future<void> inviteProviderQuick({
  required String email,
  String businessName = '',
  String whatsapp = '',
  String city = '',
}) async {
  try {
    await supa.functions.invoke('admin-invite-provider', body: {
      'email': email,
      'businessName': businessName,
      'whatsapp': whatsapp,
      'city': city,
    });
  } on FunctionException catch (e) {
    final d = e.details;
    final msg = (d is Map && d['error'] != null)
        ? d['error'].toString()
        : 'No se pudo registrar el proveedor.';
    throw Exception(msg);
  }
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

/// Crea (o reutiliza) un rubro dentro de una categoría — RPC SECURITY DEFINER
/// `create_provider_rubro` (migración `create_provider_rubro_rpc`). `rubros`
/// tiene RLS que bloquea el INSERT directo de `authenticated`, así que va por
/// la RPC (espeja el server fn `createProviderRubro` de la web: deduplica
/// case-insensitive dentro de la categoría, marca sort_order 999).
Future<Map<String, dynamic>> createProviderRubro({
  required String categoryId,
  required String name,
}) async {
  final res =
      await supa.rpc('create_provider_rubro',
              params: {'_category_id': categoryId, '_name': name})
          as Map<String, dynamic>;
  return res; // {id, name, category_id, created}
}

/// Sube la foto de la cédula al bucket PRIVADO `business-id-docs` y devuelve el
/// PATH de storage (no URL pública — se ve con signed URL). El path espeja la
/// web (`IdDocSection`): `{uid}/{businessId}-cedula-{ts}.{ext}`.
Future<String> uploadIdDocPhoto(String filePath, String businessId) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext =
      (dot == -1 ? '' : filePath.substring(dot + 1).toLowerCase()).isEmpty
      ? 'jpg'
      : filePath.substring(dot + 1).toLowerCase();
  final path =
      '$uid/$businessId-cedula-${DateTime.now().millisecondsSinceEpoch}.$ext';
  await supa.storage.from('business-id-docs').upload(
        path,
        File(filePath),
        fileOptions:
            FileOptions(upsert: true, contentType: _imageContentType(ext)),
      );
  return path;
}

/// Guarda la cédula del proveedor informal/técnico — upsert directo a
/// `provider_business_id_docs` (políticas de dueño; la web lo hace igual
/// client-side). Sin esto el trigger `enforce_business_can_offer` bloquea toda
/// oferta de ese proveedor.
Future<void> saveIdDoc({
  required String businessId,
  required String idNumber,
  required String idPhotoPath,
}) async {
  await supa.from('provider_business_id_docs').upsert({
    'business_id': businessId,
    'id_number': idNumber,
    'id_photo_path': idPhotoPath,
  }, onConflict: 'business_id');
}

/// Contexto de verificación del negocio del proveedor (para Ajustes): tipo,
/// RNC y los sellos (identidad/negocio) que la web fija al aprobar.
Future<Map<String, dynamic>?> myBusinessForVerification() async {
  final uid = supa.auth.currentUser!.id;
  return await supa
      .from('provider_businesses')
      .select('id,business_type,rnc,identity_verified_at,business_verified_at')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
}

/// Confirma/actualiza el RNC del negocio formal — update directo (el dueño
/// tiene policy UPDATE + grant de columna `rnc`; no necesita RPC).
Future<void> updateRnc(String businessId, String rnc) async {
  await supa
      .from('provider_businesses')
      .update({'rnc': rnc}).eq('id', businessId);
}

/// ¿Ya subió la cédula (número no vacío)? — controla si puede ofertar.
Future<bool> hasIdDoc(String businessId) async {
  final row = await supa
      .from('provider_business_id_docs')
      .select('id_number')
      .eq('business_id', businessId)
      .maybeSingle();
  return (row?['id_number'] as String?)?.trim().isNotEmpty ?? false;
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

/// Sube la foto de perfil (bucket público `business-logos`, misma ruta que la
/// web: `{uid}/avatar-{ts}.{ext}`) y actualiza `profiles.avatar_url`. Devuelve
/// la URL pública (pedido PO 2026-07-22: foto editable en el menú lateral).
Future<String> updateMyAvatar(String filePath) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext = dot == -1 ? 'jpg' : filePath.substring(dot + 1).toLowerCase();
  final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
  await supa.storage.from('business-logos').upload(path, File(filePath),
      fileOptions: const FileOptions(upsert: true));
  final url = supa.storage.from('business-logos').getPublicUrl(path);
  await supa.from('profiles').update({'avatar_url': url}).eq('user_id', uid);
  return url;
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

/// De un set de conversaciones, cuáles tienen AL MENOS un mensaje MÍO (para el
/// chip "Nueva" = nunca has hablado, pedido PO 2026-07-22). Una sola query
/// batched sobre las conversaciones ya cargadas; RLS limita a las propias.
Future<Set<String>> conversationsWithMyMessages(List<String> convIds) async {
  if (convIds.isEmpty) return {};
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('conversation_messages')
        .select('conversation_id')
        .eq('sender_id', uid)
        .inFilter('conversation_id', convIds),
  );
  return {for (final r in rows) r['conversation_id'] as String};
}

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

// ── Calificación del PROVEEDOR al CLIENTE (bilateral) ──────────────────────
// Espejo de la web (`ProviderOffersSection`): el proveedor califica al cliente
// 1-5 + comentario en `customer_reviews`, indexado por `offer_id`. La RLS solo
// exige que el negocio sea suyo (sin gate de estado), pero la UI lo muestra al
// cerrarse el chat.

/// ¿El proveedor ya calificó al cliente de esta oferta? (una reseña por oferta).
Future<bool> hasCustomerReview(String offerId) async =>
    (await supa
        .from('customer_reviews')
        .select('id')
        .eq('offer_id', offerId)
        .maybeSingle()) !=
    null;

/// `business_id` de una oferta — el proveedor es dueño de ese negocio, así que
/// escribir el `customer_review` con él pasa la RLS.
Future<String?> offerBusinessId(String offerId) async {
  final row = await supa
      .from('provider_offers')
      .select('business_id')
      .eq('id', offerId)
      .maybeSingle();
  return row?['business_id'] as String?;
}

Future<void> submitCustomerReview({
  required String offerId,
  required String businessId,
  required String customerId,
  required int rating,
  String? comment,
}) async => supa.from('customer_reviews').insert({
  'offer_id': offerId,
  'business_id': businessId,
  'customer_id': customerId,
  'rating': rating,
  // comment es NOT NULL en el esquema → cadena vacía si no escribió nada.
  'comment': (comment ?? '').trim(),
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
/// [customerId] null = el usuario actual (su propia reputación). Con un id, la
/// de ESE cliente — el proveedor la ve en el detalle de una solicitud (pedido
/// PO 2026-07-22). `get_customer_reputation` es SECURITY DEFINER, no expone
/// contacto (solo agregados de reputación).
Future<Map<String, dynamic>?> customerReputation([String? customerId]) async {
  final id = customerId ?? supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc('get_customer_reputation', params: {'_customer_id': id}),
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
Future<
    ({
      String id,
      String name,
      String? logoUrl,
      bool verified,
      String? categoryId,
      String? city,
      bool wholesale,
      String? description,
    })?>
myBusinessProfile() async {
  final uid = supa.auth.currentUser!.id;
  final biz = await supa
      .from('provider_businesses')
      .select(
          'id,name,logo_url,business_verified_at,category_id,city,is_wholesale,description')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (biz == null) return null;
  final logo = biz['logo_url'] as String?;
  final city = (biz['city'] as String?)?.trim();
  final desc = (biz['description'] as String?)?.trim();
  final cat = (biz['category_id'] as String?)?.trim();
  return (
    id: biz['id'] as String,
    name: (biz['name'] as String?) ?? '',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    verified: businessVerifiedFrom(biz),
    categoryId: (cat != null && cat.isNotEmpty) ? cat : null,
    city: (city != null && city.isNotEmpty) ? city : null,
    wholesale: biz['is_wholesale'] == true,
    description: (desc != null && desc.isNotEmpty) ? desc : null,
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
      .select(
          'id,title,description,kind,urgency,zone,is_wholesale,created_at,image_url')
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
  // OJO: `provider_products` NO tiene FK a `provider_businesses` (verificado en
  // prod 2026-07-21) → el embed `provider_businesses!inner(...)` que hacía la
  // web y la app reventaba con PGRST200 ("Could not find a relationship…") y el
  // catálogo mostraba "No se pudo cargar" al activar "Al por mayor". Se resuelve
  // en DOS PASOS: primero los negocios mayoristas, luego se filtra el producto
  // por `business_id` (sin embed). (La web tiene el mismo bug — flag al PO.)
  List<String>? wholesaleBizIds;
  if (wholesale) {
    final biz = await supa
        .from('provider_businesses')
        .select('id')
        .eq('is_wholesale', true);
    wholesaleBizIds = List<Map<String, dynamic>>.from(biz)
        .map((b) => b['id'] as String)
        .toList();
    // Sin negocios mayoristas no hay productos que mostrar (evita un
    // `in.()` vacío, que PostgREST rechaza).
    if (wholesaleBizIds.isEmpty) return const [];
  }
  var q =
      supa.from('provider_products').select(catalogProductCols).eq('kind', kind);
  if (wholesaleBizIds != null) q = q.inFilter('business_id', wholesaleBizIds);
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

/// Tipo de negocio (`formal` | `informal` | `tecnico`) de un negocio. Se usa
/// para ordenar su tienda (PO 2026-07-21): `tecnico` = perfil de SERVICIOS
/// (servicios + trabajos primero); el resto = perfil de PRODUCTOS. Lectura
/// pública de `provider_businesses` (misma tabla que el catálogo ya lee).
Future<String?> providerBusinessType(String businessId) async {
  final row = await supa
      .from('provider_businesses')
      .select('business_type')
      .eq('id', businessId)
      .maybeSingle();
  return row?['business_type'] as String?;
}

// ── Mi tienda: productos/servicios del propio negocio ──────────────────────
// Incluye los campos que autocompletan una oferta al elegir un producto de la
// tienda (color/logística/estado/rubro), no solo lo que pinta la lista.
const storeProductCols =
    'id,name,description,color,price,price_min,price_max,image_urls,'
    'category_id,rubro,kind,condition,offers_shipping,offers_installation,'
    'requires_evaluation';

/// Todos los productos y servicios del propio negocio, más recientes primero.
/// Se separan por kind en la UI con [partitionStoreItems].
Future<List<Map<String, dynamic>>> myStoreProducts(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_products')
          .select(storeProductCols)
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(200),
    );

/// Trabajos anteriores (portafolio) del propio negocio — para "Cargar trabajos
/// anteriores" en la oferta. Mismo modelo que la web (`provider_portfolio_items`).
Future<List<Map<String, dynamic>>> myPortfolioItems(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_portfolio_items')
          .select('id,title,image_urls,category_id,completed_at')
          .eq('business_id', businessId)
          .order('position', ascending: true)
          .limit(200),
    );

/// Guarda como producto de la tienda lo que el proveedor acaba de ofertar
/// (pedido PO 2026-07-21: "¿guardar este producto para envíos futuros?").
/// RLS: owner insert. category_id/rubro/kind/color son NOT NULL en la tabla.
Future<void> saveProductToStore({
  required String businessId,
  required String name,
  required String description,
  required String categoryId,
  required String rubro,
  required String kind,
  String color = '',
  double? price,
  double? priceMin,
  double? priceMax,
  List<String> imageUrls = const [],
  String? condition,
  bool offersShipping = false,
  bool offersInstallation = false,
  bool requiresEvaluation = false,
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_products').insert({
    'user_id': uid,
    'business_id': businessId,
    'name': name,
    'description': description,
    'color': color,
    'category_id': categoryId,
    'rubro': rubro,
    'kind': kind,
    'price': price,
    'price_min': priceMin,
    'price_max': priceMax,
    'image_urls': imageUrls,
    'tags': const <String>[],
    'condition': condition,
    'offers_shipping': offersShipping,
    'offers_installation': offersInstallation,
    'requires_evaluation': requiresEvaluation,
  });
}

/// category_id (slug) + un rubro (NOMBRE) del negocio, para prefijar el
/// guardado en tienda: `provider_products` exige ambos NOT NULL y la oferta no
/// los trae. `provider_business_rubros` guarda `rubro_id` (uuid) → se resuelve
/// a `rubros.name` (que es lo que la web pone en `provider_products.rubro`).
Future<({String? categoryId, String? rubro})> myBusinessCategoryRubro(
    String businessId) async {
  final cat = await supa
      .from('provider_business_categories')
      .select('category_id')
      .eq('business_id', businessId)
      .limit(1)
      .maybeSingle();
  final categoryId = cat?['category_id'] as String?;
  String? rubro;
  final rubRow = await supa
      .from('provider_business_rubros')
      .select('rubro_id')
      .eq('business_id', businessId)
      .limit(1)
      .maybeSingle();
  final rubroId = rubRow?['rubro_id'];
  if (rubroId != null) {
    final r = await supa
        .from('rubros')
        .select('name')
        .eq('id', rubroId)
        .maybeSingle();
    rubro = r?['name'] as String?;
  }
  return (categoryId: categoryId, rubro: rubro);
}

/// Parte una lista mezclada en (productos, servicios). `kind == 'servicio'` va a
/// servicios; cualquier otro valor (incluido null) cuenta como producto.
(List<Map<String, dynamic>>, List<Map<String, dynamic>>) partitionStoreItems(
    List<Map<String, dynamic>> items) {
  final productos = <Map<String, dynamic>>[];
  final servicios = <Map<String, dynamic>>[];
  for (final i in items) {
    (i['kind'] == 'servicio' ? servicios : productos).add(i);
  }
  return (productos, servicios);
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

// ── Opiniones con texto (Mi tienda) ────────────────────────────────────────
// Anónimas a propósito: solo rating/comment/created_at, NUNCA reviewer_id
// (misma restricción que `get_business_ratings`). La web lee estas mismas
// columnas client-side, así que la RLS de `business_reviews` ya las permite a
// `authenticated`; si un cambio de RLS lo bloqueara, mover a una RPC
// SECURITY DEFINER `get_business_reviews(_business_id)` sin cambiar esta firma.
typedef BusinessReview = ({double rating, String? comment, DateTime createdAt});

BusinessReview parseBusinessReview(Map<String, dynamic> row) {
  final raw = (row['comment'] as String?)?.trim() ?? '';
  return (
    rating: (row['rating'] as num?)?.toDouble() ?? 0,
    comment: raw.isEmpty ? null : raw,
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<List<BusinessReview>> businessReviews(String businessId) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('business_reviews')
        .select('rating,comment,created_at')
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(50),
  );
  return rows.map(parseBusinessReview).toList();
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
