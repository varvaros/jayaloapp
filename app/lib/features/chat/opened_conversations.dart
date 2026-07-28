import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conversaciones que el usuario YA ABRIÓ en este dispositivo — alimenta el chip
/// "Nueva" de la lista de mensajes (pedido PO 2026-07-23: la etiqueta se quita
/// al ENTRAR al chat, no solo al escribir).
///
/// Es un `ChangeNotifier` en memoria (mismo patrón que [funnelStatusStore]): la
/// lista lo escucha con `addListener` y se repinta AL INSTANTE cuando el chat
/// marca una conversación abierta — sin depender de que el reload por router al
/// volver dispare (poco fiable) ni de una relectura de disco con posible
/// carrera. SharedPreferences solo persiste el set entre arranques. Es una pista
/// LOCAL (por dispositivo), no estado de servidor: para "ya viste esta
/// conversación" basta, y evita una tabla/RPC nuevas.
class OpenedConversationsStore extends ChangeNotifier {
  static const _key = 'opened_conversations';
  final Set<String> _ids = {};
  bool _loaded = false;

  bool contains(String id) => _ids.contains(id);

  /// Carga el set persistido una vez. Best-effort: si falla, arranca vacío
  /// (todas se muestran como "Nueva").
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _ids.addAll(p.getStringList(_key) ?? const <String>[]);
      notifyListeners();
    } catch (_) {
      // Sin persistencia se arranca vacío.
    }
  }

  /// Marca una conversación como abierta (idempotente). Notifica en el acto
  /// para que la lista se repinte y persiste en segundo plano.
  void markOpened(String id) {
    if (_ids.add(id)) {
      notifyListeners();
      _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _ids.toList());
    } catch (_) {
      // No bloquea el chat; el próximo arranque podría no recordarlo.
    }
  }
}

final openedConversationsStore = OpenedConversationsStore();

/// Conversación que el usuario tiene ABIERTA en pantalla ahora mismo (null si
/// ninguna). La fija `ChatScreen` mientras vive.
///
/// La lee `initPush`: cuando entra un push de mensaje con la app en foreground,
/// si es de ESTA conversación el sonido ya lo pone la pantalla al recibirlo por
/// realtime — sonar también desde el push lo duplicaría. Es una variable pelada
/// a propósito (no un ChangeNotifier): nadie se repinta con esto, solo se
/// consulta en el instante en que llega el push.
String? activeConversationId;
