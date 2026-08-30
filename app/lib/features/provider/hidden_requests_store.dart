import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Solicitudes que el proveedor OCULTÓ de su bandeja con el swipe «Ocultar»
/// («cuando no interesa una solicitud», pedido PO 2026-08-10).
///
/// Pista LOCAL por dispositivo (mismo patrón que `openedConversationsStore`):
/// ocultar NO toca el servidor — la solicitud sigue viva para el resto del
/// marketplace y para las métricas; solo deja de estorbar en esta bandeja.
/// SharedPreferences persiste el set entre arranques; el `ChangeNotifier`
/// repinta la lista al instante (el «Deshacer» del toast la revive igual de
/// rápido).
class HiddenRequestsStore extends ChangeNotifier {
  static const _key = 'hidden_requests';
  final Set<String> _ids = {};
  bool _loaded = false;

  bool contains(String id) => _ids.contains(id);

  /// Copia del set para pasárselo a `loadInboxData`, que lo necesita entero
  /// para descontarlo del badge. Se copia en vez de exponer `_ids` para que
  /// nadie de fuera pueda ocultar una solicitud sin pasar por [hide].
  Set<String> get ids => Set.unmodifiable(_ids);

  /// Carga el set persistido una vez. Best-effort: si falla, arranca vacío
  /// (no se oculta nada — el fallo nunca esconde solicitudes por accidente).
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

  /// Oculta una solicitud (idempotente). Notifica en el acto y persiste en
  /// segundo plano.
  void hide(String id) {
    if (_ids.add(id)) {
      notifyListeners();
      _persist();
    }
  }

  /// La vuelta atrás del «Deshacer» del toast.
  void unhide(String id) {
    if (_ids.remove(id)) {
      notifyListeners();
      _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _ids.toList());
    } catch (_) {
      // No bloquea el gesto; el próximo arranque podría no recordarlo.
    }
  }
}

final hiddenRequestsStore = HiddenRequestsStore();
