import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/error_reporter.dart';
import '../core/ttl_cache.dart';
import '../domain/chat.dart'
    show QuickItem, chatMediaPath, chatMediaPrefix, isChatMediaMarker;
import '../domain/contact_info.dart'
    show contactInfoCode, contactInfoMessage, payloadHasContactInfo;
import '../domain/credit_shop.dart' show ShopPackage;
import '../domain/phase.dart';
import '../domain/profile_address.dart';
import '../domain/request_requirements.dart';
import 'location_body.dart';

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
  ///
  /// Antes traía TODA la lista de conversaciones (`conversationsList()` = RPC
  /// agregado con 4 LATERAL por conversación) solo para sumar `unread_count`, y
  /// esto corre al montar el shell y en CADA `resumed`. Ahora un COUNT directo
  /// sobre `notifications`, con payload O(1) en vez de O(nº de chats).
  /// Auditoría de rendimiento 2026-07-22.
  ///
  /// Se filtra por el LINK, no por el kind (PO 2026-08-24). Filtrar por
  /// `kind = 'message_new'` dejaba fuera los otros CINCO kinds que apuntan a una
  /// conversación —aviso de inactividad, cierre por inactividad, valoración
  /// pendiente y las dos de fecha pautada—, así que el chat recibía una tarjeta
  /// nueva y ni el badge ni la lista lo marcaban. Medido en prod: de 44
  /// notificaciones que enlazan a un chat, las 44 llegan acompañadas de
  /// contenido nuevo en esa conversación, así que «apunta a un chat» y «pasó
  /// algo en ese chat» son el mismo conjunto. Sigue casando con el
  /// `unread_count` de la RPC, que correlaciona por el mismo link.
  Future<void> refresh() async {
    try {
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      final res = await supa
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .like('link', '/messages%')
          .isFilter('read_at', null)
          .limit(1)
          .count(CountOption.exact);
      set(res.count);
    } catch (_) {}
  }
}

final messagesBadge = MessagesBadgeStore();

// ── Caché de lecturas (auditoría de rendimiento 2026-07-28) ─────────────────
//
// La app no cacheaba NADA: cada `initState` y cada `resumed` refetcheaba. El
// saldo del wallet era, con diferencia, la query más llamada de todo el
// backend. Estos TTL son los MISMOS que los `staleTime` que la web ya usa para
// las lecturas equivalentes, para que ambos clientes envejezcan igual:
//
//   saldo del wallet   60 s  ← Navbar.tsx staleTime 60_000
//   rol proveedor       5 min ← useIsProvider.ts staleTime 5*60*1000
//   rol admin           5 min ← useIsAdmin.ts    staleTime 5*60*1000
//
// Solo se cachean lecturas de PRESENTACIÓN. Ningún gate real depende de ellas:
// el costo y el débito de un desbloqueo los calcula la RPC atómica server-side,
// y el acceso de admin lo impone la RLS. Un valor viejo pinta un número
// desactualizado un rato; nunca autoriza nada.
class AppCaches {
  AppCaches._();

  /// Saldo en puntos. Se SIEMBRA con el `new_balance` que devuelven las RPCs de
  /// desbloqueo (así el número baja al instante, sin releer) y se invalida al
  /// volver del background — que es cuando pudo recargar por PayPal en la web.
  static final wallet = TtlCache<int?>(const Duration(seconds: 60));

  static final isProvider = TtlCache<bool>(const Duration(minutes: 5));
  static final isAdmin = TtlCache<bool>(const Duration(minutes: 5));

  // ── Listas de pestaña (stale-while-revalidate) ────────────────────────────
  //
  // POR QUÉ (PO 2026-07-30: "el JayaloLoader sigue saliendo cada vez que cambio
  // de pantalla"): el `ShellRoute` destruye el `State` de la pestaña que dejas,
  // así que al volver se re-evalúa su `Future` de carga desde cero. Sin caché
  // eso era un round-trip completo a Supabase en CADA cambio de pestaña, y
  // pasados los 400ms del umbral aparecía la mascota. Con `readFresh` la
  // pantalla pinta lo último que tenía al instante y la red corre por detrás.
  //
  // Solo se cachean las lecturas SIN PARÁMETROS. `providerInbox`,
  // `allOpenRequests` y `catalogProducts` reciben filtros, y un `TtlCache`
  // guarda UN valor: cachearlas acá le serviría al usuario el resultado de otro
  // filtro. Necesitan un caché por clave — pendiente aparte.
  //
  // TTL por tipo, según qué tan rápido envejece cada cosa PARA EL USUARIO:
  static final myRequests = TtlCache<List<Map<String, dynamic>>>(
    // Las ofertas que le llegan al cliente son lo que está esperando ver.
    const Duration(seconds: 30),
  );
  static final myOffers = TtlCache<List<Map<String, dynamic>>>(
    // Del lado proveedor, que le acepten una oferta es LA noticia.
    const Duration(seconds: 30),
  );
  static final conversations = TtlCache<List<Map<String, dynamic>>>(
    // Más corto: la lista de chats es de las que más cambia, y el realtime de
    // la conversación ya la desactualiza mientras conversas.
    const Duration(seconds: 20),
  );

  /// Vacía las listas que dependen de las solicitudes y ofertas del usuario.
  ///
  /// Se llama tras CADA mutación que las cambia (crear solicitud, cancelar,
  /// ofertar, editar oferta, aceptar, rechazar). Sin esto el usuario haría una
  /// acción y al volver a la pestaña vería una lista que todavía no la refleja
  /// — que es peor que la carga que este caché vino a quitar.
  static void invalidateRequestLists() {
    myRequests.clear();
    myOffers.clear();
  }

  /// ¿Dos páginas de lista son "la misma"?
  ///
  /// Hace falta porque [TtlCache.readFresh] compara por identidad, y dos listas
  /// recién deserializadas de la red NUNCA son idénticas: sin esto cada
  /// revalidación en segundo plano avisaría "cambió" y la pantalla recargaría
  /// de más — justo el parpadeo que el caché vino a evitar.
  ///
  /// Compara tamaño y, por fila, `id` + los dos campos que mueven la aguja en
  /// estas listas (`updated_at` y `status`). Es una heurística deliberada: no
  /// compara la fila entera para no pagar un deep-equals en cada revalidación.
  /// El costo de equivocarse es que un cambio en un campo no vigilado tarde un
  /// TTL en verse; el servidor sigue siendo la autoridad.
  static bool sameRows(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['id'] != b[i]['id'] ||
          a[i]['updated_at'] != b[i]['updated_at'] ||
          a[i]['status'] != b[i]['status']) {
        return false;
      }
    }
    return true;
  }

  /// Lo que pudo cambiar MIENTRAS la app estaba en background. Lo llama el
  /// shell en `AppLifecycleState.resumed`, junto al refresh de los badges.
  /// Las listas también: en background pudieron llegar ofertas o mensajes.
  static void onResume() {
    wallet.clear();
    myRequests.clear();
    myOffers.clear();
    conversations.clear();
  }
}

/// Al cerrar sesión (o cambiar de cuenta) se vacía TODO: sin esto el saldo o el
/// rol del usuario anterior sobrevivirían al login del siguiente.
///
/// Lo llama `main()` justo después de `Supabase.initialize`. NO se auto-engancha
/// desde una `final` de nivel superior: las globales de Dart son PEREZOSAS, así
/// que una que nadie referencia jamás se inicializa y el listener no existiría.
/// El try/catch es el mismo caso que [MessagesBadgeStore]: en los widget-tests
/// Supabase no está inicializado y `supa.auth` dispara un assert.
void wireCacheInvalidation() {
  try {
    supa.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.signedOut ||
          e.event == AuthChangeEvent.signedIn) {
        TtlCache.clearAll();
      }
    });
  } catch (_) {}
}

// ── Cliente: mis solicitudes y ofertas ──────────────────────────────────────

/// Mis solicitudes, amortiguadas: al volver a la pestaña pinta lo último que
/// había y refresca por detrás. Si lo que vuelve es distinto, sube
/// `requestsChanged` — el mismo tick que ya escuchan las pantallas para
/// recargarse, así que no hace falta que ninguna sepa que existe un caché.
Future<List<Map<String, dynamic>>> myRequests() => AppCaches.myRequests.readFresh(
      _fetchMyRequests,
      equals: AppCaches.sameRows,
      onChanged: () => requestsChanged.value++,
    );

/// Las cinco columnas de requisitos de `customer_requests`, juntas en una sola
/// constante para que no se separen nunca: las leen cuatro pantallas y la
/// bandeja, y añadir una sexta a un solo `select()` es exactamente el fallo que
/// dejó estos flags invisibles durante meses.
///
/// Sin espacios: se concatena dentro de un `select()` de PostgREST.
const requestRequirementCols =
    'with_shipping,with_installation,requires_evaluation,'
    'requires_fiscal_receipt,requires_state_supplier';

/// Los requisitos de un lote de solicitudes, por id.
///
/// Existe por la bandeja del proveedor: `get_provider_inbox_unified` tiene una
/// forma fija de trece columnas que no incluye ninguno de estos flags, y esa RPC
/// la comparte la web — extenderla obligaría a un DROP/CREATE con re-grants y
/// pondría en riesgo el inbox de los dos frentes a la vez. Sale más barato
/// pedirlos aparte: la llamada corre en la oleada B de `loadInboxData`, en
/// paralelo con los estados y los conteos, así que no cuesta latencia.
Future<Map<String, RequestRequirements>> requirementsForRequests(
  List<String> ids,
) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select('id,$requestRequirementCols')
        .inFilter('id', ids),
  );
  return {
    for (final r in rows) r['id'] as String: requirementsFromRow(r),
  };
}

Future<List<Map<String, dynamic>>> _fetchMyRequests() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select(
          'id,title,kind,status,is_wholesale,created_at,image_url,image_urls,'
          '$requestRequirementCols',
        )
        .eq('user_id', uid)
        // Las canceladas (soft-delete de "Eliminar") desaparecen del listado; la
        // fila sigue en la BD (auditable / no se borra un lead pagado).
        .neq('status', 'cancelled')
        .order('created_at', ascending: false),
  );
}

// `customer_id` tiene SELECT concedido a `authenticated` (comprobado en
// information_schema.column_privileges el 2026-09-04) y lo necesita
// `showOfferContactSheet` para resolver el nombre del cliente con
// `customerPublicProfile` — la vía que NO marca `whatsapp_revealed_at`.
// No hay fuga hacia el cliente: quien lee estas ofertas ES el customer_id.
const offerCols =
    'id,request_id,business_id,user_id,customer_id,price,price_min,price_max,'
    'pricing_mode,'
    'hourly_rate,estimated_hours,message,status,unlocked_at,created_at,'
    // Fotos de la oferta (marquesina en la hoja de detalle) + logística de
    // envío (para sumar al precio en el badge "Más económica").
    'image_urls,offers_shipping,shipping_price,'
    // Detalles estructurados que la hoja de la oferta muestra si existen
    // (pedido PO: color, tiempo de entrega, garantía, etc. — no solo el
    // mensaje compuesto).
    'offers_installation,installation_price,requires_evaluation,'
    'evaluation_price,availability_note,estimated_duration,product_brand,'
    'product_colors,product_warranty,delivery_time'
    // Capacidades declaradas al ofertar (foto del momento: su UPDATE está
    // denegado). Se traen aquí porque el listado (`offersForRequest`) es lo
    // que la próxima tanda usa para que el cliente vea lo que el negocio
    // declaró. El formulario de edición POR RUTA (`?edit=`, "Mis ofertas") usa
    // [offerForEdit], que hace un `select()` completo — pero desde "Ver mi
    // oferta" (pedido PO 2026-08-03) el prefill EN SITIO sí pasa por acá, vía
    // [myOfferForRequest]: `_prefillFromOffer` en `request_detail_screen.dart`
    // lee sus 21 claves y todas están cubiertas por esta constante.
    // MANTENIMIENTO: si recortas esta lista, revisa `_prefillFromOffer` — un
    // campo que falte aquí llegaría vacío al formulario en sitio y el
    // siguiente guardado lo escribiría en blanco encima de la columna real.
    ',has_fiscal_receipt,is_state_supplier,includes_materials';

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
  List<String> requestIds,
) async {
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
      r['request_id'] as String: (r['unlocked_at'] != null
          ? 'unlocked'
          : r['status'] as String),
  };
}

/// Fila COMPLETA de la oferta de este proveedor, indexada por `request_id`
/// (pedido PO 2026-09-04): la bandeja necesitaba el ESTADO
/// ([myOfferedRequestStatuses]) para el chip, pero el botón «Conversar · N
/// crédito(s)» que lo reemplaza en la tarjeta aceptada-y-sin-desbloquear
/// (`UnlockOfferButton`, `unlock_flow.dart`) necesita la oferta entera:
/// `estimatedUnlockCost` lee las columnas de precio y `startUnlockFlow`
/// necesita el `id`. Mismas columnas que ya lee "Mis ofertas" (`offerCols`,
/// el mismo `select()` de [offersForRequest]/[myOfferForRequest]): ya están
/// cubiertas por el grant de SELECT del dueño, así que no hay sorpresa de
/// 42501 aquí. Lectura aparte y best-effort en quien llama (mismo patrón que
/// [myOfferedRequestStatuses]): no se mete en `offerCols` de golpe para no
/// pedir de más cuando solo hace falta el estado.
Future<Map<String, Map<String, dynamic>>> myOfferedOffersByRequest(
  List<String> requestIds,
) async {
  if (requestIds.isEmpty) return {};
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select(offerCols)
        .eq('user_id', uid)
        .inFilter('request_id', requestIds),
  );
  return {for (final r in rows) r['request_id'] as String: r};
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
    await supa.rpc(
      'offer_counts_for_requests',
      params: {'p_request_ids': requestIds},
    ),
  );
  return {
    for (final r in rows)
      r['request_id'] as String: (r['offer_count'] as num).toInt(),
  };
}

/// Solicitudes ABIERTAS (de otros) a las que este proveedor ya ofertó — para
/// que una oferta hecha en OTRO rubro también aparezca en "Para ti" (pedido
/// PO: "si alguien ofertó en otro rubro, esa oferta pasa a Para ti").
/// A propósito NO trae las cinco columnas de requisitos que sí tiene
/// [allOpenRequests]: estas filas solo se mezclan en la bandeja del proveedor
/// (`loadInboxData`), donde la oleada B las completa vía `fetchRequirements`
/// igual que al resto de la lista.
Future<List<Map<String, dynamic>>> myOfferedOpenRequests({String? kind}) async {
  final uid = supa.auth.currentUser!.id;
  final offers = List<Map<String, dynamic>>.from(
    await supa.from('provider_offers').select('request_id').eq('user_id', uid),
  );
  final ids = {for (final o in offers) o['request_id'] as String}.toList();
  if (ids.isEmpty) return [];
  var q = supa
      .from('customer_requests')
      .select(
        'id,title,description,kind,urgency,zone,is_wholesale,created_at,image_url',
      )
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
  String requestId,
  String businessId,
) async {
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

OfferLite offerLite(Map<String, dynamic> o, {ClosedReason? closedReason}) =>
    OfferLite(
      status: o['status'] as String,
      unlockedAt: o['unlocked_at'] == null
          ? null
          : DateTime.parse(o['unlocked_at'] as String),
      closedReason: closedReason,
    );

/// Razón de cierre por id de oferta, para las ofertas cuya CONVERSACIÓN ya
/// está cerrada (a mano, "no concretado" o el cron de inactividad). Es el
/// dato con el que la lista distingue un trato muerto de uno vivo, y CÓMO
/// murió: `conversations.status = 'perdido'` es "no concretada" (alguien lo
/// decidió); cualquier otro valor con `closed_at` puesto es el cron de
/// inactividad.
///
/// Best-effort, como `_fetchUnseenRequests`: si la consulta falla, la lista se
/// pinta sin la fase "Cerrada" en vez de romperse.
Future<Map<String, ClosedReason>> closedConversationReasons(
    List<String> offerIds) async {
  if (offerIds.isEmpty) return {};
  try {
    final rows = List<Map<String, dynamic>>.from(
      await supa
          .from('conversations')
          .select('source_id,status')
          .eq('kind', 'offer')
          .inFilter('source_id', offerIds)
          .not('closed_at', 'is', null),
    );
    return {
      for (final r in rows)
        if (r['source_id'] != null)
          r['source_id'] as String: r['status'] == 'perdido'
              ? ClosedReason.notAgreed
              : ClosedReason.inactivity,
    };
  } catch (_) {
    return {};
  }
}

/// Nombres visibles de rubros por id (para el paso "rubros sugeridos" del
/// formulario final de crear solicitud).
Future<Map<String, String>> rubroNames(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.from('rubros').select('id,name').inFilter('id', ids),
  );
  return {for (final r in rows) r['id'] as String: r['name'] as String};
}

final _reqIdRng = Random.secure();

/// UUID v4 para el token de idempotencia de una solicitud. Se genera UNA vez al
/// abrir el compositor y se reusa en todos los reintentos, para que un ack de red
/// perdido no cree una solicitud duplicada (lo valida el índice parcial
/// `uq_customer_requests_client_idempotency`). Sin dependencia nueva: `dart:math`
/// (ya importado). RFC 4122 v4 (bits de versión/variante fijados).
String newRequestClientId() {
  final b = List<int>.generate(16, (_) => _reqIdRng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante 10xx
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).toList();
  return '${h[0]}${h[1]}${h[2]}${h[3]}-${h[4]}${h[5]}-${h[6]}${h[7]}-'
      '${h[8]}${h[9]}-${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
}

/// Insert de solicitud — campos y gates EXACTOS del form final de la web
/// (requests/new.tsx `submit()` L586-608). Lo del turno `routing` viaja en
/// `categories`/`rubros`; el resto viene del FORMULARIO final:
/// - `condition` 'nuevo'|'usado'|'ambos'|'' (vacío en servicios);
/// - `withShipping`/`withInstallation` solo aplican a producto;
/// - `requiresEvaluation` aplica a ambos (la web no lo capa por kind);
/// - `urgency` = string de URGENCY_OPTIONS (producto);
/// - `serviceModality`/`urgencyLevel`/`serviceEventDate` solo servicios.
/// Devuelve el `id` de la fila creada (la política «Requests: select» del
/// dueño permite el `.select('id')` del insert), o `null` en el reintento
/// 23505 — ahí la solicitud ya existe pero no se vuelve a leer. El id lo usa
/// la transcripción (fase 0, best-effort); sin id no hay transcripción.
Future<String?> submitRequest({
  required String title,
  required List<String> bullets,
  required String kind, // 'producto' | 'servicio'
  required bool wholesale,
  required List<String> categories,
  required List<String> rubros,
  // Token de idempotencia generado por la app al ABRIR el compositor y reusado
  // en cada reintento (ver `newRequestClientId` y create_request_screen). El
  // índice parcial `uq_customer_requests_client_idempotency` rechaza el 2º INSERT
  // con el mismo token → sin solicitud duplicada ni doble fan-out de push.
  required String clientRequestId,
  List<String> imageUrls = const [],
  String condition = '',
  String urgency = 'Normal - 24 horas',
  bool withShipping = false,
  bool withInstallation = false,
  bool requiresEvaluation = false,
  // Requisitos transversales (aplican a producto Y servicio, pedido PO
  // 2026-07-22): comprobante fiscal (NCF) y suplidor del Estado.
  bool requiresFiscalReceipt = false,
  bool requiresStateSupplier = false,
  String serviceModality = '',
  String urgencyLevel = '',
  DateTime? serviceEventDate,
  // Frecuencia del servicio (opción del formulario, NUNCA pregunta de la IA —
  // decisión PO 2026-08-12). Vacío = "Una sola vez". Va a la pareja de columnas
  // que ya existía: `is_recurring` + `recurrence_note` (paridad web
  // src/lib/serviceFrequency.ts).
  String serviceFrequency = '',
  // Presupuesto estimado del cliente (opcional, solo servicios — paridad web
  // requests/new.tsx). Se guarda solo si es > 0.
  num? budgetMin,
  num? budgetMax,
  // Detalles de mayoreo (obligatorios en el form final cuando wholesale=true
  // y kind='producto'; paridad web requests/new.tsx). NULL en cualquier otro
  // caso — la restricción CHECK en la BD exige justo esto.
  int? wholesaleQuantity,
  String? wholesaleSplit,
  String? wholesalePackaging,
  String? wholesaleNote,
}) async {
  final uid = supa.auth.currentUser!.id;
  final isService = kind == 'servicio';
  // Ubicación de la solicitud: se COPIA del perfil (no se referencia) para que
  // el trabajo siga diciendo dónde era aunque el cliente se mude — mismo
  // criterio que la web (requests/new.tsx). Un fallo aquí no cancela el envío:
  // una solicitud sin ubicación sigue siendo útil (fail-open, igual que las
  // otras 4 lecturas best-effort de este archivo, p.ej. closedConversationReasons).
  //
  // A DIFERENCIA de esas 4, aquí SÍ se reporta el error (`reportError`, no
  // relanza ni bloquea el insert). Esas otras cubren datos de presentación:
  // si fallan, la pantalla queda un poco más pobre y se nota. Esta lectura
  // alimenta justo el dato que esta tarea existe para arreglar — si se
  // rompe en silencio (RLS, esquema, lo que sea), el síntoma es IDÉNTICO al
  // bug original: 100% de las solicitudes del APK nacen sin ubicación, sin
  // que nadie se entere. Mismo criterio que requests/new.tsx en la web.
  Map<String, dynamic>? prof;
  try {
    prof = await supa
        .from('profiles')
        .select('city,sector,lat,lng')
        .eq('user_id', uid)
        .maybeSingle();
  } catch (e, s) {
    prof = null;
    unawaited(reportError(e, s));
  }
  String? id;
  try {
    final row = await supa.from('customer_requests').insert({
      'user_id': uid,
      'city': prof?['city'] ?? '',
      'sector': prof?['sector'] ?? '',
      'lat': prof?['lat'],
      'lng': prof?['lng'],
      'client_request_id': clientRequestId,
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
      'requires_fiscal_receipt': requiresFiscalReceipt,
      'requires_state_supplier': requiresStateSupplier,
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
      'budget_min': isService && budgetMin != null && budgetMin > 0
          ? budgetMin
          : null,
      'budget_max': isService && budgetMax != null && budgetMax > 0
          ? budgetMax
          : null,
      'is_recurring': isService && serviceFrequency.trim().isNotEmpty,
      'recurrence_note': isService ? serviceFrequency.trim() : '',
      'is_wholesale': !isService && wholesale,
      'wholesale_quantity': (!isService && wholesale)
          ? wholesaleQuantity
          : null,
      'wholesale_split': (!isService && wholesale) ? wholesaleSplit : null,
      'wholesale_packaging': (!isService && wholesale)
          ? wholesalePackaging
          : null,
      'wholesale_note': (!isService && wholesale) ? wholesaleNote : null,
      'target_business_id': null,
    }).select('id').single();
    id = row['id'] as String?;
  } on PostgrestException catch (e) {
    // 23505 = choque con `uq_customer_requests_client_idempotency`: el primer
    // intento SÍ creó la solicitud y su ack de red se perdió; este es el
    // reintento con el MISMO token. Idempotente: no es error — la solicitud ya
    // existe, así que se trata como éxito (no se re-inserta, no se re-dispara el
    // fan-out de notificaciones a proveedores). Sin id: no se hace un select
    // por `client_request_id` (grant de columna no verificado; la memoria del
    // proyecto manda mirar `column_privileges` antes de un `.select()`).
    if (e.code != '23505') rethrow;
  }
  AppCaches.invalidateRequestLists();
  requestsChanged.value++;
  return id;
}

/// Cancela (retira) una solicitud del marketplace. La regla dura la impone la
/// RPC `cancel_customer_request` (SECURITY DEFINER, migración 20260717120000),
/// NO el cliente: solo el dueño, solo si está `open`, y NUNCA si un proveedor
/// ya pagó por desbloquear el contacto — en ese caso la RPC lanza
/// `unlocked_offer_exists` (el llamador lo detecta en el mensaje del error).
Future<void> cancelCustomerRequest(String requestId) async {
  await supa.rpc('cancel_customer_request', params: {'_request_id': requestId});
  AppCaches.invalidateRequestLists();
  requestsChanged.value++;
}

Future<bool> acceptOffer({required String offerId}) async {
  // Tope de 3 finalistas ATÓMICO server-side (RPC en prod). Reemplaza el UPDATE
  // directo. La RPC valida dueño, idempotencia, solicitud abierta y el cap; el
  // caller envuelve en catchError, así que una excepción (p.ej. "ya tiene 3
  // finalistas") cae al mensaje genérico "esta oferta ya no está disponible".
  final res = await supa.rpc('accept_offer', params: {'_offer_id': offerId});
  // Aceptar mueve las DOS listas: la solicitud del cliente gana un finalista y
  // la oferta del proveedor pasa a 'accepted'. Se invalida aunque la RPC diga
  // que no (idempotencia, o cupo lleno): en ese caso el estado real tampoco es
  // el que la lista tiene guardado.
  AppCaches.invalidateRequestLists();
  return res is Map && res['ok'] == true;
}

Future<void> rejectOffer({
  required String offerId,
  required String reason,
}) async {
  await supa
      .from('provider_offers')
      .update({'status': 'rejected', 'rejection_reason': reason})
      .eq('id', offerId);
  AppCaches.invalidateRequestLists();
}

Future<void> submitReview({
  required String businessId,
  required int rating,
  String comment = '',
}) async {
  // upsert (no insert): una reseña VIGENTE por (negocio, reseñador). Re-reseñar
  // EDITA la existente en vez de acumular filas que sesgarían el promedio de
  // reputación (`get_business_ratings`), apoyado en el índice UNIQUE
  // `uq_business_reviews_one_per_reviewer` (migración 20260722180100, ya en
  // prod). La escribe la web (detalle de solicitud) y, desde 2026-07-31,
  // también la app: el chat y el detalle de solicitud completada.
  await supa.from('business_reviews').upsert({
    'business_id': businessId,
    'reviewer_id': supa.auth.currentUser!.id,
    'rating': rating,
    'comment': comment,
  }, onConflict: 'business_id,reviewer_id');
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
      'id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at,image_url,image_urls,budget_min,budget_max,wholesale_quantity,wholesale_split,wholesale_packaging,wholesale_note,offers_count,accepted_offers_count'
      // target_categories: decide si la oferta pregunta por los materiales
      // (un abogado no los tiene) — ver `domain/offer_materials.dart`.
      ',target_categories'
      // updated_at: el detalle lo guarda como "version vista" para el badge de
      // la bandeja (ver `features/provider/opened_requests.dart`).
      ',updated_at'
      ',$requestRequirementCols',
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

/// El negocio con el que se oferta, **y** las capacidades que tiene declaradas.
///
/// Existe aparte de [myBusinessId] a propósito: esa la llaman también el estado
/// de sesión, el chat y ajustes, que solo necesitan el id y no deben pagar
/// columnas de más.
///
/// El proveedor declara estas capacidades en la WEB (en la app "Mi tienda" es
/// solo lectura y editar va por magic link). Aquí solo se leen, para premarcar
/// las casillas de la oferta.
Future<({String id, bool hasFiscalReceipt, bool isStateSupplier})?>
myBusinessForOffer() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_businesses')
      .select('id,has_fiscal_receipt,is_state_supplier')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (row == null) return null;
  return (
    id: row['id'] as String,
    hasFiscalReceipt: row['has_fiscal_receipt'] == true,
    isStateSupplier: row['is_state_supplier'] == true,
  );
}

/// Ofertar es GRATIS. Campos idénticos al insert de la web
/// (RequestRespondSection.tsx L940-954, camino precio fijo/rango).
/// Campos compartidos entre CREAR ([makeOffer]) y EDITAR ([updateOffer]) una
/// oferta. Aísla la forma del payload en un solo lugar para no duplicar la
/// regla de "guardar el costo solo si el toggle está activo Y > 0 (0 = gratis)"
/// ni la de "por hora solo aplica en ese modo".
///
/// Todo campo de texto que entre a este mapa queda cubierto AUTOMÁTICAMENTE por
/// el barrido anti-elusión de [makeOffer]/[updateOffer] (`payloadHasContactInfo`,
/// espejo del de la web): no hay lista de campos que mantener a mano.
///
/// ⚠️ **Este mapa lo comparten CREAR y EDITAR, y eso restringe qué puede
/// llevar.** `provider_offers` tiene el `UPDATE` de `has_fiscal_receipt` e
/// `is_state_supplier` DENEGADO a propósito (son una foto de lo que el negocio
/// declaraba al ofertar). Si esas dos columnas entraran aquí, el `UPDATE` las
/// incluiría, PostgREST tumbaría la fila ENTERA por falta de permiso y
/// "mejorar oferta" dejaría de funcionar del todo. Van solo en el `insert` de
/// [makeOffer]. Lo vigila un test en `repos_test.dart`.
///
/// Es público solo para que ese test pueda mirar dentro; no lo llames desde
/// una pantalla.
@visibleForTesting
Map<String, dynamic> offerFields({
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
  // Tres estados: true incluye, false no incluye, null no aplica u oferta vieja.
  // Va en offerFields (no aparte como has_fiscal_receipt) porque su UPDATE SÍ
  // está permitido: la migración 20260817160000 la metió en las DOS listas
  // blancas, de INSERT y de UPDATE, justo para que "mejorar oferta" pueda tocarla.
  bool? includesMaterials,
}) => {
  'price': price,
  'price_min': priceMin,
  'price_max': priceMax,
  'message': message,
  'image_urls': imageUrls,
  // Logística de producto (paridad web RequestRespondSection.tsx:952-957): el
  // precio solo se guarda si el toggle está activo Y el costo > 0 (0 = gratis).
  'offers_shipping': offersShipping,
  'shipping_price': offersShipping && (shippingPrice ?? 0) > 0
      ? shippingPrice
      : null,
  'offers_installation': offersInstallation,
  'installation_price': offersInstallation && (installationPrice ?? 0) > 0
      ? installationPrice
      : null,
  'requires_evaluation': requiresEvaluation,
  'evaluation_price': requiresEvaluation && (evaluationPrice ?? 0) > 0
      ? evaluationPrice
      : null,
  'pricing_mode': pricingMode,
  // Por hora (servicio): tarifa + horas solo aplican en ese modo.
  'hourly_rate': pricingMode == 'hourly' ? hourlyRate : null,
  'estimated_hours': pricingMode == 'hourly' ? estimatedHours : null,
  'availability_note': availabilityNote,
  'estimated_duration': estimatedDuration,
  // Detalles del producto (paridad web): solo se guardan si vienen.
  'product_brand': productBrand.trim().isEmpty ? null : productBrand.trim(),
  'product_colors': productColors.isEmpty ? null : productColors,
  'product_warranty': productWarranty.trim().isEmpty
      ? null
      : productWarranty.trim(),
  'delivery_time': deliveryTime.trim().isEmpty ? null : deliveryTime.trim(),
  'includes_materials': includesMaterials,
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
  // Capacidades declaradas para ESTA oferta. Van aquí y NO en `offerFields`
  // porque su UPDATE está denegado: ver la advertencia de ese mapa.
  bool hasFiscalReceipt = false,
  bool isStateSupplier = false,
  bool? includesMaterials,
}) async {
  final uid = supa.auth.currentUser!.id;
  final fields = offerFields(
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
    includesMaterials: includesMaterials,
  );
  // Red de seguridad anti-elusión: barre el payload ENTERO en vez de confiar en
  // la lista de campos que la pantalla revisa a mano antes de subir fotos. Así
  // una columna vigilada nueva no puede quedarse sin cobertura por olvido. El
  // JY422 del trigger sigue siendo la autoridad; esto solo evita el viaje.
  if (payloadHasContactInfo(fields)) {
    throw PostgrestException(message: contactInfoMessage, code: contactInfoCode);
  }
  try {
    await supa.from('provider_offers').insert({
      'user_id': uid,
      'business_id': businessId,
      'request_id': request['id'],
      'request_title': request['title'],
      'status': 'pending',
      'has_fiscal_receipt': hasFiscalReceipt,
      'is_state_supplier': isStateSupplier,
      ...fields,
    });
  } on PostgrestException catch (e) {
    // 23505 = choque con el índice UNIQUE parcial
    // `uq_provider_offers_active_per_request_user`: el proveedor YA tiene una
    // oferta VIVA en esta solicitud (reintento tras un ack de red perdido o
    // doble envío). Idempotente: no es error — la oferta ya existe, se retorna
    // en silencio para que la UI muestre éxito, no un fallo.
    if (e.code == '23505') return;
    rethrow;
  } finally {
    // También en el camino idempotente del 23505: si la oferta ya existía, la
    // lista guardada tampoco la tiene.
    AppCaches.invalidateRequestLists();
  }
}

/// Edita una oferta PENDIENTE propia (RLS: dueño). No toca
/// request_id/business_id/status; misma forma de payload que [makeOffer].
/// Devuelve el mapa que REALMENTE quedó escrito, para quien necesite refrescar
/// su copia de la oferta sin releerla del servidor (el detalle de solicitud, al
/// editar EN SITIO, se queda en pantalla). Recomponerlo a mano divergía: aquí
/// abajo [offerFields] anula el costo de envío/instalación/evaluación si su
/// toggle está apagado, y los detalles de producto vacíos los guarda como
/// `null`, no como `''`.
Future<Map<String, dynamic>> updateOffer({
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
  bool? includesMaterials,
}) async {
  final fields = offerFields(
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
    includesMaterials: includesMaterials,
  );
  // Misma red de seguridad que en [makeOffer]: barrido del payload entero.
  if (payloadHasContactInfo(fields)) {
    throw PostgrestException(message: contactInfoMessage, code: contactInfoCode);
  }
  await supa.from('provider_offers').update(fields).eq('id', offerId);
  AppCaches.invalidateRequestLists();
  return fields;
}

/// Fila COMPLETA de una oferta propia (todas las columnas) para prefijar el
/// formulario de edición POR RUTA (`?edit=`, desde "Mis ofertas"). No es la
/// única fuente para el prefill: la edición EN SITIO ("Ver mi oferta", pedido
/// PO 2026-08-03) prefija desde [myOfferForRequest] (`offerCols`), que sí trae
/// los detalles de producto — ver el comentario de `offerCols` arriba.
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

/// Mis ofertas, amortiguadas (ver [myRequests] para el porqué). No avisa por
/// `requestsChanged`: esa pantalla no lo escucha, y su propio pull-to-refresh
/// más el `onResume` del shell ya cubren el caso de datos viejos.
Future<List<Map<String, dynamic>>> myOffers() => AppCaches.myOffers.readFresh(
      _fetchMyOffers,
      equals: AppCaches.sameRows,
    );

Future<List<Map<String, dynamic>>> _fetchMyOffers() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(
    await supa
        .from('provider_offers')
        .select(
          '$offerCols,request_title,points_charged,purchase_completed',
        )
        .eq('user_id', uid)
        .order('created_at', ascending: false),
  );
}

/// Saldo en puntos. Cacheado 60 s (paridad con el `staleTime` del Navbar de la
/// web) — era la query más llamada del backend porque cada pantalla que muestra
/// el saldo lo pedía al montar. Se invalida solo en los tres momentos en que
/// puede haber cambiado: un desbloqueo (lo SIEMBRA con el saldo que devuelve la
/// RPC), volver del background (pudo comprar créditos) y cerrar sesión.
Future<int?> walletBalance() => AppCaches.wallet.read(() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_wallets')
      .select('balance')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['balance'] as int?;
});

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
  final newBalance = (res['new_balance'] as num?)?.toInt();
  _syncWalletCache(newBalance);
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: newBalance,
  );
}

/// Tras cobrar, el saldo cacheado quedó viejo. Si la RPC devolvió el nuevo se
/// SIEMBRA (el número baja al instante, sin un viaje extra a la red); si no lo
/// devolvió, se invalida para que la próxima lectura vaya a la fuente. Nunca se
/// deja el valor anterior: un saldo inflado le haría creer al proveedor que
/// puede pagar otro desbloqueo.
void _syncWalletCache(int? newBalance) {
  if (newBalance != null) {
    AppCaches.wallet.set(newBalance);
  } else {
    AppCaches.wallet.clear();
  }
  onWalletBalanceChanged?.call(newBalance);
}

/// Hueco para avisar de que el saldo cambió; lo rellena el contador de las
/// cabeceras (`saldoStore`). Vive aquí como función suelta a propósito: la capa
/// de datos avisa, pero no conoce a la UI ni la importa.
///
/// `null` = "cambió y no sé a cuánto" (la RPC no devolvió el saldo): quien
/// escuche tiene que ir a releerlo, nunca quedarse con el número viejo.
void Function(int? nuevoSaldo)? onWalletBalanceChanged;

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
  final newBalance = (res['new_balance'] as num?)?.toInt();
  _syncWalletCache(newBalance);
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: newBalance,
  );
}

/// `customer_id` de un interés — quién tocó "Me interesa".
///
/// La RPC del inbox (`get_provider_inbox_unified`) NO lo devuelve, pero el
/// proveedor sí puede leerlo de la tabla: la política de SELECT admite
/// `auth.uid() = provider_user_id` y `customer_id` está en el grant por
/// columna. Con él se pinta la MISMA ficha de cliente que el detalle de
/// solicitud (alias anónimo + reputación + sellos) — sin exponer contacto:
/// nombre y teléfono siguen saliendo solo de
/// `get_unlocked_product_interest_contact`, tras pagar.
Future<String?> productInterestCustomerId(String interestId) async {
  final row = await supa
      .from('product_interests')
      .select('customer_id')
      .eq('id', interestId)
      .maybeSingle();
  return row?['customer_id'] as String?;
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

/// Cacheado 5 min (paridad con `useIsProvider` en la web). El rol de una cuenta
/// no cambia dentro de una sesión salvo en el propio onboarding, que invalida.
Future<bool> isProviderAccount() => AppCaches.isProvider.read(() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supa
      .from('profiles')
      .select('account_type')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['account_type'] == 'provider';
});

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
      .update({'whatsapp_reveal_enabled': enabled})
      .eq('user_id', uid);
}

/// ¿El CLIENTE aceptó que lo contacten por WhatsApp?
///
/// Lee `profiles.whatsapp_reveal_enabled` de OTRO usuario. Lo permite la
/// política `Profiles: select`, que además del dueño y de los admin admite al
/// proveedor con un `product_interests` desbloqueado de ese cliente; la
/// columna tiene SELECT concedido a `authenticated` (ambas cosas comprobadas
/// contra prod el 2026-09-04). Fuera de ese caso la fila simplemente no llega
/// y se devuelve `false` — default seguro, igual que la columna.
///
/// ⚠️ Es una reja de UI, NO del servidor:
/// `get_unlocked_product_interest_contact` sigue devolviendo el teléfono sin
/// mirar esta bandera. Apretarla es un ticket con migración propia (ver §9 del
/// spec 2026-09-04); no se hace desde el cliente.
Future<bool> customerWhatsappRevealEnabled(String customerId) async {
  final row = await supa
      .from('profiles')
      .select('whatsapp_reveal_enabled')
      .eq('user_id', customerId)
      .maybeSingle();
  return row?['whatsapp_reveal_enabled'] as bool? ?? false;
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
  current[provider ? 'provider' : 'customer'] = items
      .map((e) => e.toJson())
      .toList();
  await supa
      .from('profiles')
      .update({'custom_quick_replies': current})
      .eq('user_id', uid);
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
/// Cacheado 5 min (paridad con `useIsAdmin` en la web). Es un gate de UI: quien
/// de verdad impide el acceso es la RLS sobre `user_roles` y el `assertAdmin`
/// del servidor, así que cachearlo no abre nada.
Future<bool> isAdmin() => AppCaches.isAdmin.read(() async {
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
});

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
    await supa.functions.invoke(
      'admin-invite-provider',
      body: {
        'email': email,
        'businessName': businessName,
        'whatsapp': whatsapp,
        'city': city,
      },
    );
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
  // Opcionales con default '': no rompen a los llamadores actuales. Una
  // tarea posterior los cablea desde el onboarding con datos estructurados.
  String city = '',
  String sector = '',
  String street = '',
  String streetNumber = '',
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
    'city': city.isEmpty ? null : city,
    'sector': sector.isEmpty ? null : sector,
    'street': street.isEmpty ? null : street,
    'street_number': streetNumber.isEmpty ? null : streetNumber,
    // '?lat'/'?lng' (patrón de updateMyAddress, más abajo en este fichero):
    // si el usuario no dio permiso de GPS, lat/lng llegan null y la clave se
    // omite del upsert — sin esto se machacaba con NULL cualquier coordenada
    // que el perfil ya tuviera. location_captured_at solo se sella si AMBAS
    // coordenadas llegaron.
    'lat': ?lat,
    'lng': ?lng,
    if (lat != null && lng != null)
      'location_captured_at': DateTime.now().toIso8601String(),
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
  // La cuenta ACABA de volverse proveedor: el `false` cacheado por
  // `isProviderAccount` mandaría al usuario recién registrado a la UI de
  // cliente durante los próximos 5 minutos.
  AppCaches.isProvider.set(true);
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
      await supa.rpc(
            'create_provider_rubro',
            params: {'_category_id': categoryId, '_name': name},
          )
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
  await supa.storage
      .from('business-id-docs')
      .upload(
        path,
        File(filePath),
        fileOptions: FileOptions(
          upsert: true,
          contentType: _imageContentType(ext),
        ),
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
      .update({'rnc': rnc})
      .eq('id', businessId);
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

/// Paquetes activos con producto de Play. Los créditos SIEMPRE vienen de aquí
/// (la consola de Play solo aporta el precio localizado).
///
/// `credit_packages` tiene GRANT SELECT para `authenticated` y política
/// USING (true), así que se lee directo sin RPC.
Future<List<ShopPackage>> activeCreditPackages() async {
  final rows = await supa
      .from('credit_packages')
      .select('id, points, price_usd, label, play_product_id')
      .eq('is_active', true)
      .not('play_product_id', 'is', null)
      .order('sort_order');
  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map((r) => ShopPackage(
            id: r['id'] as String,
            points: (r['points'] as num).toInt(),
            priceUSD: (r['price_usd'] as num).toDouble(),
            label: r['label'] as String?,
            playProductId: r['play_product_id'] as String?,
          ))
      .toList();
}

/// Chequeo liviano PRE-cobro (paridad web ProviderOffersSection.tsx:670):
/// nunca desbloquear si el contacto no es revelable.
Future<bool> canRevealOffer(String offerId) async =>
    await supa.rpc(
      'can_reveal_offer_whatsapp',
      params: {'_offer_id': offerId},
    ) ==
    true;

/// Los rubros que puede elegir a mano una solicitud de [kind].
///
/// La MISMA reja que el clasificador del servidor (`filterRubrosByKind` en
/// jayalo-main): sin ella el picker de una solicitud de producto seguía
/// ofreciendo «Vibe coding» y «Ciberseguridad» aunque la IA ya no pudiera
/// elegirlos. `ambos` entra en los dos lados a propósito (un aire se vende y
/// se instala); sin [kind] no se filtra, porque no hay señal con la que decidir.
Future<List<Map<String, dynamic>>> rubrosForCategories(
  List<String> categoryIds, {
  String? kind,
}) async {
  final kinds = kind == null
      ? const ['producto', 'servicio', 'ambos']
      : [kind, 'ambos'];
  return List<Map<String, dynamic>>.from(
    await supa
        .from('rubros')
        .select('id,name,category_id')
        .inFilter('category_id', categoryIds)
        .inFilter('kind', kinds)
        .order('name'),
  );
}

/// El catálogo CERRADO de profesiones, entero y en alfabético.
///
/// Sin filtrar por categoría a propósito (PO 2026-08-20): es un selector de
/// profesiones, no un derivado de lo que vendes. `oficio_categories` sigue
/// existiendo para el ruteo de solicitudes; aquí no pinta nada.
Future<List<Map<String, dynamic>>> fetchOficios() async =>
    List<Map<String, dynamic>>.from(
      await supa.from('oficios').select('slug,name').order('name'),
    );

/// Declara los oficios de un negocio. Reemplaza la lista entera.
///
/// Va por RPC y no por un INSERT directo porque `authenticated` NO tiene GRANT
/// de INSERT sobre `provider_business_oficios` — su política RLS de inserción
/// es inalcanzable, hallazgo de 2026-08-20. La RPC (SECURITY DEFINER) valida
/// dueño, tope de 4 y que cada slug exista; lanza `not_owner`,
/// `demasiados_oficios` u `oficio_desconocido`.
Future<int> setBusinessOficios(String businessId, List<String> slugs) async {
  final n = await supa.rpc(
    'set_business_oficios',
    params: {'_business_id': businessId, '_slugs': slugs},
  );
  return (n as num).toInt();
}

Future<String?> uploadBusinessLogo(String filePath) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext = dot == -1 ? 'jpg' : filePath.substring(dot + 1).toLowerCase();
  final path = '$uid/logo-${DateTime.now().millisecondsSinceEpoch}.jpg';
  await supa.storage
      .from('business-logos')
      .upload(
        path,
        File(filePath),
        // Sin `contentType` el cliente lo deduce de la ruta LOCAL y manda
        // `application/octet-stream` cuando no reconoce la extension. Los
        // buckets llevan lista blanca de MIME, asi que eso seria un rechazo.
        fileOptions: FileOptions(contentType: _imageContentType(ext)),
      );
  return supa.storage.from('business-logos').getPublicUrl(path);
}

// ── Identidad del negocio editable desde la app (logo/portada/descripción/
// chips de servicios) ───────────────────────────────────────────────────────

/// Ruta de imagen de negocio. Espeja la web (`uploadCover` en
/// `business.$id.tsx`): la RLS del bucket exige primera carpeta = auth.uid().
String businessImagePath({
  required String uid,
  required String businessId,
  required String kind,
  required String ext,
  required int ts,
}) => '$uid/$kind/$businessId-$ts.$ext';

Future<String> _uploadBusinessImage(
  String businessId,
  String filePath,
  String kind,
  String column,
) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext = (dot == -1 ? 'jpg' : filePath.substring(dot + 1).toLowerCase());
  final path = businessImagePath(
    uid: uid,
    businessId: businessId,
    kind: kind,
    ext: ext,
    ts: DateTime.now().millisecondsSinceEpoch,
  );
  await supa.storage
      .from('business-logos')
      .upload(
        path,
        File(filePath),
        fileOptions: FileOptions(
          upsert: true,
          contentType: _imageContentType(ext),
        ),
      );
  final url = supa.storage.from('business-logos').getPublicUrl(path);
  await supa
      .from('provider_businesses')
      .update({column: url})
      .eq('id', businessId);
  return url;
}

Future<String> updateBusinessLogo(String businessId, String filePath) =>
    _uploadBusinessImage(businessId, filePath, 'logos', 'logo_url');
Future<String> updateBusinessCover(String businessId, String filePath) =>
    _uploadBusinessImage(businessId, filePath, 'covers', 'cover_url');

// `logo_url` es NOT NULL en prod (un UPDATE con null revienta 23502); '' es el estado histórico "sin logo" y tanto `myBusinessProfile` como `BusinessCoverHero` ya lo tratan como ausente.
Future<void> clearBusinessLogo(String businessId) async => supa
    .from('provider_businesses')
    .update({'logo_url': ''})
    .eq('id', businessId);
Future<void> clearBusinessCover(String businessId) async => supa
    .from('provider_businesses')
    .update({'cover_url': null})
    .eq('id', businessId);

Future<void> updateBusinessDescription(
  String businessId,
  String description,
) async => supa
    .from('provider_businesses')
    .update({'description': description.trim()})
    .eq('id', businessId);

Future<void> updateBusinessServices(
  String businessId,
  List<String> services,
) async => supa
    .from('provider_businesses')
    .update({'services': services})
    .eq('id', businessId);

/// Sube la foto de perfil (bucket público `business-logos`, misma ruta que la
/// web: `{uid}/avatar-{ts}.{ext}`) y actualiza `profiles.avatar_url`. Devuelve
/// la URL pública (pedido PO 2026-07-22: foto editable en el menú lateral).
Future<String> updateMyAvatar(String filePath) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext = dot == -1 ? 'jpg' : filePath.substring(dot + 1).toLowerCase();
  final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
  await supa.storage
      .from('business-logos')
      .upload(
        path,
        File(filePath),
        // Mismo motivo que en `uploadBusinessLogo`: el MIME se declara, no se
        // adivina desde la extension del fichero temporal.
        fileOptions: FileOptions(
          upsert: true,
          contentType: _imageContentType(ext),
        ),
      );
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

Future<String> _uploadMarketplaceImage(
  String filePath,
  String kind, {
  // Bucket destino. Todas las fotos del marketplace comparten el bucket
  // público `business-logos` — [uploadPackageImage] (Task 7) es la primera
  // excepción, porque la web ya sube los paquetes a `provider-products`
  // (`PackageEditorDialog.tsx:123`) y no hay motivo para abrir un bucket
  // nuevo cuando ese ya existe y es público.
  String bucket = 'business-logos',
}) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext =
      (dot == -1 ? '' : filePath.substring(dot + 1).toLowerCase()).isEmpty
      ? 'jpg'
      : filePath.substring(dot + 1).toLowerCase();
  final rand = _rand.nextInt(1 << 31).toRadixString(16);
  final path = '$uid/$kind/${DateTime.now().millisecondsSinceEpoch}-$rand.$ext';
  await supa.storage
      .from(bucket)
      .upload(
        path,
        File(filePath),
        fileOptions: FileOptions(contentType: _imageContentType(ext)),
      );
  return supa.storage.from(bucket).getPublicUrl(path);
}

String _imageContentType(String ext) => switch (ext) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

// ── Chat (spec 2026-07-17-chat-app-design.md) ───────────────────────────────

const chatMsgCols = 'id,sender_id,kind,body,created_at';

/// La lista de chats, amortiguada (ver [myRequests] para el porqué).
///
/// Ojo con el TTL corto: acá `sameRows` compara por `id`/`updated_at`/`status`,
/// pero lo que de verdad cambia en esta lista es `last_message_at` y el conteo
/// de no leídos. Se deja así a propósito — el badge de Mensajes tiene su propio
/// store en vivo y el chat trae realtime, así que la lista no es la fuente por
/// la que el usuario se entera de un mensaje nuevo.
Future<List<Map<String, dynamic>>> conversationsList() =>
    AppCaches.conversations.readFresh(
      _fetchConversationsList,
      equals: AppCaches.sameRows,
    );

Future<List<Map<String, dynamic>>> _fetchConversationsList() async =>
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

/// Marca la conversación como NO CONCRETADA (`perdido`). Irreversible.
///
/// Invalida la caché de la lista: hasta la revisión final (2026-08-01) no lo
/// hacía, y no le hacía falta porque solo se llamaba desde el chat, cuyo
/// `_reload()` va por `fetchConversation()` (consulta directa, sin caché).
/// Desde que la lista de chats ofrece la acción por swipe, sin esto
/// `readFresh` devolvía la entrada cacheada (TTL 20 s) y la fila se quedaba en
/// "Abierto": el usuario confirmaba un diálogo que le advierte de que es
/// IRREVERSIBLE y no veía cambiar nada. `setConversationArchived` ya lo hacía;
/// la asimetría era el olvido.
Future<void> markConversationLost(String convId) async {
  await supa.from('conversations').update({'status': 'perdido'}).eq('id', convId);
  AppCaches.conversations.clear();
}

/// Archiva/desarchiva la conversación por MI lado. La otra columna es del otro
/// participante y el trigger `trg_enforce_archive_own_side` lo impone en la BD.
/// Archivar OCULTA de la bandeja; nunca borra (la conversación es el registro
/// de un lead pagado).
/// Qué columna de archivado le toca a cada rol. Pura y pública para poder
/// fijar el mapeo en un test: es la única línea del archivado donde un
/// copy-paste invertido haría que un usuario intentara archivar el lado del
/// OTRO. El trigger `trg_enforce_archive_own_side` lo bloquearía con P0001,
/// pero el usuario vería "No se pudo archivar" sobre una acción perfectamente
/// legítima, y el motivo real quedaría enterrado en la BD.
String archivedColumnFor({required bool asProvider}) =>
    asProvider ? 'archived_by_provider' : 'archived_by_customer';

Future<void> setConversationArchived(
  String convId,
  bool archived, {
  required bool asProvider,
}) async {
  await supa
      .from('conversations')
      .update({archivedColumnFor(asProvider: asProvider): archived})
      .eq('id', convId);
  AppCaches.conversations.clear();
}

/// `archived` tal como lo resuelve `get_my_conversations_list` para quien
/// llama. Ausente = no archivada: una caché escrita antes de la migración no
/// puede hacer desaparecer conversaciones de la bandeja.
bool conversationArchived(Map<String, dynamic> c) => c['archived'] == true;

/// Baja el precio acordado y avisa al cliente en el chat, ATÓMICAMENTE.
///
/// Antes eran dos viajes desde el cliente (UPDATE del precio + INSERT de un
/// mensaje `kind='system'`) y los dos estaban rotos: el UPDATE moría en el
/// trigger `enforce_agreed_price_provider_only` (42704, no resolvía su propio
/// tipo con el search_path vacío) y el INSERT lo rechazaba la RLS desde que
/// M-2 quitó 'system' de los kinds del cliente (42501). Ahora todo vive en
/// `improve_offer_price` (migración 20260801150000), que además construye el
/// texto del aviso — si lo mandara el cliente, volvería a poder escribir
/// mensajes 'system' arbitrarios.
///
/// Lanza `PostgrestException` con `code == 'P0001'` para las reglas de negocio
/// (precio no menor, conversación cerrada, no eres el proveedor); pasarla por
/// [improveOfferErrorCopy] para el mensaje al usuario.
Future<void> improveOfferPrice(String convId, num newPrice) async =>
    supa.rpc(
      'improve_offer_price',
      params: {'_conversation_id': convId, '_new_price': newPrice},
    );

/// Propone una fecha pautada en el chat. `startsAt` viaja como fue
/// construido (hora LOCAL del dispositivo desde el selector de fecha/hora de
/// Task 5) y se convierte a UTC real recién aquí, al armar el parámetro —
/// nunca antes, para no perder la zona con la que el usuario eligió la hora.
///
/// Lanza `PostgrestException` con `code == 'P0001'` — validado contra
/// `supabase/migrations/20260823071753_fecha_pautada_nucleo.sql`, la RPC solo
/// puede levantar: 'No autenticado', 'Conversación no encontrada', 'No
/// participas en esta conversación', 'Esta conversación está cerrada',
/// 'Indica para qué es la fecha', 'El motivo no puede pasar de 60
/// caracteres', 'El motivo no puede incluir datos de contacto', 'La fecha
/// debe ser futura', 'La fecha no puede pasar de 90 días' o 'Espera unos
/// segundos antes de proponer otra fecha' (cooldown propio de 30 s por
/// conversación y proponente, DISTINTO del anti-flood de abajo).
///
/// TAMBIÉN puede lanzar `code == 'JY429'` (anti-flood del chat,
/// `chatRateLimitCode` en `domain/chat.dart`): esta RPC inserta la tarjeta
/// como un mensaje `kind='appointment'`, y el trigger
/// `enforce_chat_message_rate_limit` solo exime `('system','audit')` — la
/// tarjeta consume el cupo de 10 mensajes/30 s del proponente igual que
/// cualquier mensaje de chat. `respondScheduledDate` (abajo) NO comparte
/// este riesgo: inserta `kind='system'`, que SÍ está exento.
///
/// Mismo patrón que [sendFailureMessage] en `domain/chat.dart`: no inventar
/// un mapeo propio, mostrar `e.message` tal cual (ambos códigos ya traen
/// texto en español listo para el usuario).
Future<void> proposeScheduledDate(
  String convId,
  String subject,
  DateTime startsAt,
) async =>
    supa.rpc('propose_scheduled_date', params: {
      '_conversation_id': convId,
      '_subject': subject,
      '_starts_at': startsAt.toUtc().toIso8601String(),
    });

/// Responde (confirma/cancela) una fecha pautada propuesta. `_action` solo
/// acepta 'confirm'/'cancel' server-side — 'propose_again' y 'calendar' que
/// menciona Task 5 son acciones LOCALES de la app que nunca llegan a esta
/// RPC (ver `src/components/marketplace/AppointmentBubble.tsx`, mismo
/// contrato en la web).
///
/// Lanza `PostgrestException` con `code == 'P0001'` — validado contra la
/// misma migración, esta RPC solo puede levantar: 'No autenticado', 'Acción
/// inválida', 'Fecha pautada no encontrada', 'No participas en esta
/// conversación', 'Esta conversación está cerrada', 'Esta propuesta ya no
/// está activa' (al confirmar), 'La otra parte es quien confirma la fecha'
/// (quien propuso no puede autoconfirmarse) o 'Esta fecha ya no está
/// activa' (al cancelar).
///
/// NUNCA `JY429`: el aviso que deja esta RPC en el chat es `kind='system'`
/// ("📅 Fecha pautada confirmada…" / "Fecha pautada cancelada…"), y
/// `enforce_chat_message_rate_limit` exime exactamente `('system','audit')`
/// — a diferencia de `proposeScheduledDate` arriba, que sí puede tropezar
/// con el anti-flood porque inserta `kind='appointment'`.
Future<void> respondScheduledDate(String appointmentId, String action) async =>
    supa.rpc('respond_scheduled_date', params: {
      '_appointment_id': appointmentId,
      '_action': action,
    });

/// Responde la tarjeta de SEGUIMIENTO («¿Se realizó?») que el servidor
/// inserta 2 h después de una fecha confirmada. Cada lado contesta UNA vez;
/// el UPDATE del body llega por realtime igual que el resto de acciones de
/// fecha pautada, así que aquí no hay nada optimista que pintar.
///
/// Lanza `PostgrestException` con `code == 'P0001'` — esta RPC solo puede
/// levantar: 'No autenticado', 'Respuesta inválida', 'Este seguimiento no
/// está activo', 'Ya respondiste este seguimiento' o 'No participas en esta
/// conversación'.
///
/// NUNCA `JY429`: a diferencia de [proposeScheduledDate], esta RPC no
/// inserta ningún mensaje de chat — solo reescribe el body existente.
///
/// A propósito NO exige que la conversación esté abierta: la señal de si el
/// trato se cumplió no debe perderse porque nadie volvió a escribir tras
/// concluirlo. La UI (`bubbles.dart`) respeta esa asimetría y no vuelve a
/// imponer la reja de conversación abierta para esta acción.
Future<void> answerScheduledFollowup(String appointmentId, bool done) async =>
    supa.rpc('answer_scheduled_followup', params: {
      '_appointment_id': appointmentId,
      '_done': done,
    });

/// Horario de servicio del negocio de esta conversación, o `null` si no hay
/// horario configurado (hoy: TODOS los negocios en prod) — indistinguible de
/// "no soy participante de esta conversación". `null` es un estado válido,
/// nunca un error: no debe mostrarse como fallo en la UI.
Future<Map<String, dynamic>?> conversationServiceHours(String convId) async {
  final raw = await supa.rpc('get_conversation_service_hours',
      params: {'_conversation_id': convId});
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

/// ¿Ya calificó este cliente a este proveedor?
///
/// 🔴 Mirar SOLO `conversation_ratings` era una rotura de DOS orillas desde el
/// 2026-08-29: en la web se puede calificar desde la tarjeta de seguimiento con
/// el chat todavía ABIERTO, y la RLS de esa tabla exige `status='cerrado'`, así
/// que en ese caso la nota vive SOLO en `business_reviews`. Con el chequeo viejo,
/// el cliente que calificaba en la web y luego abría la APP al cerrarse el chat
/// **veía el formulario otra vez**, y el segundo envío hace `upsert` con
/// `onConflict: business_id,reviewer_id` ⇒ **pisaba su primera nota en silencio**.
///
/// Se consultan las DOS y basta con una. `_offerId` es el `source_id` de la
/// conversación y solo existe en los chats de OFERTA: en `product_interest` no
/// hay negocio detrás y la respuesta correcta es «no ha calificado».
Future<bool> hasConversationRating(String convId, {String? offerId}) async {
  final r = await supa
      .from('conversation_ratings')
      .select('id')
      .eq('conversation_id', convId)
      .maybeSingle();
  if (r != null) return true;
  if (offerId == null) return false;

  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;

  final off = await supa
      .from('provider_offers')
      .select('business_id')
      .eq('id', offerId)
      .maybeSingle();
  final bizId = off?['business_id'] as String?;
  if (bizId == null) return false;

  return (await supa
          .from('business_reviews')
          .select('id')
          .eq('business_id', bizId)
          .eq('reviewer_id', uid)
          .maybeSingle()) !=
      null;
}

// `hasAuditMessage` se retiró el 2026-08-28 con su único llamador (la
// "auditoría 72h" de chat_screen.dart, que no podía escribir desde 2026-07-29).
// Ver el comentario allí antes de resucitarla: buscaba CUALQUIER `audit`, así
// que los carteles del cron la daban siempre por satisfecha.

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
// **1-10** + comentario en `customer_reviews`, indexado por `offer_id`. La RLS solo
// exige que el negocio sea suyo (sin gate de estado), pero la UI lo muestra al
// cerrarse el chat.
// ⚠️ Este comentario decía "1-5" y era falso: la columna tiene `CHECK (1..10)` desde
// la migración `20260619014535` y el formulario de la app escribía 1-5 contra ella
// (arreglado el 2026-08-17). El `rating` se manda CRUDO, sin conversión de escala.

/// ¿El proveedor ya calificó al cliente de esta oferta? (una reseña por oferta).
Future<bool> hasCustomerReview(String offerId) async =>
    (await supa
        .from('customer_reviews')
        .select('id')
        .eq('offer_id', offerId)
        .maybeSingle()) !=
    null;

/// Ids de las ofertas de esta tanda que YA tienen reseña del cliente. Una sola
/// consulta para toda la lista (mismo patrón que la web en
/// `ProviderOffersSection.tsx:208`): por tarjeta serían N viajes.
Future<Set<String>> customerReviewsFor(List<String> offerIds) async {
  if (offerIds.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_reviews')
        .select('offer_id')
        .inFilter('offer_id', offerIds),
  );
  return rows.map((r) => r['offer_id'] as String).toSet();
}

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

/// `business_id` de un interés de producto — el otro tipo de conversación
/// (`get_or_create_conversation` solo acepta 'offer' y 'product_interest').
/// `product_interests` lleva `business_id` propio, así que no hace falta pasar
/// por `provider_products`.
///
/// ⚠️ HOY NO SE USA en el camino de calificación, a propósito: la política de
/// INSERT de `business_reviews` (migración 20260729210000) exige una
/// `provider_offers` desbloqueada de ese cliente con ese negocio, y un chat de
/// producto no tiene ninguna — la escritura rebotaba con 42501 y el catch
/// best-effort la perdía en silencio (revisión final, 2026-08-01). Se conserva
/// porque volverá a hacer falta el día que se amplíe esa política para admitir
/// intereses de producto desbloqueados. Ver `canResolveReviewBusiness` en
/// `chat_screen.dart`.
Future<String?> interestBusinessId(String interestId) async {
  final row = await supa
      .from('product_interests')
      .select('business_id')
      .eq('id', interestId)
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
///
/// Sin filtro de `kind`, en espejo exacto de [MessagesBadgeStore.refresh] y del
/// `unread_count` de la RPC (PO 2026-08-24): al abrir el chat se marca leído
/// TODO lo que apuntaba a él. Si aquí se filtrara por `message_new` y allí no,
/// el contador no bajaría al abrir y quedaría pegado — el defecto que el propio
/// gotcha #14 describe, por la otra puerta.
Future<void> markChatNotificationsRead(String convId) async {
  final uid = supa.auth.currentUser!.id;
  final readAt = DateTime.now().toUtc().toIso8601String();
  // Los kinds de inactividad se marcan leídos AQUÍ desde el 2026-08-28. Antes
  // solo `message_new`, pero `get_my_conversations_list.unread_count` cuenta por
  // LINK sin mirar el kind (decisión del PO, migración 20260824174418) ⇒ el
  // aviso de inactividad se quedaba sin leer para siempre y el globito de ese
  // chat no se apagaba nunca abriéndolo. Medido antes del arreglo: 11 de 22
  // avisos sin leer, el doble de tasa que los mensajes. Con tres avisos
  // escalonados en vez de uno el problema se triplicaba.
  // La lista es EXPLÍCITA a propósito, no un "todos menos": quitar el filtro
  // marcaría también `review_pending_reminder` y los `appointment_*` de este
  // chat, y abrir el chat borraría un recordatorio de calificar sin atender.
  const kinds = [
    'message_new',
    'conversation_inactivity_warning',
    'conversation_closed_inactivity',
  ];
  await Future.wait([
    supa
        .from('notifications')
        .update({'read_at': readAt})
        .eq('user_id', uid)
        .inFilter('kind', kinds)
        .eq('link', '/messages?c=$convId')
        .isFilter('read_at', null),
    supa
        .from('notifications')
        .update({'read_at': readAt})
        .eq('user_id', uid)
        .inFilter('kind', kinds)
        .eq('link', '/messages/$convId')
        .isFilter('read_at', null),
  ]);
  // La lista de chats amortiguada acaba de quedar MINTIENDO: su `unread_count`
  // es de antes de esta lectura. Sin esto, al volver atrás dentro del TTL
  // `conversations_screen` la servía tal cual y pisaba el badge con el número
  // viejo — "entré a un chat y no se quita el número" (PO 2026-08-25).
  final cached = AppCaches.conversations.staleValue;
  if (cached != null) clearUnreadCountFor(cached, convId);
}

/// Pone a cero, EN EL SITIO, el `unread_count` de [convId] dentro de [rows].
/// Devuelve `true` si de verdad cambió algo.
///
/// Se corrige la lista en vez de vaciar el caché a propósito: vaciarlo obligaría
/// a un round-trip al volver a la bandeja y devolvería el `JayaloLoaderBlock`
/// que ese caché existe para quitar (ver [AppCaches.conversations]).
///
/// Pura y pública para poder fijarla en un test sin Supabase.
bool clearUnreadCountFor(List<Map<String, dynamic>> rows, String convId) {
  var tocado = false;
  for (final r in rows) {
    if (r['id'] == convId && ((r['unread_count'] as int?) ?? 0) != 0) {
      r['unread_count'] = 0;
      tocado = true;
    }
  }
  return tocado;
}

/// Kinds de notificación que hablan de UNA OFERTA TUYA: su `entity_id` es el id
/// de la oferta. Cualquiera de estos sin leer significa "esta oferta tiene algo
/// que todavía no has visto".
///
/// Se listan explícitamente en vez de filtrar por `like 'offer_%'` para que
/// añadir un kind nuevo sea una decisión, no un efecto colateral.
const kOfferUpdateKinds = <String>[
  'offer_accepted',
  'offer_rejected',
  'offer_cancelled_customer',
  'offer_improved',
  'offer_unlocked',
];

/// Ids de OFERTA con AL MENOS UNA notificación sin leer: las que tienen algo
/// que no has abierto todavía. Alimenta el borde de "nuevo" en Mis ofertas.
///
/// Regla del PO (2026-08-22): "debe ser lo que no has abierto; si una oferta
/// tiene una actualización que no has abierto, cuenta". Por eso mira TODOS los
/// kinds de [kOfferUpdateKinds] y no solo `offer_accepted` como al principio:
/// que te la rechacen o que el cliente la cancele también son novedades, y
/// antes pasaban mudas.
///
/// Se re-arma solo: cada actualización nueva crea su notificación sin leer, así
/// que el borde vuelve sin necesidad de comparar relojes ni versiones.
///
/// La novedad vive en la notificación, no en la oferta: cero columnas nuevas.
/// Best-effort: si la consulta falla se devuelve vacío — el borde es una marca
/// de más, nunca puede tumbar la lista.
Future<Set<String>> unseenOfferIds() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return {};
  try {
    final notifs = List<Map<String, dynamic>>.from(
      await supa
          .from('notifications')
          .select('entity_id')
          .eq('user_id', uid)
          .inFilter('kind', kOfferUpdateKinds)
          .isFilter('read_at', null),
    );
    return notifs
        .map((n) => n['entity_id'] as String?)
        .whereType<String>()
        .toSet();
  } catch (_) {
    return {};
  }
}

/// Al ABRIR la oferta queda vista: marca leídas TODAS sus notificaciones
/// pendientes, no solo la de aceptación. Si solo se marcara una, el borde
/// volvería en la siguiente carga por las otras que quedaron sin leer.
///
/// Best-effort por lo mismo que su hermana: la pantalla ya quitó el borde de
/// forma optimista antes de llamar acá.
Future<void> markOfferSeen(String offerId) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return;
  try {
    await supa
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .inFilter('kind', kOfferUpdateKinds)
        .eq('entity_id', offerId)
        .isFilter('read_at', null);
  } catch (_) {}
}

/// `updated_at` de cada solicitud, por id. Es la marca de "esta fila cambió"
/// que la bandeja del proveedor necesita para saber si una solicitud que ya
/// abriste trae algo nuevo — `get_provider_inbox_unified` NO devuelve esa
/// columna y ampliar el RPC costaba una migración en producción.
///
/// Sale de la MISMA tabla que `requirementsForRequests` y viaja en la misma
/// oleada concurrente, así que no añade latencia.
///
/// Best-effort: sin esto, una solicitud abierta se queda abierta (el badge
/// puede quedarse corto, nunca de más).
Future<Map<String, DateTime>> updatedAtForRequests(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select('id,updated_at')
        .inFilter('id', ids),
  );
  return {
    for (final r in rows)
      if (DateTime.tryParse(r['updated_at'] as String? ?? '') != null)
        r['id'] as String: DateTime.parse(r['updated_at'] as String).toUtc(),
  };
}

/// `offers_count` de cada solicitud del marketplace, por id — para el chip
/// «¡Haz la primera oferta!» de la bandeja (pedido PO 2026-09-04):
/// `get_provider_inbox_unified` NO devuelve esta columna (igual que
/// `updated_at` arriba), así que se lee aparte de `customer_requests`, donde
/// ya vive con SELECT concedido (la usa `request_detail_screen.dart` en la
/// misma tabla).
///
/// Sale de la MISMA tabla que [updatedAtForRequests] y [requirementsForRequests]
/// y puede viajar en la misma oleada concurrente.
///
/// Best-effort: quien llama debe tratar la ausencia de un id (fallo o fila
/// sin esa columna) como "desconocido", NUNCA como 0 — un 0 falso enciende el
/// chip sobre una solicitud que sí tiene ofertas.
Future<Map<String, int>> offersCountForRequests(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select('id,offers_count')
        .inFilter('id', ids),
  );
  return {
    for (final r in rows)
      if (r['offers_count'] != null)
        r['id'] as String: (r['offers_count'] as num).toInt(),
  };
}

/// Foto del chat → bucket **privado** `chat-media`, carpeta por conversación.
/// Devuelve el marcador `chat-media:{path}`, NO una URL: el bucket no es
/// público y una URL firmada guardada en el `body` caducaría.
///
/// La ruta TIENE que empezar por el `conversation_id`: la política RLS del
/// bucket valida participación comparando `foldername[1]` contra
/// `conversations.customer_id / provider_user_id`. Por eso no se puede reusar
/// [_uploadMarketplaceImage] con `bucket:'chat-media'` — construye la ruta como
/// `{uid}/{kind}/…` y el INSERT saldría rechazado.
///
/// Hasta el 2026-08-13 esto subía al bucket PÚBLICO `business-logos`, así que
/// las fotos privadas de un chat quedaban legibles por URL para cualquiera; la
/// web ya lo había cerrado el 2026-07-31. El formato del marcador es el mismo
/// que emite `persistChatImage` en la web, para que las fotos crucen en las dos
/// direcciones.
Future<String> uploadChatImage(String filePath, String conversationId) async {
  final dot = filePath.lastIndexOf('.');
  final raw = dot == -1 ? '' : filePath.substring(dot + 1).toLowerCase();
  final ext = raw.isEmpty ? 'jpg' : raw;
  final rand = _rand.nextInt(1 << 31).toRadixString(16);
  final path =
      '$conversationId/${DateTime.now().millisecondsSinceEpoch}-$rand-chat.$ext';
  await supa.storage
      .from('chat-media')
      .upload(
        path,
        File(filePath),
        fileOptions: FileOptions(contentType: _imageContentType(ext)),
      );
  return '$chatMediaPrefix$path';
}

/// Firma los marcadores `chat-media:` de una tanda de mensajes para poder
/// pintarlos. Devuelve un mapa marcador → URL firmada; los que fallen
/// simplemente no aparecen (la burbuja se queda en su placeholder).
///
/// Los bodies que ya son `http(s)`/`data:` NO pasan por aquí: el compartir-
/// artículo del chat inserta URLs públicas de otros buckets y firmarlas
/// rompería lo que hoy funciona.
Future<Map<String, String>> signChatImages(
  List<String> markers, {
  int ttlSeconds = 3600,
}) async {
  final unique = markers.where(isChatMediaMarker).toSet().toList();
  if (unique.isEmpty) return const {};
  final results = await supa.storage
      .from('chat-media')
      .createSignedUrlsResult(unique.map(chatMediaPath).toList(), ttlSeconds);
  // Se empareja por la RUTA que devuelve cada resultado, no por posición: así no
  // depende de que el servidor conserve el orden de lo pedido.
  final porRuta = <String, String>{
    for (final r in results)
      if (r is SignedUrlSuccess) r.path: r.signedUrl,
  };
  final out = <String, String>{};
  for (final marker in unique) {
    final url = porRuta[chatMediaPath(marker)];
    if (url != null) out[marker] = url;
  }
  return out;
}

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
  // lat/lng NO tienen GRANT SELECT en provider_businesses (migracion
  // 20260709000001): pedirlas en el select hacia fallar la peticion ENTERA con
  // un error de permiso de columna, asi que esta accion no mandaba nada.
  double? lat, lng;
  try {
    final loc = await supa
        .rpc('get_business_location', params: {'_business_id': biz['id']});
    final row = (loc is List && loc.isNotEmpty) ? loc.first : null;
    if (row is Map) {
      lat = (row['lat'] as num?)?.toDouble();
      lng = (row['lng'] as num?)?.toDouble();
    }
  } catch (_) {
    // Sin coordenadas se manda igual: el texto de la direccion ya sirve.
  }
  return businessAddressBody(
    name: biz['name'] is String ? biz['name'] as String : '',
    address: address,
    cityLine: [biz['sector'], biz['city']]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', '),
    lat: lat,
    lng: lng,
  );
}

/// Normaliza la respuesta cruda de una RPC de ubicacion (`get_request_location`
/// / `get_business_location`, Task 11) a coordenadas o null. Extraida como
/// funcion pura (sin red) para que un test la pueda blindar sin mockear
/// Supabase — mismo motivo que [businessVerifiedFrom] mas arriba.
///
/// Las dos RPCs dicen "sin ubicacion" de DOS formas distintas y esta funcion
/// las colapsa a la misma: `get_request_location` filtra nulls, asi que
/// responde una lista VACIA; `get_business_location` NO filtra, asi que
/// responde 1 fila con `lat`/`lng` en null. Ambas caen aqui en null — nunca
/// un `null` colado en la URL del mapa. `as num?` (no `as double?`) importa:
/// PostgREST puede devolver `numeric` como `int` cuando el valor no tiene
/// decimales.
({double lat, double lng})? latLngFromRpcRow(dynamic res) {
  final row = (res is List && res.isNotEmpty) ? res.first : null;
  if (row is! Map) return null;
  final lat = (row['lat'] as num?)?.toDouble();
  final lng = (row['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return (lat: lat, lng: lng);
}

/// Coordenadas de una solicitud (Task 11: boton "Ver en el mapa" en el
/// detalle que ve el proveedor). Devuelve null si la reja de
/// `get_request_location` no deja pasar al llamador (la RPC responde 0 filas
/// por diseno, no lanza) o si la solicitud no tiene coordenadas guardadas —
/// ver [latLngFromRpcRow].
Future<({double lat, double lng})?> requestLocation(String requestId) async {
  try {
    final res = await supa
        .rpc('get_request_location', params: {'_request_id': requestId});
    return latLngFromRpcRow(res);
  } catch (_) {
    return null;
  }
}

/// Coordenadas de un negocio (Task 11: boton "Ver en el mapa" en la tienda
/// que ve el cliente). A diferencia de [requestLocation], `get_business_
/// location` NO filtra nulls — ver [latLngFromRpcRow] para como se colapsan
/// las dos formas a null igual.
Future<({double lat, double lng})?> businessLocation(String businessId) async {
  try {
    final res = await supa
        .rpc('get_business_location', params: {'_business_id': businessId});
    return latLngFromRpcRow(res);
  } catch (_) {
    return null;
  }
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
      .select('address,address_reference,sector,city,lat,lng')
      .eq('user_id', uid)
      .maybeSingle();
  if (p == null) return null;
  final cityLine = [
    p['sector'],
    p['city'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  return buildLocationBody(
    address: p['address'] is String ? p['address'] as String : '',
    cityLine: cityLine,
    reference: p['address_reference'] is String
        ? p['address_reference'] as String
        : '',
    lat: (p['lat'] as num?)?.toDouble(),
    lng: (p['lng'] as num?)?.toDouble(),
  );
}

/// Actualiza SOLO la direccion del perfil. Existe porque hasta 2026-08-04 la
/// direccion solo se podia poner en el onboarding: si salia mal el dia del alta,
/// no habia ninguna forma de corregirla dentro de la app.
Future<void> updateMyAddress({
  required String address,
  required String city,
  required String sector,
  required String street,
  required String streetNumber,
  required String reference,
  double? lat,
  double? lng,
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('profiles').update({
    'address': address,
    'city': city.isEmpty ? null : city,
    'sector': sector.isEmpty ? null : sector,
    'street': street.isEmpty ? null : street,
    'street_number': streetNumber.isEmpty ? null : streetNumber,
    'address_reference': reference.isEmpty ? null : reference,
    'lat': ?lat,
    'lng': ?lng,
    if (lat != null && lng != null)
      'location_captured_at': DateTime.now().toIso8601String(),
  }).eq('user_id', uid);
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

/// Identidad del cliente, GATEADA por desbloqueo server-side y POR SOLICITUD
/// (migración `20260811140000`, decisión PO 2026-08-11): la RPC devuelve
/// nombre/apellido/avatar SOLO si el llamador pagó el desbloqueo de ESE
/// contexto — la solicitud ([requestId]), la oferta ([offerId]) o el interés
/// ([interestId]) — y ese contexto es de ese cliente. Sin contexto o sin pago
/// → `unlocked: false` y todo null: el perfil se pinta anónimo. El cliente
/// NUNCA decide esto: el gate vive en la RPC, no aquí.
Future<({bool unlocked, String? firstName, String? lastName, String? avatarUrl})>
    customerPublicProfile(
  String customerId, {
  String? requestId,
  String? offerId,
  String? interestId,
}) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_customer_public_profile',
      params: {
        '_customer_id': customerId,
        '_request_id': requestId,
        '_offer_id': offerId,
        '_interest_id': interestId,
      },
    ),
  );
  final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
  return (
    unlocked: r['unlocked'] == true,
    firstName: r['first_name'] as String?,
    lastName: r['last_name'] as String?,
    avatarUrl: r['avatar_url'] as String?,
  );
}

/// Reseñas que OTROS proveedores dejaron sobre un cliente (rating + comentario
/// + negocio + fecha), para el perfil del cliente. La RPC EXCLUYE las reseñas
/// de los negocios del que llama (regla PO 2026-08-11: reconocer tu propio
/// comentario desanonimiza al cliente). Campos por fila: rating, comment,
/// business_name, created_at.
Future<List<Map<String, dynamic>>> customerReviews(
  String customerId, {
  int limit = 5,
}) async =>
    List<Map<String, dynamic>>.from(
      await supa.rpc(
        'get_customer_reviews',
        params: {'_customer_id': customerId, '_limit': limit},
      ),
    );

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
    String? coverUrl,
    bool verified,
    String? categoryId,
    String? city,
    bool wholesale,
    String? description,
    List<String> seals,
    List<String> services,
    Map<String, dynamic> raw,
  })?
>
myBusinessProfile() async {
  final uid = supa.auth.currentUser!.id;
  // `cover_url` y las columnas de detalle (experiencia, fundación, equipo,
  // cobertura, horario, idiomas, pagos, garantía) entraron el 2026-08-01: la
  // app enseñaba tres chips donde la web tiene una ficha entera, y la portada
  // no se leía en ningún sitio. Todas son de lectura pública — verificado en
  // los grants por columna, no hizo falta migración.
  final biz = await supa
      .from('provider_businesses')
      .select(
        'id,name,logo_url,cover_url,business_verified_at,identity_verified_at,'
        'whatsapp_verified_at,category_id,city,is_wholesale,description,'
        'business_type,experience_years,founded_year,employees_count,'
        'service_area,service_hours,languages,payment_methods,warranty,'
        'services,offers,profession,team_photos,'
        // La profesión ya no es el texto libre `profession` sino el catálogo
        // (paridad con `BusinessDetailsCard.tsx` de la web). `approved_at`
        // viaja porque el DUEÑO ve también los suyos sin aprobar y su ficha
        // no debe prometer al público algo que el público no ve.
        'provider_business_oficios(approved_at,oficios(name))',
      )
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (biz == null) return null;
  final logo = biz['logo_url'] as String?;
  final cover = biz['cover_url'] as String?;
  final city = (biz['city'] as String?)?.trim();
  final desc = (biz['description'] as String?)?.trim();
  final cat = (biz['category_id'] as String?)?.trim();
  return (
    id: biz['id'] as String,
    name: (biz['name'] as String?) ?? '',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    coverUrl: (cover != null && cover.isNotEmpty) ? cover : null,
    verified: businessVerifiedFrom(biz),
    categoryId: (cat != null && cat.isNotEmpty) ? cat : null,
    city: (city != null && city.isNotEmpty) ? city : null,
    wholesale: biz['is_wholesale'] == true,
    description: (desc != null && desc.isNotEmpty) ? desc : null,
    seals: verificationSealsFrom(biz),
    services: (biz['services'] as List?)?.cast<String>() ?? const [],
    raw: biz,
  );
}

/// Los tres sellos de verificación resueltos a ETIQUETA, en el orden de la web
/// (identidad → RNC → WhatsApp). Lista vacía = negocio sin verificar.
///
/// ⚠️ "Negocio verificado" sale de `business_verified_at` (el RNC revisado por
/// un admin) y NUNCA del WhatsApp del negocio: son credenciales distintas y
/// confundirlas ya fue un bug (ver [businessVerifiedFrom]).
List<String> verificationSealsFrom(Map<String, dynamic> biz) => [
  if (biz['identity_verified_at'] != null) 'Identidad verificada',
  if (biz['business_verified_at'] != null) 'Negocio verificado',
  if (biz['whatsapp_verified_at'] != null) 'WhatsApp verificado',
];

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
        'id,title,description,kind,urgency,zone,is_wholesale,created_at,'
        'image_url,$requestRequirementCols',
      )
      .eq('status', 'open')
      .neq('user_id', uid);
  if (kind != null) q = q.eq('kind', kind);
  return List<Map<String, dynamic>>.from(
    await q.order('created_at', ascending: false).limit(100),
  );
}

// ── Catálogo (Task 6): listado de productos/servicios publicados ───────────

// `condition`/`offers_shipping`/`color`/`offer_defaults`: la fila de
// atributos de la tarjeta de rejilla (mockup Variante A, PO 2026-08-11).
const catalogProductCols =
    'id,user_id,business_id,name,description,price,'
    'price_min,price_max,image_urls,category_id,rubro,kind,'
    'condition,offers_shipping,color,offer_defaults';

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
    wholesaleBizIds = List<Map<String, dynamic>>.from(
      biz,
    ).map((b) => b['id'] as String).toList();
    // Sin negocios mayoristas no hay productos que mostrar (evita un
    // `in.()` vacío, que PostgREST rechaza).
    if (wholesaleBizIds.isEmpty) return const [];
  }
  var q = supa
      .from('provider_products')
      .select(catalogProductCols)
      .eq('kind', kind);
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

/// Identidad PÚBLICA de un negocio: nombre y logo (PO 2026-07-28 — el cliente
/// ve nombre, tienda y logo sin desbloquear nada). Lectura directa: los grants
/// por columna de `provider_businesses` conceden `name`/`logo_url` y NO
/// conceden whatsapp/address/rnc, así que el contacto sigue siendo ilegible.
/// `coverUrl` y `raw` se sumaron el 2026-08-01 con el rediseño de la tienda:
/// la portada y las columnas de detalle también son de lectura pública (están
/// en los mismos grants por columna), así que la tienda ajena puede lucir
/// igual que la propia sin abrir ni un permiso nuevo.
///
/// `services` (Task 5, 2026-08-09) sigue el mismo trato: chips de servicios
/// del negocio, de lectura pública — viene en el mismo select principal
/// (Task 1: `provider_businesses.services text[]` ya aplicada en prod), sin
/// un segundo viaje a la red.
///
/// `offers`, `profession` y `team_photos` (Task 9, 2026-08-14 — paridad del
/// perfil diferenciado técnico vs. tienda) van en `raw`, no como campos
/// propios: `offers` alimenta `profileSections` (orden/presencia de
/// productos/servicios/paquetes) y `team_photos` la galería del equipo,
/// visible solo si `business_type == 'tecnico'`. Las tres columnas ya tienen
/// `GRANT SELECT` para `anon`/`authenticated` en prod.
typedef BusinessIdentity = ({
  String name,
  String? logoUrl,
  String? coverUrl,
  List<String> services,
  Map<String, dynamic> raw,
});

Future<BusinessIdentity?> businessPublicIdentity(String businessId) async {
  final row = await supa
      .from('provider_businesses')
      .select(
        'name,logo_url,cover_url,is_wholesale,business_type,experience_years,'
        'founded_year,employees_count,service_area,service_hours,languages,'
        'payment_methods,warranty,category_id,city,services,offers,'
        'profession,team_photos,'
        'provider_business_oficios(approved_at,oficios(name))',
      )
      .eq('id', businessId)
      .maybeSingle();
  if (row == null) return null;
  final logo = row['logo_url'] as String?;
  final cover = row['cover_url'] as String?;
  return (
    name: (row['name'] as String?)?.trim().isNotEmpty == true
        ? (row['name'] as String).trim()
        : 'Proveedor',
    logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
    coverUrl: (cover != null && cover.isNotEmpty) ? cover : null,
    services: (row['services'] as List?)?.cast<String>() ?? const [],
    raw: row,
  );
}

/// Cabecera de identidad de un negocio para una TARJETA: nombre, logo y los 3
/// sellos crudos (PO 2026-07-29 — la lista de ofertas del cliente cierra el
/// hueco que dejó `offer_actions.dart`/la tienda/el catálogo el 2026-07-28).
/// Mismas columnas públicas que [BusinessIdentity] más `whatsapp_verified_at`,
/// `identity_verified_at` y `business_verified_at`: son de lectura pública
/// (grants por columna a `authenticated`/`anon`, RLS permite cualquier
/// negocio no suspendido), así que no hace falta una RPC nueva.
typedef BusinessCardInfo = ({
  String name,
  String? logoUrl,
  bool whatsappVerified,
  bool identityVerified,
  bool businessVerified,
  bool hasPhysicalLocation,
});

/// Versión POR LOTE de [businessPublicIdentity]: una sola consulta con
/// `.inFilter('id', ...)` para toda una pantalla con N tarjetas, en vez de una
/// consulta por tarjeta (N+1). De-duplica ids y no llama a la red con lista
/// vacía. Un negocio que no resuelve (borrado, suspendido) simplemente no
/// aparece en el mapa devuelto — quien lo consuma debe tratar la ausencia como
/// "sin cabecera", nunca como un "Proveedor" fantasma.
Future<Map<String, BusinessCardInfo>> businessesCardInfo(
  List<String> businessIds,
) async {
  final ids = businessIds.toSet().toList();
  if (ids.isEmpty) return const {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('provider_businesses')
        .select('id,name,logo_url,whatsapp_verified_at,'
            'identity_verified_at,business_verified_at')
        .inFilter('id', ids),
  );
  // Consulta separada y con su propio try/catch (ver doc de
  // [businessesPhysicalLocation]): si la columna nueva aún no existe, este
  // select falla solo y el resto de la cabecera (nombre/logo/sellos de
  // verificación) sigue intacto.
  final physical = await businessesPhysicalLocation(ids);
  return {
    for (final r in rows)
      r['id'] as String: (
        name: (r['name'] as String?)?.trim().isNotEmpty == true
            ? (r['name'] as String).trim()
            : 'Proveedor',
        logoUrl: (r['logo_url'] as String?)?.isNotEmpty == true
            ? r['logo_url'] as String
            : null,
        whatsappVerified: r['whatsapp_verified_at'] != null,
        identityVerified: r['identity_verified_at'] != null,
        businessVerified: r['business_verified_at'] != null,
        hasPhysicalLocation: physical[r['id'] as String] ?? false,
      ),
  };
}

/// Sello "Tienda física" (pedido PO 2026-08-12, paridad con la web — commit
/// `3d4cacb`). Es AUTODECLARADO: el proveedor dice que atiende en un local
/// abierto al público, nadie lo comprueba. A diferencia de [businessesVerified]
/// (que sí necesita la RPC porque esas columnas NO están en los grants para un
/// tercero), `has_physical_location` SÍ tiene `GRANT SELECT` para
/// `anon`/`authenticated` — verificado en producción — así que un select
/// directo por columna basta, sin RPC nueva.
///
/// La migración que crea la columna (`20260812130000_has_physical_location
/// .sql`, repo web) puede no estar aplicada todavía en este momento. Por eso
/// vive en su PROPIA consulta con su PROPIO try/catch, nunca mezclada en el
/// mismo `.select(...)` que nombre/logo/sellos: si la columna no existe,
/// Postgres responde con error y esta función degrada a mapa vacío (el sello
/// simplemente no se pinta) sin tumbar el resto de la pantalla — mismo trato
/// best-effort que el resto de este archivo (ver `paquetesF` en
/// `provider_store_screen.dart`).
Future<Map<String, bool>> businessesPhysicalLocation(
  List<String> businessIds,
) async {
  final ids = businessIds.toSet().toList();
  if (ids.isEmpty) return const {};
  try {
    final rows = List<Map<String, dynamic>>.from(
      await supa
          .from('provider_businesses')
          .select('id,has_physical_location')
          .inFilter('id', ids),
    );
    return {
      for (final r in rows)
        r['id'] as String: r['has_physical_location'] == true,
    };
  } catch (_) {
    return const {};
  }
}

// ── Mi tienda: productos/servicios del propio negocio ──────────────────────
// Incluye los campos que autocompletan una oferta al elegir un producto de la
// tienda (color/logística/estado/rubro), no solo lo que pinta la lista.
// `brand`/`warranty` (Task 6, revisión Fix round 1): columnas REALES que ya
// pintaba la ficha pública (`productDetailCols`) — el editor de ítem de
// tienda ahora también las escribe (antes solo iban al jsonb
// `offer_defaults`, así que "Marca"/"Garantía" nunca movían la ficha
// pública y aparecían vacías al reabrir el editor).
const storeProductCols =
    'id,name,description,color,price,price_min,price_max,image_urls,'
    'category_id,rubro,kind,condition,offers_shipping,offers_installation,'
    'requires_evaluation,brand,warranty,offer_defaults';

/// Todos los productos y servicios del propio negocio, más recientes primero.
/// Se separan por kind en la UI con [partitionStoreItems].
///
/// Incluye `offer_defaults` (Task 6: molde de oferta que escribe el editor de
/// ítem de tienda) en [storeProductCols] — select directo, sin fallback:
/// la migración `20260809120001_products_offer_defaults.sql` ya está
/// aplicada en prod.
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
///
/// Incluye `description` (Task 8, 2026-08-09): el editor de trabajo de "Mi
/// negocio" la prellena — antes de esta tarea el select no la traía porque
/// nada la leía todavía.
Future<List<Map<String, dynamic>>> myPortfolioItems(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_portfolio_items')
          .select('id,title,description,image_urls,category_id,completed_at')
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
  // Columnas REALES (Task 6, revisión Fix round 1) — las mismas que pinta la
  // ficha pública (`productDetailCols`). Van SIEMPRE en el mismo save que
  // `offerDefaults.brand`/`.warranty`, así que nunca pueden divergir.
  String? brand,
  String? warranty,
  // Molde de oferta del ítem (Task 6, jsonb): lo que el editor de "Mi
  // negocio" guarda para prellenar futuras ofertas (lectura en la Task 9).
  // `null`/`{}` no manda la columna.
  Map<String, dynamic>? offerDefaults,
}) async {
  final uid = supa.auth.currentUser!.id;
  final row = {
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
    'brand': brand,
    'warranty': warranty,
    if (offerDefaults != null && offerDefaults.isNotEmpty)
      'offer_defaults': offerDefaults,
  };
  await supa.from('provider_products').insert(row);
}

/// Edita un producto/servicio propio (RLS: dueño) — editor de ítem de tienda
/// (Task 6, "Mi negocio" → tocar una tarjeta propia). `payload` ya viene
/// armado por quien llama (mismas columnas que [saveProductToStore], más
/// `offer_defaults`); aquí no se interpreta. Escritura directa: la migración
/// `20260809120001_products_offer_defaults.sql` (Task 6) ya está aplicada en
/// prod.
Future<void> updateStoreItem(String id, Map<String, dynamic> payload) =>
    supa.from('provider_products').update(payload).eq('id', id);

/// Borra un producto/servicio propio (RLS: dueño) — "mantener presionada →
/// Eliminar de tu tienda" (Task 6).
Future<void> deleteStoreItem(String id) =>
    supa.from('provider_products').delete().eq('id', id);

/// Foto de un producto/servicio de la tienda → `{uid}/products/<ts>-<rand>`.
Future<String> uploadStoreProductImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'products');

/// Foto de un trabajo del portafolio → `{uid}/portfolio/<ts>-<rand>`.
Future<String> uploadPortfolioImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'portfolio');

/// Alta de un trabajo del portafolio desde la app (espejo del insert de
/// `PortfolioEditorDialog.tsx` de la web: RLS de dueño, solo exige
/// business_id + user_id + title). A diferencia de la web, las fotos van a
/// Storage y aquí se guardan URLs — nunca base64 en la BD (regla de la casa).
Future<void> savePortfolioItem({
  required String businessId,
  required String title,
  String? description,
  List<String> imageUrls = const [],
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_portfolio_items').insert({
    'user_id': uid,
    'business_id': businessId,
    'title': title,
    'description':
        (description == null || description.trim().isEmpty) ? null : description.trim(),
    'image_urls': imageUrls,
  });
}

/// Edita un trabajo propio del portafolio (RLS: dueño) — "Mi negocio" →
/// tocar un `_PortfolioTile` propio (Task 8). Mismo criterio de
/// `description` en blanco que [savePortfolioItem]: cadena vacía se guarda
/// como `null`, no como `''`.
Future<void> updatePortfolioItem(
  String id, {
  required String title,
  String? description,
  required List<String> imageUrls,
}) =>
    supa.from('provider_portfolio_items').update({
      'title': title,
      'description': (description == null || description.trim().isEmpty)
          ? null
          : description.trim(),
      'image_urls': imageUrls,
    }).eq('id', id);

/// Borra un trabajo propio del portafolio (RLS: dueño) — "mantener presionado
/// → Eliminar" (Task 8), mismo trato que [deleteStoreItem].
Future<void> deletePortfolioItem(String id) =>
    supa.from('provider_portfolio_items').delete().eq('id', id);

// ── Mi tienda: paquetes (Task 7, 2026-08-09) ────────────────────────────────
// Espejo de `provider_packages` / `PackageEditorDialog.tsx` de la web, sin
// `is_featured` ("Más popular"): el brief de esta tarea no pidió ese slot —
// alta/edición/borrado básicos del paquete, mismo trato que el resto de "Mi
// negocio" (edición limitada en la app, V2 completa en la web).

const packageCols =
    'id,business_id,name,description,price,items,image_url,created_at';

/// Paquetes/planes del propio negocio, más recientes primero.
Future<List<Map<String, dynamic>>> myPackages(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_packages')
          .select(packageCols)
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(100),
    );

/// Arma el payload de [savePackage], sin tocar Supabase — extraído para
/// poder probar el fix del hallazgo C-1 (revisión final) sin un cliente real.
/// `provider_packages.price` es `NOT NULL DEFAULT 0` en la base: mandar
/// `price: null` explícito (precio en blanco en el formulario) pisaba ese
/// default con un `null` real y el INSERT/UPDATE entero reventaba con 23502
/// ("not-null constraint"). `price ?? 0` respeta la intención del default de
/// la columna en vez de contradecirlo.
@visibleForTesting
Map<String, dynamic> packagePayload({
  required String businessId,
  required String name,
  String description = '',
  double? price,
  required List<String> items,
  String? imageUrl,
}) => {
  'business_id': businessId,
  'name': name,
  'description': description,
  'price': price ?? 0,
  'items': items,
  'image_url': imageUrl,
};

/// Alta o edición de un paquete propio (RLS: dueño). `id` nulo → INSERT;
/// con `id` → UPDATE. La tabla exige `user_id` NOT NULL en el insert — la web
/// lo manda explícito (`PackageEditorDialog.tsx:147`), así que aquí también
/// (mismo criterio que [savePortfolioItem]/[saveProductToStore], en vez de
/// confiar en un default de columna que la tabla podría no tener).
Future<void> savePackage({
  String? id,
  required String businessId,
  required String name,
  String description = '',
  double? price,
  required List<String> items,
  String? imageUrl,
}) async {
  final payload = packagePayload(
    businessId: businessId,
    name: name,
    description: description,
    price: price,
    items: items,
    imageUrl: imageUrl,
  );
  if (id == null) {
    final uid = supa.auth.currentUser!.id;
    await supa.from('provider_packages').insert({'user_id': uid, ...payload});
  } else {
    await supa.from('provider_packages').update(payload).eq('id', id);
  }
}

/// Borra un paquete propio (RLS: dueño) — "mantener presionado → Eliminar"
/// (Task 7, "Mi negocio").
Future<void> deletePackage(String id) =>
    supa.from('provider_packages').delete().eq('id', id);

/// Paquetes/planes de un negocio AJENO — tienda pública que ve el cliente
/// (`provider_store_screen.dart`, pedido PO 2026-08-09: "los paquetes... con
/// todo lo que se ha hecho del lado del proveedor, pero debe verse del lado
/// del cliente"). Mismas columnas ([packageCols]) y mismo orden que
/// [myPackages]; distinta solo en el nombre, para no confundir "mis
/// paquetes" con "los paquetes de otro negocio" en las pantallas que la
/// llaman. Depende de la migración `20260809130000_packages_public_read.sql`
/// (`provider_packages` solo tenía política de lectura del dueño) — mientras
/// esa migración no esté aplicada, RLS filtra a lista vacía sin lanzar, así
/// que la sección de paquetes de la tienda simplemente no se pinta.
Future<List<Map<String, dynamic>>> storePackages(String businessId) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('provider_packages')
          .select(packageCols)
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(100),
    );

/// Foto de un paquete/plan → bucket `provider-products` (Task 7, espejo de
/// `PackageEditorDialog.tsx:121`: `${user.id}/packages/${uuid}`). El
/// rand-hex de [_uploadMarketplaceImage] cumple el mismo papel que el
/// `crypto.randomUUID()` de la web — mismo objetivo (nombre único), otra
/// fuente de aleatoriedad.
Future<String> uploadPackageImage(String filePath) =>
    _uploadMarketplaceImage(filePath, 'packages', bucket: 'provider-products');

/// Columnas del DETALLE de un paquete (`package_detail_screen.dart`, pedido
/// PO 2026-08-09: "El paquete no abre nada" en la tienda del cliente).
/// [packageCols] + `user_id`: la lista (`myPackages`/`storePackages`) no lo
/// necesita, pero el detalle sí — para el chequeo `isOwner`, mismo criterio
/// que `productDetailCols` frente a las columnas de lista del catálogo.
const packageDetailCols =
    'id,user_id,business_id,name,description,price,items,image_url,created_at';

Future<Map<String, dynamic>?> packageDetail(String id) async => await supa
    .from('provider_packages')
    .select(packageDetailCols)
    .eq('id', id)
    .maybeSingle();

/// category_id (slug) + un rubro (NOMBRE) del negocio, para prefijar el
/// guardado en tienda: `provider_products` exige ambos NOT NULL y la oferta no
/// los trae. `provider_business_rubros` guarda `rubro_id` (uuid) → se resuelve
/// a `rubros.name` (que es lo que la web pone en `provider_products.rubro`).
Future<({String? categoryId, String? rubro})> myBusinessCategoryRubro(
  String businessId,
) async {
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
  List<Map<String, dynamic>> items,
) {
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
    'offers_shipping,offers_installation,kind'
    // Detalles que la tabla YA guardaba y el detalle no traía ni pintaba
    // (pedido PO 2026-08-03: coherencia visual con las ofertas). Ojo:
    // `provider_products` NO tiene `delivery_time` — eso es de las ofertas.
    ',brand,warranty,requires_evaluation'
    // Rediseño de la ficha en chips (pedido PO 2026-08-09): `offer_defaults`
    // trae "tiempo de entrega" (`delivery`) y la lista completa de colores
    // (`colors`) que `brand`/`warranty` — arriba — no cubren porque son
    // columnas propias; esto es jsonb, mismo molde que escribe el editor de
    // ítem de tienda (`OfferDefaults`, `add_store_item_screen.dart`).
    ',offer_defaults';

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
  List<String> businessIds,
) async {
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

// ── Indicadores de confianza de la tienda (paridad con la web) ─────────────

/// Bloque de reputación de la tienda anónima: rating, trabajos completados,
/// tiempo de respuesta (promedio solicitud→oferta, como la web), año de alta y
/// sellos de verificación. Todo agregado/booleano — cero PII.
typedef BusinessStorefrontStats = ({
  double? avgRating,
  int reviewsCount,
  int completedJobs,
  double? medianResponseMinutes,
  int? memberSinceYear,
  bool identityVerified,
  bool businessVerified,
  bool whatsappVerified,
});

/// Trae el bloque de confianza de un negocio en UNA llamada vía la RPC
/// `get_business_storefront_stats`. `null` si no hay fila (negocio inexistente).
Future<BusinessStorefrontStats?> businessStorefrontStats(
  String businessId,
) async {
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_business_storefront_stats',
      params: {'_business_id': businessId},
    ),
  );
  if (rows.isEmpty) return null;
  final r = rows.first;
  return (
    avgRating: (r['avg_rating'] as num?)?.toDouble(),
    reviewsCount: (r['reviews_count'] as num?)?.toInt() ?? 0,
    completedJobs: (r['completed_jobs'] as num?)?.toInt() ?? 0,
    medianResponseMinutes: (r['median_response_minutes'] as num?)?.toDouble(),
    memberSinceYear: (r['member_since_year'] as num?)?.toInt(),
    identityVerified: r['identity_verified'] == true,
    businessVerified: r['business_verified'] == true,
    whatsappVerified: r['whatsapp_verified'] == true,
  );
}

/// Sellos de verificación de una contraparte (RPC `get_peer_verification_badges`,
/// migración 20260728120000). Devuelve SOLO booleanos: la RPC nunca expone el
/// número ni el documento. Best-effort: si falla, se omiten los sellos.
typedef PeerBadges = ({bool whatsappVerified, bool idVerified});

Future<Map<String, PeerBadges>> peerVerificationBadges(
  List<String> userIds,
) async {
  if (userIds.isEmpty) return const {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'get_peer_verification_badges',
      params: {'_user_ids': userIds},
    ),
  );
  return {
    for (final r in rows)
      r['user_id'] as String: (
        whatsappVerified: r['whatsapp_verified'] == true,
        idVerified: r['id_verified'] == true,
      ),
  };
}

/// MI reseña vigente de este negocio (o null). La RLS de `business_reviews`
/// permite al reseñador leer la suya; el índice único
/// `uq_business_reviews_one_per_reviewer` garantiza que haya como mucho una.
Future<({int rating, String? comment})?> myBusinessReview(
  String businessId,
) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await supa
      .from('business_reviews')
      .select('rating,comment')
      .eq('business_id', businessId)
      .eq('reviewer_id', uid)
      .maybeSingle();
  if (row == null) return null;
  final c = (row['comment'] as String?)?.trim() ?? '';
  return (
    rating: (row['rating'] as num).toInt(),
    comment: c.isEmpty ? null : c,
  );
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
  List<Map<String, dynamic>> items,
  Map<String, BusinessRating> ratings,
) {
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
    wholesale: wholesale,
  );
  final ids = <String>{
    for (final it in items)
      if (it['business_id'] is String) it['business_id'] as String,
  }.toList();
  // La reputación es un adorno (spec §2): si la RPC por lote falla, se ocultan
  // las estrellas — NO se tira todo el catálogo a la pantalla de error.
  final ratings = await businessRatings(
    ids,
  ).catchError((_) => <String, BusinessRating>{});
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

/// Ya existe una fila de interés del cliente actual para este producto —
/// alimenta el estado idempotente "ya enviaste tu interés" (el SELECT sigue
/// permitido tras la migración 20260718150000, que solo revocó
/// INSERT/UPDATE de tabla). El gate de identidad del negocio que antes vivía
/// aquí (`unlocked`) se eliminó (PO 2026-07-28): el cliente ve nombre/logo
/// del proveedor siempre, vía `businessPublicIdentity`, sin relación con si
/// algún proveedor pagó por desbloquear este interés.
Future<bool> productInterestExists(String productId) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supa
      .from('product_interests')
      .select('id')
      .eq('product_id', productId)
      .eq('customer_id', uid)
      .limit(1)
      .maybeSingle();
  return row != null;
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

/// Ids de categoría con artículos PUBLICADOS del kind dado ('producto' o
/// 'servicio'). Alimenta el filtrado de categorías «navegables» de la hoja de
/// filtros del catálogo (decisión PO 2026-08-31, paridad con la web). Sale de
/// la RPC `get_product_counts` — agregado en servidor, el mismo que usa la web
/// para su sidebar. Ante cualquier error devuelve `null`: el caller enseña la
/// lista completa (degradar a como era antes, nunca a una hoja vacía).
Future<Set<String>?> categoriasConCatalogo(String kind) async {
  try {
    final rows =
        List<Map<String, dynamic>>.from(await supa.rpc('get_product_counts'));
    return {
      for (final r in rows)
        if ((r['kind'] ?? 'producto') == kind && r['category_id'] != null)
          r['category_id'] as String,
    };
  } catch (_) {
    return null;
  }
}
