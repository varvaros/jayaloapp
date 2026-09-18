# Intro «Jayi te recibe» — plan de implementación (app)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reescribir el carrusel de primera apertura de la app con el guion del PO, un Jayi persistente que cambia de mano (pulgar arriba, moneda dorada) y la lámina de créditos leída de `bonus_config()`.

**Architecture:** Se conserva el `PageView` de `LoginScreen` (deslizar, PopScope, `animateToPage` ya probados) y se saca de él solo la escena: `JayiScene(pose:)` vive fija sobre el PageView y anima el cambio de pose en `didUpdateWidget`. La secuencia de láminas es una función pura `introSteps()`; el copy vive en `intro_copy.dart`; las revelaciones de texto van en `intro_reveal.dart` sobre `flutter_animate`; los créditos se leen una vez y se congelan al elegir rol.

**Tech Stack:** Flutter 3 / Dart 3, `flutter_animate ^4.5.0` (ya en `pubspec`), `shared_preferences`, `supabase_flutter`, `flutter_test`. Spec: `docs/superpowers/specs/2026-09-18-intro-jayi-te-recibe-design.md`.

## Global Constraints

- Repo vivo: `C:/Users/ac/Downloads/jayalo-app`, rama `feat/fecha-pautada-app`, HEAD `77f77c2`. **Esta tanda va en worktree propio** `C:/Users/ac/Downloads/jayalo-app-intro`, rama `feat/intro-jayi-te-recibe`. No tocar `app/pubspec.yaml` (está sucio en el otro worktree) hasta la Task 9.
- Todos los comandos de Flutter se corren desde `app/` del worktree: `cd C:/Users/ac/Downloads/jayalo-app-intro/app`.
- **⛔ No usar `assets/anim/jayi_celebrando*.json`** (Lottie de ganar cosas dentro de la app).
- Anatomía de Jayi intocable: cuerpo `0xFF6B3FE8`, un ojo, pupila `0xFF5A2FD6`, dos antenas, sin boca. La moneda es lo único no violeta.
- Copy exacto del spec §3, con «Jáyalo» con tilde. Pesos tipográficos 400–700 máximo (el grito va en 700; nada por encima).
- Toda duración y curva sale de `JayaloMotion`; ningún `Duration(milliseconds:)` ni `Curves.` suelto en las pantallas.
- `dart format` solo sobre los ficheros tocados (reescribe medio repo si se pasa entero).
- Cada cambio que quite o renombre un símbolo lleva su inventario de consumidores (regla PO de 4 agentes: analista + contraste antes; verificador + certificador después). El inventario de esta tanda está en la Task 0.
- Los tests con animación NO usan `pumpAndSettle` (ticker perpetuo de `JayiScene`): pumps explícitos con los tokens.
- Commits pequeños, en español, con `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## Mapa de ficheros

| Fichero | Acción | Responsabilidad |
|---|---|---|
| `app/lib/core/motion.dart` | modificar | tokens `intro`, `introGesture`, `introLand`, `introRead`, `introHint`, `bounce` |
| `app/lib/features/auth/intro_copy.dart` | reescribir | `IntroSlide`, `IntroStep`, `introSteps()`, `introSlideFor()`, `IntroRoleCard`, copys |
| `app/lib/features/auth/intro_reveal.dart` | crear | `IntroReveal`, `IntroWords`, `IntroCounter` |
| `app/lib/features/auth/jayi_scene.dart` | reescribir | `JayiPose`, `JayiScene(pose:)`, transiciones, oro |
| `app/lib/data/repos.dart` | añadir | `welcomeCreditsFrom()`, `fetchWelcomeCredits()` |
| `app/lib/features/auth/login_screen.dart` | modificar | flujo por `IntroStep`, escenario fuera del PageView, recuadros, chevrón, reacción, créditos |
| `app/test/intro_copy_test.dart` | reescribir | secuencia y copys |
| `app/test/intro_reveal_test.dart` | crear | revelaciones y contador |
| `app/test/jayi_scene_test.dart`, `app/test/jayi_scene_pixels_test.dart` | reescribir | poses, oro, transición |
| `app/test/welcome_credits_test.dart` | crear | parser |
| `app/test/login_intro_carousel_test.dart`, `app/test/login_intro_once_test.dart` | reescribir | flujo completo |
| `docs/qa/2026-09-18-smoke-intro-jayi.md` | crear | smoke del PO |

---

### Task 0: Worktree, rama e inventario (analista + contraste)

**Files:**
- Ninguno de código. Crea el worktree y deja el inventario en el ledger.

- [ ] **Step 1: Crear el worktree desde el HEAD vivo**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git worktree add -b feat/intro-jayi-te-recibe C:/Users/ac/Downloads/jayalo-app-intro 77f77c2
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter pub get
```
Expected: `Preparing worktree (new branch 'feat/intro-jayi-te-recibe')` y `pub get` sin cambios en `pubspec.lock`.

- [ ] **Step 2: Comprobar que la suite parte en verde**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/intro_copy_test.dart test/login_intro_carousel_test.dart test/login_intro_once_test.dart test/jayi_scene_test.dart test/jayi_scene_pixels_test.dart
```
Expected: `All tests passed!` (30 casos).

- [ ] **Step 3: Inventario de consumidores (entregable del analista)**

Símbolos que esta tanda quita o renombra, y quién los consume hoy (medido con `grep -rn` en `app/lib` y `app/test` el 2026-09-18):

| Símbolo | Consumidores | Qué pasa con cada uno |
|---|---|---|
| `JayiSceneKind` (enum) y `JayiScene(kind:)` | `login_screen.dart`, `jayi_scene_test.dart`, `jayi_scene_pixels_test.dart` | Task 3 añade `JayiPose`/`JayiScene(pose:)` y deja `JayiScene.kind()` como puente; Task 6 quita el puente y el enum |
| `kIntroCommon`, `kIntroSlides`, `IntroSlide.highlight` obligatorio | `login_screen.dart`, `intro_copy_test.dart`, `jayi_scene_test.dart`, `login_intro_carousel_test.dart` | Task 1 reescribe copy y tests de copy; Tasks 3 y 6 reescriben el resto |
| Textos «Busco algo» / «Vendo algo» | `login_screen.dart`; comentarios en `core/session_state.dart:37`, `push/push_permission.dart:14`, `push/push_service.dart:277`; tests del intro | Task 6 cambia la pantalla y los tests; Task 8 corrige los tres comentarios |
| `_pageCount`, `_isAccessSlide`, `_sceneFor` (privados de `LoginScreen`) | solo `login_screen.dart` | sustituidos por `introSteps()` en Task 6 |

Nada fuera del intro consume estos símbolos. `IntroRoleStore`, `IntroSeenStore`, `introRoleRedirect` y `RoleStore` **no cambian**.

- [ ] **Step 4: Contraste (agente independiente)**

Dispara un agente de solo lectura con este encargo literal: «En `C:/Users/ac/Downloads/jayalo-app-intro/app`, comprueba con grep que la tabla del Step 3 del plan `docs/superpowers/plans/2026-09-18-intro-jayi-te-recibe.md` es COMPLETA (¿algún consumidor más de `JayiSceneKind`, `kIntroCommon`, `kIntroSlides`, «Busco algo», «Vendo algo»?) y MÍNIMA (¿el plan propone cambiar algo que el spec §1 no exige?). Devuelve solo diferencias.» Si devuelve un consumidor nuevo, añádelo a la tabla y al task que lo cubre antes de seguir.

---

### Task 1: Tokens de movimiento y copy del guion

**Files:**
- Modify: `app/lib/core/motion.dart` (después de `mascotPum`, línea ~231)
- Rewrite: `app/lib/features/auth/intro_copy.dart`
- Rewrite: `app/test/intro_copy_test.dart`

**Interfaces:**
- Produces: `JayaloMotion.intro` (420 ms), `JayaloMotion.introGesture` (560 ms), `JayaloMotion.introLand` (720 ms), `JayaloMotion.introRead` (2600 ms), `JayaloMotion.introHint` (1000 ms), `JayaloMotion.bounce` (`Cubic`).
- Produces: `enum IntroStep { ask, react, consumerFree, providerOffers, providerCoin, neutralClose }`; `List<IntroStep> introSteps({required IntroRole? role, required bool skipped, required int credits})`; `IntroSlide introSlideFor(IntroStep step, {IntroRole? role, int credits = 0})`; `class IntroSlide { String? shout; String headline; String? highlight; String sub; int? counter; }` (el `headline` de la moneda lleva el marcador literal `{n}`); `class IntroRoleCard { String title; String sub; }` con `kIntroConsumerCard`, `kIntroProviderCard`; `bool introStepIsAccess(List<IntroStep> steps, int i)`.

- [ ] **Step 1: Escribir los tests del copy (fallan: símbolos inexistentes)**

`app/test/intro_copy_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  group('introSteps', () {
    test('sin rol ni saltar: solo la pregunta', () {
      expect(introSteps(role: null, skipped: false, credits: 5), [IntroStep.ask]);
    });
    test('saltó sin elegir: pregunta y cierre neutro', () {
      expect(
        introSteps(role: null, skipped: true, credits: 5),
        [IntroStep.ask, IntroStep.neutralClose],
      );
    });
    test('cliente: tres láminas, la última es la gratis', () {
      expect(
        introSteps(role: IntroRole.consumer, skipped: false, credits: 5),
        [IntroStep.ask, IntroStep.react, IntroStep.consumerFree],
      );
    });
    test('proveedor con bono: cuatro láminas y la moneda al final', () {
      expect(
        introSteps(role: IntroRole.provider, skipped: false, credits: 5),
        [IntroStep.ask, IntroStep.react, IntroStep.providerOffers, IntroStep.providerCoin],
      );
    });
    test('proveedor SIN bono: la moneda no existe', () {
      expect(
        introSteps(role: IntroRole.provider, skipped: false, credits: 0),
        [IntroStep.ask, IntroStep.react, IntroStep.providerOffers],
      );
    });
    test('los accesos van SIEMPRE en la última lámina cuando hay más de una', () {
      final one = introSteps(role: null, skipped: false, credits: 0);
      expect(introStepIsAccess(one, 0), isFalse);
      final prov = introSteps(role: IntroRole.provider, skipped: false, credits: 0);
      expect(introStepIsAccess(prov, 2), isTrue);
      expect(introStepIsAccess(prov, 1), isFalse);
    });
  });

  group('copy', () {
    test('la pregunta lleva la marca con tilde y bifurca', () {
      final s = introSlideFor(IntroStep.ask);
      expect(s.headline, 'En Jáyalo conectamos clientes con proveedores.');
      expect(s.sub, '¿Tú qué eres?');
      expect(s.shout, isNull);
    });
    test('la reacción grita según el lado', () {
      expect(introSlideFor(IntroStep.react, role: IntroRole.consumer).shout, '¡Genial!');
      expect(introSlideFor(IntroStep.react, role: IntroRole.provider).shout, '¡Bien!');
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.consumer).sub,
        'Aquí haces una solicitud y esperas que proveedores te hagan ofertas.',
      );
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.provider).sub,
        'Aquí encontrarás clientes que buscan exactamente lo que vendes.',
      );
    });
    test('solo la reacción grita', () {
      for (final step in IntroStep.values.where((s) => s != IntroStep.react)) {
        expect(introSlideFor(step, role: IntroRole.provider, credits: 5).shout, isNull, reason: '$step');
      }
    });
    test('la moneda lleva el número en el marcador y como contador', () {
      final s = introSlideFor(IntroStep.providerCoin, credits: 5);
      expect(s.headline, 'Tienes {n} créditos de regalo para desbloquear clientes.');
      expect(s.counter, 5);
    });
    test('el realce, cuando existe, es subcadena del titular', () {
      for (final step in IntroStep.values) {
        final s = introSlideFor(step, role: IntroRole.consumer, credits: 5);
        if (s.highlight != null) expect(s.headline, contains(s.highlight));
      }
    });
    test('ningún titular va vacío y solo la moneda va sin apoyo', () {
      for (final step in IntroStep.values) {
        final s = introSlideFor(step, role: IntroRole.provider, credits: 5);
        expect(s.headline.isNotEmpty || s.shout != null, isTrue, reason: '$step');
        if (step != IntroStep.providerCoin) expect(s.sub, isNotEmpty, reason: '$step');
      }
    });
    test('los recuadros dicen quién eres', () {
      expect(kIntroConsumerCard.title, 'Soy un cliente');
      expect(kIntroProviderCard.title, 'Soy un proveedor');
    });
  });
}
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/intro_copy_test.dart
```
Expected: error de compilación (`introSteps` no definido).

- [ ] **Step 3: Tokens en `motion.dart`**

Añadir dentro de `JayaloMotion`, justo después de `mascotPum`:
```dart
  // ── Intro de primera apertura (spec 2026-09-18-intro-jayi-te-recibe) ──
  /// Revelaciones de texto y objetos pequeños: palabras del titular,
  /// recuadros, la frase de la reacción, los accesos, la etiqueta.
  static const intro = Duration(milliseconds: 420);

  /// Un gesto de Jayi: el pulgar que sube, el saltito, el grito «¡Genial!».
  static const introGesture = Duration(milliseconds: 560);

  /// Jayi aterriza al abrir; la moneda sube y aterriza.
  static const introLand = Duration(milliseconds: 720);

  /// Tiempo de lectura de la reacción antes de avanzar sola. NO es
  /// animación: con «reducir animaciones» se respeta igual.
  static const introRead = Duration(milliseconds: 2600);

  /// Cuándo aparece el «Siguiente» fantasma de la reacción.
  static const introHint = Duration(milliseconds: 1000);

  /// El ÚNICO rebote del sistema de movimiento. Solo lo usan el pulgar de
  /// Jayi y el grito de la reacción: es un gesto de personaje, no un menú.
  static const bounce = Cubic(.34, 1.45, .64, 1);
```

- [ ] **Step 4: Reescribir `intro_copy.dart`**

```dart
import 'intro_role_store.dart';

/// Una lámina del intro.
///
/// [shout] es el grito de la reacción («¡Genial!»); solo esa lámina lo tiene.
/// [highlight] es subcadena LITERAL de [headline] y se pinta en violeta.
/// [counter] es el número que cuenta de 0 a n donde [headline] lleva `{n}`.
class IntroSlide {
  const IntroSlide({
    this.shout,
    required this.headline,
    this.highlight,
    required this.sub,
    this.counter,
  });

  final String? shout;
  final String headline;
  final String? highlight;
  final String sub;
  final int? counter;
}

/// Un recuadro de la lámina común.
class IntroRoleCard {
  const IntroRoleCard(this.title, this.sub);
  final String title;
  final String sub;
}

/// Las láminas posibles. La secuencia real la da [introSteps].
enum IntroStep { ask, react, consumerFree, providerOffers, providerCoin, neutralClose }

/// Qué láminas ve este usuario, en orden. Pura: la pantalla solo la lee.
///
/// Sin rol el carrusel es de UNA lámina (no se puede deslizar a una lámina
/// que aún no sabe de qué lado está el usuario); al «Saltar» sin elegir se
/// abre un cierre neutro. Con rol, el cliente ve 3 y el proveedor 4 — o 3 si
/// el bono de bienvenida vale 0: el gancho solo se promete si se paga.
List<IntroStep> introSteps({
  required IntroRole? role,
  required bool skipped,
  required int credits,
}) {
  if (role == null) {
    return skipped ? const [IntroStep.ask, IntroStep.neutralClose] : const [IntroStep.ask];
  }
  return switch (role) {
    IntroRole.consumer => const [IntroStep.ask, IntroStep.react, IntroStep.consumerFree],
    IntroRole.provider => [
      IntroStep.ask,
      IntroStep.react,
      IntroStep.providerOffers,
      if (credits > 0) IntroStep.providerCoin,
    ],
  };
}

/// ¿La lámina `i` es la de los accesos (el FINAL del carrusel)?
/// Con una sola lámina no hay final: esa única lámina es la de la pregunta.
bool introStepIsAccess(List<IntroStep> steps, int i) =>
    steps.length > 1 && i == steps.length - 1;

const kIntroConsumerCard = IntroRoleCard('Soy un cliente', 'Busco productos o servicios');
const kIntroProviderCard = IntroRoleCard('Soy un proveedor', 'Vendo productos o servicios');

const _ask = IntroSlide(
  headline: 'En Jáyalo conectamos clientes con proveedores.',
  sub: '¿Tú qué eres?',
);

const _reactConsumer = IntroSlide(
  shout: '¡Genial!',
  headline: '',
  sub: 'Aquí haces una solicitud y esperas que proveedores te hagan ofertas.',
);

const _reactProvider = IntroSlide(
  shout: '¡Bien!',
  headline: '',
  sub: 'Aquí encontrarás clientes que buscan exactamente lo que vendes.',
);

const _consumerFree = IntroSlide(
  headline: 'Para ti, todas las funciones son gratis.',
  sub: 'Navega con libertad.',
);

// El apoyo es propuesta (no guion del PO): se quita sin tocar nada más.
const _providerOffers = IntroSlide(
  headline: 'Hacer ofertas es gratis.',
  sub: 'Responde a las solicitudes de tu zona sin gastar ni un crédito.',
);

// El apoyo es propuesta (no guion del PO): se quita sin tocar nada más.
const _neutralClose = IntroSlide(
  headline: 'En Jáyalo conectamos clientes con proveedores.',
  sub: 'Entra y elige tu lado cuando quieras.',
);

/// El copy de una lámina. [role] solo importa en la reacción; [credits] solo
/// en la moneda.
IntroSlide introSlideFor(IntroStep step, {IntroRole? role, int credits = 0}) =>
    switch (step) {
      IntroStep.ask => _ask,
      IntroStep.react =>
        role == IntroRole.provider ? _reactProvider : _reactConsumer,
      IntroStep.consumerFree => _consumerFree,
      IntroStep.providerOffers => _providerOffers,
      IntroStep.providerCoin => IntroSlide(
        headline: 'Tienes {n} créditos de regalo para desbloquear clientes.',
        highlight: '{n}',
        sub: '',
        counter: credits,
      ),
      IntroStep.neutralClose => _neutralClose,
    };
```

- [ ] **Step 5: Correr los tests del copy**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/intro_copy_test.dart
```
Expected: `All tests passed!` (13). El resto del proyecto **no compila todavía** (`login_screen.dart` usa `kIntroCommon`): es esperado hasta la Task 6; `flutter analyze` se corre al final de la Task 6.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/core/motion.dart app/lib/features/auth/intro_copy.dart app/test/intro_copy_test.dart && git commit -m "feat(intro): el guion del PO como secuencia pura, y los tokens ilustrativos

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Revelaciones de texto (`intro_reveal.dart`)

**Files:**
- Create: `app/lib/features/auth/intro_reveal.dart`
- Create: `app/test/intro_reveal_test.dart`

**Interfaces:**
- Consumes: `JayaloMotion.intro`, `JayaloMotion.brake`, `JayaloMotion.bounce`, `JayaloMotion.reduced(context)`, `JayaloMotion.fast`.
- Produces: `IntroReveal({required Widget child, Duration delay = Duration.zero, Duration duration = JayaloMotion.intro, double dy = 10, Curve curve = JayaloMotion.brake, double? scaleFrom})`; `IntroWords({required String text, required TextStyle style, Duration delay = Duration(milliseconds: 120), Duration step = Duration(milliseconds: 38)})`; `IntroCounter({required int to, required TextStyle style, Duration delay = Duration(milliseconds: 360)})`.

- [ ] **Step 1: Tests (fallan: fichero inexistente)**

`app/test/intro_reveal_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/intro_reveal.dart';

void main() {
  Widget host(Widget child, {required bool reduced}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  double opacityOf(WidgetTester t, String text) {
    final el = t.element(find.text(text));
    final fades = el.findAncestorWidgetOfExactType<FadeTransition>();
    return fades?.opacity.value ?? 1;
  }

  testWidgets('con reduce-motion el hijo está a la vista desde el primer frame', (t) async {
    await t.pumpWidget(host(const IntroReveal(child: Text('hola')), reduced: true));
    await t.pump();
    expect(find.text('hola'), findsOneWidget);
    expect(opacityOf(t, 'hola'), 1);
  });

  testWidgets('con animación: invisible al montar, visible tras delay + duración', (t) async {
    await t.pumpWidget(host(
      const IntroReveal(delay: JayaloMotion.fast, child: Text('hola')),
      reduced: false,
    ));
    await t.pump();
    expect(opacityOf(t, 'hola'), 0);
    await t.pump(JayaloMotion.fast + JayaloMotion.intro + const Duration(milliseconds: 20));
    expect(opacityOf(t, 'hola'), 1);
  });

  testWidgets('IntroWords parte el titular en palabras', (t) async {
    await t.pumpWidget(host(
      const IntroWords(text: 'En Jáyalo conectamos', style: TextStyle(fontSize: 20)),
      reduced: true,
    ));
    await t.pump();
    expect(find.text('En'), findsOneWidget);
    expect(find.text('Jáyalo'), findsOneWidget);
    expect(find.text('conectamos'), findsOneWidget);
  });

  testWidgets('IntroCounter cuenta hasta n y con reduce-motion nace en n', (t) async {
    await t.pumpWidget(host(
      const IntroCounter(to: 5, style: TextStyle(fontSize: 20)),
      reduced: true,
    ));
    await t.pump();
    expect(find.text('5'), findsOneWidget);

    await t.pumpWidget(host(
      const IntroCounter(to: 5, style: TextStyle(fontSize: 20), delay: Duration.zero),
      reduced: false,
    ));
    await t.pump();
    expect(find.text('0'), findsOneWidget);
    await t.pump(JayaloMotion.fast * 2 + const Duration(milliseconds: 10)); // 310 ms
    expect(find.text('3'), findsOneWidget, reason: 'a 120 ms por cifra, 310 ms son 3');
    await t.pump(JayaloMotion.fast * 3);
    expect(find.text('5'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/intro_reveal_test.dart
```
Expected: error de compilación (`intro_reveal.dart` no existe).

- [ ] **Step 3: Implementar `intro_reveal.dart`**

```dart
// Revelaciones del intro: fade + subida con retardo, palabra a palabra, y el
// contador de créditos. Todas respetan «reducir animaciones» pintando el
// estado FINAL desde el primer frame (no el instante 0).
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/motion.dart';

/// Aparece con fundido y una subida corta, tras [delay].
class IntroReveal extends StatelessWidget {
  const IntroReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = JayaloMotion.intro,
    this.dy = 10,
    this.curve = JayaloMotion.brake,
    this.scaleFrom,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double dy;
  final Curve curve;

  /// Si se da, además crece desde este factor (el grito: .72 con `bounce`).
  final double? scaleFrom;

  @override
  Widget build(BuildContext context) {
    if (JayaloMotion.reduced(context)) return child;
    var a = child
        .animate(delay: delay)
        .fadeIn(duration: duration, curve: curve)
        .moveY(begin: dy, end: 0, duration: duration, curve: curve);
    if (scaleFrom != null) {
      a = a.scale(
        begin: Offset(scaleFrom!, scaleFrom!),
        end: const Offset(1, 1),
        duration: duration,
        curve: curve,
        alignment: Alignment.centerLeft,
      );
    }
    return a;
  }
}

/// El titular palabra a palabra: cada una sube 10 px, escalonadas [step].
class IntroWords extends StatelessWidget {
  const IntroWords({
    super.key,
    required this.text,
    required this.style,
    this.delay = const Duration(milliseconds: 120),
    this.step = const Duration(milliseconds: 38),
  });

  final String text;
  final TextStyle style;
  final Duration delay;
  final Duration step;

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: style.fontSize! * .28,
      runSpacing: 0,
      children: [
        for (var i = 0; i < words.length; i++)
          IntroReveal(delay: delay + step * i, child: Text(words[i], style: style)),
      ],
    );
  }
}

/// Cuenta de 0 a [to] a 120 ms por cifra; cada cifra entra a 122 % y baja.
class IntroCounter extends StatelessWidget {
  const IntroCounter({
    super.key,
    required this.to,
    required this.style,
    this.delay = const Duration(milliseconds: 360),
  });

  final int to;
  final TextStyle style;
  final Duration delay;

  /// 120 ms por cifra, o sea `JayaloMotion.fast` menos 30: el ritmo de un
  /// contador, no el de un toque.
  static const stepPerDigit = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    if (JayaloMotion.reduced(context) || to <= 0) return Text('$to', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: to.toDouble()),
      duration: stepPerDigit * to,
      curve: Curves.linear,
      builder: (_, v, __) {
        final shown = v.ceil();
        final frac = v - v.floorToDouble();
        final scale = (shown == 0 || frac == 0) ? 1.0 : 1.22 - .22 * frac;
        return Transform.scale(scale: scale, child: Text('$shown', style: style));
      },
    ).animate(delay: delay).fadeIn(duration: JayaloMotion.fast);
  }
}
```

Nota sobre el retardo del contador: `TweenAnimationBuilder` arranca al montar; el `delay`
solo retrasa el fundido. Si el test de «310 ms ⇒ 3» falla por ese arranque temprano,
envolver el builder en `FutureBuilder(future: Future.delayed(delay))` y hasta entonces
pintar `Text('0')`. El test fija `delay: Duration.zero` justo para no depender de ello.

- [ ] **Step 4: Correr los tests**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/intro_reveal_test.dart
```
Expected: `All tests passed!` (4). Si `opacityOf` no encuentra `FadeTransition` (flutter_animate usa su propio `Animate` con `Opacity`), cambiar el helper a buscar `Opacity` u `FadeTransition`, el primero que exista: `el.findAncestorWidgetOfExactType<Opacity>()?.opacity`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/features/auth/intro_reveal.dart app/test/intro_reveal_test.dart && git commit -m "feat(intro): revelaciones de texto y contador de créditos, con reduce-motion en estado final

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Las cinco poses de Jayi (estáticas)

**Files:**
- Modify: `app/lib/features/auth/jayi_scene.dart` (enum, widget, painter)
- Rewrite: `app/test/jayi_scene_pixels_test.dart`
- (`app/test/jayi_scene_test.dart` NO se toca aquí: no compila desde la Task 1 por `kIntroCommon` y se reescribe entero en la Task 6)

**Interfaces:**
- Produces: `enum JayiPose { open, thumbsUp, free, priceTag, coin }`; `JayiScene({Key? key, required JayiPose pose})`; **puente temporal** `factory JayiScene.kind(JayiSceneKind kind)` (common→open, consumerOffers→free, consumerLock→free, providerTray→priceTag, providerCoin→coin) para que `login_screen.dart` siga compilando hasta la Task 6.
- Colores: `_oro = Color(0xFFF2BD4A)`, `_oroHondo = Color(0xFFD89A22)`, `_oroBorde = Color(0xFFC98D1F)`, `_oroLuz = Color(0xFFFFF0BF)`.

- [ ] **Step 1: Test de píxeles (falla: `JayiPose` no existe)**

`app/test/jayi_scene_pixels_test.dart` (sustituye el fichero):
```dart
// Que cada pose pinte SU escena, comprobado en píxeles, y que la moneda sea
// DORADA de verdad (única figura no violeta del intro).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/jayi_scene.dart';

void main() {
  Future<ui.Image> pintar(WidgetTester t, JayiPose pose, {bool reduced = true, Duration? after}) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 220, child: JayiScene(pose: pose)),
            ),
          ),
        ),
      ),
    );
    if (after != null) {
      await t.pump(after);
    } else {
      await t.pumpAndSettle();
    }
    late ui.Image img;
    await t.runAsync(() async {
      final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      img = await render.toImage(pixelRatio: 1);
    });
    return img;
  }

  Future<List<int>> png(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  testWidgets('las 5 poses son visualmente DISTINTAS entre sí', (t) async {
    final porPose = <JayiPose, List<int>>{};
    for (final pose in JayiPose.values) {
      final img = await pintar(t, pose);
      await t.runAsync(() async => porPose[pose] = await png(img));
      img.dispose();
    }
    final poses = JayiPose.values;
    for (var i = 0; i < poses.length; i++) {
      for (var j = i + 1; j < poses.length; j++) {
        expect(porPose[poses[i]], isNot(equals(porPose[poses[j]])),
            reason: '${poses[i]} y ${poses[j]} pintan lo mismo');
      }
    }
  });

  testWidgets('la moneda es DORADA: hay píxeles con rojo alto y azul bajo', (t) async {
    final img = await pintar(t, JayiPose.coin);
    late int dorados;
    await t.runAsync(() async {
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      dorados = 0;
      for (var i = 0; i < px.length; i += 4) {
        final r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3];
        if (a > 200 && r > 200 && g > 140 && b < 120) dorados++;
      }
    });
    img.dispose();
    expect(dorados, greaterThan(150), reason: 'la moneda mide r=16 en un lienzo de 220: cientos de píxeles');
  });

  testWidgets('el pulgar arriba NO pinta oro (la moneda es lo único no violeta)', (t) async {
    final img = await pintar(t, JayiPose.thumbsUp);
    late int dorados;
    await t.runAsync(() async {
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      dorados = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i + 3] > 200 && px[i] > 200 && px[i + 1] > 140 && px[i + 2] < 120) dorados++;
      }
    });
    img.dispose();
    expect(dorados, 0);
  });
}
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/jayi_scene_pixels_test.dart
```
Expected: error de compilación (`JayiPose` no definido).

- [ ] **Step 3: Enum, widget y puente**

En `jayi_scene.dart`, sustituir `enum JayiSceneKind {…}` por:
```dart
/// Qué tiene Jayi en la mano. Una pose por lámina del intro.
enum JayiPose {
  /// Pregunta y cierre neutro: bracitos abiertos entre la solicitud y la oferta.
  open,

  /// La reacción: pulgar arriba.
  thumbsUp,

  /// «Navega con libertad»: bracitos abiertos y flote amplio.
  free,

  /// «Hacer ofertas es gratis»: la etiqueta de precio.
  priceTag,

  /// Los créditos de regalo: la moneda dorada.
  coin,
}

/// PUENTE hasta la Task 6 del plan 2026-09-18: `login_screen.dart` todavía
/// habla en láminas viejas. Se borra junto con este enum.
enum JayiSceneKind { common, consumerOffers, consumerLock, providerTray, providerCoin }
```
Y el widget:
```dart
class JayiScene extends StatefulWidget {
  const JayiScene({super.key, required this.pose});

  factory JayiScene.kind(JayiSceneKind kind, {Key? key}) => JayiScene(
    key: key,
    pose: switch (kind) {
      JayiSceneKind.common => JayiPose.open,
      JayiSceneKind.consumerOffers || JayiSceneKind.consumerLock => JayiPose.free,
      JayiSceneKind.providerTray => JayiPose.priceTag,
      JayiSceneKind.providerCoin => JayiPose.coin,
    },
  );

  final JayiPose pose;

  @override
  State<JayiScene> createState() => _JayiSceneState();
}
```
En `login_screen.dart`, **solo** cambiar `JayiScene(kind: _sceneFor(i))` por `JayiScene.kind(_sceneFor(i))` (una línea; la reescritura de verdad es la Task 6). En `_JayiSceneState.build`, `painter: _ScenePainter(pose: widget.pose, …)`.

- [ ] **Step 4: Colores y el pintor por pose**

Añadir junto a `_jayi`/`_hondo`:
```dart
/// La moneda: lo ÚNICO no violeta del intro (PO 2026-09-18).
const _oro = Color(0xFFF2BD4A);
const _oroHondo = Color(0xFFD89A22);
const _oroBorde = Color(0xFFC98D1F);
const _oroLuz = Color(0xFFFFF0BF);
const _oroClaro = Color(0xFFFBD66E);
const _oroOscuro = Color(0xFFE5A72A);
```
En `_ScenePainter`: campo `final JayiPose pose;` (sustituye `kind`), y en `paint`:
```dart
    switch (pose) {
      case JayiPose.open:
        _paintOpen(canvas, bubbles: true);
      case JayiPose.free:
        _paintOpen(canvas, bubbles: false);
      case JayiPose.thumbsUp:
        _paintThumb(canvas);
      case JayiPose.priceTag:
        _paintTag(canvas);
      case JayiPose.coin:
        _paintCoin(canvas);
    }
```
Renombrar `_paintCommon` → `_paintOpen(Canvas canvas, {required bool bubbles})` (las dos `_bubble` solo si `bubbles`). Borrar `_paintOffers`, `_offer`, `_paintLock`, `_paintTray` y la moneda violeta. Renombrar `_paintTray` NO: la etiqueta es nueva:
```dart
  // ── Proveedor: la etiqueta de precio («Hacer ofertas es gratis») ────────
  void _paintTag(Canvas canvas) {
    final dy = animated ? _pingPong(_phase(_t, 3.4), 0, -6) : 0.0;
    _arm(canvas, const Offset(104, 78), const Offset(114, 76), const Offset(120, 68));
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawPath(
      Path()
        ..moveTo(118, 30)
        ..lineTo(144, 30)
        ..arcToPoint(const Offset(152, 38), radius: const Radius.circular(8))
        ..lineTo(152, 58)
        ..arcToPoint(const Offset(144, 66), radius: const Radius.circular(8))
        ..lineTo(118, 66)
        ..lineTo(106, 48)
        ..close(),
      _fill,
    );
    canvas.drawCircle(const Offset(124, 47), 4, Paint()..color = const Color(0xFFFFFFFF));
    final linea = _stroke(3.4, const Color(0xFFFFFFFF));
    canvas.drawLine(const Offset(134, 42), const Offset(147, 42), linea);
    canvas.drawLine(const Offset(134, 52), const Offset(143, 52), linea);
    canvas.restore();
  }

  // ── La reacción: pulgar arriba. Un solo grupo que rota desde el hombro ──
  /// [rot] en grados: 0 = arriba; 78 = brazo caído (estado de entrada).
  void _paintThumb(Canvas canvas, {double rot = 0, double alpha = 1}) {
    const shoulder = Offset(104, 78);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(rot * math.pi / 180);
    canvas.translate(-shoulder.dx, -shoulder.dy);
    _arm(canvas, shoulder, const Offset(116, 72), const Offset(124, 60));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(116, 50, 21, 17), const Radius.circular(7.5)),
      _fill,
    );
    canvas.save();
    canvas.translate(119.75, 53);
    canvas.rotate(-14 * math.pi / 180);
    canvas.translate(-119.75, -53);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(115.5, 35, 8.5, 20), const Radius.circular(4.25)),
      _fill,
    );
    canvas.restore();
    final nudillo = _stroke(1.6, _hondo.withValues(alpha: .55));
    canvas.drawLine(const Offset(122, 58.5), const Offset(131, 58.5), nudillo);
    canvas.drawLine(const Offset(122, 63), const Offset(130, 63), nudillo);
    canvas.restore();
  }

  // ── Los créditos: la moneda dorada en la palma ──────────────────────────
  void _paintCoin(Canvas canvas) {
    _arm(canvas, const Offset(104, 78), const Offset(118, 76), const Offset(126, 66));
    _arm(canvas, const Offset(124, 68), const Offset(134, 72), const Offset(146, 66), 7);
    const c = Offset(141, 46);
    const r = 16.0;
    // Giro de reposo: de frente el 68 % del ciclo, de canto solo al final.
    final sx = animated
        ? _stops(_phase(_t, 3.2), const [0, .68, .79, .86, 1], const [1, 1, .12, .12, 1])
        : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    canvas.translate(-c.dx, -c.dy);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_oroClaro, _oroOscuro],
        ).createShader(rect),
    );
    canvas.drawCircle(c, r, _stroke(2.6, _oroBorde));
    canvas.drawCircle(c, 10.5, _stroke(2, _oroLuz.withValues(alpha: .9)));
    // La «J».
    final j = _stroke(2.4, _oroBorde);
    canvas.drawPath(
      Path()
        ..moveTo(137, 40)
        ..lineTo(142.5, 40)
        ..arcToPoint(const Offset(142.5, 46), radius: const Radius.circular(3))
        ..lineTo(137, 46)
        ..moveTo(137, 46)
        ..lineTo(137, 52.5),
      j,
    );
    // El brillo cruza una vez por ciclo, recortado al círculo.
    final gx = animated
        ? _stops(_phase(_t, 3.2), const [0, .22, .60, 1], const [-26, 26, 26, -26])
        : 0.0;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 1)));
    canvas.translate(gx, 0);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(28 * math.pi / 180);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(137.5, 26, 7, 40), const Radius.circular(3.5)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .55),
    );
    canvas.restore();
    canvas.restore();
  }
```
`_oro` y `_oroHondo` quedan reservados para el destello (Task 4). Si el analizador avisa de constantes sin usar, dejar solo las que se usen y volver a añadir en Task 4.

- [ ] **Step 5: Correr el test de píxeles**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/jayi_scene_pixels_test.dart
```
Expected: `All tests passed!` (3). (`jayi_scene_test.dart` sigue sin compilar hasta la Task 6; es esperado.)

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/features/auth/jayi_scene.dart app/lib/features/auth/login_screen.dart app/test/jayi_scene_pixels_test.dart && git commit -m "feat(jayi): cinco poses del intro nuevo — pulgar arriba y moneda dorada

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Jayi persistente: aterriza, salta y cambia de mano

**Files:**
- Modify: `app/lib/features/auth/jayi_scene.dart` (`_JayiSceneState`, `_ScenePainter`)
- Modify: `app/test/jayi_scene_pixels_test.dart` (+2 casos)

**Interfaces:**
- Consumes: `JayaloMotion.introLand`, `introGesture`, `intro`, `base`, `bounce`, `brake`, `emphasized`, `exit`.
- Produces: el mismo `JayiScene(pose:)`; internamente el painter recibe `prev`, `changedAt`, `pose`.

- [ ] **Step 1: Tests de transición (fallan: hoy el cambio de pose es instantáneo)**

Añadir a `jayi_scene_pixels_test.dart`:
```dart
  testWidgets('cambiar de pose ANIMA: a 100 ms el frame difiere del final', (t) async {
    final key = GlobalKey();
    Widget host(JayiPose pose) => MediaQuery(
      data: const MediaQueryData(disableAnimations: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: SizedBox(width: 220, child: JayiScene(pose: pose))),
        ),
      ),
    );
    Future<List<int>> shot() async {
      late List<int> bytes;
      await t.runAsync(() async {
        final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await render.toImage(pixelRatio: 1);
        bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        img.dispose();
      });
      return bytes;
    }

    await t.pumpWidget(host(JayiPose.open));
    await t.pump(const Duration(seconds: 2)); // el aterrizaje ya terminó
    await t.pumpWidget(host(JayiPose.thumbsUp));
    await t.pump(const Duration(milliseconds: 100));
    final medio = await shot();
    await t.pump(const Duration(milliseconds: 900)); // 1 000 ms: pulgar arriba
    final fin = await shot();
    expect(medio, isNot(equals(fin)), reason: 'el pulgar debe estar subiendo a los 100 ms');
  });

  testWidgets('con reduce-motion el cambio de pose es INSTANTÁNEO y sin accesorio saliente', (t) async {
    final a = await pintar(t, JayiPose.thumbsUp);
    late List<int> directo;
    await t.runAsync(() async => directo = await png(a));
    a.dispose();

    // Montar en `open`, cambiar a `thumbsUp`, y sin dejar pasar tiempo debe
    // pintar exactamente lo mismo que montar directo en `thumbsUp`.
    final key = GlobalKey();
    Widget host(JayiPose pose) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: RepaintBoundary(key: key, child: SizedBox(width: 220, child: JayiScene(pose: pose)))),
      ),
    );
    await t.pumpWidget(host(JayiPose.open));
    await t.pump();
    await t.pumpWidget(host(JayiPose.thumbsUp));
    await t.pump();
    late List<int> cambiado;
    await t.runAsync(() async {
      final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await render.toImage(pixelRatio: 1);
      cambiado = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      img.dispose();
    });
    expect(cambiado, equals(directo));
  });
```

- [ ] **Step 2: Correr y ver que falla el primero**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/jayi_scene_pixels_test.dart
```
Expected: «cambiar de pose ANIMA» falla (los dos frames son iguales porque hoy no hay entrada). El de reduce-motion pasa ya.

- [ ] **Step 3: Estado de transición en `_JayiSceneState`**

```dart
class _JayiSceneState extends State<JayiScene> with TickerProviderStateMixin {
  final ValueNotifier<double> _t = ValueNotifier(0);
  Ticker? _ticker;
  bool _reduced = false;

  /// La pose anterior y en qué segundo del reloj cambió: el pintor anima la
  /// entrada de la nueva y la salida de la vieja a partir de aquí. `null` =
  /// nunca cambió (solo el aterrizaje del montaje).
  JayiPose? _prev;
  double _changedAt = 0;

  @override
  void didUpdateWidget(covariant JayiScene old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) {
      _prev = old.pose;
      _changedAt = _t.value;
    }
  }

  // didChangeDependencies y dispose: como hoy.

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _vbW / _vbH,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _ScenePainter(
          pose: widget.pose,
          prev: _prev,
          changedAt: _changedAt,
          time: _t,
          animated: !_reduced,
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: El pintor con tiempo desde el cambio**

Campos y helpers nuevos en `_ScenePainter`:
```dart
  final JayiPose? prev;
  final double changedAt;

  /// Segundos desde el último cambio de pose (∞ sin animación ⇒ estado final).
  double get _since => animated ? time.value - changedAt : double.infinity;

  /// Segundos desde el montaje (el aterrizaje).
  double get _sinceMount => animated ? time.value : double.infinity;

  static double _sec(Duration d) => d.inMilliseconds / 1000;
  static final _land = _sec(JayaloMotion.introLand);
  static final _gesture = _sec(JayaloMotion.introGesture);
  static final _reveal = _sec(JayaloMotion.intro);
  static final _out = _sec(JayaloMotion.base);

  /// Progreso 0..1 de una entrada de [dur] segundos que empezó en [delay].
  double _in(double dur, [double delay = 0]) => ((_since - delay) / dur).clamp(0.0, 1.0);
```
`paint` pasa a:
```dart
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _vbW);
    _paintHalo(canvas);
    _paintGround(canvas);
    _paintJayi(canvas);
    // La pose saliente se apaga en `base` (250 ms). Sin animación no hay
    // saliente: `_since` es infinito.
    if (prev != null && _since < _out) {
      final q = JayaloMotion.exit.transform((_since / _out).clamp(0.0, 1.0));
      _paintPose(canvas, prev!, entering: 1, alpha: 1 - q, thumbRot: 78 * q);
    }
    _paintPose(canvas, pose, entering: 1, alpha: 1, thumbRot: 0);
    canvas.restore();
  }

  void _paintPose(Canvas canvas, JayiPose p, {required double entering, required double alpha, required double thumbRot}) {
    switch (p) {
      case JayiPose.open:
        _paintOpen(canvas, bubbles: true, alpha: alpha);
      case JayiPose.free:
        _paintOpen(canvas, bubbles: false, alpha: alpha);
      case JayiPose.thumbsUp:
        // Entrada: de 78° a 0° con el único rebote del sistema, en `introGesture`.
        // Luego, dos golpecitos en el último tercio de un ciclo de 2,8 s.
        final p = _in(_gesture);
        var rot = 78 * (1 - JayaloMotion.bounce.transform(p));
        if (p >= 1 && animated) {
          rot += _stops(_phase(time.value - changedAt - _gesture, 2.8),
              const [0, .62, .70, .78, .86, .94, 1], const [0, 0, -6, 0, -5, 0, 0]);
        }
        _paintThumb(canvas, rot: thumbRot > 0 ? thumbRot : rot, alpha: alpha);
      case JayiPose.priceTag:
        _paintTag(canvas, alpha: alpha * _in(_reveal), dy: 12 * (1 - JayaloMotion.brake.transform(_in(_reveal))));
      case JayiPose.coin:
        _paintCoin(canvas, alpha: alpha);
    }
  }
```
Adaptar `_paintOpen`, `_paintTag` y `_paintCoin` para recibir `alpha` (y `dy` en la etiqueta) envolviendo su dibujo en `canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha))` … `canvas.restore()`. En `_paintOpen`, las burbujas entran subiendo 12 px y fundiendo en `_reveal` s con retardos `_land * .8` y `_land * .9` cuando `prev == null` (primer montaje), y sin retardo tras un cambio de pose.

Entrada de la moneda dentro de `_paintCoin`, antes de dibujarla (sustituye el `sx` fijo cuando la entrada está en curso):
```dart
    // Entrada: sale de detrás de la palma girando, se pasa y aterriza
    // (`introLand`), empezando a mitad de la subida del brazo.
    final pin = _in(_land, _reveal * .5);
    final e = JayaloMotion.brake.transform(pin);
    final dyIn = _stops(e, const [0, .60, .78, 1], const [30, -6, 2, 0]);
    final sxIn = _stops(e, const [0, .60, 1], const [.15, 1, 1]);
    final aIn = _stops(e, const [0, .35, 1], const [0, 1, 1]);
    // El destello: uno solo, al 80 % del aterrizaje, dura `intro`.
    final ps = ((_since - _reveal * .5 - _land * .8) / _reveal).clamp(0.0, 1.0);
```
y usar `sx = pin < 1 ? sxIn : <giro de reposo>`, `translate(0, dyIn)`, alpha `alpha * aIn`. El destello (solo si `animated && ps > 0 && ps < 1`): estrella de 4 puntas en (158, 27), radio exterior 5 y interior 1.6, `_oro`, opacidad `_stops(ps, [0,.4,1],[0,1,0])`, escala `_stops(ps,[0,.4,1],[.2,1.15,.7])`, rotación `45° * ps`.

Aterrizaje y saltito en `_paintJayi`:
```dart
  void _paintJayi(Canvas canvas) {
    var dy = animated ? _pingPong(_phase(_t, pose == JayiPose.free ? 3.4 : 4), 0, pose == JayiPose.free ? -9 : -4) : 0.0;
    var sx = 1.0, sy = 1.0, rot = 0.0;
    if (pose == JayiPose.free && animated) rot = _pingPong(_phase(_t, 3.4), -1.2, 1.2) * math.pi / 180;
    // Aterrizaje al abrir (los primeros `introLand` s desde el montaje).
    if (_sinceMount < _land) {
      final p = JayaloMotion.brake.transform(_sinceMount / _land);
      dy += _stops(p, const [0, .55, 1], const [-34, 0, 0]);
      sx = _stops(p, const [0, .55, .68, .84, 1], const [.98, 1, 1.06, .98, 1]);
      sy = _stops(p, const [0, .55, .68, .84, 1], const [1.02, 1, .93, 1.03, 1]);
    }
    // Saltito al entrar en la reacción (los primeros `introGesture` s).
    if (pose == JayiPose.thumbsUp && prev != null && _since < _gesture) {
      final p = JayaloMotion.emphasized.transform(_since / _gesture);
      dy += _stops(p, const [0, .22, .52, .78, 1], const [0, 0, -10, 0, 0]);
      sx *= _stops(p, const [0, .22, .52, .78, 1], const [1, 1.05, .97, 1.03, 1]);
      sy *= _stops(p, const [0, .22, .52, .78, 1], const [1, .93, 1.05, .96, 1]);
    }
    // Las antenas tiemblan al 75 % del aterrizaje y del saltito.
    final wob = _wobble(_sinceMount, _land) + (pose == JayiPose.thumbsUp && prev != null ? _wobble(_since, _gesture) : 0);
    canvas.save();
    canvas.translate(70, 78 + dy); // pivote: el centro del cuerpo
    canvas.rotate(rot);
    canvas.scale(sx, sy);
    canvas.translate(-70, -78);
    canvas.translate(14, 8);
    canvas.scale(112 / 120);
    _antena(canvas, const Offset(46, 33), const Offset(42, 21), const Offset(38, 16), const Offset(33, 11), wob);
    _antena(canvas, const Offset(74, 33), const Offset(78, 21), const Offset(82, 16), const Offset(87, 11), wob);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 30, 80, 72), const Radius.circular(26)), _fill);
    canvas.drawCircle(const Offset(49, 64), 17, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(const Offset(55, 70) + _pupil(), 7, Paint()..color = _hondo);
    canvas.restore();
  }

  /// Grados de temblor de antena tras un evento de [dur] s ocurrido hace [since] s.
  double _wobble(double since, double dur) {
    final start = dur * .75;
    if (since < start || since > start + _gesture) return 0;
    return _stops((since - start) / _gesture, const [0, .28, .58, .82, 1], const [0, -9, 6, -2.5, 0]);
  }

  void _antena(Canvas canvas, Offset base, Offset c1, Offset c2, Offset tip, double deg) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-base.dx, -base.dy);
    canvas.drawPath(Path()..moveTo(base.dx, base.dy)..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, tip.dx, tip.dy), _stroke(5));
    canvas.restore();
  }

  static Offset _lookOf(JayiPose p) => switch (p) {
    JayiPose.open => const Offset(-1, 2),
    JayiPose.thumbsUp => const Offset(3, -3),
    JayiPose.free => Offset.zero,
    JayiPose.priceTag => const Offset(3, -1),
    JayiPose.coin => const Offset(4, -2),
  };

  /// La pupila mira al objeto nuevo en `intro` s, con `emphasized`.
  Offset _pupil() {
    final to = _lookOf(pose);
    if (prev == null || _since >= _reveal) return to;
    final k = JayaloMotion.emphasized.transform(_since / _reveal);
    return Offset.lerp(_lookOf(prev!), to, k)!;
  }
```
`shouldRepaint`: `old.pose != pose || old.prev != prev || old.changedAt != changedAt || old.animated != animated`.

- [ ] **Step 5: Correr los tests de escena**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/jayi_scene_pixels_test.dart
```
Expected: `All tests passed!` (5). Si «reduce-motion instantáneo» falla, la causa típica es que `_paintOpen` usa `prev == null` para retardar las burbujas: con `animated == false` los retardos no deben aplicar (usar `_in` que ya devuelve 1 con `_since = ∞`).

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/features/auth/jayi_scene.dart app/test/jayi_scene_pixels_test.dart && git commit -m "feat(jayi): un solo Jayi que aterriza, salta y cambia de mano entre láminas

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Los créditos de regalo desde `bonus_config()`

**Files:**
- Modify: `app/lib/data/repos.dart` (al final del fichero)
- Create: `app/test/welcome_credits_test.dart`

**Interfaces:**
- Produces: `int welcomeCreditsFrom(dynamic row)` (puro) y `Future<int> fetchWelcomeCredits()` (red; nunca lanza; 0 en error o timeout de 3 s).

- [ ] **Step 1: Test del parser (falla)**

`app/test/welcome_credits_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  test('lee welcome_credits de una fila', () {
    expect(welcomeCreditsFrom({'welcome_credits': 5, 'referral_credits': 5}), 5);
  });
  test('acepta la fila envuelta en lista (forma de PostgREST para RETURNS TABLE)', () {
    expect(welcomeCreditsFrom([{'welcome_credits': 3}]), 3);
  });
  test('acepta el número como texto', () {
    expect(welcomeCreditsFrom({'welcome_credits': '7'}), 7);
  });
  test('cualquier forma rara es 0: nunca se promete lo que no se sabe', () {
    expect(welcomeCreditsFrom(null), 0);
    expect(welcomeCreditsFrom([]), 0);
    expect(welcomeCreditsFrom({'welcome_credits': -2}), 0);
    expect(welcomeCreditsFrom({'welcome_credits': 'cinco'}), 0);
    expect(welcomeCreditsFrom({'otra': 1}), 0);
  });
}
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/welcome_credits_test.dart
```
Expected: error de compilación (`welcomeCreditsFrom` no definido).

- [ ] **Step 3: Implementar en `repos.dart`**

Al final del fichero:
```dart
// ── Bono de bienvenida (intro de primera apertura, spec 2026-09-18) ────────

/// `welcome_credits` de la respuesta de `bonus_config()`. Pura.
///
/// La RPC es `RETURNS TABLE`, así que PostgREST puede devolver una lista de
/// una fila o la fila sola según el cliente. Cualquier cosa que no sea un
/// entero ≥ 0 vale 0: el intro solo promete créditos que de verdad se pagan.
int welcomeCreditsFrom(dynamic row) {
  var r = row;
  if (r is List) {
    if (r.isEmpty) return 0;
    r = r.first;
  }
  if (r is! Map) return 0;
  final v = r['welcome_credits'];
  final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  return n < 0 ? 0 : n;
}

/// Cuántos créditos regala el alta de proveedor hoy. `anon` puede ejecutar
/// `bonus_config()` (medido 2026-09-18): se llama ANTES de autenticarse.
/// Nunca lanza; sin red o pasados 3 s devuelve 0, y la lámina de la moneda
/// no existe.
Future<int> fetchWelcomeCredits() async {
  try {
    final res = await supa.rpc('bonus_config').timeout(const Duration(seconds: 3));
    return welcomeCreditsFrom(res);
  } catch (_) {
    return 0;
  }
}
```

- [ ] **Step 4: Correr**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/welcome_credits_test.dart
```
Expected: `All tests passed!` (4).

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/data/repos.dart app/test/welcome_credits_test.dart && git commit -m "feat(intro): leer el bono de bienvenida de bonus_config() sin prometer lo que no se paga

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: La pantalla: flujo nuevo con Jayi fuera del carrusel

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart` (`_LoginScreenState` entero salvo login/Google/hoja de contraseña)
- Modify: `app/lib/features/auth/jayi_scene.dart` (borrar `JayiSceneKind` y `JayiScene.kind`)
- Rewrite: `app/test/login_intro_carousel_test.dart`, `app/test/login_intro_once_test.dart`, `app/test/jayi_scene_test.dart`

**Interfaces:**
- Consumes: `introSteps`, `introSlideFor`, `introStepIsAccess`, `kIntroConsumerCard`, `kIntroProviderCard`, `IntroReveal`, `IntroWords`, `IntroCounter`, `JayiScene(pose:)`, `JayiPose`, `fetchWelcomeCredits`.
- Produces: `LoginScreen({Key? key, Future<int> Function() fetchWelcomeCredits = fetchWelcomeCredits})`. En esta task la lámina `react` lleva un «Siguiente» normal y NO avanza sola (eso es la Task 7).

- [ ] **Step 1: Reescribir `login_intro_carousel_test.dart` (falla: copy y API nuevos)**

Cabecera y helpers (sustituyen a los actuales; el `phone()` y el `app()` se mantienen, `app()` gana créditos):
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app({int credits = 5, bool reduced = true}) => MaterialApp(
    home: LoginScreen(fetchWelcomeCredits: () async => credits),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(420 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Finder dots() => find.byKey(const Key('intro-dots'));
  int dotCount(WidgetTester t) => (t.widget<Row>(find.descendant(of: dots(), matching: find.byType(Row))).children.length);

  final ask = introSlideFor(IntroStep.ask);
  const cliente = 'Soy un cliente';
  const proveedor = 'Soy un proveedor';
```
Casos (cada `testWidgets` completo):
```dart
  testWidgets('primera apertura: la pregunta y los DOS recuadros', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    for (final w in ask.headline.split(' ')) {
      expect(find.text(w), findsWidgets, reason: 'palabra «$w» del titular');
    }
    expect(find.text(ask.sub), findsOneWidget);
    expect(find.text(cliente), findsOneWidget);
    expect(find.text(proveedor), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(dotCount(t), 3, reason: 'sin elegir se pintan 3, nunca 1');
  });

  testWidgets('tocar «Soy un proveedor» persiste la elección', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(await IntroRoleStore().read(), IntroRole.provider);
    expect(find.text('¡Bien!'), findsOneWidget);
  });

  testWidgets('proveedor con bono: 4 puntos, la etiqueta, y la moneda con el 5 al final', (t) async {
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(dotCount(t), 4);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Hacer ofertas es gratis.'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.textContaining('créditos de regalo'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Entrar con correo y contraseña'), findsOneWidget);
  });

  testWidgets('proveedor SIN bono: 3 láminas y los accesos en «Hacer ofertas es gratis»', (t) async {
    phone(t);
    await t.pumpWidget(app(credits: 0));
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(dotCount(t), 3);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Hacer ofertas es gratis.'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.textContaining('créditos de regalo'), findsNothing);
  });

  testWidgets('el bono que llega TARDE no mueve la lámina de accesos', (t) async {
    phone(t);
    final late = Completer<int>();
    await t.pumpWidget(MaterialApp(
      home: LoginScreen(fetchWelcomeCredits: () => late.future),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.pumpAndSettle();
    expect(dotCount(t), 3, reason: 'sin dato todavía, se congela en 0');
    late.complete(5);
    await t.pumpAndSettle();
    expect(dotCount(t), 3, reason: 'llegar tarde no añade lámina bajo el dedo');
  });

  testWidgets('cliente: tres láminas y «Navega con libertad» con los accesos', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(cliente));
    await t.pumpAndSettle();
    expect(find.text('¡Genial!'), findsOneWidget);
    expect(dotCount(t), 3);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Para ti, todas las funciones son gratis.'), findsOneWidget);
    expect(find.text('Navega con libertad.'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });

  testWidgets('CON animaciones: el avance ANIMA, no salta', (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(home: LoginScreen(fetchWelcomeCredits: () async => 5)));
    await t.pump();
    await t.pump(JayaloMotion.fast);
    await t.pump(JayaloMotion.introLand); // los recuadros ya se revelaron
    expect(find.text(cliente), findsOneWidget);
    await t.tap(find.text(cliente));
    await t.pump(); // save() resuelve
    await t.pump(); // postFrame pidió la página
    await t.pump(JayaloMotion.fast); // 150 de los 300 ms de `page`
    expect(find.text(cliente), findsOneWidget, reason: 'la lámina 0 aún sale');
    expect(find.text('¡Genial!'), findsOneWidget, reason: 'la reacción ya entra');
    await t.pump(JayaloMotion.page + JayaloMotion.introGesture);
    expect(find.text(cliente), findsNothing);
    expect(find.text('¡Genial!'), findsOneWidget);
  });

  testWidgets('tocar los DOS recuadros seguidos: gana el primero', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text(proveedor));
    await t.tap(find.text(cliente), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(await IntroRoleStore().read(), IntroRole.provider);
    expect(find.text('¡Bien!'), findsOneWidget);
  });

  testWidgets('con rol guardado arranca en la lámina de acceso', (t) async {
    SharedPreferences.setMockInitialValues({IntroRoleStore.kKey: 'provider'});
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await t.pumpAndSettle();
    expect(find.text(proveedor), findsNothing);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.textContaining('créditos de regalo'), findsOneWidget);
  });

  group('«Saltar» sin elegir lado', () {
    testWidgets('cierra en neutro con los DOS accesos y sin rol guardado', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(find.text('Entra y elige tu lado cuando quieras.'), findsOneWidget);
      expect(find.text('¡Genial!'), findsNothing);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(await IntroRoleStore().read(), isNull);
      expect(dotCount(t), 2);
    });
  });

  group('«Saltar» con rol ya elegido', () {
    testWidgets('cae en los accesos, no en una lámina intermedia', (t) async {
      phone(t);
      await t.pumpWidget(app(credits: 5));
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Saltar'), findsOneWidget);
      await t.tap(find.text('Saltar'));
      await t.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);
    });
  });

  group('atrás de Android', () {
    testWidgets('canPop es false fuera de la lámina 0', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop, isTrue);
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      expect(t.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop, isFalse);
    });

    testWidgets('el chevrón retrocede una lámina y deja reelegir', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text(proveedor));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('intro-back')));
      await t.pumpAndSettle();
      expect(find.text(cliente), findsOneWidget);
      expect(find.text(proveedor), findsOneWidget);
      await t.tap(find.text(cliente));
      await t.pumpAndSettle();
      expect(await IntroRoleStore().read(), IntroRole.consumer);
      expect(find.text('¡Genial!'), findsOneWidget);
    });
  });
}
```
(El caso «back machacado en plena transición no dobla la animación» se conserva tal cual está hoy, cambiando «Vendo algo» por `proveedor`.)

- [ ] **Step 2: Reescribir `login_intro_once_test.dart` y `jayi_scene_test.dart`**

En `login_intro_once_test.dart`: `LoginScreen(fetchWelcomeCredits: () async => 5)` en el `app()`, «Busco algo» → `'Soy un cliente'`, «Vendo algo» → `'Soy un proveedor'`, y el caso «elegir rol y avanzar hasta los accesos deja la marca» toca «Siguiente» **dos veces** (proveedor con bono son 4 láminas).

`jayi_scene_test.dart` queda con estos casos (sustituye el fichero; helpers `app()`/`phone()` como en el carrusel):
```dart
  JayiPose poseOnScreen(WidgetTester t) => t.widget<JayiScene>(find.byType(JayiScene)).pose;

  testWidgets('hay UN SOLO Jayi y vive fuera del carrusel', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(JayiScene), findsOneWidget);
    expect(find.descendant(of: find.byType(PageView), matching: find.byType(JayiScene)), findsNothing);
    expect(poseOnScreen(t), JayiPose.open);
  });

  testWidgets('cliente: pulgar arriba y luego libre — el MISMO widget cambia de pose', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    final antes = t.state(find.byType(JayiScene));
    await t.tap(find.text('Soy un cliente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.thumbsUp);
    expect(identical(t.state(find.byType(JayiScene)), antes), isTrue, reason: 'no se remonta');
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.free);
  });

  testWidgets('proveedor: pulgar, etiqueta y moneda', (t) async {
    phone(t);
    await t.pumpWidget(app(credits: 5));
    await t.pumpAndSettle();
    await t.tap(find.text('Soy un proveedor'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.thumbsUp);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.priceTag);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.coin);
  });

  testWidgets('saltar sin elegir: el cierre neutro sigue con los brazos abiertos', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('Saltar'));
    await t.pumpAndSettle();
    expect(poseOnScreen(t), JayiPose.open);
  });

  testWidgets('el fondo es el lienzo limpio, NO la portada a pantalla completa', (t) async {
    // Se conserva tal cual está hoy (busca que NO haya PortadaJayi en modo intro).
  });

  for (final pose in JayiPose.values) {
    testWidgets('$pose se pinta sin reventar', (t) async {
      await t.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 200, child: JayiScene(pose: pose)))));
      await t.pump();
      expect(tester.takeException(), isNull);
    });
  }
```

- [ ] **Step 3: Correr y ver que falla**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/login_intro_carousel_test.dart
```
Expected: error de compilación (`LoginScreen` no acepta `fetchWelcomeCredits`).

- [ ] **Step 4: Reescribir el estado de `LoginScreen`**

Imports nuevos en `login_screen.dart`: `'../../data/repos.dart' show fetchWelcomeCredits;` (o el import de repos que ya exista), `'intro_reveal.dart'`. Widget:
```dart
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.fetchWelcomeCredits = fetchWelcomeCredits});

  /// Inyectable para los tests: cuántos créditos regala el alta de proveedor.
  final Future<int> Function() fetchWelcomeCredits;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
```
Campos del estado (sustituyen a `_introRole`, `_skipped`, `_page`, `_pageCount`, `_isAccessSlide`, `_sceneFor`):
```dart
  IntroRole? _introRole;
  bool _skipped = false;
  int _page = 0;
  bool? _introSeen;
  bool _seenMarked = false;
  bool _choosing = false;

  /// Créditos de bienvenida según el servidor; `null` mientras no llega.
  int? _welcomeCredits;

  /// Los créditos CONGELADOS al elegir rol. Que el valor llegue después no
  /// cambia el número de láminas: si no, la lámina de accesos se movería bajo
  /// el dedo del usuario.
  int _credits = 0;

  List<IntroStep> get _steps =>
      introSteps(role: _introRole, skipped: _skipped, credits: _credits);

  bool _isAccessSlide(int i) => introStepIsAccess(_steps, i);

  JayiPose _poseFor(int i) => switch (_steps[i.clamp(0, _steps.length - 1)]) {
    IntroStep.ask || IntroStep.neutralClose => JayiPose.open,
    IntroStep.react => JayiPose.thumbsUp,
    IntroStep.consumerFree => JayiPose.free,
    IntroStep.providerOffers => JayiPose.priceTag,
    IntroStep.providerCoin => JayiPose.coin,
  };
```
`_restore()`:
```dart
  Future<void> _restore() async {
    final seen = await IntroSeenStore().read();
    if (!mounted) return;
    if (seen) {
      setState(() => _introSeen = true);
      return;
    }
    // Los créditos se piden en paralelo con el rol: no bloquean la lámina 0.
    unawaited(widget.fetchWelcomeCredits().then((n) {
      if (mounted) setState(() => _welcomeCredits = n);
    }));
    final role = await IntroRoleStore().read();
    if (!mounted) return;
    if (role == null) {
      setState(() => _introSeen = false);
      return;
    }
    // Con rol ya guardado se aterriza en los accesos: hace falta saber cuántas
    // láminas hay, así que aquí SÍ se espera a los créditos (3 s como mucho).
    final credits = _welcomeCredits ?? await widget.fetchWelcomeCredits();
    if (!mounted) return;
    setState(() {
      _introSeen = false;
      _introRole = role;
      _credits = credits;
      _page = _steps.length - 1;
    });
    _markSeenIfDone();
    unawaited(_afterLayout(() async {
      if (_pages.hasClients) _pages.jumpToPage(_steps.length - 1);
    }));
  }
```
`_chooseRole` congela: dentro del `setState` → `_introRole = role; _credits = _welcomeCredits ?? 0;`. `_skip`: `unawaited(_afterLayout(() => _goToPage(_steps.length - 1)))`. Añadir `_back()`:
```dart
  void _back() {
    if (_choosing || _busy || _page == 0) return;
    _choosing = true;
    unawaited(_goToPage(_page - 1).whenComplete(() => _choosing = false));
  }
```
y `_handleBackPop` pasa a llamar a `_back()`.

`build` (solo la rama del carrusel; las otras dos ramas quedan como hoy):
```dart
          : PopScope<Object?>(
              canPop: _page == 0,
              onPopInvokedWithResult: _handleBackPop,
              child: Scaffold(
                backgroundColor: JayaloColors.background,
                body: SafeArea(
                  child: Column(
                    children: [
                      _topRow(context),
                      // UN SOLO Jayi, fuera del carrusel: nunca se remonta, solo
                      // cambia de pose (y la escena anima ese cambio).
                      Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 6),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 210),
                            child: JayiScene(pose: _poseFor(_page)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _pages,
                          physics: _busy ? const NeverScrollableScrollPhysics() : null,
                          itemCount: _steps.length,
                          onPageChanged: (i) {
                            setState(() => _page = i);
                            _markSeenIfDone();
                          },
                          itemBuilder: _buildSlide,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Dots(active: _page, count: _steps.length == 1 ? 3 : _steps.length),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
```
`_topRow`: `Row` con tres celdas de ancho fijo: chevrón atrás (`IconButton(key: Key('intro-back'), icon: Icon(Icons.chevron_left_rounded), onPressed: _back)` dentro de `AnimatedOpacity` + `IgnorePointer`, visible si `_page > 0`), `_Wordmark` centrado, «Saltar» (visible con `_showSkip`). `_showSkip` pasa a: `_steps.length == 1 || (_page != _steps.length - 1 && _steps[_page] != IntroStep.react)`.

`_buildSlide`:
```dart
  Widget _buildSlide(BuildContext context, int i) {
    final step = _steps[i];
    final slide = introSlideFor(step, role: _introRole, credits: _credits);
    final Widget action = switch (step) {
      IntroStep.ask => _roleCards(context),
      _ when _isAccessSlide(i) => _accessStack(context),
      _ => FilledButton(style: _pill, onPressed: () => _goToPage(i + 1), child: const Text('Siguiente')),
    };
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SlideCopy(slide, wordByWord: step == IntroStep.ask),
              Padding(padding: const EdgeInsets.only(top: 22), child: action),
            ],
          ),
        ),
      ),
    );
  }
```
`_roleCards`: `kIntroConsumerCard` con `Icons.search_rounded` y `kIntroProviderCard` con `Icons.storefront_outlined`, cada `_RoleCard` envuelto en `IntroReveal(delay: Duration(milliseconds: 560 / 640), dy: 14)` (constantes locales `_cardDelay1`/`_cardDelay2` documentadas como «tras el aterrizaje de Jayi»). `_RoleCard` no cambia (sus íconos ya van sin fondo). `_accessStack`: envolver los tres hijos en `IntroReveal` con retardos `JayaloMotion.page * 1.1`, `+90 ms`, `+170 ms`, `dy: 14`. `_Dots`: añadir `key: const Key('intro-dots')` al `Row` y envolver cada punto en `TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: reduced ? Duration.zero : JayaloMotion.page, curve: JayaloMotion.bounce, key: ValueKey(i), builder: (_, s, child) => Transform.scale(scale: s, child: child), child: AnimatedContainer(...))` para que un punto nuevo nazca desde cero.

`_SlideCopy` nuevo:
```dart
class _SlideCopy extends StatelessWidget {
  const _SlideCopy(this.slide, {this.wordByWord = false});
  final IntroSlide slide;
  final bool wordByWord;

  static const _head = TextStyle(fontSize: 22, height: 1.28, fontWeight: FontWeight.w600, color: JayaloColors.head);

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (slide.shout != null) {
      children.add(IntroReveal(
        delay: const Duration(milliseconds: 110),
        duration: JayaloMotion.introGesture,
        curve: JayaloMotion.bounce,
        scaleFrom: .72,
        dy: 6,
        child: Text(slide.shout!, textAlign: TextAlign.left,
          style: const TextStyle(fontSize: 38, height: 1, fontWeight: FontWeight.w700, color: JayaloColors.primary)),
      ));
      children.add(const SizedBox(height: 10));
    }
    if (slide.headline.isNotEmpty) {
      children.add(wordByWord
          ? IntroWords(text: slide.headline, style: _head)
          : IntroReveal(child: _headline(slide)));
    }
    if (slide.sub.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      final isQuestion = slide == introSlideFor(IntroStep.ask);
      children.add(IntroReveal(
        delay: slide.shout != null ? const Duration(milliseconds: 520) : (isQuestion ? JayaloMotion.intro * 1.4 : Duration.zero),
        child: Text(slide.sub, textAlign: TextAlign.center,
          style: isQuestion
              ? const TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: JayaloColors.primary)
              : TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, color: JayaloColors.foreground.withValues(alpha: .9))),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: slide.shout != null ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: children);
  }

  /// El titular con el realce en violeta; si trae `{n}` y `counter`, ahí va el
  /// contador (la moneda).
  Widget _headline(IntroSlide s) {
    if (s.counter != null && s.headline.contains('{n}')) {
      final parts = s.headline.split('{n}');
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: parts[0]),
          WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
            child: IntroCounter(to: s.counter!, style: _head.copyWith(color: JayaloColors.primary, fontWeight: FontWeight.w700))),
          TextSpan(text: parts[1]),
        ]),
        textAlign: TextAlign.center, style: _head,
      );
    }
    final h = s.highlight;
    final i = h == null ? -1 : s.headline.indexOf(h);
    final span = i < 0
        ? TextSpan(text: s.headline)
        : TextSpan(children: [
            TextSpan(text: s.headline.substring(0, i)),
            TextSpan(text: h, style: const TextStyle(color: JayaloColors.primary)),
            TextSpan(text: s.headline.substring(i + h!.length)),
          ]);
    return Text.rich(span, textAlign: TextAlign.center, style: _head);
  }
}
```
Borrar en `jayi_scene.dart` el enum `JayiSceneKind` y el `factory JayiScene.kind`.

- [ ] **Step 5: Correr los tres ficheros de tests**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/login_intro_carousel_test.dart test/login_intro_once_test.dart test/jayi_scene_test.dart
```
Expected: `All tests passed!`. Fallos típicos y su causa: (a) `find.text('5')` no aparece → el `IntroCounter` con reduce-motion debe pintar `Text('5')` directo (Task 2) y `_credits` debe valer 5 (congelado en `_chooseRole`); (b) el test «llega TARDE» ve 4 puntos → `_steps` está leyendo `_welcomeCredits` en vez de `_credits`; (c) `pumpAndSettle` no asienta → algún `IntroReveal` no respeta `disableAnimations` (debe devolver el hijo pelado).

- [ ] **Step 6: `flutter analyze` del proyecto entero (primera vez que vuelve a compilar)**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter analyze
```
Expected: `No issues found!`. Si avisa de `_oro`/`_oroHondo` sin usar en `jayi_scene.dart`, el destello de la Task 4 no los está usando: corregir ahí, no borrar la constante.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/features/auth/login_screen.dart app/lib/features/auth/jayi_scene.dart app/test/login_intro_carousel_test.dart app/test/login_intro_once_test.dart app/test/jayi_scene_test.dart && git commit -m "feat(intro): el guion del PO en pantalla, con un solo Jayi fuera del carrusel y la lámina de créditos

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: La reacción avanza sola, con «Siguiente» fantasma

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart` (`_LoginScreenState`: temporizadores y la acción de `react`)
- Modify: `app/test/login_intro_carousel_test.dart` (+3 casos)

**Interfaces:**
- Consumes: `JayaloMotion.introRead`, `JayaloMotion.introHint`, `JayaloMotion.base`, `JayaloMotion.enter`.

- [ ] **Step 1: Tests (fallan: hoy la reacción no avanza sola)**

```dart
  group('la reacción', () {
    testWidgets('avanza sola a los 2 600 ms, no antes', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text(cliente));
      await t.pumpAndSettle();
      expect(find.text('¡Genial!'), findsOneWidget);
      await t.pump(JayaloMotion.introRead - const Duration(milliseconds: 1));
      expect(find.text('¡Genial!'), findsOneWidget, reason: 'todavía leyendo');
      await t.pump(const Duration(milliseconds: 2));
      await t.pumpAndSettle();
      expect(find.text('Para ti, todas las funciones son gratis.'), findsOneWidget);
      expect(find.text('¡Genial!'), findsNothing);
    });

    testWidgets('«Siguiente» aparece al segundo y permite adelantarse', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text(cliente));
      await t.pumpAndSettle();
      final ghost = find.byKey(const Key('intro-ghost-next'));
      expect(t.widget<AnimatedOpacity>(ghost).opacity, 0);
      await t.pump(JayaloMotion.introHint + const Duration(milliseconds: 1));
      await t.pump();
      expect(t.widget<AnimatedOpacity>(ghost).opacity, 1);
      await t.tap(find.text('Siguiente'));
      await t.pumpAndSettle();
      expect(find.text('Para ti, todas las funciones son gratis.'), findsOneWidget);
      // Y el temporizador de lectura ya no dispara nada raro después.
      await t.pump(JayaloMotion.introRead);
      await t.pumpAndSettle();
      expect(find.text('Para ti, todas las funciones son gratis.'), findsOneWidget);
    });

    testWidgets('atrás desde la reacción CANCELA el avance', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text(cliente));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('intro-back')));
      await t.pumpAndSettle();
      expect(find.text(cliente), findsOneWidget);
      await t.pump(JayaloMotion.introRead + const Duration(milliseconds: 10));
      await t.pumpAndSettle();
      expect(find.text(cliente), findsOneWidget, reason: 'no saltó a la lámina 2 por su cuenta');
      expect(find.text('Para ti, todas las funciones son gratis.'), findsNothing);
    });
  });
```

- [ ] **Step 2: Correr y ver que fallan**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/login_intro_carousel_test.dart --plain-name "la reacción"
```
Expected: los 3 fallan (no avanza; no existe `intro-ghost-next`).

- [ ] **Step 3: Temporizadores en el estado**

```dart
  /// La reacción avanza sola tras `introRead`; el «Siguiente» fantasma
  /// aparece a `introHint`. Se cancelan al cambiar de lámina, al retroceder y
  /// en dispose (si no, los tests de widgets mueren por temporizadores vivos).
  Timer? _readTimer;
  Timer? _hintTimer;
  bool _hintVisible = false;

  void _armReaction(int i) {
    _disarmReaction();
    if (_steps[i] != IntroStep.react) return;
    _hintTimer = Timer(JayaloMotion.introHint, () {
      if (mounted) setState(() => _hintVisible = true);
    });
    // Tiempo de LECTURA, no animación: con «reducir animaciones» también avanza.
    _readTimer = Timer(JayaloMotion.introRead, () {
      if (!mounted || _page != i || _busy) return;
      unawaited(_goToPage(i + 1));
    });
  }

  void _disarmReaction() {
    _readTimer?.cancel();
    _hintTimer?.cancel();
    _readTimer = null;
    _hintTimer = null;
    if (_hintVisible) _hintVisible = false;
  }
```
En `onPageChanged`: `setState(() { _page = i; _disarmReaction(); }); _markSeenIfDone(); _armReaction(i);`. En `dispose`: `_disarmReaction();` antes de `_pages.dispose()`. En `_back()`: `_disarmReaction()` al principio.

Acción de la lámina `react` en `_buildSlide` (sustituye el «Siguiente» normal solo para ese paso):
```dart
      IntroStep.react => AnimatedOpacity(
        key: const Key('intro-ghost-next'),
        opacity: _hintVisible ? 1 : 0,
        duration: JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        curve: JayaloMotion.enter,
        child: IgnorePointer(
          ignoring: !_hintVisible,
          child: TextButton(
            onPressed: () => _goToPage(i + 1),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(54), foregroundColor: JayaloColors.primary,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            child: const Text('Siguiente'),
          ),
        ),
      ),
```
Ojo con el test «el avance ANIMA» de la Task 6: ahora tras `page + introGesture` la reacción sigue en pantalla (2 600 ms no han pasado): sigue verde. Y con `_hintVisible` en `false` el «Siguiente» de la reacción no se puede tocar hasta el segundo 1: en los tests de la Task 6 que tocan «Siguiente» desde la reacción, añadir `await t.pump(JayaloMotion.introHint + const Duration(milliseconds: 1)); await t.pump();` antes del `tap` (o dejar que avance sola con `await t.pump(JayaloMotion.introRead)`).

- [ ] **Step 4: Correr todo el carrusel**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter test test/login_intro_carousel_test.dart test/login_intro_once_test.dart test/jayi_scene_test.dart
```
Expected: `All tests passed!`. Un fallo «A Timer is still pending» señala un camino donde no se llamó a `_disarmReaction` (dispose o back).

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/lib/features/auth/login_screen.dart app/test/login_intro_carousel_test.dart app/test/login_intro_once_test.dart && git commit -m "feat(intro): la reacción avanza sola a los 2,6 s, con «Siguiente» fantasma desde el segundo

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Comentarios, formato y suite completa

**Files:**
- Modify: `app/lib/core/session_state.dart:37`, `app/lib/push/push_permission.dart:14`, `app/lib/push/push_service.dart:277` (solo comentarios)
- Formato: solo los ficheros tocados en las Tasks 1–7

- [ ] **Step 1: Actualizar los tres comentarios**

En cada uno, «Busco algo / Vendo algo» → «Soy un cliente / Soy un proveedor» y «Vendo algo» → «Soy un proveedor». Comprobar con:
```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && grep -rn "Busco algo\|Vendo algo" app/lib app/test
```
Expected: sin resultados.

- [ ] **Step 2: Formato SOLO de los tocados**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && dart format lib/core/motion.dart lib/features/auth/intro_copy.dart lib/features/auth/intro_reveal.dart lib/features/auth/jayi_scene.dart lib/features/auth/login_screen.dart lib/data/repos.dart test/intro_copy_test.dart test/intro_reveal_test.dart test/jayi_scene_test.dart test/jayi_scene_pixels_test.dart test/welcome_credits_test.dart test/login_intro_carousel_test.dart test/login_intro_once_test.dart
```
Expected: `Formatted N files (M changed)`. Si `repos.dart` cambia más allá del bloque añadido, revertir el formato de ese fichero (`git checkout -- lib/data/repos.dart` y volver a añadir el bloque) para no arrastrar ruido.

- [ ] **Step 3: Analyze y suite completa**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter analyze && flutter test
```
Expected: `No issues found!` y `All tests passed!` (la suite venía en ~1 940 casos; ahora unos 20 más).

- [ ] **Step 4: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add -A app/lib app/test && git commit -m "chore(intro): comentarios al copy nuevo y formato de los ficheros tocados

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: APK, smoke del PO y cierre (verificador + certificador)

**Files:**
- Modify: `app/pubspec.yaml` (`version: 1.0.4+132` → `1.0.4+133`; **antes**, traer del worktree vivo el `+132` que está sin commitear: el worktree nuevo nace en `+130`)
- Create: `docs/qa/2026-09-18-smoke-intro-jayi.md`
- Create: `docs/superpowers/plans/2026-09-18-intro-jayi-te-recibe.ledger.md`

- [ ] **Step 1: Bump de versión**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && sed -i 's/^version: 1\.0\.4+130$/version: 1.0.4+133/' app/pubspec.yaml && grep -n "^version" app/pubspec.yaml
```
Expected: `version: 1.0.4+133`. (El `+132` del otro worktree es del APK instalado hoy; el siguiente número libre es 133.)

- [ ] **Step 2: Compilar el APK release**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro/app && flutter build apk --release && cp build/app/outputs/flutter-apk/app-release.apk C:/Users/ac/Downloads/jayalo-1.0.4+133-intro-jayi.apk
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 3: Escribir el smoke del PO**

`docs/qa/2026-09-18-smoke-intro-jayi.md`:
```markdown
# Smoke — intro «Jayi te recibe» (APK 1.0.4+133)

Antes: `adb uninstall com.jayalo.app` (un APK local no se instala encima del de
Play, y desinstalar borra `intro_seen_v1`, que es lo que se quiere).
`adb shell pm grant com.jayalo.app android.permission.POST_NOTIFICATIONS` para que el
diálogo de permiso no tape los recuadros. Instalar con ruta Windows:
`adb install C:\Users\ac\Downloads\jayalo-1.0.4+133-intro-jayi.apk`.

1. Abrir. Jayi cae y aplasta; el titular entra palabra a palabra; «¿Tú qué eres?» en
   violeta; los dos recuadros suben. Íconos SIN fondo.
2. Tocar «Soy un proveedor». El recuadro crece, el otro se hunde; desliza a «¡Bien!»;
   el pulgar SUBE con exceso y Jayi da un saltito. 4 puntos, el 4.º nace desde cero.
3. No tocar nada: al segundo aparece «Siguiente» en violeta sin relleno; a los 2,6 s
   avanza sola a «Hacer ofertas es gratis.» con la etiqueta subiendo.
4. «Siguiente»: la etiqueta se apaga, la moneda DORADA sube girando desde la palma,
   un destello, y el «5» cuenta de 0 a 5. Google, nota y correo suben escalonados.
5. Atrás (chevrón): vuelve a la etiqueta; atrás de Android: vuelve a «¡Bien!» y NO
   avanza sola otra vez si se vuelve a la lámina 0 antes de 2,6 s.
6. Desinstalar, reinstalar, elegir «Soy un cliente»: «¡Genial!», y la tercera lámina
   «Para ti, todas las funciones son gratis.» con Jayi flotando más alto.
7. «Saltar» en la lámina 0 (reinstalado): cierre neutro con los accesos, Jayi con los
   brazos abiertos. Cerrar y abrir: ya no sale el intro (una vez por teléfono).
8. Ajustes de Android → Accesibilidad → «Quitar animaciones». Reinstalar: todo se
   pinta en su estado final, sin animación, y la reacción SIGUE avanzando a los 2,6 s.
9. Admin web → Bonos → bienvenida = 0. Reinstalar, «Soy un proveedor»: 3 puntos y los
   accesos en «Hacer ofertas es gratis». Volver a poner 5 al terminar.
10. Modo avión. Reinstalar, «Soy un proveedor»: igual que el 9 (sin red no se promete).
```

- [ ] **Step 4: Verificador (agente independiente)**

Encargo literal: «En `C:/Users/ac/Downloads/jayalo-app-intro`, rama `feat/intro-jayi-te-recibe`, comprueba con evidencia (comandos y su salida, no lectura) que: `flutter analyze` está limpio; `flutter test` pasa entero; `grep -rn "jayi_celebrando" app/lib/features/auth` no devuelve nada; `grep -rn "Duration(milliseconds" app/lib/features/auth/login_screen.dart app/lib/features/auth/intro_reveal.dart` solo devuelve los retardos documentados (560/640 de los recuadros, 110/520 del grito y la frase, 120/38 de las palabras, 360 del contador, 120 por cifra) y ningún otro; `grep -n "bounce" app/lib` solo aparece en `motion.dart`, en el pulgar de `jayi_scene.dart`, en el grito de `login_screen.dart` y en el nacimiento del punto; el copy de `intro_copy.dart` coincide letra por letra con la tabla §3 del spec. Reporta qué rompió, si algo.»

- [ ] **Step 5: Certificador (agente independiente) y ledger**

Encargo literal: «Con el spec `docs/superpowers/specs/2026-09-18-intro-jayi-te-recibe-design.md` y el plan, di si la tanda se puede cerrar. Sección obligatoria COBERTURA: qué requisitos del spec §4, §5, §6 y §9 tienen test que los trace (nombra el test) y cuáles NO (por ejemplo: el temblor de antenas, el destello, la pupila y el `pump` del pulgar solo se cubren por el test de píxeles “el cambio de pose ANIMA”; el smoke en device está pendiente del PO).» Volcar ambos informes, los rulings tomados durante la ejecución y las desviaciones del plan en `docs/superpowers/plans/2026-09-18-intro-jayi-te-recibe.ledger.md`.

- [ ] **Step 6: Commit final (sin push: doctrina PO)**

```bash
cd C:/Users/ac/Downloads/jayalo-app-intro && git add app/pubspec.yaml docs/qa/2026-09-18-smoke-intro-jayi.md docs/superpowers/plans/2026-09-18-intro-jayi-te-recibe.ledger.md && git commit -m "chore(app): 1.0.4+133 con el intro «Jayi te recibe», smoke y ledger

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Entregar al PO: la ruta del APK, qué trae (el intro nuevo) y qué NO trae (nada de la rama `feat/fecha-pautada-app` posterior a `77f77c2`, ni el `+132` de pubspec de la otra sesión, que se queda sin commitear allí).

---

## Autorrevisión del plan

- **Cobertura del spec**: §3 copy → Task 1; §4 flujo (`introSteps`, accesos al final, puntos, Saltar, atrás, reacción, restaurar) → Tasks 1, 6, 7; §5 coreografía (tokens, aterrizaje, saltito, cambio de mano, moneda, contador, accesos escalonados, reduce-motion) → Tasks 1, 2, 4, 6; §6 datos (`bonus_config`, congelar, 0 ⇒ sin lámina, inyección) → Tasks 5, 6; §7 poses y oro → Tasks 3, 4; §8 arquitectura → mapa de ficheros; §9 pruebas → cada task; §11 worktree/bump → Tasks 0, 9. Sin huecos.
- **Placeholders**: ninguno; el único «se conserva tal cual» apunta a tests existentes que no cambian de contenido.
- **Consistencia de nombres**: `introSteps/introSlideFor/introStepIsAccess` (Task 1) se usan igual en Task 6; `JayiScene(pose:)`/`JayiPose` (Task 3) en Tasks 4 y 6; `fetchWelcomeCredits` (Task 5) como parámetro con el mismo nombre en Task 6; `IntroReveal/IntroWords/IntroCounter` (Task 2) en Task 6; claves `intro-dots`, `intro-back`, `intro-ghost-next` en Tasks 6 y 7.
