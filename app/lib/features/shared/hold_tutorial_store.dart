import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestos de "mantén presionado" que el usuario YA logró en este dispositivo.
/// Alimenta el tutorial coach-mark ([HoldCoachMark]): mientras un gesto no se
/// haya logrado, el tutorial se muestra encima del botón; al primer hold
/// exitoso se marca y no vuelve a salir.
///
/// Mismo patrón que [OpenedConversationsStore]: `ChangeNotifier` en memoria +
/// `SharedPreferences` solo para persistir entre arranques. Es una pista LOCAL
/// por dispositivo (no estado de servidor): para "ya aprendió el gesto" basta y
/// evita una tabla/RPC nuevas. Best-effort: si la persistencia falla, arranca
/// vacío y el tutorial se muestra (falla hacia enseñar, nunca bloquea).
///
/// Gestos válidos: 'accept' (aceptar oferta) y 'unlock' (desbloquear contacto),
/// contados por separado.
class HoldTutorialStore extends ChangeNotifier {
  static const _key = 'hold_tutorial_done';
  final Set<String> _done = {};
  bool _loaded = false;

  bool isDone(String gesture) => _done.contains(gesture);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _done.addAll(p.getStringList(_key) ?? const <String>[]);
      notifyListeners();
    } catch (_) {
      // Sin persistencia se arranca vacío: el tutorial se mostrará.
    }
  }

  void markDone(String gesture) {
    if (_done.add(gesture)) {
      notifyListeners();
      _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _done.toList());
    } catch (_) {
      // No bloquea la acción; el próximo arranque podría mostrar el tutorial
      // una vez más.
    }
  }
}

final holdTutorialStore = HoldTutorialStore();
