/// Dominio puro del chat — espejo de la lógica de
/// `src/routes/messages.$conversationId.tsx` (web). Sin Flutter ni Supabase.
library;

import 'dart:convert';
import 'chat_time.dart';

const int maxMessageLen = 1000;

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

/// Trim + quita caracteres de control + cap a [maxMessageLen]
/// (espejo de sanitizeUserText + slice de la web).
String sanitizeChatText(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .trim();
  return cleaned.length > maxMessageLen ? cleaned.substring(0, maxMessageLen) : cleaned;
}

// ── Imagen ──────────────────────────────────────────────────────────────────

final _dataImg = RegExp(r'^data:image/(png|jpe?g|webp|gif|svg\+xml);base64,', caseSensitive: false);

bool isRenderableImageSrc(String src) {
  if (_dataImg.hasMatch(src)) return true;
  final uri = Uri.tryParse(src);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

// ── Quick messages ──────────────────────────────────────────────────────────

class QuickPayload {
  const QuickPayload({required this.question, required this.options, this.selected, this.answeredBy});
  final String question;
  final List<String> options;
  final String? selected;
  final String? answeredBy;
}

QuickPayload? parseQuick(String body) {
  try {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final q = m['question'];
    if (q is! String) return null;
    return QuickPayload(
      question: q,
      options: List<String>.from((m['options'] as List?) ?? const []),
      selected: m['selected'] as String?,
      answeredBy: m['answered_by'] as String?,
    );
  } catch (_) {
    return null;
  }
}

String answerQuickBody(QuickPayload p, String option, String userId) => jsonEncode({
      'question': p.question,
      'options': p.options,
      'selected': option,
      'answered_by': userId,
    });

class QuickItem {
  const QuickItem(this.question, [this.options = const [], this.replies = const {}]);
  final String question;
  final List<String> options;
  final Map<String, String> replies;
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
