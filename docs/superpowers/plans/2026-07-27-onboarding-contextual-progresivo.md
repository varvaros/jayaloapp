# Onboarding contextual y progresivo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sistema reutilizable de guías tipo spotlight que se muestran la primera vez que el usuario entra a cada sección de la app, con estado persistido por usuario en Supabase (sobrevive logout y cambio de dispositivo), absorbiendo el coach-mark de "mantén presionado" que hoy es local.

**Architecture:** Un `OnboardingStore` (`ChangeNotifier`) es la única fuente de verdad: carga las claves completadas desde una tabla de Supabase al iniciar sesión, cachea local para offline/anti-parpadeo, y expone `isDone(key)`/`markDone(key)`. Un widget `OnboardingGuide` generaliza el spotlight de `HoldCoachMark` (velo + elemento resaltado + tarjeta + botones, con fallback de anclaje). Cada pantalla envuelve su elemento objetivo con `OnboardingGuide`. El coach-mark de gesto se migra a consultar `OnboardingStore` con claves versionadas.

**Tech Stack:** Flutter, `supabase_flutter`, `shared_preferences`, `OverlayPortal` + `LayerLink`/`CompositedTransformFollower`. Tests con `flutter_test` + `SharedPreferences.setMockInitialValues` + repo falso inyectado.

## Global Constraints

- Plataforma: solo Flutter (app `jayalo-app`) + una migración Supabase. Web fuera de alcance.
- Proyecto Supabase: `mfaiklvobnvgusbcssbx`. Migración vía **MCP de Supabase** (autorizado).
- Grants mínimo privilegio: `authenticated` = SELECT + INSERT; **REVOKE** de `anon`, `PUBLIC`. Sin UPDATE/DELETE. Verificar `anon` bloqueado.
- Mantener la suite verde (hoy **428/428**) y `flutter analyze` en **0** al cerrar cada tarea.
- Clave de guía versionada (`.v1`) como `text`, nunca booleano fijo.
- Fail-safe: si el fetch inicial del estado falla en un dispositivo sin cache, **no** se muestran guías esa sesión.
- **No hacer push**: el push a `origin/feat/error-tracking` lo decide el PO. Commits locales sí.
- Comandos Flutter desde `C:/Users/ac/Downloads/jayalo-app/app`.

---

## File Structure

- `supabase/migrations/20260727000000_user_onboarding_guides.sql` — **crear**: tabla + RLS + grants.
- `app/lib/features/shared/onboarding_store.dart` — **crear**: `OnboardingRepo` (abstracto), `SupabaseOnboardingRepo`, `OnboardingStore`, singleton `onboardingStore`.
- `app/lib/features/shared/onboarding_guide.dart` — **crear**: `OnboardingGuide` widget + `OnboardingStep` + `OnboardingMode`.
- `app/lib/features/shared/onboarding_copy.dart` — **crear**: catálogo de claves + copys (una sola fuente, DRY).
- `app/lib/features/shared/brand_kit.dart` — **modificar** (~914, 941): `HoldCoachMark` usa `onboardingStore` con claves de gesto.
- `app/lib/features/client/offer_actions.dart` — **modificar** (180, 470): `ensureLoaded` + envolver 1ª oferta.
- `app/lib/features/provider/unlock_flow.dart` — **modificar** (102, 145): `ensureLoaded` de onboarding.
- `app/lib/features/client/create_request_screen.dart` — **modificar**: guía en "Crear solicitud".
- `app/lib/features/client/request_status_screen.dart` — **modificar** (confirmar archivo): guía en 1ª oferta.
- `app/lib/features/provider/inbox_screen.dart` — **modificar**: guía en listado.
- `app/lib/features/provider/request_detail_screen.dart` — **modificar**: guía en "Hacer oferta".
- `app/lib/features/chat/chat_screen.dart` — **modificar**: guía de chat (por rol).
- Pantalla de wallet/recarga (confirmar archivo) — **modificar**: guía de créditos.
- `app/lib/features/shared/hold_tutorial_store.dart` — **eliminar** al final (Task 4).
- Tests: `app/test/onboarding_store_test.dart`, `app/test/onboarding_guide_test.dart`.

---

## Task 1: Migración Supabase — tabla + RLS + grants

**Files:**
- Create: `supabase/migrations/20260727000000_user_onboarding_guides.sql`

**Interfaces:**
- Produces: tabla `public.user_onboarding_guides(user_id uuid, guide_key text, completed_at timestamptz)`, PK `(user_id, guide_key)`, RLS "solo propias filas", grants `authenticated` SELECT/INSERT.

- [ ] **Step 1: Escribir la migración**

Create `supabase/migrations/20260727000000_user_onboarding_guides.sql`:

```sql
-- Guías de onboarding contextual ya vistas, por usuario. Persistencia
-- cross-device del sistema de spotlight. Marcar visto = INSERT idempotente.
create table if not exists public.user_onboarding_guides (
  user_id      uuid        not null references auth.users(id) on delete cascade,
  guide_key    text        not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, guide_key)
);

alter table public.user_onboarding_guides enable row level security;

-- El usuario solo ve sus filas.
create policy "own_select" on public.user_onboarding_guides
  for select using (user_id = auth.uid());

-- El usuario solo inserta filas propias.
create policy "own_insert" on public.user_onboarding_guides
  for insert with check (user_id = auth.uid());

-- Mínimo privilegio: nada para anon/PUBLIC; authenticated solo lee e inserta.
revoke all on public.user_onboarding_guides from anon, public;
grant select, insert on public.user_onboarding_guides to authenticated;
```

- [ ] **Step 2: Aplicar la migración vía MCP de Supabase**

Usar `apply_migration` (MCP `supabase`, proyecto `mfaiklvobnvgusbcssbx`) con `name = user_onboarding_guides` y el SQL de arriba.

- [ ] **Step 3: Verificar RLS y grants**

Ejecutar vía `execute_sql`:

```sql
select
  has_table_privilege('anon',          'public.user_onboarding_guides', 'SELECT') as anon_select,
  has_table_privilege('anon',          'public.user_onboarding_guides', 'INSERT') as anon_insert,
  has_table_privilege('authenticated', 'public.user_onboarding_guides', 'SELECT') as auth_select,
  has_table_privilege('authenticated', 'public.user_onboarding_guides', 'INSERT') as auth_insert,
  (select relrowsecurity from pg_class where oid = 'public.user_onboarding_guides'::regclass) as rls_on;
```

Expected: `anon_select=false`, `anon_insert=false`, `auth_select=true`, `auth_insert=true`, `rls_on=true`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260727000000_user_onboarding_guides.sql
git commit -m "feat(db): tabla user_onboarding_guides con RLS y grants minimos"
```

---

## Task 2: `OnboardingStore` + repo (TDD)

**Files:**
- Create: `app/lib/features/shared/onboarding_store.dart`
- Test: `app/test/onboarding_store_test.dart`

**Interfaces:**
- Produces:
  - `abstract class OnboardingRepo { Future<Set<String>> fetchCompleted(); Future<void> markCompleted(String key); bool get isLoggedIn; }`
  - `class SupabaseOnboardingRepo implements OnboardingRepo` (usa `supa`).
  - `class OnboardingStore extends ChangeNotifier` con: `Future<void> ensureLoaded()`, `bool isDone(String key)`, `Future<void> markDone(String key)`, `bool acquire(String key)`, `void release(String key)`, `@visibleForTesting void reset()`, `@visibleForTesting OnboardingStore.forTest(OnboardingRepo repo)`.
  - `final OnboardingStore onboardingStore` (singleton con `SupabaseOnboardingRepo`).
- Consumes: `data/repos.dart` (`supa`), `shared_preferences`.

**Comportamiento clave a testear:**
- `ensureLoaded`: si backend devuelve `{a}` y cache local tiene `{b}` → `_done = {a,b}` y persiste merge.
- Fail-safe: backend lanza y NO hay cache local → `isDone` devuelve `true` para todo (suprimido).
- Fail-safe con cache: backend lanza pero había cache `{b}` → usa `{b}` (no suprime).
- `markDone`: agrega, notifica, persiste local, llama `repo.markCompleted`. Idempotente.
- Import único del flag viejo `hold_tutorial_done` (`['accept','unlock']`) → marca `gesture.accept.v1`/`gesture.unlock.v1` una sola vez.
- Coordinador: `acquire('a')` true; `acquire('b')` false mientras 'a' activo; `release('a')` libera y notifica.

- [ ] **Step 1: Escribir los tests que fallan**

Create `app/test/onboarding_store_test.dart` (archivo completo):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

class FakeRepo implements OnboardingRepo {
  FakeRepo({this.remote = const {}, this.throwOnFetch = false, this.loggedIn = true});
  Set<String> remote;
  bool throwOnFetch;
  bool loggedIn;
  final List<String> marked = [];

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<Set<String>> fetchCompleted() async {
    if (throwOnFetch) throw Exception('network');
    return {...remote};
  }

  @override
  Future<void> markCompleted(String key) async {
    marked.add(key);
    remote = {...remote, key};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('merge de backend y cache local persistido', () async {
    SharedPreferences.setMockInitialValues({'onboarding_guides': ['b']});
    final repo = FakeRepo(remote: {'a'});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('a'), isTrue);
    expect(store.isDone('b'), isTrue);
    expect(store.isDone('c'), isFalse);
  });

  test('fail-safe: backend falla sin cache local suprime todo', () async {
    final repo = FakeRepo(throwOnFetch: true);
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('cualquiera'), isTrue); // suprimido: no muestra guias
  });

  test('fail-safe: backend falla pero hay cache local usa el cache', () async {
    SharedPreferences.setMockInitialValues({'onboarding_guides': ['b']});
    final repo = FakeRepo(throwOnFetch: true);
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('b'), isTrue);
    expect(store.isDone('z'), isFalse);
  });

  test('markDone agrega, marca en repo e idempotente', () async {
    final repo = FakeRepo(remote: {});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    await store.markDone('client.create_request.v1');
    await store.markDone('client.create_request.v1');
    expect(store.isDone('client.create_request.v1'), isTrue);
    expect(repo.marked, ['client.create_request.v1']);
  });

  test('import unico del flag viejo hold_tutorial_done', () async {
    SharedPreferences.setMockInitialValues({'hold_tutorial_done': ['accept', 'unlock']});
    final repo = FakeRepo(remote: {});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('gesture.accept.v1'), isTrue);
    expect(store.isDone('gesture.unlock.v1'), isTrue);
    expect(repo.marked.toSet(), {'gesture.accept.v1', 'gesture.unlock.v1'});
  });

  test('coordinador: solo una guia activa a la vez', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    expect(store.acquire('a'), isTrue);
    expect(store.acquire('b'), isFalse);
    expect(store.acquire('a'), isTrue); // reentrante para la misma clave
    store.release('a');
    expect(store.acquire('b'), isTrue);
  });
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `flutter test test/onboarding_store_test.dart`
Expected: FAIL — `onboarding_store.dart` no existe / símbolos indefinidos.

- [ ] **Step 3: Implementar `OnboardingStore`**

Create `app/lib/features/shared/onboarding_store.dart`:

```dart
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

    final prefs = await SharedPreferences.getInstance();
    final localCache = prefs.getStringList(_cacheKey);
    final hadLocal = localCache != null;
    if (hadLocal) _done.addAll(localCache);

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
    await _persist(prefs);
    notifyListeners();
  }

  /// Traduce el flag local del coach-mark viejo a claves versionadas, una sola
  /// vez, para no re-enseñar el gesto a quien ya lo domina.
  Future<void> _importOldHoldFlag(SharedPreferences prefs) async {
    if (prefs.getBool(_importFlag) == true) return;
    final old = prefs.getStringList(_oldHoldKey) ?? const [];
    for (final g in old) {
      final key = 'gesture.$g.v1';
      if (_done.add(key)) {
        try {
          await _repo.markCompleted(key);
        } catch (_) {/* best-effort */}
      }
    }
    await prefs.setBool(_importFlag, true);
  }

  Future<void> markDone(String key) async {
    if (!_done.add(key)) return;
    notifyListeners();
    await _persist(await SharedPreferences.getInstance());
    try {
      await _repo.markCompleted(key);
    } catch (_) {/* el cache local ya evita re-mostrar en este device */}
  }

  /// Recarga pública (p. ej. al iniciar sesión otro usuario). Limpia el estado y
  /// vuelve a leer del backend. `_importFlag` en prefs evita re-importar el flag
  /// viejo del gesto.
  Future<void> reload() async {
    _done.clear();
    _loaded = false;
    _suppressed = false;
    await ensureLoaded();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    try {
      await prefs.setStringList(_cacheKey, _done.toList());
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
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `flutter test test/onboarding_store_test.dart`
Expected: PASS (6 tests). Quitar el `test('...', async: () {})` placeholder si quedó.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shared/onboarding_store.dart app/test/onboarding_store_test.dart
git commit -m "feat(onboarding): OnboardingStore con backend, cache local, fail-safe e import"
```

---

## Task 3: Widget `OnboardingGuide` + catálogo de copys (TDD)

**Files:**
- Create: `app/lib/features/shared/onboarding_copy.dart`
- Create: `app/lib/features/shared/onboarding_guide.dart`
- Test: `app/test/onboarding_guide_test.dart`

**Interfaces:**
- Consumes: `onboardingStore` (`isDone`/`markDone`/`acquire`/`release`).
- Produces:
  - `enum OnboardingMode { anchored, welcome }`
  - `class OnboardingStep { const OnboardingStep(this.message); final String message; }`
  - `class OnboardingGuide extends StatefulWidget` con params `{ required String guideKey, required List<OnboardingStep> steps, required Widget child, bool enabled = true, OnboardingMode mode = OnboardingMode.anchored }`.
  - `onboardingCopy` en `onboarding_copy.dart`: `Map<String, List<OnboardingStep>>` por clave.

- [ ] **Step 1: Escribir los tests que fallan**

Create `app/test/onboarding_guide_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('muestra la guia la primera vez y la oculta al Saltar', (t) async {
    // Tras reset() el store no está suprimido (_suppressed=false) y isDone es
    // falso: la guía se muestra. NO llamar ensureLoaded aquí (sin login suprime).
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.demo.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsOneWidget);

    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsNothing);
    expect(onboardingStore.isDone('x.demo.v1'), isTrue);
  });

  testWidgets('no reaparece si ya esta hecha', (t) async {
    await onboardingStore.markDone('x.demo.v1');
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.demo.v1',
        steps: [OnboardingStep('Hola guia')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Hola guia'), findsNothing);
    expect(find.text('destino'), findsOneWidget);
  });

  testWidgets('multi-paso avanza con Siguiente y cierra en el ultimo', (t) async {
    await t.pumpWidget(_host(
      const OnboardingGuide(
        guideKey: 'x.multi.v1',
        steps: [OnboardingStep('Paso 1'), OnboardingStep('Paso 2')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Paso 1'), findsOneWidget);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Paso 2'), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(find.text('Paso 2'), findsNothing);
    expect(onboardingStore.isDone('x.multi.v1'), isTrue);
  });

  testWidgets('enabled=false solo renderiza el hijo', (t) async {
    await t.pumpWidget(_host(
      const OnboardingGuide(
        enabled: false,
        guideKey: 'x.off.v1',
        steps: [OnboardingStep('No sale')],
        child: SizedBox(width: 100, height: 40, child: Text('destino')),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('No sale'), findsNothing);
    expect(find.text('destino'), findsOneWidget);
    expect(onboardingStore.isDone('x.off.v1'), isFalse);
  });
}
```

> **Nota del plan:** para que el store no quede en modo suprimido en los tests de
> widget, `onboardingStore.reset()` + `markDone`/lecturas operan sin pasar por
> `ensureLoaded` (que suprime si no hay login). En el primer test, en lugar de
> `ensureLoaded`, basta con no llamarlo: tras `reset()`, `_loaded=false` y
> `_suppressed=false`, así `isDone` es falso y la guía se muestra. **Eliminar la
> línea `await onboardingStore.ensureLoaded();` del primer test** (queda como
> recordatorio de por qué). El widget NO debe llamar `ensureLoaded` por su cuenta.

- [ ] **Step 2: Crear el catálogo de copys**

Create `app/lib/features/shared/onboarding_guide.dart` primero con los tipos (los usa el copy). Empieza por el archivo del widget en el Step 3; aquí crea el catálogo que depende de esos tipos:

Create `app/lib/features/shared/onboarding_copy.dart`:

```dart
import 'onboarding_guide.dart';

/// Copys de cada guía, en un solo lugar (DRY). El PO puede ajustarlos aquí sin
/// tocar las pantallas. Claves versionadas: subir a `.v2` reaparece la guía.
const Map<String, List<OnboardingStep>> onboardingCopy = {
  'client.create_request.v1': [
    OnboardingStep(
        'Aquí puedes contarnos qué necesitas para que los proveedores te hagan ofertas.'),
  ],
  'client.view_offers.v1': [
    OnboardingStep(
        'Aquí podrás comparar las ofertas de los proveedores y elegir la que más te convenga.'),
  ],
  'client.chat_reveal.v1': [
    OnboardingStep('Aquí coordinas los detalles con el proveedor antes de cerrar el trato.'),
  ],
  'provider.requests_list.v1': [
    OnboardingStep(
        'Aquí encontrarás personas que están buscando servicios como los que tú ofreces.'),
  ],
  'provider.make_offer.v1': [
    OnboardingStep(
        'Puedes enviar tu oferta gratis. Solo desbloqueas el contacto si el cliente acepta tu propuesta.'),
  ],
  'provider.chat_reveal.v1': [
    OnboardingStep(
        'Aquí coordinas con el cliente. El contacto de WhatsApp se comparte cuando ambos avanzan.'),
  ],
  'wallet.credits.v1': [
    OnboardingStep(
        'Ofertar siempre es gratis. Los créditos solo se usan para desbloquear el contacto de un cliente que aceptó tu oferta.'),
  ],
};
```

- [ ] **Step 3: Implementar el widget `OnboardingGuide`**

Create `app/lib/features/shared/onboarding_guide.dart`:

```dart
import 'package:flutter/material.dart';

import 'onboarding_store.dart';

enum OnboardingMode { anchored, welcome }

class OnboardingStep {
  const OnboardingStep(this.message);
  final String message;
}

/// Guía contextual tipo spotlight. Envuelve el elemento objetivo ([child]).
/// La primera vez (según [onboardingStore]) monta un overlay: velo oscuro, el
/// hijo resaltado encima del velo (modo [OnboardingMode.anchored]) o una tarjeta
/// centrada (modo [OnboardingMode.welcome]), con el mensaje del paso actual y
/// botones Saltar / Siguiente / Entendido. Cerrar, saltar, tocar el velo o
/// terminar → `markDone` permanente. Reúsa la técnica y el fallback de anclaje
/// de [HoldCoachMark]: si el ancla no se puede medir, renderiza el hijo en línea
/// (nunca deja la UI tapada ni el elemento inaccesible).
class OnboardingGuide extends StatefulWidget {
  const OnboardingGuide({
    super.key,
    required this.guideKey,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.mode = OnboardingMode.anchored,
  });

  final String guideKey;
  final List<OnboardingStep> steps;
  final Widget child;
  final bool enabled;
  final OnboardingMode mode;

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchorKey = GlobalKey();

  Size? _anchorSize;
  bool _done = false;
  bool _measureFailed = false;
  bool _acquired = false;
  int _step = 0;

  bool get _shouldShow =>
      widget.enabled && !_done && !onboardingStore.isDone(widget.guideKey);

  @override
  void initState() {
    super.initState();
    onboardingStore.addListener(_onStore);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
    }
  }

  @override
  void didUpdateWidget(OnboardingGuide old) {
    super.didUpdateWidget(old);
    // Disparo por evento con datos: enabled pasa de false a true (p. ej. llegó
    // la primera oferta) → intentar mostrar ahora.
    if (widget.enabled && !old.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
    }
  }

  @override
  void dispose() {
    onboardingStore.removeListener(_onStore);
    if (_acquired) onboardingStore.release(widget.guideKey);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    if (!_shouldShow && _portal.isShowing) _portal.hide();
    // Si otra guía se liberó, reintentar mostrar esta.
    if (_shouldShow && !_portal.isShowing) _measureAndMaybeShow();
    setState(() {});
  }

  void _measureAndMaybeShow() {
    if (!mounted || !_shouldShow) return;
    if (widget.mode == OnboardingMode.welcome) {
      _tryShow(); // sin ancla que medir
      return;
    }
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      setState(() => _anchorSize = box.size);
      _tryShow();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
        if (retry != null && retry.hasSize) {
          setState(() => _anchorSize = retry.size);
          _tryShow();
        } else {
          setState(() => _measureFailed = true); // fallback: hijo en línea
        }
      });
    }
  }

  void _tryShow() {
    if (!mounted || !_shouldShow) return;
    if (!onboardingStore.acquire(widget.guideKey)) return; // otra guía activa
    _acquired = true;
    _portal.show();
  }

  Future<void> _complete() async {
    setState(() => _done = true);
    if (_portal.isShowing) _portal.hide();
    if (_acquired) {
      onboardingStore.release(widget.guideKey);
      _acquired = false;
    }
    await onboardingStore.markDone(widget.guideKey);
  }

  void _next() {
    if (_step < widget.steps.length - 1) {
      setState(() => _step++);
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow || _measureFailed) return widget.child;

    if (widget.mode == OnboardingMode.welcome) {
      return OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: widget.child,
      );
    }

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: KeyedSubtree(key: _anchorKey, child: widget.child),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _step == widget.steps.length - 1;
    final card = Card(
      key: const Key('onboardingCard'),
      color: cs.surface,
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.steps[_step].message,
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _complete, child: const Text('Saltar')),
                FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Entendido' : 'Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        // Velo oscuro: atenúa todo; tocarlo cierra y marca visto.
        Positioned.fill(
          child: GestureDetector(
            key: const Key('onboardingScrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _complete,
            child: const ColoredBox(color: Color(0x8C000000)),
          ),
        ),
        if (widget.mode == OnboardingMode.anchored && _anchorSize != null)
          // Hijo resaltado sobre el velo (spotlight).
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topLeft,
            showWhenUnlinked: false,
            child: IgnorePointer(
              child: SizedBox.fromSize(size: _anchorSize, child: widget.child),
            ),
          ),
        // Tarjeta: centrada (welcome) o abajo (anchored).
        Align(
          alignment: widget.mode == OnboardingMode.welcome
              ? Alignment.center
              : Alignment.bottomCenter,
          child: SafeArea(child: card),
        ),
      ],
    );
  }
}
```

> El spotlight v1 es estático (cumple reduced-motion por construcción), por eso
> el widget NO importa `core/motion.dart`. Cuando se anime el resaltado, agregar
> `import '../../core/motion.dart';` y guardar la animación con
> `JayaloMotion.reduced(context)`.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `flutter test test/onboarding_guide_test.dart`
Expected: PASS (4 tests). Ajustar el primer test quitando la línea de `ensureLoaded` como indica la nota.

- [ ] **Step 5: `flutter analyze` y commit**

```bash
cd app && flutter analyze
git add app/lib/features/shared/onboarding_guide.dart app/lib/features/shared/onboarding_copy.dart app/test/onboarding_guide_test.dart
git commit -m "feat(onboarding): widget OnboardingGuide y catalogo de copys"
```

---

## Task 4: Unificar el coach-mark de gesto + cargar el store en el arranque

**Files:**
- Modify: `app/lib/features/shared/brand_kit.dart` (~914, ~941)
- Modify: `app/lib/features/client/offer_actions.dart:180`
- Modify: `app/lib/features/provider/unlock_flow.dart:102`
- Modify: `app/lib/app.dart` (bootstrap del load post-login)
- Delete: `app/lib/features/shared/hold_tutorial_store.dart`
- Delete: `app/test/hold_tutorial_store_test.dart` (si existe)

**Interfaces:**
- Consumes: `onboardingStore` (Task 2). `HoldCoachMark.gesture` sigue siendo `'accept'`/`'unlock'`; internamente mapea a `'gesture.$gesture.v1'`.

- [ ] **Step 1: Cambiar `HoldCoachMark` para usar `onboardingStore`**

En `brand_kit.dart`, agregar cerca de los imports (si no está): `import 'onboarding_store.dart';` y quitar el import/uso de `hold_tutorial_store.dart`.

Reemplazar los usos de `holdTutorialStore` por `onboardingStore` con la clave versionada. Añadir un getter privado en `_HoldCoachMarkState`:

```dart
String get _guideKey => 'gesture.${widget.gesture}.v1';
```

Cambios puntuales:
- Línea ~914: `!_dismissed && !holdTutorialStore.isDone(widget.gesture)` → `!_dismissed && !onboardingStore.isDone(_guideKey)`
- Líneas ~919/926: `holdTutorialStore.addListener/removeListener(_onStore)` → `onboardingStore.addListener/removeListener(_onStore)`
- Línea ~941: `holdTutorialStore.markDone(widget.gesture)` → `onboardingStore.markDone(_guideKey)`

- [ ] **Step 2: Reemplazar `ensureLoaded` del gesto**

- `offer_actions.dart:180`: `unawaited(holdTutorialStore.ensureLoaded());` → `unawaited(onboardingStore.ensureLoaded());` (ajustar import).
- `unlock_flow.dart:102`: `unawaited(holdTutorialStore.ensureLoaded());` → `unawaited(onboardingStore.ensureLoaded());` (ajustar import).

- [ ] **Step 3: Cargar el store al entrar la app / cambiar de sesión**

En `app.dart`, en el `initState` del widget raíz de la app (o donde ya se escuche auth), disparar la carga y recargar en login. Añadir:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/shared/onboarding_store.dart';

// dentro del State del widget raíz:
@override
void initState() {
  super.initState();
  onboardingStore.ensureLoaded();
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn) {
      onboardingStore.reload();
    }
  });
}
```

> Confirmar en implementación el nombre del State raíz en `app.dart` (`JayaloApp`)
> y que no exista ya un listener de auth ahí para no duplicarlo (si existe, añadir
> la llamada a `onboardingStore.reload()` dentro del handler existente en vez de
> crear otro listener). `reload()` es el método público de Task 2 — no usar el
> `reset()` de test en producción.

- [ ] **Step 4: Borrar `HoldTutorialStore`**

```bash
git rm app/lib/features/shared/hold_tutorial_store.dart
```

Si hay un test suyo, borrarlo también. Buscar referencias residuales:

Run: `cd app && grep -rn "holdTutorialStore\|hold_tutorial_store" lib test`
Expected: sin resultados.

- [ ] **Step 5: Ejecutar toda la suite y analyze**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze 0; suite verde (los tests del coach-mark existentes siguen pasando; si alguno mockeaba `holdTutorialStore`, actualizarlo a `onboardingStore` con clave `gesture.accept.v1`/`gesture.unlock.v1`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(onboarding): unificar coach-mark de gesto bajo OnboardingStore (backend)"
```

---

## Task 5: Guías del cliente — Crear solicitud + primera oferta

**Files:**
- Modify: `app/lib/features/client/create_request_screen.dart`
- Modify: `app/lib/features/client/request_status_screen.dart` (confirmar: pantalla donde el cliente ve las ofertas de SU solicitud)
- Modify: `app/lib/features/client/offer_actions.dart:470` (si ahí se listan las ofertas del cliente)

**Interfaces:**
- Consumes: `OnboardingGuide`, `onboardingCopy`.

- [ ] **Step 1: Confirmar el archivo de "recibe ofertas"**

Run: `cd app && grep -rln "oferta" lib/features/client | head` y abrir el candidato para ubicar el widget de la 1ª tarjeta de oferta y la lista.
Elegir la pantalla donde el CLIENTE ve las ofertas recibidas (no la del proveedor).

- [ ] **Step 2: Envolver el botón "Crear solicitud"**

En `create_request_screen.dart`, localizar el botón principal de crear/enviar y envolverlo:

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

// ...
OnboardingGuide(
  guideKey: 'client.create_request.v1',
  steps: onboardingCopy['client.create_request.v1']!,
  child: <el boton de Crear solicitud existente>,
)
```

- [ ] **Step 3: Envolver la primera tarjeta de oferta (disparo por evento)**

En la pantalla de ofertas del cliente, envolver la **primera** tarjeta de la lista, habilitando solo cuando hay ofertas:

```dart
final hasOffers = offers.isNotEmpty;
// en el itemBuilder, para index == 0:
OnboardingGuide(
  guideKey: 'client.view_offers.v1',
  enabled: hasOffers && index == 0,
  steps: onboardingCopy['client.view_offers.v1']!,
  child: <la tarjeta de oferta existente>,
)
```

- [ ] **Step 4: Test de widget del disparo por evento**

Create/append `app/test/onboarding_client_offers_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('la guia de ofertas no sale con lista vacia y si con >=1', (t) async {
    Widget build(bool hasOffers) => MaterialApp(
          home: Scaffold(
            body: OnboardingGuide(
              guideKey: 'client.view_offers.v1',
              enabled: hasOffers,
              steps: onboardingCopy['client.view_offers.v1']!,
              child: const SizedBox(width: 200, height: 60, child: Text('oferta')),
            ),
          ),
        );

    await t.pumpWidget(build(false));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsNothing);

    await t.pumpWidget(build(true));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
  });
}
```

- [ ] **Step 5: Ejecutar, analyze y commit**

```bash
cd app && flutter analyze && flutter test test/onboarding_client_offers_test.dart
git add -A
git commit -m "feat(onboarding): guias de cliente (crear solicitud y primera oferta)"
```

---

## Task 6: Guías del proveedor — Listado + Hacer oferta

**Files:**
- Modify: `app/lib/features/provider/inbox_screen.dart` (listado de solicitudes)
- Modify: `app/lib/features/provider/request_detail_screen.dart` (botón "Hacer oferta")

**Interfaces:**
- Consumes: `OnboardingGuide`, `onboardingCopy`.

- [ ] **Step 1: Envolver el listado de solicitudes**

En `inbox_screen.dart`, envolver la **primera** tarjeta de la lista (o el encabezado del listado) con modo anclado:

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

OnboardingGuide(
  guideKey: 'provider.requests_list.v1',
  enabled: requests.isNotEmpty && index == 0,
  steps: onboardingCopy['provider.requests_list.v1']!,
  child: <la primera tarjeta de solicitud existente>,
)
```

- [ ] **Step 2: Envolver el botón "Hacer oferta"**

En `request_detail_screen.dart`, envolver el botón de hacer oferta:

```dart
OnboardingGuide(
  guideKey: 'provider.make_offer.v1',
  steps: onboardingCopy['provider.make_offer.v1']!,
  child: <el boton Hacer oferta existente>,
)
```

- [ ] **Step 3: Test de humo (reusa la mecánica ya testeada)**

Append `app/test/onboarding_provider_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('guia hacer oferta se muestra y se marca', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnboardingGuide(
          guideKey: 'provider.make_offer.v1',
          steps: onboardingCopy['provider.make_offer.v1']!,
          child: const SizedBox(width: 160, height: 48, child: Text('Hacer oferta')),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(onboardingStore.isDone('provider.make_offer.v1'), isTrue);
  });
}
```

- [ ] **Step 4: Ejecutar, analyze y commit**

```bash
cd app && flutter analyze && flutter test test/onboarding_provider_test.dart
git add -A
git commit -m "feat(onboarding): guias de proveedor (listado y hacer oferta)"
```

---

## Task 7: Guías de chat (por rol) + créditos (welcome)

**Files:**
- Modify: `app/lib/features/chat/chat_screen.dart`
- Modify: pantalla de wallet/recarga (confirmar en Step 1)

**Interfaces:**
- Consumes: `OnboardingGuide`, `onboardingCopy`. Rol del usuario para elegir la clave de chat.

- [ ] **Step 1: Confirmar la pantalla de wallet/recarga**

Run: `cd app && grep -rln "recarga\|creditos\|saldo\|wallet\|PayPal" lib/features` y abrir el candidato de la pantalla de saldo/recarga.

- [ ] **Step 2: Guía de chat por rol**

En `chat_screen.dart`, determinar el rol actual (ya disponible en la pantalla; si no, derivarlo del contexto de la conversación) y elegir la clave:

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';

final chatGuideKey =
    isProvider ? 'provider.chat_reveal.v1' : 'client.chat_reveal.v1';

// envolver el area principal del chat (p. ej. el header o el primer mensaje)
OnboardingGuide(
  key: ValueKey(chatGuideKey),
  guideKey: chatGuideKey,
  mode: OnboardingMode.welcome, // no hay un unico elemento que resaltar
  steps: onboardingCopy[chatGuideKey]!,
  child: <el cuerpo del chat existente>,
)
```

- [ ] **Step 3: Guía de créditos (welcome)**

En la pantalla de wallet/recarga, envolver el cuerpo con modo welcome:

```dart
OnboardingGuide(
  guideKey: 'wallet.credits.v1',
  mode: OnboardingMode.welcome,
  steps: onboardingCopy['wallet.credits.v1']!,
  child: <el cuerpo de la pantalla de wallet existente>,
)
```

- [ ] **Step 4: Test de humo de guía welcome**

Append `app/test/onboarding_welcome_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('guia welcome de creditos se muestra centrada y se marca', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnboardingGuide(
          guideKey: 'wallet.credits.v1',
          mode: OnboardingMode.welcome,
          steps: onboardingCopy['wallet.credits.v1']!,
          child: const SizedBox(width: 300, height: 400, child: Text('wallet')),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('onboardingCard')), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(onboardingStore.isDone('wallet.credits.v1'), isTrue);
  });
}
```

- [ ] **Step 5: Verificación final completa**

```bash
cd app && flutter analyze && flutter test
```
Expected: analyze 0; suite verde (≥ 428 previos + los nuevos de onboarding).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(onboarding): guias de chat por rol y de creditos (welcome)"
```

---

## Verificación cruzada con el spec

- Persistencia backend cross-device → Task 1 (tabla) + Task 2 (store).
- Sin grandfather (todos ven las guías) → no hay bulk-insert de "visto"; comportamiento por defecto.
- Unificar coach-mark de gesto → Task 4.
- Import local→backend del flag viejo → Task 2 (`_importOldHoldFlag`).
- Fail-safe en error de fetch → Task 2 (`_suppressed`).
- Overlay + resaltado + mensaje + avanzar/cerrar/saltar → Task 3.
- Una guía a la vez (coordinador) → Task 2 (`acquire`/`release`) + Task 3.
- Anclada vs bienvenida; disparo por evento → Task 3 (`mode`, `enabled`, `didUpdateWidget`).
- Fallback de anclaje (nunca bloquear la UI) → Task 3 (`_measureFailed`).
- Reduced-motion → Task 3 (spotlight estático por construcción).
- Catálogo de 9 guías → Task 3 (copy) + Tasks 4–7 (wiring): gesture.accept, gesture.unlock (T4); client.create_request, client.view_offers (T5); provider.requests_list, provider.make_offer (T6); client/provider.chat_reveal, wallet.credits (T7).
- Web fuera de alcance → ninguna tarea de web.

## Notas de ejecución

- **No push** hasta que el PO lo autorice.
- La rama `feat/error-tracking` tiene cambios ajenos sin commitear: usar `git add` de rutas concretas en cada commit para no arrastrarlos.
- Los archivos marcados "confirmar" (ofertas del cliente, wallet) se resuelven con el `grep` del primer step de su tarea antes de tocar código.
```