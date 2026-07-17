/// Estado puro de una conversación abierta: lista cronológica de mensajes,
/// envíos optimistas pendientes, paginación por cursor compuesto
/// (created_at, id) y reconciliación con realtime. Sin Flutter ni Supabase.
library;

import 'chat.dart';

class _Pending {
  _Pending(this.tempId, this.senderId, this.kind, this.body);
  final String tempId;
  final String? senderId;
  final String kind;
  final String body;
}

class ChatSession {
  final List<ChatMessage> messages = [];
  final List<_Pending> _pending = [];
  bool hasMore = false;

  void seedFirstPage(List<Map<String, dynamic>> rowsDesc, int pageSize) {
    messages
      ..clear()
      ..addAll(rowsDesc.reversed.map(ChatMessage.fromRow));
    hasMore = rowsDesc.length >= pageSize;
  }

  /// Cursor (created_at, id) del mensaje REAL más viejo cargado.
  (String, String)? oldestCursor() {
    for (final m in messages) {
      if (m.sendStatus == SendStatus.sent) return (m.createdAtRaw, m.id);
    }
    return null;
  }

  void prependOlder(List<Map<String, dynamic>> rowsDesc, int pageSize) {
    messages.insertAll(0, rowsDesc.reversed.map(ChatMessage.fromRow));
    hasMore = rowsDesc.length >= pageSize;
  }

  String addOptimistic({required String tempId, required String? senderId, required String kind, required String body, required DateTime now}) {
    messages.add(ChatMessage(
      id: tempId,
      senderId: senderId,
      kind: kind,
      body: body,
      createdAtRaw: now.toUtc().toIso8601String(),
      sendStatus: SendStatus.sending,
    ));
    if (senderId != null) _pending.add(_Pending(tempId, senderId, kind, body));
    return tempId;
  }

  void confirmOptimistic(String tempId, Map<String, dynamic> row) {
    _pending.removeWhere((p) => p.tempId == tempId);
    final i = messages.indexWhere((m) => m.id == tempId);
    if (i >= 0) messages[i] = ChatMessage.fromRow(row);
  }

  void removeOptimistic(String tempId) {
    _pending.removeWhere((p) => p.tempId == tempId);
    messages.removeWhere((m) => m.id == tempId);
  }

  /// Mensaje llegado por realtime. true si la lista cambió.
  bool mergeServer(Map<String, dynamic> row) {
    final id = row['id'] as String;
    if (messages.any((m) => m.id == id)) return false;
    final pi = _pending.indexWhere((p) =>
        p.senderId == row['sender_id'] && p.kind == row['kind'] && p.body == row['body']);
    if (pi >= 0) {
      final tempId = _pending[pi].tempId;
      _pending.removeAt(pi);
      final mi = messages.indexWhere((m) => m.id == tempId);
      if (mi >= 0) {
        messages[mi] = ChatMessage.fromRow(row);
        return true;
      }
    }
    final msg = ChatMessage.fromRow(row);
    final at = messages.indexWhere((m) =>
        m.createdAtRaw.compareTo(msg.createdAtRaw) > 0 ||
        (m.createdAtRaw == msg.createdAtRaw && m.id.compareTo(msg.id) > 0));
    if (at < 0) {
      messages.add(msg);
    } else {
      messages.insert(at, msg);
    }
    return true;
  }

  void applyUpdate(Map<String, dynamic> row) {
    final i = messages.indexWhere((m) => m.id == row['id']);
    if (i < 0) return;
    messages[i]
      ..kind = row['kind'] as String
      ..body = row['body'] as String;
  }

  String? newestServerCreatedAtRaw() {
    for (final m in messages.reversed) {
      if (m.sendStatus == SendStatus.sent) return m.createdAtRaw;
    }
    return null;
  }

  void mergeGap(List<Map<String, dynamic>> rowsAsc) {
    for (final r in rowsAsc) {
      mergeServer(r);
    }
  }
}
