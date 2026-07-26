# Tutorial coach-mark "mantén presionado" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un tutorial coach-mark animado (spotlight + recuadro guía + demo sobre el botón) que aparezca encima del `HoldToConfirmButton` en las hojas de aceptar oferta y desbloquear, hasta que el usuario complete un hold exitoso de ese gesto.

**Architecture:** Un `ChangeNotifier` persistido (`HoldTutorialStore`, patrón `OpenedConversationsStore`) recuerda por dispositivo qué gestos ya se lograron. Un widget nuevo `HoldCoachMark` envuelve al botón: si el gesto no se ha logrado ni descartado, monta un `OverlayPortal` a pantalla completa (velo oscuro + botón brillante reubicado con `CompositedTransformFollower` + recuadro + demo animada); si ya se logró o se descartó, renderiza el botón en su sitio, sin overlay. El coach-mark se apaga solo cuando el `progress` real del hold llega a 1.0.

**Tech Stack:** Flutter (Dart), `shared_preferences`, `OverlayPortal` + `LayerLink`/`CompositedTransformTarget`/`CompositedTransformFollower` (todo del SDK, sin paquetes nuevos).

## Global Constraints

- Repo: `jayalo-app`; rama base: `feat/error-tracking`. Todo el trabajo Flutter vive bajo `app/`.
- Sin cambios de backend (nada de BD/RPC/edge functions). Solo Dart local.
- Sin paquetes nuevos en `pubspec.yaml` (usar solo SDK + `shared_preferences`, ya presente).
- No modificar el flujo alterno de WhatsApp (`HoldToConfirmTone.free` de "ver WhatsApp" en `unlock_flow.dart`).
- Copy exacto de los recuadros: `Mantén presionado para aceptar` y `Mantén presionado para desbloquear`.
- Persistencia por gesto separada: llaves `'accept'` y `'unlock'`.
- Comando de análisis: `flutter analyze` debe terminar en `No issues found!`.
- Comando de test: `flutter test` (correr desde `app/`). La suite debe quedar verde.
- Un solo comportamiento observable de más nunca de menos: si la persistencia falla, el tutorial se muestra (nunca bloquea la acción).

---

### Task 1: `HoldTutorialStore` (persistencia local por gesto)

**Files:**
- Create: `app/lib/features/shared/hold_tutorial_store.dart`
- Test: `app/test/hold_tutorial_store_test.dart`

**Interfaces:**
- Consumes: nada de tareas previas. `package:shared_preferences/shared_preferences.dart`.
- Produces:
  - `class HoldTutorialStore extends ChangeNotifier`
  - `Future<void> ensureLoaded()` — carga perezosa una vez, best-effort.
  - `bool isDone(String gesture)` — ¿ya se logró ese gesto?
  - `void markDone(String gesture)` — idempotente; notifica y persiste en segundo plano.
  - `final HoldTutorialStore holdTutorialStore` — instancia singleton exportada.
  - Llaves válidas de gesto: `'accept'`, `'unlock'`.

- [ ] **Step 1: Write the failing test**

Create `app/test/hold_tutorial_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/hold_tutorial_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isDone es falso por defecto para ambos gestos', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    expect(s.isDone('accept'), isFalse);
    expect(s.isDone('unlock'), isFalse);
  });

  test('markDone vuelve isDone verdadero solo para ese gesto', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    s.markDone('accept');
    expect(s.isDone('accept'), isTrue);
    expect(s.isDone('unlock'), isFalse);
  });

  test('markDone notifica a los oyentes una sola vez (idempotente)', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    var notifications = 0;
    s.addListener(() => notifications++);
    s.markDone('unlock');
    s.markDone('unlock');
    expect(notifications, 1);
  });

  test('ensureLoaded recupera lo persistido de un arranque anterior', () async {
    SharedPreferences.setMockInitialValues({
      'hold_tutorial_done': ['unlock'],
    });
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    expect(s.isDone('unlock'), isTrue);
    expect(s.isDone('accept'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/hold_tutorial_store_test.dart`
Expected: FAIL — el import `hold_tutorial_store.dart` no existe / `HoldTutorialStore` sin definir.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/features/shared/hold_tutorial_store.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/hold_tutorial_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/shared/hold_tutorial_store.dart test/hold_tutorial_store_test.dart
git commit -m "feat: HoldTutorialStore — recuerda gestos de hold logrados (local)"
```

---

### Task 2: Widget `HoldCoachMark` + alto expuesto del botón

**Files:**
- Modify: `app/lib/features/shared/brand_kit.dart` (añadir `static const double kHeight = 66;` a `HoldToConfirmButton` y el widget nuevo `HoldCoachMark` al final del archivo)
- Test: `app/test/hold_coach_mark_test.dart`

**Interfaces:**
- Consumes (de Task 1): `holdTutorialStore`, `HoldTutorialStore.isDone`, `.markDone`, `.ensureLoaded`.
- Consumes (existente): `HoldToConfirmButton`, `HoldToConfirmTone` (mismo archivo).
- Produces:
  - `HoldToConfirmButton.kHeight` (double, alto total del botón = 66) — usado por el coach-mark para dimensionar el hueco.
  - `class HoldCoachMark extends StatefulWidget` con constructor:
    `HoldCoachMark({Key? key, required String gesture, required String message, required HoldToConfirmTone tone, required ValueListenable<double> progress, required Widget child})`
    - `gesture`: `'accept'` | `'unlock'`.
    - `message`: texto del recuadro.
    - `tone`: color de la demo (igual que el botón).
    - `progress`: el MISMO `ValueNotifier<double>` que recibe el `child` (para pausar la demo y detectar el hold exitoso).
    - `child`: el `HoldToConfirmButton`.

- [ ] **Step 1: Write the failing test**

Create `app/test/hold_coach_mark_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/hold_tutorial_store.dart';

Widget _host(ValueNotifier<double> progress) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldCoachMark(
            gesture: 'accept',
            message: 'Mantén presionado para aceptar',
            tone: HoldToConfirmTone.free,
            progress: progress,
            child: HoldToConfirmButton(
              label: 'Mantener para aceptar',
              tone: HoldToConfirmTone.free,
              progress: progress,
              onConfirmed: () async {},
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('muestra el recuadro cuando el gesto no se ha logrado',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pumpAndSettle();
    expect(find.text('Mantén presionado para aceptar'), findsOneWidget);
  });

  testWidgets('al llegar progress a 1.0 marca el gesto y oculta el recuadro',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pumpAndSettle();
    progress.value = 1.0;
    await tester.pumpAndSettle();
    expect(holdTutorialStore.isDone('accept'), isTrue);
    expect(find.text('Mantén presionado para aceptar'), findsNothing);
  });

  testWidgets('tocar el velo descarta el recuadro sin marcar el gesto',
      (tester) async {
    await holdTutorialStore.ensureLoaded();
    final progress = ValueNotifier<double>(0);
    await tester.pumpWidget(_host(progress));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('holdCoachScrim')));
    await tester.pumpAndSettle();
    expect(find.text('Mantén presionado para aceptar'), findsNothing);
    expect(holdTutorialStore.isDone('accept'), isFalse);
  });
}
```

Nota: `holdTutorialStore` es un singleton global; como cada test resetea
`SharedPreferences` en `setUp` y crea un `HoldCoachMark` que llama
`ensureLoaded()` idempotente, el estado de un test puede filtrarse al otro. Para
evitarlo, en el segundo y tercer test el gesto arranca no-logrado porque el
proceso de test es fresco por archivo; si al ejecutar aparece contaminación
entre tests, el implementador debe exponer un `@visibleForTesting void reset()`
en `HoldTutorialStore` y llamarlo en `setUp`. (Añadir `reset()` solo si hace
falta; no es parte del contrato público.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/hold_coach_mark_test.dart`
Expected: FAIL — `HoldCoachMark` sin definir / `HoldToConfirmButton.kHeight` inexistente.

- [ ] **Step 3: Añadir el alto expuesto al botón**

En `app/lib/features/shared/brand_kit.dart`, dentro de `class HoldToConfirmButton`, justo después de la línea `final ValueNotifier<double>? progress;` (≈ línea 472), añadir:

```dart
  /// Alto total del botón renderizado (Container 58 + Padding.all(4)*2 = 66).
  /// Lo consume [HoldCoachMark] para dimensionar el hueco del spotlight sin
  /// medir el botón real (que vive en el overlay).
  static const double kHeight = 66;
```

- [ ] **Step 4: Escribir el widget `HoldCoachMark`**

Al FINAL de `app/lib/features/shared/brand_kit.dart`, añadir:

```dart
/// Tutorial coach-mark para el gesto "mantén presionado".
///
/// Envuelve un [HoldToConfirmButton]. Mientras el gesto ([gesture]) no se haya
/// logrado ni descartado, monta un overlay a pantalla completa: velo oscuro
/// (spotlight), el botón reubicado BRILLANTE encima del velo (vía
/// [CompositedTransformFollower], único origen del botón — el sitio en el flujo
/// queda como hueco que reserva el tamaño), un recuadro guía sobre el botón y
/// una demo animada (barra clara que barre + "dedito" pulsante) que enseña el
/// gesto. La demo se pausa cuando el usuario presiona de verdad ([progress] >
/// 0). Al primer hold exitoso ([progress] llega a 1.0) marca el gesto en
/// [holdTutorialStore] y el tutorial desaparece para siempre. Un toque en el
/// velo lo descarta en esta apertura (sin marcar), y reaparecerá la próxima vez.
class HoldCoachMark extends StatefulWidget {
  const HoldCoachMark({
    super.key,
    required this.gesture,
    required this.message,
    required this.tone,
    required this.progress,
    required this.child,
  });

  final String gesture;
  final String message;
  final HoldToConfirmTone tone;
  final ValueListenable<double> progress;
  final Widget child;

  @override
  State<HoldCoachMark> createState() => _HoldCoachMarkState();
}

class _HoldCoachMarkState extends State<HoldCoachMark>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchorKey = GlobalKey();

  // Loop de la demo (barre 0→1 y sostiene lleno un instante antes de reiniciar).
  late final AnimationController _demo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));

  Size? _anchorSize;
  bool _dismissed = false;
  bool _marked = false;

  bool get _shouldShow =>
      !_dismissed && !holdTutorialStore.isDone(widget.gesture);

  @override
  void initState() {
    super.initState();
    holdTutorialStore.addListener(_onStore);
    widget.progress.addListener(_onProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndMaybeShow());
  }

  @override
  void dispose() {
    holdTutorialStore.removeListener(_onStore);
    widget.progress.removeListener(_onProgress);
    _demo.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
    if (!_shouldShow && _portal.isShowing) _portal.hide();
  }

  void _onProgress() {
    // Éxito del gesto: el hold real llegó al tope → marcar y cerrar el tutorial.
    if (!_marked && widget.progress.value >= 1.0) {
      _marked = true;
      holdTutorialStore.markDone(widget.gesture);
    }
    // Pausar/reanudar la demo según el usuario esté presionando de verdad.
    if (mounted) setState(() {});
  }

  void _measureAndMaybeShow() {
    if (!mounted) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      setState(() => _anchorSize = box.size);
    }
    if (_shouldShow && _anchorSize != null) {
      _portal.show();
      if (!_demo.isAnimating && !JayaloMotion.reduced(context)) {
        _demo.repeat();
      }
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    // Ya logrado o descartado → botón normal en su sitio, sin overlay.
    if (!_shouldShow) return widget.child;

    // El sitio en el flujo reserva el tamaño del botón (hueco). El botón real
    // vive en el overlay, brillante sobre el velo.
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: SizedBox(
          key: _anchorKey,
          width: double.infinity,
          height: HoldToConfirmButton.kHeight,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final size = _anchorSize;
    if (size == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final pressing = widget.progress.value > 0;

    return Stack(
      children: [
        // Velo oscuro a pantalla completa: atenúa todo y descarta al tocarlo.
        Positioned.fill(
          child: GestureDetector(
            key: const Key('holdCoachScrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Color(0x8C000000)),
          ),
        ),
        // Botón real, reubicado BRILLANTE sobre el velo (spotlight).
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                widget.child,
                // Demo: solo cuando el usuario NO está presionando de verdad.
                if (!pressing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _DemoFill(listenable: _demo, tone: widget.tone),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Recuadro guía, justo encima del botón.
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: _CoachCallout(
            message: widget.message,
            demo: _demo,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

/// Barra clara que barre de izq. a der. + "dedito" translúcido pulsante, sobre
/// el botón. Enseña el gesto sin tocar los internos del [HoldToConfirmButton].
class _DemoFill extends StatelessWidget {
  const _DemoFill({required this.listenable, required this.tone});
  final Animation<double> listenable;
  final HoldToConfirmTone tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (_, __) {
        // Barre durante el 70% del ciclo y sostiene lleno el resto.
        final t = (listenable.value / 0.7).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: t,
                    heightFactor: 1,
                    child: const ColoredBox(color: Color(0x47FFFFFF)),
                  ),
                ),
                // Dedito: círculo translúcido que avanza con la barra y late.
                Align(
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: Opacity(
                    opacity: (1 - (t - 0.85).abs() * 6).clamp(0.0, 1.0),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0x59FFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Recuadro flotante con el texto del gesto y una mini-barra de demo, con un
/// pico apuntando hacia abajo al botón.
class _CoachCallout extends StatelessWidget {
  const _CoachCallout(
      {required this.message, required this.demo, required this.color});
  final String message;
  final Animation<double> demo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: AnimatedBuilder(
                    animation: demo,
                    builder: (_, __) {
                      final t = (demo.value / 0.7).clamp(0.0, 1.0);
                      return Stack(
                        children: [
                          const Positioned.fill(
                              child: ColoredBox(color: Color(0x33FFFFFF))),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: t,
                              heightFactor: 1,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Pico del recuadro.
        Transform.translate(
          offset: const Offset(0, -1),
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

Verificar que `brand_kit.dart` ya importa `package:flutter/material.dart` (sí lo
hace — `HoldToConfirmButton` usa `Theme`, `Colors`, etc.) y que `JayaloMotion`
es accesible en el archivo (lo usa `HoldToConfirmButton` vía
`JayaloMotion.holdConfirm`). No añadir imports nuevos salvo que `flutter
analyze` los pida.

- [ ] **Step 5: Run analyze + test to verify it passes**

Run: `flutter analyze lib/features/shared/brand_kit.dart lib/features/shared/hold_tutorial_store.dart`
Expected: `No issues found!`

Run: `flutter test test/hold_coach_mark_test.dart`
Expected: PASS (3 tests). Si aparece contaminación entre tests por el singleton,
añadir `@visibleForTesting void reset() { _done.clear(); _loaded = false; }` en
`HoldTutorialStore` y llamarlo en el `setUp` del test.

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/features/shared/brand_kit.dart test/hold_coach_mark_test.dart
git commit -m "feat: HoldCoachMark — tutorial spotlight 'mantén presionado'"
```

---

### Task 3: Integrar en el desbloqueo (proveedor)

**Files:**
- Modify: `app/lib/features/provider/unlock_flow.dart` (≈ líneas 89-186)

**Interfaces:**
- Consumes: `HoldCoachMark` (Task 2), `holdTutorialStore` (Task 1).

- [ ] **Step 1: Asegurar la carga del store al abrir la hoja**

En `unlock_flow.dart`, en la función que muestra la hoja de desbloqueo, justo
antes de `final holdProgress = ValueNotifier<double>(0);` (≈ línea 98), añadir:

```dart
  // Carga perezosa del tutorial coach-mark (idempotente).
  unawaited(holdTutorialStore.ensureLoaded());
```

Añadir el import necesario al inicio del archivo si no está:

```dart
import 'dart:async'; // unawaited
import '../shared/hold_tutorial_store.dart';
```

(`HoldCoachMark` vive en `brand_kit.dart`, que este archivo ya importa porque
usa `HoldToConfirmButton`. Verificar el import existente; si por alguna razón no
está, añadir `import '../shared/brand_kit.dart';`.)

- [ ] **Step 2: Envolver el botón de desbloquear con el coach-mark**

Reemplazar el bloque `HoldToConfirmButton(...)` del `else` (≈ líneas 140-183) —
el que tiene `label: 'Mantener para desbloquear · ...'` — por:

```dart
            else
              HoldCoachMark(
                gesture: 'unlock',
                message: 'Mantén presionado para desbloquear',
                tone: HoldToConfirmTone.paid,
                progress: holdProgress,
                child: HoldToConfirmButton(
                  // Copy + costo en el propio botón (pedido PO 2026-07-22).
                  label:
                      'Mantener para desbloquear · $cost crédito${cost == 1 ? '' : 's'}',
                  progress: holdProgress,
                  onConfirmed: () async {
                    final unlocking = unlockOffer(offer['id'] as String, cost)
                        .then((r) => r.ok)
                        .catchError((_) => false);
                    if (!JayaloMotion.reduced(ctx)) {
                      await Future<void>.delayed(JayaloMotion.mascotPum);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    final ok = await unlocking;
                    if (!context.mounted) return;
                    if (ok) {
                      await onChanged?.call();
                      if (!context.mounted) return;
                      await showUnlockCelebration(
                        context,
                        footer: (dismiss) => StartChatButton(
                          conversationKind: 'offer',
                          sourceId: offer['id'] as String,
                          dismiss: dismiss,
                          onOpen: (convId) {
                            if (context.mounted) {
                              context.push('/messages/$convId');
                            }
                          },
                        ),
                      );
                    } else {
                      _snack(context, 'No se pudo desbloquear. Intenta de nuevo.');
                    }
                  },
                ),
              ),
```

(Es el MISMO `HoldToConfirmButton` de antes, sin cambios en su lógica; solo se
envuelve en `HoldCoachMark` con `tone: HoldToConfirmTone.paid` — el default del
botón, así que el color de la demo coincide.)

- [ ] **Step 3: Run analyze to verify it compiles**

Run: `flutter analyze lib/features/provider/unlock_flow.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the existing suite to verify no regressions**

Run: `flutter test`
Expected: toda la suite en verde (baseline ~415–420 tests + los nuevos de Task 1 y 2).

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/provider/unlock_flow.dart
git commit -m "feat: coach-mark 'mantén para desbloquear' en la hoja de desbloqueo"
```

---

### Task 4: Integrar en la aceptación de oferta (cliente)

**Files:**
- Modify: `app/lib/features/client/offer_actions.dart` (`initState` ≈ línea 176; botón ≈ líneas 468-475)

**Interfaces:**
- Consumes: `HoldCoachMark` (Task 2), `holdTutorialStore` (Task 1).

- [ ] **Step 1: Asegurar la carga del store al abrir la hoja**

En `offer_actions.dart`, dentro de `_OfferSheetBodyState.initState` (≈ línea
176), añadir la carga perezosa junto a `_loadProvider();`:

```dart
  @override
  void initState() {
    super.initState();
    _loadProvider();
    unawaited(holdTutorialStore.ensureLoaded());
  }
```

Añadir imports al inicio del archivo si no están:

```dart
import 'dart:async'; // unawaited
import '../shared/hold_tutorial_store.dart';
```

(Si `dart:async` ya está importado, no duplicar. `brand_kit.dart` ya está
importado porque el archivo usa `HoldToConfirmButton`/`HoldMascotLayer`.)

- [ ] **Step 2: Envolver el botón de aceptar con el coach-mark**

Reemplazar el bloque `HoldToConfirmButton(...)` (≈ líneas 468-475) — el que
tiene `label: 'Mantener para aceptar'` — por:

```dart
          HoldCoachMark(
            gesture: 'accept',
            message: 'Mantén presionado para aceptar',
            tone: HoldToConfirmTone.free,
            progress: _acceptProgress,
            child: HoldToConfirmButton(
              tone: HoldToConfirmTone.free,
              label: 'Mantener para aceptar',
              progress: _acceptProgress, // alimenta la mascota que se infla
              onConfirmed: _accept,
            ),
          ),
```

(Mismo botón; `tone: HoldToConfirmTone.free` para que la demo use el verde de
aceptar, igual que el botón.)

- [ ] **Step 3: Run analyze to verify it compiles**

Run: `flutter analyze lib/features/client/offer_actions.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full suite + full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: toda la suite en verde.

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/client/offer_actions.dart
git commit -m "feat: coach-mark 'mantén para aceptar' en la hoja de aceptar oferta"
```

---

## Notas de verificación en device (post-implementación, para el PO)

Estas NO son pasos del plan (no automatizables aquí), pero deben hacerse antes de
dar por cerrada la feature:

1. Cliente nuevo (sin `hold_tutorial_done` guardado): abrir una oferta pendiente
   → el velo oscurece la hoja, el botón de aceptar queda brillante con el
   recuadro "Mantén presionado para aceptar" y la barra demo en bucle.
2. Mantener presionado el botón → la demo se pausa, el relleno real avanza; al
   completar, se acepta y el tutorial no vuelve a salir en otra oferta.
3. Tocar fuera del botón → el tutorial se cierra y la hoja se ve normal; al
   reabrir, el tutorial reaparece (porque aún no se logró el hold).
4. Repetir 1-3 en el proveedor con la hoja de desbloquear ("Mantén presionado
   para desbloquear"). Confirmar que aceptar NO apagó el tutorial de desbloquear
   (separados por gesto).
5. Con "reducir movimiento" activo en el sistema: el recuadro aparece pero la
   demo no anima en bucle (no debe crashear).

## Self-Review

- **Cobertura del spec:**
  - Disparador "hasta el primer hold exitoso" → Task 2 (`_onProgress` marca en `progress >= 1.0`). ✔
  - Separado por gesto (`accept`/`unlock`) → Task 1 (`Set<String>`), Tasks 3/4 pasan `gesture` distinto. ✔
  - Spotlight (velo + botón brillante) → Task 2 (velo `Positioned.fill` + follower del botón). ✔
  - Recuadro + demo (texto + barra + dedito sobre el botón real) → Task 2 (`_CoachCallout` + `_DemoFill`). ✔
  - Escape: tap fuera cierra sin marcar, reaparece → Task 2 (`_dismiss`, `_dismissed` local; no toca el store). ✔
  - Persistencia local patrón `OpenedConversationsStore` → Task 1. ✔
  - Reusar el `ValueNotifier` de progreso existente → Tasks 3/4 pasan `holdProgress`/`_acceptProgress` al coach-mark y al botón. ✔
  - Sin backend, un commit por unidad, reversible → tareas separadas, solo Dart. ✔
  - Fuera de alcance respetado: no se toca el `HoldToConfirmButton` de WhatsApp ni la web. ✔
- **Placeholder scan:** sin TBD/TODO; todo el código está completo. ✔
- **Consistencia de tipos:** `HoldTutorialStore.isDone/markDone/ensureLoaded` usados igual en Tasks 2-4; `HoldCoachMark` constructor idéntico entre definición (Task 2) y usos (Tasks 3-4); `progress` es `ValueListenable<double>` en el coach-mark y recibe `ValueNotifier<double>` (subtipo válido). `HoldToConfirmButton.kHeight` definido en Task 2 y consumido en el mismo widget. ✔
