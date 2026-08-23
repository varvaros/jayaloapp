/// Dominio puro del chat — espejo de la lógica de
/// `src/routes/messages.$conversationId.tsx` (web). Sin Flutter ni Supabase.
library;

import 'dart:convert';
import 'chat_time.dart';

/// Tope de un mensaje de chat. Bajado de 1000 a 300 (pedido PO 2026-07-28):
/// el chat es para coordinar, no para parrafadas, y un tope corto acota de paso
/// lo que un flood puede meter por mensaje. Mantener en paridad con
/// `MAX_MESSAGE_LEN` de `src/routes/messages.$conversationId.tsx` (web).
const int maxMessageLen = 300;

enum SendStatus { sent, sending }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.createdAtRaw,
    this.sendStatus = SendStatus.sent,
  }) : createdAt = DateTime.parse(createdAtRaw).toLocal();

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
        id: row['id'] as String,
        senderId: row['sender_id'] as String?,
        kind: row['kind'] as String,
        body: row['body'] as String,
        createdAtRaw: row['created_at'] as String,
      );

  final String id;
  final String? senderId;
  String kind;
  String body;
  final String createdAtRaw;
  final DateTime createdAt;
  SendStatus sendStatus;
}

bool isSystemKind(String kind) => kind == 'system' || kind == 'audit';

bool needsDaySep(List<ChatMessage> ms, int i) =>
    i == 0 || dayKey(ms[i - 1].createdAt) != dayKey(ms[i].createdAt);

bool isGroupEnd(List<ChatMessage> ms, int i) {
  if (i >= ms.length - 1) return true;
  final n = ms[i + 1];
  return n.senderId != ms[i].senderId ||
      isSystemKind(n.kind) ||
      dayKey(n.createdAt) != dayKey(ms[i].createdAt);
}

// ── Texto ───────────────────────────────────────────────────────────────────

/// Trim + quita caracteres de control + cap a [maxMessageLen]. Espejo de
/// `sanitizeChatText` + `truncateByCodePoints` de la web: los emojis se
/// CONSERVAN (nunca se borraron aquí) y el corte va por runas.
///
/// `substring` cuenta unidades UTF-16, así que partía en dos el emoji que cayera
/// en el carácter 300 y dejaba media pareja suelta; al codificar salía un
/// carácter roto al final del mensaje.
String sanitizeChatText(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .trim();
  final runas = cleaned.runes.toList();
  return runas.length > maxMessageLen
      ? String.fromCharCodes(runas.take(maxMessageLen))
      : cleaned;
}

/// SQLSTATE propio del anti-flood del servidor (trigger
/// `enforce_chat_message_rate_limit`, migración 20260728120000): 10 mensajes
/// por 30 s y emisor.
const String chatRateLimitCode = 'JY429';

/// SQLSTATE de `check_violation`: lo lanza el mismo trigger cuando un 'text'
/// pasa de [maxMessageLen] (red server-side del tope del composer).
const String chatCheckViolationCode = '23514';

/// SQLSTATE `insufficient_privilege`: es lo que devuelve PostgREST cuando la
/// RLS rechaza la fila ("new row violates row-level security policy"). En el
/// envío de un mensaje la causa realista es UNA: la política
/// `Participants can send messages when open` exige `conversations.status =
/// 'abierto'`, así que la conversación se cerró mientras la teníamos delante.
const String chatPermissionDeniedCode = '42501';

/// ¿Hay que RELEER la conversación antes de decidir el aviso de un envío que
/// rebotó? Solo ante un rechazo de la RLS: es la señal de que la conversación
/// probablemente se cerró mientras la teníamos delante, y sin releer el aviso
/// mentiría ("intenta de nuevo" contra una puerta cerrada).
///
/// Pura y pública para poder fijar el disparador en un test: el camino completo
/// (`_send` → 42501 → `_reload` → `!_isOpen` → aviso) vive en `ChatScreen`, que
/// no se puede montar en un widget-test porque su `initState` toca Supabase.
bool shouldRecheckConversation(String? code) =>
    code == chatPermissionDeniedCode;

/// Qué mostrarle al usuario cuando rebota un envío. Si el rechazo viene de una
/// de NUESTRAS guardas, el servidor ya manda una explicación en español
/// ("Vas muy rápido…") y repetirla es mucho mejor que el genérico: "intenta de
/// nuevo" invita a reintentar justo lo que acaba de rebotar.
///
/// [conversationClosed] lo pasa la pantalla DESPUÉS de releer la conversación:
/// un chat cerrado no se arregla reintentando, y decir "intenta de nuevo" ahí
/// manda al usuario a golpear una puerta cerrada (bug del PO 2026-07-31: el
/// cron de inactividad cerró el chat a las 72 h y el composer seguía pintado).
/// Para cualquier otro fallo (red, permisos de otra causa) se queda el
/// genérico, que no filtra detalles internos.
String sendFailureMessage({
  String? code,
  String? serverMessage,
  bool conversationClosed = false,
}) {
  final msg = serverMessage?.trim() ?? '';
  if ((code == chatRateLimitCode || code == chatCheckViolationCode) &&
      msg.isNotEmpty) {
    return msg;
  }
  if (conversationClosed) {
    return 'Esta conversación está cerrada: ya no se pueden enviar mensajes.';
  }
  return 'No se pudo enviar. Intenta de nuevo.';
}

/// SQLSTATE de un `RAISE EXCEPTION` de nuestras propias funciones. Todo lo que
/// levantan `propose_scheduled_date` / `respond_scheduled_date` con este código
/// ya viene REDACTADO EN ESPAÑOL para el usuario («La fecha debe ser futura»,
/// «La otra parte es quien confirma la fecha»…).
const String chatRaiseExceptionCode = 'P0001';

/// Qué mostrarle al usuario cuando rebota una acción de fecha pautada. Mismo
/// criterio que [sendFailureMessage]: se repite el texto del servidor SOLO
/// cuando viene de una guarda NUESTRA —[chatRaiseExceptionCode] (las RPCs de la
/// fecha pautada) y [chatRateLimitCode] (el anti-inundación del chat, que la
/// tarjeta también consume)—, y para todo lo demás se queda el genérico.
///
/// No es cosmética: sin esta reja, un `PGRST202` («Could not find the function
/// public.propose_scheduled_date in the schema cache» — lo que pasa si un APK
/// llega al teléfono ANTES de que se aplique la migración, cosa que ya ha
/// mordido en este repo), un `42501` o un error de JWT le salen al usuario
/// dominicano en inglés y con tripas del servidor dentro.
String appointmentFailureMessage({
  String? code,
  String? serverMessage,
  required String fallback,
}) {
  final msg = serverMessage?.trim() ?? '';
  if ((code == chatRaiseExceptionCode || code == chatRateLimitCode) &&
      msg.isNotEmpty) {
    return msg;
  }
  return fallback;
}

// ── Imagen ──────────────────────────────────────────────────────────────────

final _dataImg = RegExp(r'^data:image/(png|jpe?g|webp|gif|svg\+xml);base64,', caseSensitive: false);

/// Prefijo que marca el `body` de una imagen como RUTA dentro del bucket privado
/// `chat-media`, en vez de una URL. Espejo de `CHAT_MEDIA_PREFIX` de la web
/// (`src/lib/image/uploadRequestImage.ts`).
///
/// El bucket es privado desde el 2026-07-31, así que no hay URL pública que
/// guardar: hay que pedir una firmada antes de pintar. Por eso
/// [isRenderableImageSrc] sigue diciendo `false` para el marcador — se resuelve
/// ANTES de llegar ahí. Guardar la URL firmada en el `body` no vale: caduca.
const chatMediaPrefix = 'chat-media:';

bool isChatMediaMarker(String body) => body.startsWith(chatMediaPrefix);

/// La ruta dentro del bucket, sin el prefijo.
String chatMediaPath(String body) =>
    isChatMediaMarker(body) ? body.substring(chatMediaPrefix.length) : body;

bool isRenderableImageSrc(String src) {
  if (_dataImg.hasMatch(src)) return true;
  final uri = Uri.tryParse(src);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

// ── Quick messages ──────────────────────────────────────────────────────────

class QuickPayload {
  const QuickPayload(
      {required this.question,
      required this.options,
      this.selected,
      this.answeredBy,
      this.replies = const {}});
  final String question;
  final List<String> options;
  final String? selected;
  final String? answeredBy;

  /// Mapa opción→frase de confirmación que VIAJA en el payload (para que las
  /// respuestas rápidas EDITADAS por el usuario se confirmen con su texto, aun
  /// cuando el que contesta no tiene esa pregunta en sus defaults). Vacío en
  /// payloads viejos/web → se cae al lookup por defaults.
  final Map<String, String> replies;
}

QuickPayload? parseQuick(String body) {
  try {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final q = m['question'];
    if (q is! String) return null;
    final rawReplies = m['replies'];
    return QuickPayload(
      question: q,
      options: List<String>.from((m['options'] as List?) ?? const []),
      selected: m['selected'] as String?,
      answeredBy: m['answered_by'] as String?,
      replies: rawReplies is Map
          ? rawReplies.map((k, v) => MapEntry('$k', '$v'))
          : const {},
    );
  } catch (_) {
    return null;
  }
}

/// Cuerpo de un mensaje 'quick' recién ENVIADO (sin responder). Incluye
/// `replies` para que la confirmación honre el texto personalizado del emisor.
String quickSendBody(QuickItem item) => jsonEncode({
      'question': item.question,
      'options': item.options,
      'selected': null,
      'answered_by': null,
      if (item.replies.isNotEmpty) 'replies': item.replies,
    });

String answerQuickBody(QuickPayload p, String option, String userId) => jsonEncode({
      'question': p.question,
      'options': p.options,
      'selected': option,
      'answered_by': userId,
      if (p.replies.isNotEmpty) 'replies': p.replies,
    });

class QuickItem {
  const QuickItem(this.question, [this.options = const [], this.replies = const {}]);
  final String question;
  final List<String> options;
  final Map<String, String> replies;

  Map<String, dynamic> toJson() => {
        'question': question,
        if (options.isNotEmpty) 'options': options,
        if (replies.isNotEmpty) 'replies': replies,
      };

  /// Tolerante: una entrada guardada sin `question` válido se descarta (null).
  static QuickItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final q = raw['question'];
    if (q is! String || q.trim().isEmpty) return null;
    final options =
        (raw['options'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final replies = (raw['replies'] is Map)
        ? (raw['replies'] as Map).map((k, v) => MapEntry('$k', '$v'))
        : const <String, String>{};
    return QuickItem(q.trim(), options, replies);
  }
}

/// Preguntas que envía el CLIENTE; las contesta el proveedor. Copy exacto web.
const quickReplies = <QuickItem>[
  QuickItem('¿Es nuevo o usado?', ['Nuevo', 'Usado'],
      {'Nuevo': 'Es nuevo', 'Usado': 'Es usado'}),
  QuickItem('¿Ustedes lo instalan?', ['Sí', 'No'],
      {'Sí': 'Sí, lo instalamos', 'No': 'No, no lo instalamos'}),
  QuickItem('¿Qué tipos de pago aceptan?', ['Efectivo', 'Transferencia', 'Tarjeta', 'Todos'], {
    'Efectivo': 'Aceptamos efectivo',
    'Transferencia': 'Aceptamos transferencia',
    'Tarjeta': 'Aceptamos tarjeta',
    'Todos': 'Aceptamos todos los métodos de pago',
  }),
  QuickItem('¿Tienen envío a domicilio?', ['Sí', 'No'],
      {'Sí': 'Sí, tenemos envío a domicilio', 'No': 'No, no tenemos envío'}),
  QuickItem('¿Qué tiempo de entrega manejan?', ['Hoy mismo', '1-2 días', '3-5 días', 'Más de 5 días'], {
    'Hoy mismo': 'Lo entregamos hoy mismo',
    '1-2 días': 'Lo entregamos en 1-2 días',
    '3-5 días': 'Lo entregamos en 3-5 días',
    'Más de 5 días': 'Lo entregamos en más de 5 días',
  }),
  QuickItem('¿Tiene algún defecto o rayón?', ['Sí', 'No'],
      {'Sí': 'Sí, tiene algún defecto o rayón', 'No': 'No, está en perfectas condiciones'}),
  QuickItem('¿Es original?', ['Sí', 'No'],
      {'Sí': 'Sí, es original', 'No': 'No, no es original'}),
  QuickItem('¿El precio incluye materiales?', ['Sí', 'No'],
      {'Sí': 'Sí, el precio incluye materiales', 'No': 'No, el precio no incluye materiales'}),
];

/// Preguntas que envía el PROVEEDOR; las contesta el cliente. Copy exacto web.
const providerReplies = <QuickItem>[
  QuickItem('¿La quiere por envío o pasará por nuestro local?', ['Por envío', 'Pasaré por el local'],
      {'Por envío': 'La quiero por envío', 'Pasaré por el local': 'Pasaré por el local'}),
  QuickItem('¿Cuál color le gustaría?', ['Negro', 'Blanco', 'Gris', 'Azul', 'Rojo', 'Otro'], {
    'Negro': 'Lo quiero en negro',
    'Blanco': 'Lo quiero en blanco',
    'Gris': 'Lo quiero en gris',
    'Azul': 'Lo quiero en azul',
    'Rojo': 'Lo quiero en rojo',
    'Otro': 'Me gustaría otro color',
  }),
  QuickItem('¿Lo quiere nuevo o usado?', ['Nuevo', 'Usado'],
      {'Nuevo': 'Lo quiero nuevo', 'Usado': 'Lo quiero usado'}),
  QuickItem('¿Cómo le gustaría pagar?', ['Efectivo', 'Transferencia', 'Tarjeta'], {
    'Efectivo': 'Pagaré en efectivo',
    'Transferencia': 'Pagaré por transferencia',
    'Tarjeta': 'Pagaré con tarjeta',
  }),
  QuickItem('¿Me envía su dirección, por favor?'),
  QuickItem('¡Listo! Gracias por su compra 🙌'),
];

/// Los defaults de la app para un rol (semilla del editor y respaldo si el
/// usuario no ha personalizado nada).
List<QuickItem> defaultQuickReplies({required bool provider}) =>
    provider ? providerReplies : quickReplies;

/// Traduce lo GUARDADO en `profiles.custom_quick_replies` (jsonb
/// `{"customer":[...],"provider":[...]}`) a la lista efectiva de un rol. Si la
/// clave del rol no existe o queda vacía tras filtrar entradas inválidas, se
/// cae a los defaults (nunca deja al usuario sin respuestas rápidas).
List<QuickItem> quickRepliesFromStored(dynamic stored, {required bool provider}) {
  final key = provider ? 'provider' : 'customer';
  if (stored is Map && stored[key] is List) {
    final items = (stored[key] as List)
        .map(QuickItem.fromJson)
        .whereType<QuickItem>()
        .toList();
    if (items.isNotEmpty) return items;
  }
  return defaultQuickReplies(provider: provider);
}

String quickConfirmation(String question, String option) {
  for (final item in [...quickReplies, ...providerReplies]) {
    if (item.question == question) return item.replies[option] ?? option;
  }
  return option;
}

// ── Saludo / auditoría / notificaciones ────────────────────────────────────

String buildGreeting(String template,
        {required String firstName, required String business, required String product, required String priceTxt}) =>
    template
        .replaceAll('{first_name}', firstName)
        .replaceAll('{business}', business)
        .replaceAll('{product}', product)
        .replaceAll('{price}', priceTxt);

bool needsAudit({required String status, required DateTime createdAt, required bool hasAudit, required DateTime now}) =>
    status == 'abierto' && !hasAudit && now.difference(createdAt) >= const Duration(hours: 72);

/// Gotcha #14: el convId viene SOLO en el link (`/messages?c=<id>` actual,
/// `/messages/<id>` legado) — NUNCA en entity_id.
String? convIdFromMessageLink(String? link) {
  if (link == null) return null;
  if (link.startsWith('/messages?c=')) {
    final id = link.substring('/messages?c='.length);
    return id.isEmpty ? null : id;
  }
  if (link.startsWith('/messages/')) {
    final id = link.substring('/messages/'.length);
    return id.isEmpty ? null : id;
  }
  return null;
}

/// Los 40 emojis del popover de la web, en el mismo orden.
const chatEmojis = <String>[
  '😀','😄','😅','😉','😊','😍','🤩','😘','😎','🤔',
  '🙌','👍','👎','👏','🙏','💪','🤝','✌️','👌','🫶',
  '❤️','🔥','✨','🎉','💯','✅','❌','⚠️','📦','🚚',
  '💰','💵','🛒','🏷️','📍','📞','💬','⏰','📷','🎁',
];

/// Caption de un producto/servicio de MI TIENDA enviado al chat (pedido PO
/// 2026-07-21: el proveedor comparte artículos "que carguen con algunos
/// detalles"). Mismo patrón que `PortfolioChatButton` de la web: la IMAGEN va
/// en un mensaje `kind 'image'` (body = URL) y los detalles en un `text`
/// aparte — este es ese texto. Puro para poder testearlo sin Flutter.
String storeItemChatCaption(
  Map<String, dynamic> item, {
  required String priceLabel,
}) {
  final isService = item['kind'] == 'servicio';
  final name = (item['name'] as String? ?? '').trim();
  final desc = (item['description'] as String? ?? '').trim();
  final condition = item['condition'] as String?;
  final lines = <String>[
    '${isService ? '🛠️' : '🛍️'} De mi tienda: $name',
    'Precio: $priceLabel',
    if (!isService && condition == 'nuevo') 'Estado: Nuevo',
    if (!isService && condition == 'usado') 'Estado: Usado',
    if (item['offers_shipping'] == true) '🚚 Con traslado disponible',
    if (item['offers_installation'] == true) '🔧 Con instalación',
    if (desc.isNotEmpty) desc.length > 240 ? desc.substring(0, 240) : desc,
  ];
  return lines.join('\n');
}
