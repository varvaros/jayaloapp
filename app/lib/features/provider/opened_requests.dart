import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hasta qué VERSIÓN de cada solicitud llegó el proveedor en este dispositivo.
/// Alimenta el badge de la pestaña "Solicitudes".
///
/// Regla del PO (2026-08-22): «debe ser "lo que no has abierto"; si tiene una
/// actualización que no has abierto, cuenta». Por eso no guarda un simple
/// conjunto de "ya abiertas" —eso apagaba la marca PARA SIEMPRE, y una
/// solicitud editada después habría quedado muda— sino el `content_updated_at`
/// que tenía la fila cuando la abriste. Hay novedad cuando el CONTENIDO cambió
/// después.
///
/// ⚠️ La versión es `content_updated_at`, **nunca** `updated_at`: esa se
/// resella con cualquier UPDATE de la fila, incluido el contador de ofertas de
/// OTROS proveedores, y resucitaba solicitudes ya leídas (20 de 25 medidas el
/// 2026-08-31). La columna buena la mantiene un trigger que solo se mueve
/// cuando cambia lo que escribió el cliente (migración `20260901133140`).
///
/// **Se guarda la versión vista, no la hora a la que miraste**, a propósito: el
/// `content_updated_at` lo pone el servidor y compararlo contra
/// `DateTime.now()` del
/// teléfono metería el reloj del dispositivo en la ecuación — con un reloj
/// atrasado, una solicitud recién abierta volvería a contar como nueva. Así la
/// comparación es servidor contra servidor.
///
/// Sigue siendo una pista LOCAL, por dispositivo (decisión PO: no pagar tabla +
/// migración + RLS por un contador), y gemelo de `OpenedConversationsStore`.
class OpenedRequestsStore extends ChangeNotifier {
  static const _key = 'opened_requests_v2';
  final Map<String, DateTime> _seen = {};
  bool _loaded = false;

  /// Versión vista de cada solicitud. Solo lectura.
  Map<String, DateTime> get seen => Map.unmodifiable(_seen);

  /// ¿Le queda algo por ver? Sin abrir nunca, o cambiada desde que la abriste.
  ///
  /// [updatedAt] en null = no sabemos si cambió (la consulta best-effort
  /// falló): se cree lo que se sabe, y una solicitud ya abierta sigue vista.
  bool hasUnseen(String id, DateTime? updatedAt) {
    final visto = _seen[id];
    if (visto == null) return true;
    if (updatedAt == null) return false;
    return updatedAt.isAfter(visto);
  }

  /// ¿La CAMBIARON desde que la abriste? Es la mitad estricta de [hasUnseen]:
  /// «nunca abierta» NO cuenta aquí. Sirve para el orden de la bandeja (pedido
  /// PO 2026-09-04): «las que actualizaron algo» son un grupo propio, y una
  /// solicitud que este teléfono no ha abierto nunca no dice nada sobre si el
  /// cliente tocó algo — en un móvil recién estrenado `_seen` está vacío y
  /// TODO parecería recién cambiado.
  bool hasUpdateSinceSeen(String id, DateTime? updatedAt) {
    final visto = _seen[id];
    if (visto == null || updatedAt == null) return false;
    return updatedAt.isAfter(visto);
  }

  /// Carga lo persistido una vez. Best-effort: si falla, arranca vacío (todo
  /// cuenta como sin abrir — el badge exagera, nunca se queda corto).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((id, iso) {
          final t = DateTime.tryParse(iso as String? ?? '');
          if (t != null) _seen[id] = t.toUtc();
        });
      }
      notifyListeners();
    } catch (_) {
      // Sin persistencia se arranca vacío.
    }
  }

  /// Marca que viste la solicitud [id] tal como estaba en [updatedAt].
  ///
  /// Sin versión (fila incompleta) se guarda el epoch: cuenta como vista
  /// ahora, y cualquier cambio futuro —que sí traerá fecha— la reactivará.
  void markSeen(String id, DateTime? updatedAt) {
    final v = (updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc();
    final previo = _seen[id];
    if (previo != null && !v.isAfter(previo)) return; // idempotente
    _seen[id] = v;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({
        for (final e in _seen.entries) e.key: e.value.toIso8601String(),
      }));
    } catch (_) {
      // No bloquea la pantalla; el próximo arranque podría no recordarlo.
    }
  }

  /// Solo para tests: devuelve el store a su estado de recién nacido.
  @visibleForTesting
  void reset() {
    _seen.clear();
    _loaded = false;
  }
}

final openedRequestsStore = OpenedRequestsStore();
