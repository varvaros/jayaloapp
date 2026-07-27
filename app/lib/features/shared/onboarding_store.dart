import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repos.dart' show supa;

/// Puerto de persistencia remota del onboarding. Inyectable para testear el
/// store sin red (ver [OnboardingStore.forTest]).
abstract class OnboardingRepo {
  bool get isLoggedIn;
  Future<Set<String>> fetchCompleted();
  Future<void> markCompleted(String key);
}

/// Implementación real contra la tabla `user_onboarding_guides` (RLS filtra por
/// usuario, así que no hace falta pasar el `user_id` en el SELECT).
class SupabaseOnboardingRepo implements OnboardingRepo {
  @override
  bool get isLoggedIn => supa.auth.currentUser != null;

  @override
  Future<Set<String>> fetchCompleted() async {
    final rows = await supa.from('user_onboarding_guides').select('guide_key');
    return (rows as List).map((r) => r['guide_key'] as String).toSet();
  }

  @override
  Future<void> markCompleted(String key) async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    await supa.from('user_onboarding_guides').upsert(
      {'user_id': uid, 'guide_key': key},
      onConflict: 'user_id,guide_key',
      ignoreDuplicates: true,
    );
  }
}

/// Única fuente de verdad de "esta guía ya se vio". Carga del backend al iniciar
/// sesión, cachea local (offline + anti-parpadeo), y coordina que solo una guía
/// se muestre a la vez. Mismo espíritu que [OpenedConversationsStore], pero con
/// backend porque el requisito es cross-device.
class OnboardingStore extends ChangeNotifier {
  OnboardingStore(this._repo);

  @visibleForTesting
  OnboardingStore.forTest(this._repo);

  static const _cacheKey = 'onboarding_guides';
  static const _oldHoldKey = 'hold_tutorial_done';
  static const _importFlag = 'onboarding_hold_imported';

  final OnboardingRepo _repo;
  final Set<String> _done = {};
  bool _loaded = false;
  bool _suppressed = false;
  String? _active;

  bool isDone(String key) => _suppressed || _done.contains(key);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    // Todo el acceso a prefs (incluido getInstance) va adentro del try: si
    // falla, se trata como "sin cache local" y el fail-safe de abajo decide
    // si se suprime o no — nunca debe propagar y dejar el store atascado con
    // `_loaded = true` pero sin datos.
    SharedPreferences? prefs;
    var hadLocal = false;
    try {
      prefs = await SharedPreferences.getInstance();
      final localCache = prefs.getStringList(_cacheKey);
      if (localCache != null) {
        hadLocal = true;
        _done.addAll(localCache);
      }
    } catch (_) {
      // Sin prefs se arranca como si no hubiera cache local.
    }

    if (_repo.isLoggedIn) {
      try {
        _done.addAll(await _repo.fetchCompleted());
      } catch (_) {
        // Sin cache local NO mostramos nada esta sesión (evitar spamear por un
        // error de red en un dispositivo fresco). Con cache seguimos con él.
        if (!hadLocal) _suppressed = true;
      }
    } else {
      _suppressed = true; // sin usuario, sin guías
    }

    await _importOldHoldFlag(prefs);
    await _persist();
    notifyListeners();
  }

  /// Traduce el flag local del coach-mark viejo a claves versionadas, una sola
  /// vez, para no re-enseñar el gesto a quien ya lo domina. Reusa la instancia
  /// de prefs de [ensureLoaded] si está disponible; si no (falló arriba),
  /// intenta la suya propia y también degrada sin propagar.
  Future<void> _importOldHoldFlag(SharedPreferences? prefs) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      if (p.getBool(_importFlag) == true) return;
      final old = p.getStringList(_oldHoldKey) ?? const [];
      for (final g in old) {
        final key = 'gesture.$g.v1';
        if (_done.add(key)) {
          try {
            await _repo.markCompleted(key);
          } catch (_) {/* best-effort */}
        }
      }
      await p.setBool(_importFlag, true);
    } catch (_) {/* best-effort */}
  }

  Future<void> markDone(String key) async {
    if (!_done.add(key)) return;
    notifyListeners();
    await _persist();
    try {
      await _repo.markCompleted(key);
    } catch (_) {/* el cache local ya evita re-mostrar en este device */}
  }

  /// Recarga pública (p. ej. al iniciar sesión otro usuario). Limpia el estado y
  /// vuelve a leer del backend. `_importFlag` en prefs evita re-importar el flag
  /// viejo del gesto. Limpia `_active` también: si una guía había quedado
  /// mostrándose para el usuario anterior, no debe bloquear al nuevo.
  Future<void> reload() async {
    _done.clear();
    _loaded = false;
    _suppressed = false;
    _active = null;
    await ensureLoaded();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_cacheKey, _done.toList());
    } catch (_) {/* no bloquea */}
  }

  // --- Coordinador: solo una guía visible a la vez ---
  bool acquire(String key) {
    if (_active == null || _active == key) {
      _active = key;
      return true;
    }
    return false;
  }

  void release(String key) {
    if (_active == key) {
      _active = null;
      notifyListeners(); // las guías en espera reintentan
    }
  }

  @visibleForTesting
  void reset() {
    _done.clear();
    _loaded = false;
    _suppressed = false;
    _active = null;
  }
}

final OnboardingStore onboardingStore = OnboardingStore(SupabaseOnboardingRepo());
