# Onboarding de primera apertura (app) — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que quien abra la app recién instalada sepa qué es Jayalo y de qué lado está, antes de que se le pida una cuenta.

**Architecture:** Las tres láminas viven **dentro de `LoginScreen`**, convertida en carrusel, no en rutas nuevas. Motivo duro: `redirectTarget()` empieza con `if (!loggedIn) return onLogin ? null : '/login';` — sin sesión, **toda ruta que no sea `/login` rebota**. Metiendo el carrusel dentro de `/login` no se toca el router. La lámina 1 es común y bifurca por rol; las láminas 2 y 3 son propias de cada rama. La elección se guarda en `SharedPreferences` y, tras autenticar, salta `ChooseRoleScreen`.

**Tech Stack:** Flutter, go_router, Supabase Flutter, `shared_preferences`, `google_sign_in`, `flutter_test`.

**Spec:** `../../../jayalo-main/integracion/docs/superpowers/specs/2026-08-19-onboarding-tres-pasos-design.md` (el spec vive en el repo web porque cubre las dos plataformas).

## Global Constraints

- **Worktree y rama:** `C:/Users/ac/Downloads/jayalo-app-playbilling`, rama `feat/play-billing`. **NO es `C:/Users/ac/Downloads/jayalo-app`**, que está congelado en `feat/tanda-ui-08-05` del 08-08 y da respuestas falsas. Comprobar con `git worktree list` si hay duda.
- **No commitear ni pushear salvo que el PO lo pida.**
- **`flutter analyze` en 0** y la suite completa verde antes de dar nada por hecho.
- **Duraciones y curvas SOLO desde `JayaloMotion`.** Nunca `Duration(...)` ni `Curves....` sueltos en pantalla. Los valores están cerrados y aprobados por el PO en device: **no re-optimizarlos por iniciativa propia.**
- **Jayi no se rediseña.** En la app la mascota es el asset `assets/images/mascot.png` y el widget `JayaloMascot`. **No dibujar una mascota nueva**: las escenas con accesorios son de la maqueta web; aquí se reusa el asset existente.
- **Tokens:** violeta de acción `JayaloColors.primary`, pesos 400-600 (**nunca 700+**), botones en pill (`BorderRadius.circular(999)`), tarjetas sin borde con sombra suave.
- **Copys exactos**, literales en la Task 2.
- **Gotcha de tests:** un velo o carrusel a pantalla completa **intercepta taps**. Todo test existente que tapee algo en `/login` se romperá; se arregla saltando el carrusel en el `setUp`, no borrando el test.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `app/lib/features/auth/intro_copy.dart` | **Crear.** Los copys de las láminas, como datos puros. Sin widgets. |
| `app/lib/features/auth/intro_role_store.dart` | **Crear.** Guardar/leer/borrar la elección de rol en `SharedPreferences`. |
| `app/lib/features/auth/login_screen.dart` | **Modificar.** Envolver el contenido actual en un carrusel de 3 láminas. |
| `app/lib/core/router.dart:74` | **Modificar.** `/onboarding` consulta la elección guardada antes de pintar `ChooseRoleScreen`. |
| `app/test/intro_copy_test.dart` | **Crear.** |
| `app/test/intro_role_store_test.dart` | **Crear.** |

---

### Task 1: La elección de rol, persistida

**Files:**
- Create: `app/lib/features/auth/intro_role_store.dart`
- Test: `app/test/intro_role_store_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`.
- Produces: `enum IntroRole { consumer, provider }`; `class IntroRoleStore` con `static const String kKey = 'intro_role_choice'`, `Future<void> save(IntroRole role)`, `Future<IntroRole?> read()`, `Future<void> clear()`.

**Por qué la clave NO lleva sufijo de usuario:** en la lámina 1 todavía no hay sesión ni `uid`, a diferencia de `onboarding_guides_<uid>` del `OnboardingStore`. Por eso **debe borrarse en cuanto se consume**, o el siguiente que se registre en ese mismo teléfono hereda la elección del anterior.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/intro_role_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin elección guardada devuelve null', () async {
    expect(await IntroRoleStore().read(), isNull);
  });

  test('guarda y relee cliente', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.consumer);
    expect(await store.read(), IntroRole.consumer);
  });

  test('guarda y relee proveedor', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.provider);
    expect(await store.read(), IntroRole.provider);
  });

  test('clear borra la elección', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.provider);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('un valor basura en prefs se trata como sin elección', () async {
    // Defensa contra una versión anterior que hubiera escrito otro formato.
    SharedPreferences.setMockInitialValues({IntroRoleStore.kKey: 'gerente'});
    expect(await IntroRoleStore().read(), isNull);
  });

  test('la clave NO lleva sufijo de usuario', () {
    // En la lámina 1 aún no hay sesión, así que no hay uid que colgarle.
    expect(IntroRoleStore.kKey, 'intro_role_choice');
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/intro_role_store_test.dart` (desde `app/`)
Expected: FAIL — no existe `intro_role_store.dart`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `app/lib/features/auth/intro_role_store.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// De qué lado dijo el usuario que está, en la lámina 1 del intro.
enum IntroRole { consumer, provider }

/// Guarda la elección de rol hecha ANTES de autenticarse.
///
/// La clave no lleva sufijo de usuario (a diferencia de
/// `onboarding_guides_<uid>` del OnboardingStore) porque en ese momento no hay
/// sesión ni uid. Consecuencia directa: hay que BORRARLA en cuanto se consume,
/// o el siguiente que se registre en el mismo teléfono hereda la elección del
/// anterior.
class IntroRoleStore {
  static const String kKey = 'intro_role_choice';

  Future<void> save(IntroRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kKey, role.name);
  }

  Future<IntroRole?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kKey);
    if (raw == null) return null;
    // Un valor que no reconocemos se trata como "sin elección": mejor caer en
    // ChooseRoleScreen que abrir un alta equivocada.
    for (final r in IntroRole.values) {
      if (r.name == raw) return r;
    }
    return null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kKey);
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/intro_role_store_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth/intro_role_store.dart app/test/intro_role_store_test.dart
git commit -m "feat(intro): persistir la eleccion de rol previa al login"
```

---

### Task 2: Los copys de las láminas

**Files:**
- Create: `app/lib/features/auth/intro_copy.dart`
- Test: `app/test/intro_copy_test.dart`

**Interfaces:**
- Consumes: `IntroRole` de `intro_role_store.dart`.
- Produces: `class IntroSlide { final String headline; final String highlight; final String sub; }`; `const IntroSlide kIntroCommon`; `const Map<IntroRole, List<IntroSlide>> kIntroSlides` (2 láminas por rol).

`highlight` es subcadena literal de `headline`, igual que en el plan web; la pantalla la parte y la pinta en `JayaloColors.primary`. Hay precedente: el titular actual del login es «Todo empieza con una **idea**.» con «idea» en ese mismo violeta.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/intro_copy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  test('cada rol tiene exactamente 2 láminas propias', () {
    expect(kIntroSlides[IntroRole.consumer]!.length, 2);
    expect(kIntroSlides[IntroRole.provider]!.length, 2);
  });

  test('el realce es siempre subcadena del titular', () {
    final todas = [
      kIntroCommon,
      ...kIntroSlides[IntroRole.consumer]!,
      ...kIntroSlides[IntroRole.provider]!,
    ];
    for (final s in todas) {
      expect(s.headline.contains(s.highlight), isTrue,
          reason: 'realce "${s.highlight}" no está en "${s.headline}"');
    }
  });

  test('la lámina común nombra los dos lados', () {
    expect(kIntroCommon.headline,
        'Jayalo conecta a quien pide con quien vende, cerca de ti.');
  });

  test('el cierre del cliente lleva la privacidad con «aceptes»', () {
    expect(kIntroSlides[IntroRole.consumer]![1].sub,
        'Tus datos son privados: solo los proveedores que aceptes podrán ver tu contacto.');
  });

  test('el cierre del proveedor quita la objeción del costo', () {
    expect(kIntroSlides[IntroRole.provider]![1].headline,
        'Ofertar es gratis. Solo pagas cuando ya te aceptaron.');
  });

  test('ningún copy va vacío', () {
    final todas = [
      kIntroCommon,
      ...kIntroSlides[IntroRole.consumer]!,
      ...kIntroSlides[IntroRole.provider]!,
    ];
    for (final s in todas) {
      expect(s.headline.trim(), isNotEmpty);
      expect(s.sub.trim(), isNotEmpty);
      expect(s.highlight.trim(), isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/intro_copy_test.dart`
Expected: FAIL — no existe `intro_copy.dart`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `app/lib/features/auth/intro_copy.dart`:

```dart
import 'intro_role_store.dart';

/// Una lámina del intro: titular, la palabra que va en violeta, y el apoyo.
///
/// `highlight` es subcadena LITERAL de `headline`; la pantalla la parte y pinta
/// esa parte en `JayaloColors.primary`. Guardarlo así, y no con marcas dentro
/// del texto, deja el copy legible de principio a fin. Precedente en la propia
/// pantalla: «Todo empieza con una idea.» con «idea» en violeta.
class IntroSlide {
  const IntroSlide({
    required this.headline,
    required this.highlight,
    required this.sub,
  });

  final String headline;
  final String highlight;
  final String sub;
}

/// Lámina 1: común a los dos roles. Explica y bifurca en la misma pantalla,
/// para que nadie tenga que elegir su lado antes de saber qué es Jayalo.
const IntroSlide kIntroCommon = IntroSlide(
  headline: 'Jayalo conecta a quien pide con quien vende, cerca de ti.',
  highlight: 'quien pide',
  sub: 'Dime de qué lado estás y te lo cuento en dos pantallas.',
);

/// Láminas 2 y 3, ya según el lado elegido.
const Map<IntroRole, List<IntroSlide>> kIntroSlides = {
  IntroRole.consumer: [
    IntroSlide(
      headline:
          'Pide con una foto y los proveedores cerca de ti compiten por dártelo.',
      highlight: 'compiten por dártelo',
      sub: 'Te llegan varias ofertas con precio, foto y reputación. '
          'Comparas sin compromiso.',
    ),
    IntroSlide(
      headline: '¡Aceptas la oferta que más te convenga!',
      highlight: 'más te convenga',
      sub: 'Tus datos son privados: solo los proveedores que aceptes podrán ver tu contacto.',
    ),
  ],
  IntroRole.provider: [
    IntroSlide(
      headline: 'Hay clientes cerca de ti pidiendo justo lo que tú vendes.',
      highlight: 'clientes cerca de ti',
      sub: 'Ves las solicitudes abiertas de tus rubros y respondes con tu '
          'precio, una foto y en cuánto lo tienes listo.',
    ),
    IntroSlide(
      headline: 'Ofertar es gratis. Solo pagas cuando ya te aceptaron.',
      highlight: 'Ofertar es gratis.',
      sub: 'Cuando el cliente acepta tu oferta, recibes sus datos y cierras la venta.',
    ),
  ],
};
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/intro_copy_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth/intro_copy.dart app/test/intro_copy_test.dart
git commit -m "feat(intro): copys de las laminas de primera apertura"
```

---

### Task 3: `LoginScreen` como carrusel

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart`

**Interfaces:**
- Consumes: `IntroRole`, `IntroRoleStore` (Task 1); `kIntroCommon`, `kIntroSlides`, `IntroSlide` (Task 2); lo que ya existe en el fichero: `signInWithGoogleNative`, `_openPasswordSheet`, `_go`, `PortadaJayi`, `JayaloMascot`, `JayaloSpinner`, `JayaloColors`, `JayaloMotion`.
- Produces: nada fuera del fichero.

**Lo que NO se toca**, porque ya está resuelto y probado:
- `signInWithGoogleNative` y su manejo de errores (mensaje accionable, `SignInCancelled` en silencio).
- `_PasswordLoginSheet` y su `passwordLoginError`. Esa puerta **solo inicia sesión**; crear cuenta sigue siendo Google + alta nativa.
- El fondo `PortadaJayi`.

**Estructura nueva del `build`:**

1. `PageView` de 3 páginas con `PageController`, `physics: NeverScrollableScrollPhysics()` **no** — se deja deslizable, pero el avance también ocurre por botón.
2. Página 0: `kIntroCommon` + **dos recuadros** de rol (tarjeta blanca, sombra suave, ícono lineal, título y subtítulo). Al tocar uno: `IntroRoleStore().save(...)`, guardar en estado y avanzar a la página 1.
3. Página 1: `kIntroSlides[rol]![0]` + botón «Siguiente».
4. Página 2: `kIntroSlides[rol]![1]` + la pila de acceso **que ya existe**: botón «Continuar con Google» → `_go`, la frase «¿Primera vez?…», y el `TextButton` «Entrar con correo y contraseña» → `_openPasswordSheet`.
5. Indicador de 3 puntos, con el activo alargado.
6. «Saltar» arriba a la derecha en las páginas 0 y 1; en la 2 no, porque ya es el final.

**Reglas al implementar:**
- Si `_introRole == null`, las páginas 1 y 2 no existen todavía: construir el `PageView` con `itemCount: _introRole == null ? 1 : 3`. Así no se puede deslizar a una lámina sin rol.
- «Saltar» va directo a la página 2 **con el rol que haya**; si no hay rol elegido, guarda `null` (no guarda nada) y muestra la lámina de cierre del cliente, que es la más neutra. Sin rol guardado, tras autenticar cae en `ChooseRoleScreen`, que es exactamente la red de seguridad prevista.
- Transición entre páginas con `JayaloMotion` (`page` / `emphasized`). **No inventar duraciones.**
- El realce del titular con `Text.rich` partiendo por `highlight`, igual que hace hoy el titular «Todo empieza con una idea.».
- Respetar `JayaloMotion.reduced(context)` en cualquier animación añadida.

- [ ] **Step 1: Implementar el carrusel**

Modificar `_LoginScreenState`: añadir `final _pages = PageController()`, `IntroRole? _introRole`, `int _page = 0`, y el `dispose` del controller. Envolver el contenido actual (wordmark, titular, mascota, botones) de forma que **la página 2 conserve exactamente la pila de acceso de hoy**.

- [ ] **Step 2: Verificar análisis estático**

Run: `flutter analyze` (desde `app/`)
Expected: 0 issues.

- [ ] **Step 3: Correr la suite completa y arreglar lo que el carrusel rompa**

Run: `flutter test`

**Esperado: fallos.** Cualquier test que monte `/login` y tapee algo ahora se topa con la lámina 0. El arreglo correcto **no** es borrar el test: es saltar el carrusel en su `setUp` sembrando una elección de rol, de forma que la pantalla arranque donde el test espera:

```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({
    IntroRoleStore.kKey: IntroRole.consumer.name,
  });
});
```

Si con eso no basta porque el test necesita la lámina de acceso, hacer que la pantalla arranque en la última página cuando ya hay rol guardado. **Esa es además la conducta correcta en producción:** quien ya eligió y volvió a la app no debe tragarse el intro otra vez.

- [ ] **Step 4: Test del carrusel**

Añadir a `app/test/` un test de widget que compruebe:
1. Con prefs vacías, se pinta el titular de `kIntroCommon` y **los dos recuadros** de rol.
2. Al tocar «Vendo algo», `IntroRoleStore().read()` devuelve `IntroRole.provider`.
3. Tras elegir proveedor y avanzar dos páginas, se ve «Ofertar es gratis. Solo pagas cuando ya te aceptaron.» y **ambos** accesos: «Continuar con Google» y «Entrar con correo y contraseña».

Usar `SharedPreferences.setMockInitialValues({})` en el `setUp` y `await tester.pumpAndSettle()` tras cada toque. **Ojo:** el brillo de `flutter_animate` agenda un `Timer(0)`; si algún pump se queda colgado con «Pending timers», usar `pump` **con duración** en vez de `pumpAndSettle`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth/login_screen.dart app/test/
git commit -m "feat(intro): LoginScreen como carrusel de tres laminas con bifurcacion de rol"
```

---

### Task 4: Saltar `ChooseRoleScreen` con la elección guardada

**Files:**
- Modify: `app/lib/core/router.dart:74`

**Interfaces:**
- Consumes: `IntroRole`, `IntroRoleStore` (Task 1).
- Produces: nada.

Hoy la ruta es:

```dart
GoRoute(path: '/onboarding', builder: (_, _) => const ChooseRoleScreen()),
```

Tras autenticar con Google, `roleFrom(accountType: null, hasBusiness: false)` devuelve `needsOnboarding` y el router manda a `/onboarding`. Si hay elección guardada, hay que ir directo al alta correcta.

**`ChooseRoleScreen` NO se borra:** queda de red de seguridad para quien llegue sin elección (sesión reanudada, login por correo, deep link).

- [ ] **Step 1: Redirigir según la elección guardada**

Añadir un `redirect` asíncrono a esa `GoRoute` que lea `IntroRoleStore().read()`:
- `IntroRole.consumer` → `/onboarding/consumer`
- `IntroRole.provider` → `/onboarding/provider`
- `null` → `null` (se queda en `ChooseRoleScreen`)

**Y borrar la elección en cuanto se consume** (`IntroRoleStore().clear()`), por lo dicho en la Task 1: la clave no lleva uid.

**Caso borde obligatorio.** Si el rol real ya está resuelto —`RoleState.consumer` o `RoleState.provider`— **manda el rol real y se ignora la elección guardada**. Es el caso de quien elige «Vendo algo» pero su cuenta de Google ya existe como cliente: meterlo en el alta de proveedor sería un error. El `redirect` global de `router.dart` ya saca de `/onboarding` a quien tiene rol resuelto; **verificar que sigue ganando** y no dejar que este `redirect` nuevo lo pise.

- [ ] **Step 2: Verificar análisis estático y suite**

Run: `flutter analyze && flutter test`
Expected: 0 issues, suite verde.

- [ ] **Step 3: Test de la decisión de ruteo**

Si el `redirect` queda embebido en el `GoRoute`, extraer la decisión a una función pura testeable, al estilo de `redirectTarget` en `session_state.dart`:

```dart
String? introRoleRedirect({
  required RoleState role,
  required IntroRole? choice,
}) {
  // El rol real manda: quien ya es cliente no entra al alta de proveedor
  // aunque en el intro tocara «Vendo algo».
  if (role != RoleState.needsOnboarding) return null;
  if (choice == null) return null;
  return choice == IntroRole.provider
      ? '/onboarding/provider'
      : '/onboarding/consumer';
}
```

Y testearla en `app/test/intro_role_redirect_test.dart` con los cuatro casos: sin elección, cliente, proveedor, y **rol real ya resuelto con elección contraria** (debe devolver `null`).

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/router.dart app/test/intro_role_redirect_test.dart
git commit -m "feat(intro): la eleccion del intro salta ChooseRoleScreen"
```

---

### Task 5: Smoke en device

- [ ] **Step 1: Compilar e instalar**

Compilar el APK release e instalarlo. **Gotcha conocido:** `flutter install` **no recompila**; hay que hacer `flutter build apk --release` antes. Y la ruta del APK para `adb` debe ir en formato Windows (`C:/...`), **no** `/c/...`. Un APK debug **no** instala sobre un release: desinstalar primero.

- [ ] **Step 2: Recorrido de cliente, con cuenta nueva**

1. Instalación limpia → sale la lámina 1 con los dos recuadros.
2. «Busco algo» → láminas 2 y 3 de cliente.
3. En la 3 están **los dos accesos**: Google en pill y el enlace de correo.
4. Google → cae **directo** en el alta de cliente, **sin pasar por `ChooseRoleScreen`**.
5. Completar el alta: el OTP de WhatsApp sigue siendo bloqueante, igual que antes.

- [ ] **Step 3: Recorrido de proveedor**

Lo mismo con «Vendo algo» → debe caer en `/onboarding/provider`.

- [ ] **Step 4: Los casos borde**

1. **Elegir «Vendo algo» con una cuenta de Google que ya es cliente** → debe ir a su panel de cliente, **no** al alta de proveedor. Es el caso que más fácil se rompe.
2. **Matar la app tras elegir rol, antes de autenticar** → al volver, no repite el intro y el acceso lleva al alta elegida.
3. **«Saltar»** desde la lámina 1 → llega al cierre y, tras Google, cae en `ChooseRoleScreen` (la red de seguridad).
4. **Segundo usuario en el mismo teléfono:** cerrar sesión y registrar otra cuenta con el rol contrario. Si hereda el rol del anterior, el `clear()` de la Task 4 no está corriendo.
5. **Reduce-motion** encendido en accesibilidad del sistema → sin animaciones, todo legible.

- [ ] **Step 5: Reportar al PO, sin pushear**

Decir qué se verificó y qué no. **No pushear:** eso lo autoriza el PO.

---

## Auto-repaso del plan

**Cobertura del spec:**

| Requisito del spec | Task |
|---|---|
| Láminas dentro de `LoginScreen`, sin tocar el router de sesión | 3 |
| Lámina 1 explica y bifurca; los recuadros no navegan | 3 |
| Láminas 2 y 3 según rol | 2, 3 |
| Cierre con Google + enlace de correo, tal como están hoy | 3 |
| Elección en `SharedPreferences`, clave `intro_role_choice`, sin uid | 1 |
| Borrar la elección al consumirse | 1 (API), 4 (uso), 5 (caso 4) |
| Saltar `ChooseRoleScreen`; no borrarla | 4 |
| Realce violeta del titular | 2 (dato), 3 (pintado) |
| Rol real gana sobre la elección guardada | 4 (test), 5 (caso 1) |
| Reduce-motion | 3, 5 |
| Gotcha de taps interceptados en tests | 3, Step 3 |

**Escaneo de marcadores:** la Task 3 Step 1 y la Task 4 Step 1 describen el cambio sin volcar el fichero entero. Es deliberado y no es un placeholder: `login_screen.dart` tiene 300+ líneas ya resueltas (manejo de errores de Google, hoja de contraseña, `PortadaJayi`) que **no deben reescribirse**, y pegar el fichero completo invita justamente a eso. Lo que sí está fijado con exactitud es la estructura del `PageView`, qué conserva cada página, y el código completo de las partes nuevas.

**Consistencia de tipos:** `IntroRole` se define en Task 1 y se usa igual en 2, 3 y 4. `IntroRoleStore.kKey` es la misma constante en el store, en los `setUp` de los tests y en el `redirect`. `IntroSlide` con sus tres campos (`headline`, `highlight`, `sub`) es idéntico en definición y uso. `kIntroCommon` y `kIntroSlides` mantienen el nombre en las tres tasks que los tocan.

**Dependencia entre planes:** ninguna. Este plan y el de web no comparten código ni despliegue; pueden ejecutarse en cualquier orden o a la vez.
