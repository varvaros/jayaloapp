import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repos.dart' show supa;

/// Puerto de persistencia remota del onboarding. Inyectable para testear el
/// store sin red (ver [OnboardingStore.forTest]).
abstract class OnboardingRepo {
  bool get isLoggedIn;

  /// Id del usuario actual (o `null` sin sesión). Usado para namespacear el
  /// cache local por usuario — en un teléfono compartido, el cache global
  /// mezclaba las guías "vistas" de un usuario con las del siguiente que
  /// inicia sesión.
  String? get currentUserId;
  Future<Set<String>> fetchCompleted();
  Future<void> markCompleted(String key);

  /// Borra TODAS las guías vistas del usuario. Lo usa "Reiniciar tutorial"
  /// (Ajustes): sin esto, limpiar el cache local no serviría de nada — el
  /// siguiente `fetchCompleted` volvería a traerlas del backend.
  Future<void> clearCompleted();
}

/// Implementación real contra la tabla `user_onboarding_guides` (RLS filtra por
/// usuario, así que no hace falta pasar el `user_id` en el SELECT).
class SupabaseOnboardingRepo implements OnboardingRepo {
  @override
  bool get isLoggedIn => supa.auth.currentUser != null;

  @override
  String? get currentUserId => supa.auth.currentUser?.id;

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

  @override
  Future<void> clearCompleted() async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    // El `eq` es redundante con la política de RLS (`user_id = auth.uid()`),
    // pero PostgREST rechaza un DELETE sin filtro: hay que nombrarlo igual.
    await supa.from('user_onboarding_guides').delete().eq('user_id', uid);
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

  /// Namespaceado por usuario (fix: en un teléfono compartido, la clave
  /// global mezclaba el cache de "guías vistas" de un usuario con el del
  /// siguiente que inicia sesión en el mismo device). Sin usuario ('anon'),
  /// cache separado también.
  String get _cacheKey => 'onboarding_guides_${_repo.currentUserId ?? 'anon'}';
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

  /// Cuántas veces se ha reiniciado el tutorial en esta sesión. Las guías lo
  /// miran para distinguir "el store ya no me tiene por vista" (que también
  /// pasa por un instante entre cerrar una guía y persistirla) de "el usuario
  /// pidió empezar de cero". Sin esta distinción, una guía recién descartada
  /// resucitaba sola en ese hueco.
  int get resetGeneration => _resetGeneration;
  int _resetGeneration = 0;

  /// "Reiniciar tutorial" (Ajustes): olvida TODAS las guías vistas — backend,
  /// cache local y memoria — para que la ayuda de cada botón vuelva a salir
  /// desde cero. Las guías montadas ahora mismo se enteran por el
  /// `notifyListeners` y vuelven a pedir turno sin salir de la pantalla.
  ///
  /// El borrado remoto va PRIMERO y sin tragar el error: si falla, no se
  /// limpia nada — un reinicio que solo borra el cache local revive al
  /// siguiente `fetchCompleted` y el usuario creería que la app le mintió.
  Future<void> resetAll() async {
    await _repo.clearCompleted();
    _resetGeneration++;
    _done.clear();
    _suppressed = false;
    _active = null;
    _candidates.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cacheKey);
      // También el flag viejo del gesto de mantener pulsado: si sobreviviera,
      // `_importOldHoldFlag` volvería a marcar esas guías como vistas.
      await p.remove(_oldHoldKey);
    } catch (_) {/* el borrado remoto ya es la fuente de verdad */}
    notifyListeners();
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
    _candidates.clear();
    await ensureLoaded();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_cacheKey, _done.toList());
    } catch (_) {/* no bloquea */}
  }

  // --- Coordinador ORDENADO: una guía visible a la vez, por prioridad. Las
  // guías se registran como candidatas con su `order`; el turno se concede (en
  // `resolvePending`, que las guías llaman en un post-frame — ventana de
  // recolección de un frame) a la de MENOR `order`. Al liberar, entra la
  // siguiente de menor orden.
  final Map<String, int> _candidates = {};

  /// Registra la guía [key] como candidata con prioridad [order]. No concede el
  /// turno de inmediato: se resuelve en [resolvePending].
  void requestSlot(String key, int order) {
    if (_active == key) return;
    _candidates[key] = order;
  }

  /// Concede el turno a la candidata de MENOR `order` si no hay ninguna activa.
  /// Idempotente. En producción la llaman las guías en un post-frame; en tests
  /// se llama a mano.
  void resolvePending() {
    if (_active != null || _candidates.isEmpty) return;
    var best = _candidates.keys.first;
    var bestOrder = _candidates[best]!;
    _candidates.forEach((k, o) {
      if (o < bestOrder) {
        best = k;
        bestOrder = o;
      }
    });
    _active = best;
    _candidates.clear();
    notifyListeners();
  }

  bool isActive(String key) => _active == key;

  /// Saca a [key] de la cola; si era la activa, libera el turno y reevalúa (las
  /// guías en espera reintentan pedir turno vía su listener).
  void withdraw(String key) {
    _candidates.remove(key);
    if (_active == key) {
      _active = null;
      notifyListeners();
    }
  }

  /// "Terminé de mostrarme": alias de [withdraw] para la guía activa.
  void release(String key) => withdraw(key);

  /// Igual que [resetAll] pero sin backend ni prefs: para tests. Sube la
  /// generación por la misma razón que [resetAll] — una guía ya montada tiene
  /// que volver a estar pendiente.
  @visibleForTesting
  void reset() {
    _resetGeneration++;
    _done.clear();
    _loaded = false;
    _suppressed = false;
    _active = null;
    _candidates.clear();
    notifyListeners(); // como `resetAll`: las guías montadas deben enterarse
  }
}

final OnboardingStore onboardingStore = OnboardingStore(SupabaseOnboardingRepo());
