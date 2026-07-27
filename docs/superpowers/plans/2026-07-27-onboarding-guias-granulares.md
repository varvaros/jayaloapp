# Onboarding — guías granulares (tour encadenado) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar señaladores spotlight granulares (a nivel de elemento) al flujo de cliente y un coordinador ordenado que los reproduzca como tour encadenado la primera vez.

**Architecture:** Se generaliza el coordinador de `OnboardingStore` de "primero que llega" a "menor `order` gana" (recolección por frame + resolución en post-frame). `OnboardingGuide` gana un parámetro `order` y una ancla EXTERNA (`anchorKey`) para poder resaltar el botón `+` de la barra sin envolverlo. Luego se cablean las guías nuevas en Solicitudes, Crear solicitud, Catálogo y Chat, más una tarjeta de ejemplo no interactiva.

**Tech Stack:** Flutter, Dart, `OverlayPortal`/`CustomPaint`, Supabase (estado por usuario, ya existente), `flutter_test`.

## Global Constraints

- Copys SIEMPRE en `app/lib/features/shared/onboarding_copy.dart`; claves versionadas terminadas en `.v1`. Una pantalla las lee con `onboardingCopy['<clave>']!`.
- El coordinador es **global** (un solo turno para toda la app): las guías de una misma pantalla usan `order` distintos; una guía condicional que aparece tarde (al por mayor) usa `order` alto (9) para no colarse.
- No se siembran datos: la solicitud de ejemplo es puramente visual y NO navega.
- `quick_replies` y `report` aplican a ambos roles (claves sin prefijo de rol); el resto es tour de cliente.
- Al terminar cada task: `cd app && flutter analyze` en **0** y la **suite completa verde** (`flutter test`).
- Órdenes por pantalla (menor = primero): Solicitudes `+`=1, mis=2, otros=3 · Crear tipo=1, foto=2, enviar=3, al-por-mayor=9 · Chat reveal=1, quick_replies=2, report=3.

---

### Task 1: Coordinador ordenado en OnboardingStore

**Files:**
- Modify: `app/lib/features/shared/onboarding_store.dart` (campo `_active` + coordinador líneas ~69, 160-174; `reload` ~145-151; `reset` ~176-182)
- Test: `app/test/onboarding_store_test.dart`

**Interfaces:**
- Produces:
  - `void requestSlot(String key, int order)` — registra candidata.
  - `void resolvePending()` — concede el turno a la candidata de menor `order` si no hay activa.
  - `bool isActive(String key)` — ¿esta guía tiene el turno?
  - `void withdraw(String key)` — saca de la cola; si era activa, libera y notifica.
  - `void release(String key)` — alias de `withdraw`.
- **Reemplaza** al viejo `bool acquire(String key)` (ya no existe).

- [ ] **Step 1: Escribe los tests que fallan**

Reemplaza los dos tests de coordinador existentes (`'coordinador: solo una guia activa a la vez'` y `'reload limpia el coordinador...'`, líneas 84-102) por estos tres:

```dart
  test('coordinador ordenado: gana la de menor order', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('b', 2);
    store.requestSlot('a', 1);
    store.requestSlot('c', 3);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    expect(store.isActive('b'), isFalse);
    // al liberar 'a', tras re-registrar entra la siguiente de menor orden (b)
    store.release('a');
    store.requestSlot('b', 2);
    store.requestSlot('c', 3);
    store.resolvePending();
    expect(store.isActive('b'), isTrue);
  });

  test('reentrante: pedir turno para la ya activa no la saca', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('a', 0);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    store.requestSlot('a', 0); // no-op
    expect(store.isActive('a'), isTrue);
  });

  test('reload limpia el coordinador: una guia activa no queda trabada', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('a', 0);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    await store.reload();
    store.requestSlot('b', 0);
    store.resolvePending();
    expect(store.isActive('b'), isTrue);
  });
```

- [ ] **Step 2: Corre los tests para verlos fallar**

Run: `cd app && flutter test test/onboarding_store_test.dart`
Expected: FAIL — `requestSlot`/`resolvePending`/`isActive` no existen.

- [ ] **Step 3: Implementa el coordinador ordenado**

En `onboarding_store.dart`, reemplaza el bloque del coordinador (líneas ~160-174, desde `// --- Coordinador: solo una guía visible a la vez ---` hasta el cierre de `release`) por:

```dart
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
```

En `reload()` (línea ~149, donde dice `_active = null;`) añade justo debajo:

```dart
    _candidates.clear();
```

En `reset()` (línea ~181, donde dice `_active = null;`) añade justo debajo:

```dart
    _candidates.clear();
```

- [ ] **Step 4: Corre los tests para verlos pasar**

Run: `cd app && flutter test test/onboarding_store_test.dart`
Expected: PASS (todos).

- [ ] **Step 5: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/shared/onboarding_store.dart app/test/onboarding_store_test.dart
git commit -m "feat(onboarding): coordinador ordenado (menor order gana)"
```

---

### Task 2: OnboardingGuide usa order + turno del coordinador

**Files:**
- Modify: `app/lib/features/shared/onboarding_guide.dart`
- Test: `app/test/onboarding_guide_test.dart`

**Interfaces:**
- Consumes: `requestSlot`, `resolvePending`, `isActive`, `withdraw` (Task 1).
- Produces: `OnboardingGuide` con parámetro nuevo `int order = 0` y `GlobalKey? anchorKey`. Cuando `anchorKey != null`, la guía NO envuelve al hijo: mide ese ancla externa (para el `+` de la barra, Task 3).

- [ ] **Step 1: Escribe/actualiza los tests que fallan**

En `onboarding_guide_test.dart`, en el último test (`'libera el coordinador cuando enabled pasa a false...'`) reemplaza la última línea (`expect(onboardingStore.acquire('other.key.v1'), isTrue);`, línea 105) por:

```dart
    onboardingStore.requestSlot('other.key.v1', 0);
    onboardingStore.resolvePending();
    expect(onboardingStore.isActive('other.key.v1'), isTrue);
```

Y agrega este test nuevo al final del `main()`:

```dart
  testWidgets('orden: la guia de menor order se muestra primero', (t) async {
    await t.pumpWidget(_host(
      Column(mainAxisSize: MainAxisSize.min, children: const [
        OnboardingGuide(
          guideKey: 'x.b.v1',
          order: 2,
          steps: [OnboardingStep('Segunda')],
          child: SizedBox(width: 80, height: 30, child: Text('b')),
        ),
        OnboardingGuide(
          guideKey: 'x.a.v1',
          order: 1,
          steps: [OnboardingStep('Primera')],
          child: SizedBox(width: 80, height: 30, child: Text('a')),
        ),
      ]),
    ));
    await t.pumpAndSettle();
    // aunque 'b' va antes en el árbol, gana 'a' (order menor)
    expect(find.text('Primera'), findsOneWidget);
    expect(find.text('Segunda'), findsNothing);
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(find.text('Segunda'), findsOneWidget);
  });

  testWidgets('ancla externa: mide un widget por anchorKey sin envolverlo', (t) async {
    final anchor = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 20,
            top: 20,
            child: SizedBox(
              key: anchor,
              width: 60,
              height: 40,
              child: const Text('target'),
            ),
          ),
          OnboardingGuide(
            anchorKey: anchor,
            guideKey: 'x.ext.v1',
            steps: const [OnboardingStep('Externa')],
            order: 1,
            child: const SizedBox.shrink(),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Externa'), findsOneWidget);
    expect(find.text('target'), findsOneWidget);
  });
```

- [ ] **Step 2: Corre los tests para verlos fallar**

Run: `cd app && flutter test test/onboarding_guide_test.dart`
Expected: FAIL — `order`/`anchorKey` no existen; el test de orden falla.

- [ ] **Step 3: Implementa order + ancla externa + turno**

En `onboarding_guide.dart`, actualiza el constructor y los campos (líneas ~28-41):

```dart
  const OnboardingGuide({
    super.key,
    required this.guideKey,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.mode = OnboardingMode.anchored,
    this.order = 0,
    this.anchorKey,
  });

  final String guideKey;
  final List<OnboardingStep> steps;
  final Widget child;
  final bool enabled;
  final OnboardingMode mode;

  /// Prioridad en el tour encadenado: menor = se muestra antes (coordinador
  /// global). Guías condicionales que aparecen tarde usan un `order` alto.
  final int order;

  /// Ancla EXTERNA: si se pasa, la guía NO envuelve al hijo para medirlo, sino
  /// que mide el widget que lleve este [GlobalKey] en otra parte del árbol
  /// (p. ej. el botón `+` de la barra). El [child] puede ser `SizedBox.shrink`.
  final GlobalKey? anchorKey;
```

Reemplaza `_measureAnchor` (líneas ~118-123) por:

```dart
  /// Rect GLOBAL del ancla (coords de pantalla). Usa el ancla externa si se dio.
  Rect? _measureAnchor() {
    final ctx = (widget.anchorKey ?? _anchorKey).currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
```

Reemplaza `_tryShow` (líneas ~149-154) por:

```dart
  void _tryShow() {
    if (!mounted || !_shouldShow) return;
    onboardingStore.requestSlot(widget.guideKey, widget.order);
    _acquired = true;
    // Ventana de recolección: junta las candidatas de este frame y resuelve al
    // final. Idempotente si varias guías la agendan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onboardingStore.resolvePending();
    });
    _syncPortal();
  }

  /// Muestra u oculta el portal según si esta guía tiene el turno.
  void _syncPortal() {
    if (!mounted) return;
    final active = onboardingStore.isActive(widget.guideKey);
    if (active && !_portal.isShowing) _portal.show();
    if (!active && _portal.isShowing) _portal.hide();
  }
```

Reemplaza `_onStore` (líneas ~107-116) por:

```dart
  void _onStore() {
    if (!mounted) return;
    if (!_shouldShow) {
      if (_portal.isShowing) _portal.hide();
      _releaseIfHeld();
    } else {
      // Si aún no tengo turno ni portal, (re)pido turno.
      if (!_portal.isShowing && !onboardingStore.isActive(widget.guideKey)) {
        _measureAndMaybeShow();
      }
      _syncPortal();
    }
    setState(() {});
  }
```

Reemplaza `_releaseIfHeld` (líneas ~100-105) por:

```dart
  void _releaseIfHeld() {
    if (_acquired) {
      onboardingStore.withdraw(widget.guideKey);
      _acquired = false;
    }
  }
```

Reemplaza el cuerpo de `build` (líneas ~171-184) por:

```dart
  @override
  Widget build(BuildContext context) {
    if (!_shouldShow || _measureFailed) return widget.child;

    // Con ancla externa NO se envuelve el hijo (el GlobalKey vive en el target).
    final wrap =
        widget.mode == OnboardingMode.anchored && widget.anchorKey == null;
    final content =
        wrap ? KeyedSubtree(key: _anchorKey, child: widget.child) : widget.child;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: content,
    );
  }
```

- [ ] **Step 4: Corre los tests para verlos pasar**

Run: `cd app && flutter test test/onboarding_guide_test.dart`
Expected: PASS (todos, incluidos orden y ancla externa).

- [ ] **Step 5: Corre la suite de onboarding para no regresionar**

Run: `cd app && flutter test test/onboarding_client_offers_test.dart test/onboarding_welcome_test.dart test/onboarding_provider_test.dart test/onboarding_errors_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/shared/onboarding_guide.dart app/test/onboarding_guide_test.dart
git commit -m "feat(onboarding): OnboardingGuide con order y ancla externa"
```

---

### Task 3: Guía del botón `+` (ancla externa en la barra)

**Files:**
- Modify: `app/lib/features/shell/floating_nav_bar.dart` (añade `GlobalKey? centerButtonKey`, líneas ~65-72 y ~138-145)
- Modify: `app/lib/features/shell/home_shell.dart` (monta la guía + pasa el key, líneas ~41-134, 168-197)
- Modify: `app/lib/features/shared/onboarding_copy.dart` (clave `client.plus.v1`)
- Test: `app/test/onboarding_guide_test.dart` ya cubre la ancla externa (Task 2). Verificación adicional: `flutter analyze` + smoke en device.

**Interfaces:**
- Consumes: `OnboardingGuide(anchorKey:, order:)` (Task 2).
- Produces: `FloatingNavBar` con `GlobalKey? centerButtonKey` opcional aplicado al botón central.

- [ ] **Step 1: Añade el copy**

En `onboarding_copy.dart`, dentro del mapa `onboardingCopy`, agrega:

```dart
  'client.plus.v1': [
    OnboardingStep('Aquí creas una nueva solicitud.'),
  ],
```

- [ ] **Step 2: Añade el hook de key a la barra**

En `floating_nav_bar.dart`, en el constructor de `FloatingNavBar` (líneas ~66-72) agrega el parámetro:

```dart
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    this.badges = const {},
    this.centerButtonKey,
  });
```

y el campo (junto a los otros, antes de `build`):

```dart
  /// Key opcional para anclar una guía de onboarding sobre el botón central
  /// (no cambia el aspecto: solo permite medir su rect). Ver home_shell.
  final GlobalKey? centerButtonKey;
```

En el `Positioned` del botón central (líneas ~138-145) envuelve `_CenterButton` con `KeyedSubtree`:

```dart
              Positioned(
                bottom: _pillHeight - _centerSize / 2 - _centerButtonLift,
                child: KeyedSubtree(
                  key: centerButtonKey,
                  child: _CenterButton(
                    destination: destinations[kCenterIndex],
                    active: currentIndex == kCenterIndex,
                    onTap: () => onSelected(kCenterIndex),
                  ),
                ),
              ),
```

- [ ] **Step 3: Monta la guía en el shell**

En `home_shell.dart`, agrega SOLO estos imports (junto a los otros de `features/...`):

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';
```

`session_state.dart` YA está importado completo (línea 5, sin `show`), así que `roleStore` y `RoleState` ya están disponibles — NO agregues otro import de ese archivo (duplicaría).

Agrega un `GlobalKey` estable como campo de `_HomeShellState` (junto a los otros miembros de estado):

```dart
  final GlobalKey _plusAnchorKey = GlobalKey();
```

En `build`, tras calcular `final loc = ...` y `final dests = ...`, define si el `+` debe guiarse:

```dart
    final isClient = roleStore.value != RoleState.provider;
```

Reemplaza el `body:` del `Scaffold` (el `TweenAnimationBuilder`, líneas ~123-134) envolviéndolo en un `Stack` que también monte la guía del `+`:

```dart
      body: Stack(
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(GoRouterState.of(context).matchedLocation),
            tween: Tween(begin: 0, end: 1),
            duration: JayaloMotion.reduced(context)
                ? Duration.zero
                : JayaloMotion.fast,
            curve: JayaloMotion.enter,
            builder: (context, t, bodyChild) => Opacity(
              opacity: t,
              child: bodyChild,
            ),
            child: widget.child,
          ),
          // Guía spotlight del botón `+`: solo cliente y solo en su pantalla de
          // aterrizaje (`/client`). Ancla EXTERNA sobre el botón central.
          if (isClient)
            OnboardingGuide(
              anchorKey: _plusAnchorKey,
              guideKey: 'client.plus.v1',
              steps: onboardingCopy['client.plus.v1']!,
              order: 1,
              enabled: loc == '/client',
              child: const SizedBox.shrink(),
            ),
        ],
      ),
```

En la construcción de `FloatingNavBar` (líneas ~168-197) pasa el key solo para cliente:

```dart
                child: FloatingNavBar(
                key: const ValueKey('nav-bar-visible'),
                centerButtonKey: isClient ? _plusAnchorKey : null,
                destinations: dests,
                currentIndex: idx,
```

- [ ] **Step 4: Verifica análisis y no-regresión del shell**

Run: `cd app && flutter analyze`
Expected: 0 issues.

Run: `cd app && flutter test test/home_shell_test.dart test/floating_nav_bar_test.dart test/home_shell_navbar_transition_test.dart test/onboarding_guide_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/shell/floating_nav_bar.dart app/lib/features/shell/home_shell.dart app/lib/features/shared/onboarding_copy.dart
git commit -m "feat(onboarding): guia del boton + (ancla externa en la barra)"
```

> Nota de aceptación: el resaltado real del `+` se confirma en **smoke device** (ver `jayalo-app-flutter-install-no-recompila-gotcha`), porque el rect del botón central depende del layout real de la barra.

---

### Task 4: Tarjeta de ejemplo + guías de Solicitudes (mis/otros)

**Files:**
- Modify: `app/lib/features/client/my_requests_screen.dart` (import onboarding, estado vacío ~450-462, botón filtro ~385, nueva clase `_ExampleRequestCard`)
- Modify: `app/lib/features/shared/onboarding_copy.dart` (`client.my_requests.v1`, `client.others_requests.v1`)
- Test: `app/test/my_requests_onboarding_test.dart` (nuevo)

**Interfaces:**
- Consumes: `OnboardingGuide(order:)` (Task 2).
- Produces: estado vacío con `_ExampleRequestCard` (no interactiva) anclando `client.my_requests.v1`; pestaña "Ver solicitudes de usuarios" anclando `client.others_requests.v1`.

- [ ] **Step 1: Escribe el test que falla**

Crea `app/test/my_requests_onboarding_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('estado vacio: tarjeta de ejemplo + guia "mis solicitudes"',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: MyRequestsScreen(
        actions: const [],
        myFetch: () async => [],
        othersFetch: () async => [],
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Ejemplo'), findsOneWidget);
    // La guia de menor order presente en esta pantalla (2 = mis solicitudes)
    // gana el turno primero.
    expect(find.textContaining('se verán tus solicitudes'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Corre el test para verlo fallar**

Run: `cd app && flutter test test/my_requests_onboarding_test.dart`
Expected: FAIL — no existe la tarjeta 'Ejemplo' ni el copy.

- [ ] **Step 3: Añade los copys**

En `onboarding_copy.dart` agrega:

```dart
  'client.my_requests.v1': [
    OnboardingStep('Aquí se verán tus solicitudes y en qué van.'),
  ],
  'client.others_requests.v1': [
    OnboardingStep('Y aquí ves qué están pidiendo otros usuarios.'),
  ],
```

- [ ] **Step 4: Implementa la tarjeta de ejemplo y las guías**

En `my_requests_screen.dart`, agrega los imports:

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';
```

Envuelve la pestaña "Ver solicitudes de usuarios" (líneas ~385-390) con su guía:

```dart
                OnboardingGuide(
                  guideKey: 'client.others_requests.v1',
                  steps: onboardingCopy['client.others_requests.v1']!,
                  order: 3,
                  child: _filterButton('Ver solicitudes de usuarios', _others, () {
                    setState(() {
                      _others = true;
                      _othersLoad ??= _fetchOthers();
                    });
                  }),
                ),
```

Reemplaza el bloque `if (items.isEmpty) { return EmptyState(...); }` (líneas ~450-462) por:

```dart
                          if (items.isEmpty) {
                            return ListView(
                              controller: homeScrollController,
                              padding: EdgeInsets.only(
                                top: 12,
                                bottom: navBarReservedSpace(context),
                              ),
                              children: [
                                OnboardingGuide(
                                  guideKey: 'client.my_requests.v1',
                                  steps:
                                      onboardingCopy['client.my_requests.v1']!,
                                  order: 2,
                                  child: const _ExampleRequestCard(),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(
                                    'Aún no has pedido nada.\n'
                                    'Cuéntanos qué buscas y los proveedores te '
                                    'harán ofertas.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Center(
                                  child: FilledButton(
                                    onPressed: () =>
                                        context.push('/client/create'),
                                    child: const Text('Crear solicitud'),
                                  ),
                                ),
                              ],
                            );
                          }
```

Al final del archivo (tras `_OtherRequestCard`), agrega la tarjeta de ejemplo NO interactiva:

```dart
/// Tarjeta de solicitud de EJEMPLO (estado vacío): mismo lenguaje visual que
/// `_RequestCard` pero atenuada, con etiqueta "Ejemplo" y SIN `onTap`. Sirve de
/// ancla a la guía `client.my_requests.v1` y da sustancia al "aquí se verán tus
/// solicitudes". Desaparece en cuanto el cliente tiene una solicitud real.
class _ExampleRequestCard extends StatelessWidget {
  const _ExampleRequestCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: .9,
      child: JayaloCard(
        tint: cs.surfaceContainerLowest,
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.inventory_2_outlined,
                  size: 24, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Nevera 11 pies, poco uso',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Ejemplo',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('hace 2 h',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '3 ofertas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Corre el test para verlo pasar**

Run: `cd app && flutter test test/my_requests_onboarding_test.dart`
Expected: PASS.

- [ ] **Step 6: No-regresión de la pantalla**

Run: `cd app && flutter test test/my_requests_others_test.dart && flutter analyze`
Expected: PASS · 0 issues.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/client/my_requests_screen.dart app/lib/features/shared/onboarding_copy.dart app/test/my_requests_onboarding_test.dart
git commit -m "feat(onboarding): tarjeta ejemplo + guias mis/otras solicitudes"
```

---

### Task 5: Guías de Crear solicitud (tipo / foto / al por mayor)

**Files:**
- Modify: `app/lib/features/client/create_request_screen.dart` (fila tipo ~734, píldora mayor ~740, chips foto ~792, guía enviar existente ~718)
- Modify: `app/lib/features/shared/onboarding_copy.dart` (`client.request_kind.v1`, `client.request_photo.v1`, `client.request_wholesale.v1`)
- Test: `app/test/onboarding_copy_test.dart` (nuevo — guarda contra claves faltantes; las pantallas hacen `onboardingCopy['clave']!`, que revienta si falta)

**Interfaces:**
- Consumes: `OnboardingGuide(order:)` (Task 2). La guía `client.create_request.v1` ya existe: solo se le fija `order: 3`.

- [ ] **Step 1: Escribe el test que falla**

Crea `app/test/onboarding_copy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  test('todas las claves nuevas de onboarding existen y no van vacías', () {
    const keys = [
      'client.plus.v1',
      'client.my_requests.v1',
      'client.others_requests.v1',
      'client.request_kind.v1',
      'client.request_photo.v1',
      'client.request_wholesale.v1',
      'client.catalog.v1',
      'chat.quick_replies.v1',
      'chat.report.v1',
    ];
    for (final k in keys) {
      expect(onboardingCopy.containsKey(k), isTrue, reason: 'falta $k');
      expect(onboardingCopy[k]!, isNotEmpty, reason: '$k sin pasos');
      expect(onboardingCopy[k]!.first.message.trim(), isNotEmpty,
          reason: '$k con mensaje vacío');
    }
  });
}
```

- [ ] **Step 2: Corre el test para verlo fallar**

Run: `cd app && flutter test test/onboarding_copy_test.dart`
Expected: FAIL — faltan claves (aún no se agregaron todas).

- [ ] **Step 3: Añade los copys de crear-solicitud**

En `onboarding_copy.dart` agrega:

```dart
  'client.request_kind.v1': [
    OnboardingStep('Aquí eliges si buscas un producto o un servicio.'),
  ],
  'client.request_photo.v1': [
    OnboardingStep('Aquí tomas una foto o subes una imagen de lo que buscas.'),
  ],
  'client.request_wholesale.v1': [
    OnboardingStep('¿Necesitas grandes cantidades? Actívalo aquí.'),
  ],
```

- [ ] **Step 4: Ancla las guías en la pantalla**

En `create_request_screen.dart`, a la guía existente del botón enviar (línea ~718-725) agrégale `order: 3`:

```dart
              suffixIcon: OnboardingGuide(
                guideKey: 'client.create_request.v1',
                steps: onboardingCopy['client.create_request.v1']!,
                order: 3,
                child: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _startSend(_input.text),
                ),
              ),
```

Envuelve la fila de tipo (el `Row(children: [ ... _kindPill ... ])`, líneas ~734-747) con su guía. Reemplaza `Row(` de esa fila por:

```dart
          OnboardingGuide(
            guideKey: 'client.request_kind.v1',
            steps: onboardingCopy['client.request_kind.v1']!,
            order: 1,
            child: Row(
              children: [
                if (_kind != 'servicio')
                  Expanded(child: _kindPill('producto', 'Producto')),
                if (_kind == 'producto') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OnboardingGuide(
                      guideKey: 'client.request_wholesale.v1',
                      steps: onboardingCopy['client.request_wholesale.v1']!,
                      order: 9,
                      child: _kindPill('mayor', 'Al por mayor'),
                    ),
                  ),
                ],
                if (_kind != 'producto') ...[
                  if (_kind != 'servicio') const SizedBox(width: 10),
                  Expanded(child: _kindPill('servicio', 'Servicio')),
                ],
              ],
            ),
          ),
```

Envuelve los chips de foto (el `Wrap(...)` con `ActionChip` Tomar foto / Galería, líneas ~792-807) con su guía. Reemplaza ese `Wrap(` por:

```dart
          OnboardingGuide(
            guideKey: 'client.request_photo.v1',
            steps: onboardingCopy['client.request_photo.v1']!,
            order: 2,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Tomar foto'),
                  onPressed: () => _pickPhoto(ImageSource.camera),
                ),
                ActionChip(
                  avatar: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galería'),
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                ),
              ],
            ),
          ),
```

- [ ] **Step 5: Corre el test y el análisis**

Run: `cd app && flutter test test/onboarding_copy_test.dart && flutter analyze`
Expected: PASS · 0 issues.

- [ ] **Step 6: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/client/create_request_screen.dart app/lib/features/shared/onboarding_copy.dart app/test/onboarding_copy_test.dart
git commit -m "feat(onboarding): guias tipo/foto/al-por-mayor en crear solicitud"
```

> Nota de aceptación: el orden real del tour (tipo→foto→enviar, y al-por-mayor al aparecer) se confirma en **smoke device** — la pantalla depende de `AiClient`/Supabase y no se pumpa entera en tests.

---

### Task 6: Guía del Catálogo (welcome)

**Files:**
- Modify: `app/lib/features/client/catalog_screen.dart` (envuelve el `Scaffold` de `CatalogView.build`, líneas ~164-309)
- Modify: `app/lib/features/shared/onboarding_copy.dart` (`client.catalog.v1`)
- Test: `app/test/catalog_onboarding_test.dart` (nuevo)

**Interfaces:**
- Consumes: `OnboardingGuide(mode: OnboardingMode.welcome)` (existente) + copy.

- [ ] **Step 1: Escribe el test que falla**

Crea `app/test/catalog_onboarding_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/client/catalog_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  testWidgets('catalogo: guia welcome la primera vez', (t) async {
    await t.pumpWidget(MaterialApp(
      home: CatalogView(
        actions: const [],
        fetch: ({required kind, search, categoryId, rubro, wholesale = false}) async => [],
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('ofrecen en sus tiendas'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Corre el test para verlo fallar**

Run: `cd app && flutter test test/catalog_onboarding_test.dart`
Expected: FAIL — no existe el copy ni la guía.

- [ ] **Step 3: Añade el copy**

En `onboarding_copy.dart` agrega:

```dart
  'client.catalog.v1': [
    OnboardingStep('Aquí ves productos que los proveedores ofrecen en sus tiendas.'),
  ],
```

- [ ] **Step 4: Envuelve el catálogo con la guía welcome**

En `catalog_screen.dart`, agrega los imports:

```dart
import '../shared/onboarding_guide.dart';
import '../shared/onboarding_copy.dart';
```

En `_CatalogViewState.build` (línea ~165), envuelve el `Scaffold` retornado con la guía welcome:

```dart
  @override
  Widget build(BuildContext context) => OnboardingGuide(
        guideKey: 'client.catalog.v1',
        steps: onboardingCopy['client.catalog.v1']!,
        mode: OnboardingMode.welcome,
        child: Scaffold(
          body: Column(children: [
            // ... (el resto del cuerpo actual, SIN cambios) ...
          ]),
        ),
      );
```

(Envuelve todo el `Scaffold(...)` existente como `child:` de `OnboardingGuide`; no toques su contenido.)

- [ ] **Step 5: Corre el test y el análisis**

Run: `cd app && flutter test test/catalog_onboarding_test.dart && flutter analyze`
Expected: PASS · 0 issues.

- [ ] **Step 6: No-regresión del catálogo**

Run: `cd app && flutter test test/catalog_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/client/catalog_screen.dart app/lib/features/shared/onboarding_copy.dart app/test/catalog_onboarding_test.dart
git commit -m "feat(onboarding): guia welcome del catalogo"
```

---

### Task 7: Guías de Chat (respuestas rápidas + denunciar)

**Files:**
- Modify: `app/lib/features/chat/widgets/composer.dart` (botón ✨ `auto_awesome_outlined`, línea ~170)
- Modify: `app/lib/features/chat/chat_screen.dart` (guía reveal existente ~746-751: `order: 1`; menú ⋮ del header ~841-921)
- Modify: `app/lib/features/shared/onboarding_copy.dart` (`chat.quick_replies.v1`, `chat.report.v1`)
- Test: `app/test/onboarding_copy_test.dart` (ya cubre estas claves, Task 5) + análisis + smoke.

**Interfaces:**
- Consumes: `OnboardingGuide(order:)` (Task 2). La guía reveal (`*.chat_reveal.v1`) ya existe: se le fija `order: 1`.

- [ ] **Step 1: Añade los copys**

En `onboarding_copy.dart` agrega:

```dart
  'chat.quick_replies.v1': [
    OnboardingStep('Aquí eliges mensajes predefinidos para responder rápido.'),
  ],
  'chat.report.v1': [
    OnboardingStep('¿Sientes algo deshonesto? Denúncialo desde aquí.'),
  ],
```

- [ ] **Step 2: Guía en el botón ✨ del composer**

En `composer.dart`, agrega los imports:

```dart
import '../../shared/onboarding_guide.dart';
import '../../shared/onboarding_copy.dart';
```

Envuelve el `IconButton` de respuestas rápidas (línea ~170) con su guía:

```dart
        OnboardingGuide(
          guideKey: 'chat.quick_replies.v1',
          steps: onboardingCopy['chat.quick_replies.v1']!,
          order: 2,
          child: IconButton(
              onPressed: _openQuickList,
              icon: const Icon(Icons.auto_awesome_outlined)),
        ),
```

- [ ] **Step 3: order y guía del menú ⋮ (denunciar)**

En `chat_screen.dart`, agrega los imports si no están:

```dart
import '../shared/onboarding_copy.dart';
```

(`onboarding_guide.dart` ya está importado por la guía reveal.)

A la guía reveal (líneas ~746-751) agrégale `order: 1`:

```dart
      body: OnboardingGuide(
        key: ValueKey(chatGuideKey),
        guideKey: chatGuideKey,
        mode: OnboardingMode.welcome,
        order: 1,
        steps: onboardingCopy[chatGuideKey]!,
        enabled: _conv != null,
        child: Column(children: [
```

Envuelve el `PopupMenuButton<String>` del header (líneas ~841-921) con la guía de denuncia. Reemplaza `PopupMenuButton<String>(` (la apertura) por:

```dart
        OnboardingGuide(
          guideKey: 'chat.report.v1',
          steps: onboardingCopy['chat.report.v1']!,
          order: 3,
          enabled: _conv != null,
          child: PopupMenuButton<String>(
```

y cierra el paréntesis extra del `OnboardingGuide` tras el cierre del `PopupMenuButton` (el `],` de `actions:` va después). En concreto, tras el cierre actual del `PopupMenuButton` (`        ),` justo antes de `      ],` de `actions:`), déjalo así:

```dart
          ),
        ),
      ],
```

- [ ] **Step 4: Corre el copy-test y el análisis**

Run: `cd app && flutter test test/onboarding_copy_test.dart && flutter analyze`
Expected: PASS · 0 issues.

- [ ] **Step 5: No-regresión del chat**

Run: `cd app && flutter test test/chat_test.dart test/chat_session_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/chat/widgets/composer.dart app/lib/features/chat/chat_screen.dart app/lib/features/shared/onboarding_copy.dart
git commit -m "feat(onboarding): guias respuestas rapidas + denunciar en chat"
```

> Nota de aceptación: el orden reveal→respuestas→denunciar se confirma en **smoke device** (chat depende de Supabase, no se pumpa entero).

---

### Task 8: Verificación final

**Files:** ninguno (solo verificación).

- [ ] **Step 1: Suite completa**

Run: `cd app && flutter test`
Expected: TODO verde (441+ tests).

- [ ] **Step 2: Análisis**

Run: `cd app && flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Smoke en device (manual)**

Compila release e instala (ver `jayalo-app-flutter-install-no-recompila-gotcha`):
`cd app && flutter build apk --release` → instalar el APK. Con una **cuenta nueva de cliente**, recorrer: Solicitudes (`+`→ejemplo→otros), Crear (tipo→foto→enviar; elegir Producto → al por mayor), Catálogo (welcome), primer Chat (reveal→respuestas→denunciar). Confirmar orden, reduced-motion y que ninguna reaparece tras verla.

---

## Notas para el ejecutor

- **Repo:** `jayalo-app` (C:/Users/ac/Downloads/jayalo-app), rama `feat/error-tracking`. `origin` = github.com/varvaros/jayaloapp. NO pushear sin el PO.
- El coordinador es **global**: un solo turno a la vez para toda la app. Los `order` por pantalla no colisionan porque solo una pantalla está montada a la vez (excepto el `+` del shell, que convive con Solicitudes — por eso `+`=1 < mis=2 < otros=3).
- La divergencia `wallet.credits` (provider-only) NO se toca en este plan.
