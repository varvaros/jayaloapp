import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Solicitudes que el proveedor YA ABRIÓ en este dispositivo — alimenta el
/// badge de la pestaña "Solicitudes" (pedido PO 2026-08-22: "ya abrí todas las
/// ventanas y sigue ahí").
///
/// Antes ese badge contaba el INVENTARIO de "Para ti" (`items.length`), no la
/// novedad, y no había forma de apagarlo: en todo el camino de la bandeja no
/// existía nada que marcara una solicitud como vista. Ahora el badge cuenta lo
/// que queda sin abrir, y este store es quien lo sabe.
///
/// Gemelo de [OpenedConversationsStore] (`features/chat/opened_conversations.dart`)
/// a propósito, hasta en el `ChangeNotifier`: la bandeja lo escucha y el badge
/// baja AL INSTANTE al abrir una solicitud, sin esperar a que el router
/// dispare una recarga al volver. SharedPreferences solo persiste el set entre
/// arranques.
///
/// Es una pista LOCAL, por dispositivo: si el proveedor entra desde otro
/// teléfono, esas solicitudes vuelven a contar como sin abrir. Se eligió así
/// (decisión PO) para no pagar tabla + migración + RLS por un contador.
class OpenedRequestsStore extends ChangeNotifier {
  static const _key = 'opened_requests';
  final Set<String> _ids = {};
  bool _loaded = false;

  /// Vista de solo lectura para quien calcula el badge.
  Set<String> get ids => Set.unmodifiable(_ids);

  bool contains(String id) => _ids.contains(id);

  /// Carga el set persistido una vez. Best-effort: si falla, arranca vacío
  /// (todas cuentan como sin abrir, que es el estado de antes de esta tanda).
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

  /// Marca una solicitud como abierta (idempotente). Notifica en el acto para
  /// que el badge baje ya, y persiste en segundo plano.
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
      // No bloquea la pantalla; el próximo arranque podría no recordarlo.
    }
  }

  /// Solo para tests: devuelve el store a su estado de recién nacido.
  @visibleForTesting
  void reset() {
    _ids.clear();
    _loaded = false;
  }
}

final openedRequestsStore = OpenedRequestsStore();
