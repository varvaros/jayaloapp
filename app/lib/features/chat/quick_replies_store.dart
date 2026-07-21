import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../data/repos.dart';
import '../../domain/chat.dart';

/// Estado COMPARTIDO de las respuestas rápidas efectivas del usuario (pedido
/// PO: editables por usuario, partiendo de los defaults). Arranca con los
/// defaults; [ensureLoaded] trae lo personalizado de `profiles` una sola vez;
/// el editor guarda y este store se refresca para que el composer lo refleje.
/// Sin socket: se recarga al montar el composer / el editor y en cada guardado.
class QuickRepliesStore extends ChangeNotifier {
  QuickRepliesStore() {
    // Al cerrar sesión, no arrastrar las respuestas del usuario anterior. En
    // try/catch porque es global y en widget-tests Supabase no está init.
    try {
      supa.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.signedOut) clear();
      });
    } catch (_) {}
  }

  List<QuickItem> _customer = defaultQuickReplies(provider: false);
  List<QuickItem> _provider = defaultQuickReplies(provider: true);
  bool _loaded = false;
  bool _loading = false;

  /// Lista efectiva para el rol del que escribe en ESA conversación.
  List<QuickItem> forProvider(bool provider) => provider ? _provider : _customer;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    try {
      final stored = await fetchCustomQuickReplies();
      _customer = quickRepliesFromStored(stored, provider: false);
      _provider = quickRepliesFromStored(stored, provider: true);
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Best-effort: se quedan los defaults.
    } finally {
      _loading = false;
    }
  }

  Future<void> save({
    required bool provider,
    required List<QuickItem> items,
  }) async {
    await saveCustomQuickReplies(provider: provider, items: items);
    if (provider) {
      _provider = List.of(items);
    } else {
      _customer = List.of(items);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Restaura los defaults del rol (quita la personalización en el servidor).
  Future<void> resetToDefaults({required bool provider}) async {
    await resetCustomQuickReplies(provider: provider);
    if (provider) {
      _provider = defaultQuickReplies(provider: true);
    } else {
      _customer = defaultQuickReplies(provider: false);
    }
    notifyListeners();
  }

  void clear() {
    _customer = defaultQuickReplies(provider: false);
    _provider = defaultQuickReplies(provider: true);
    _loaded = false;
    notifyListeners();
  }
}

final quickRepliesStore = QuickRepliesStore();
