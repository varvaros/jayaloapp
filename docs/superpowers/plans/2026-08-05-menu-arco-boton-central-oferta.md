# Menú en arco sobre el botón central al crear una oferta — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el ＋ de la barra flotante deje de apuntar a "Crear solicitud" mientras el proveedor
redacta una oferta y se convierta en un menú en arco con las cuatro fuentes que la oferta ya tiene
(Cámara, Galería, Mi tienda, Trabajos).

**Architecture:** El store `core/center_action.dart` —que hoy solo sabe prestar el botón a *una*
pantalla y a *una* acción— se generaliza a (dueño, ruta, etiqueta, ícono, acción **o** menú). La
barra gana un `OverlayPortal` anclado al propio círculo central que pinta el arco por encima de todo,
sin enterarse de qué hacen los ítems. La pantalla de la oferta registra los cuatro ítems apuntando a
métodos que **ya existen**.

**Tech Stack:** Flutter · go_router · `OverlayPortal` + `CompositedTransformFollower` · `CustomPaint`
· `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-05-menu-arco-boton-central-oferta-design.md`

## Global Constraints

- **Solo la app.** Nada de web, nada de BD, ninguna migración, ningún cambio en `supabase/`.
- **Rama:** `feat/menu-arco-oferta` (ya creada, sale de `feat/correcciones-ui-08-04`). **No rebasar
  sobre `master`** — no es viable en este repo.
- **Directorio de trabajo:** todos los comandos se ejecutan desde `app/`.
- **Cero lógica de negocio nueva.** Los cuatro destinos del menú son llamadas a
  `_pickPhoto(ImageSource.camera)`, `_pickPhoto(ImageSource.gallery)`, `_pickFromStore` y
  `_pickFromPortfolio`, que ya están escritos y probados en device.
- **La cámara de crear-solicitud no cambia de comportamiento ni un frame.** Es la no-regresión que
  gobierna todo el plan.
- **Movimiento:** duraciones y curvas salen de `JayaloMotion` (`core/motion.dart`). Con
  `JayaloMotion.reduced(context)` el arco aparece sin escalonar ni escalar. El háptico **no** se
  apaga con `reduced` (lo dice el propio `motion.dart`).
- **Copy vinculante:** etiqueta del centro en reposo `'Cargar'`; etiquetas de los satélites
  `'Cámara'`, `'Galería'`, `'Mi tienda'`, `'Trabajos'`; aviso al tope de fotos
  `'Ya tienes 5 fotos'`.
- **Tope de fotos:** `_maxOfferPhotos = 5` (`request_detail_screen.dart:35`). No hardcodear el 5 en
  código nuevo salvo en el literal del aviso.
- **Verde antes de cada commit:** `flutter analyze` sin errores nuevos, y los tests que cada task
  nombra. La suite **entera** se corre una vez, en la Task 7 — correrla en cada task multiplicaría el
  tiempo sin añadir señal.
- **Los tests NO firman que las cuatro etiquetas quepan.** En `flutter test` el texto mide ~2× lo
  real (tanda A del 2026-08-02, costó dos agentes y un ticket falso). Eso es Task 7, en device.

---

### Task 1: El store deja de servir a un solo caso

**Files:**
- Modify: `app/lib/core/center_action.dart` (archivo entero, 86 líneas)
- Modify: `app/lib/features/client/create_request_screen.dart:189` y `:198` y `:668`
- Test: `app/test/center_action_test.dart` (existe — se amplía el `group('store')`)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `class CenterMenuItem` — `const CenterMenuItem({required IconData icon, required String label, required VoidCallback onTap, bool enabled = true})`, con `==`/`hashCode` **por valor**.
  - `final ValueNotifier<Object?> centerActionOwner`
  - `final ValueNotifier<String?> centerActionRoute`
  - `final ValueNotifier<String?> centerActionLabel`
  - `final ValueNotifier<List<CenterMenuItem>?> centerActionMenu`
  - `void takeCenterAction({required Object owner, required IconData icon, String? label, String? route, VoidCallback? action, List<CenterMenuItem>? menu})`
  - `void releaseCenterAction(Object owner)`
  - Siguen existiendo sin cambios: `centerAction`, `centerActionIcon`, `_applySafely`.

**Por qué el dueño se separa de la acción:** hoy la identidad del que tomó el botón *es* el
`VoidCallback`, y esa guarda es lo único que impide que el `dispose` de la pantalla saliente le borre
el botón a la entrante (el `initState` de la nueva corre **antes**). Con un menú no hay un callback
único: hay cuatro.

- [ ] **Step 1: Escribir los tests que fallan**

En `app/test/center_action_test.dart`, dentro de `group('store', ...)`, añadir:

```dart
    test('un menú se registra y se suelta por su DUEÑO, no por su acción', () {
      final owner = Object();
      void nada() {}
      final menu = [
        CenterMenuItem(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: nada),
        CenterMenuItem(icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: nada),
      ];

      takeCenterAction(
        owner: owner,
        icon: Icons.library_add_outlined,
        label: 'Cargar',
        route: '/provider/request/abc',
        menu: menu,
      );

      expect(centerActionOwner.value, same(owner));
      expect(centerActionMenu.value, menu);
      expect(centerActionLabel.value, 'Cargar');
      expect(centerActionRoute.value, '/provider/request/abc');
      expect(centerAction.value, isNull, reason: 'un menú no tiene acción directa');

      releaseCenterAction(owner);
      expect(centerActionOwner.value, isNull);
      expect(centerActionMenu.value, isNull);
      expect(centerActionLabel.value, isNull);
      expect(centerActionRoute.value, isNull);
      expect(centerActionIcon.value, isNull);
    });

    test('soltar con un dueño AJENO no roba el botón', () {
      final saliente = Object();
      final entrante = Object();
      void nada() {}
      final menu = [
        CenterMenuItem(icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: nada),
      ];

      takeCenterAction(owner: saliente, icon: Icons.library_add_outlined, menu: menu);
      takeCenterAction(owner: entrante, icon: Icons.library_add_outlined, menu: menu);
      releaseCenterAction(saliente);

      expect(centerActionOwner.value, same(entrante),
          reason: 'el dueño al frente debe sobrevivir al dispose del saliente');
      expect(centerActionMenu.value, isNotNull);
    });

    test('reasignar un menú EQUIVALENTE no notifica (el formulario se '
        'reconstruye con cada tecla del campo de precio)', () {
      final owner = Object();
      void nada() {}
      List<CenterMenuItem> build({required bool enabled}) => [
            CenterMenuItem(
                icon: Icons.photo_camera_outlined,
                label: 'Cámara',
                onTap: nada,
                enabled: enabled),
          ];

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: true));

      var avisos = 0;
      void contar() => avisos++;
      centerActionMenu.addListener(contar);
      addTearDown(() => centerActionMenu.removeListener(contar));

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: true));
      expect(avisos, 0, reason: 'misma lista por VALOR: no debe repintar la barra');

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: false));
      expect(avisos, 1, reason: 'cambió `enabled`: eso SÍ tiene que repintarse');
    });
```

Y actualizar el `tearDown` del archivo (líneas 15-18) para limpiar todo el estado nuevo:

```dart
  tearDown(() {
    centerAction.value = null;
    centerActionIcon.value = null;
    centerActionOwner.value = null;
    centerActionRoute.value = null;
    centerActionLabel.value = null;
    centerActionMenu.value = null;
  });
```

Los dos tests viejos del `group('store')` usan la firma posicional antigua
(`takeCenterAction(action, Icons.photo_camera_outlined)`); pasarlos a la nueva:

```dart
      takeCenterAction(owner: action, icon: Icons.photo_camera_outlined, action: action);
```
```dart
      takeCenterAction(owner: saliente, icon: Icons.photo_camera_outlined, action: saliente);
      takeCenterAction(owner: entrante, icon: Icons.photo_camera_outlined, action: entrante);
      releaseCenterAction(saliente);
```

- [ ] **Step 2: Correrlos para verificar que fallan**

Run: `flutter test test/center_action_test.dart`
Expected: FAIL de **compilación** — `Undefined name 'CenterMenuItem'`, `centerActionOwner`,
`centerActionRoute`, `centerActionLabel`, `centerActionMenu`.

- [ ] **Step 3: Implementar el store**

En `app/lib/core/center_action.dart`, añadir el import y el tipo (antes de los notifiers):

```dart
import 'package:flutter/foundation.dart' show listEquals;
```

```dart
/// Un destino del menú que despliega el botón central.
///
/// Igualdad **por valor** a propósito: la pantalla que registra el menú lo
/// reconstruye en cada `build` (su `enabled` depende de si está ocupada y de
/// cuántas fotos lleva), y el formulario de la oferta se reconstruye con cada
/// tecla que se escribe en el campo de precio. Sin esta igualdad, cada
/// pulsación repintaría la barra flotante entera.
///
/// `onTap` se compara con `==` y no con `identical`: Dart garantiza que dos
/// tear-offs del mismo método sobre la misma instancia son iguales, pero NO que
/// sean el mismo objeto.
@immutable
class CenterMenuItem {
  const CenterMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// `false` = se pinta atenuado y su toque no dispara [onTap]. No se ESCONDE:
  /// un arco que pasa de cuatro satélites a uno se lee como un fallo.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CenterMenuItem &&
          other.icon == icon &&
          other.label == label &&
          other.onTap == onTap &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(icon, label, onTap, enabled);
}
```

Añadir los cuatro notifiers junto a los dos que ya existen:

```dart
/// Identidad de quien tomó el botón. Antes ese papel lo hacía el propio
/// `VoidCallback`; con un menú no hay UN callback que sirva de identidad, hay
/// cuatro. Registrar un no-op de mentira solo para tener token sería mentir
/// sobre para qué existe el campo.
final ValueNotifier<Object?> centerActionOwner = ValueNotifier(null);

/// Ruta que tomó el botón. **Sustituye a la constante cableada** que el shell
/// comparaba (`kCreateRequestRoute`), que impedía que ninguna otra pantalla
/// pudiera apropiarse del centro.
final ValueNotifier<String?> centerActionRoute = ValueNotifier(null);

/// Etiqueta bajo el círculo mientras está tomado. Antes vivía a fuego en
/// `home_shell.dart` ('Añadir foto').
final ValueNotifier<String?> centerActionLabel = ValueNotifier(null);

/// Destinos del menú. No-nulo = el centro DESPLIEGA en vez de actuar.
final ValueNotifier<List<CenterMenuItem>?> centerActionMenu = ValueNotifier(null);
```

Reemplazar `takeCenterAction` (líneas 35-41):

```dart
/// Toma el botón central.
///
/// Idempotente: volver a llamarlo con lo mismo no notifica a nadie. Los
/// `ValueNotifier` ya comparan por `==`, así que los escalares se guardan
/// solos; la LISTA necesita la comparación explícita porque `List` no tiene
/// igualdad por valor en Dart.
void takeCenterAction({
  required Object owner,
  required IconData icon,
  String? label,
  String? route,
  VoidCallback? action,
  List<CenterMenuItem>? menu,
}) {
  assert(action != null || menu != null,
      'Un botón tomado que no hace nada es justo el estado que esto viene a eliminar.');
  _applySafely(() {
    // Todo lo que el shell LEE se asigna antes que `centerAction`/
    // `centerActionMenu`, que son los que disparan el repintado: así cuando la
    // notificación llega, quien escucha encuentra el juego completo y no un
    // ícono todavía viejo.
    centerActionIcon.value = icon;
    centerActionLabel.value = label;
    centerActionRoute.value = route;
    centerActionOwner.value = owner;
    if (!listEquals(centerActionMenu.value, menu)) centerActionMenu.value = menu;
    centerAction.value = action;
  });
}
```

Reemplazar `releaseCenterAction` (líneas 81-85):

```dart
/// Suelta el botón central, pero SOLO si [owner] sigue siendo el dueño.
///
/// La comprobación de identidad importa por el orden de ciclo de vida de
/// Flutter: al reemplazar una pantalla, el `initState` de la nueva corre ANTES
/// del `dispose` de la vieja. Un release incondicional en ese `dispose`
/// borraría lo que la pantalla nueva acaba de registrar.
void releaseCenterAction(Object owner) => _applySafely(() {
      if (!identical(centerActionOwner.value, owner)) return;
      centerActionOwner.value = null;
      centerAction.value = null;
      centerActionIcon.value = null;
      centerActionLabel.value = null;
      centerActionRoute.value = null;
      centerActionMenu.value = null;
    });
```

Actualizar el comentario de cabecera del archivo: donde dice "registrar en `initState` … limpiar
siempre en `dispose`", añadir que una pantalla cuyo estado cambia **dentro de sí misma** sincroniza
desde `build` (ver Task 6).

- [ ] **Step 4: Arreglar el único consumidor actual**

`app/lib/features/client/create_request_screen.dart` — las tres llamadas. Su tear-off guardado
`_centerCamera` (`:178`) pasa a ser **a la vez** dueño y acción, así que su comportamiento no cambia:

Línea 189 (en `initState`):
```dart
    takeCenterAction(
      owner: _centerCamera,
      icon: Icons.photo_camera_outlined,
      label: 'Añadir foto',
      route: kCreateRequestRoute,
      action: _centerCamera,
    );
```

Líneas 198 y 668:
```dart
    releaseCenterAction(_centerCamera);
```
(no cambia — ya pasa el tear-off, que ahora es el `owner`).

`kCreateRequestRoute` ya está importado en ese archivo; verificarlo con
`grep -n "create_request_nav" lib/features/client/create_request_screen.dart` y añadir el import si
faltara.

- [ ] **Step 5: Correr los tests**

Run: `flutter test test/center_action_test.dart`
Expected: PASS (los 5 tests del `group('store')`).

Run: `flutter analyze lib/core/center_action.dart lib/features/client/create_request_screen.dart`
Expected: sin errores.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/center_action.dart app/lib/features/client/create_request_screen.dart app/test/center_action_test.dart
git commit -m "feat(app): el store del boton central admite dueno explicito, ruta, etiqueta y menu"
```

---

### Task 2: El shell deja de estar cableado a crear-solicitud

**Files:**
- Modify: `app/lib/features/shell/home_shell.dart:204-273`
- Modify: `app/lib/features/shell/floating_nav_bar.dart:65-101` (solo el parámetro nuevo)
- Test: `app/test/center_action_shell_test.dart` (existe — se amplía)

**Interfaces:**
- Consumes: `centerActionRoute`, `centerActionLabel`, `centerActionMenu`, `centerActionOwner`,
  `CenterMenuItem` (Task 1).
- Produces: `FloatingNavBar` gana `final List<CenterMenuItem>? centerMenuItems;` (parámetro
  nombrado opcional del constructor). En esta task **solo se recibe y se guarda**; quien lo pinta es
  la Task 4.

- [ ] **Step 1: Escribir los tests que fallan**

En `app/test/center_action_shell_test.dart`, actualizar el `tearDown` (líneas 18-21) con los cuatro
notifiers nuevos (igual que en Task 1), y añadir al final del `main()`:

```dart
  testWidgets('una pantalla que NO es crear-solicitud también puede tomar el ＋',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/client',
      routes: [
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          routes: [
            GoRoute(path: '/client', builder: (_, _) => const Text('mis solicitudes')),
            GoRoute(path: '/otra', builder: (_, _) => const _TakesMenu()),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(centerIcon(tester), isNull);

    GoRouter.of(tester.element(find.text('mis solicitudes'))).push('/otra');
    await tester.pumpAndSettle();

    final bar = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
    expect(bar.centerIconOverride, Icons.library_add_outlined,
        reason: 'la compuerta ya no puede estar cableada a kCreateRequestRoute');
    expect(bar.centerLabelOverride, 'Cargar');
    expect(bar.centerMenuItems, isNotNull);
    expect(bar.centerMenuItems!.length, 1);
  });

  testWidgets('la etiqueta del centro sale del STORE, no del shell',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('mis solicitudes'))).push(kCreateRequestRoute);
    await tester.pumpAndSettle();

    expect(
        tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).centerLabelOverride,
        'Añadir foto',
        reason: 'crear-solicitud la registra ella misma; ya no está a fuego en home_shell');
  });
```

Y al final del archivo, la pantalla de prueba:

```dart
/// Pantalla cualquiera —NO crear-solicitud— que registra un MENÚ.
class _TakesMenu extends StatefulWidget {
  const _TakesMenu();
  @override
  State<_TakesMenu> createState() => _TakesMenuState();
}

class _TakesMenuState extends State<_TakesMenu> {
  final Object _owner = Object();
  void _nada() {}

  @override
  void initState() {
    super.initState();
    takeCenterAction(
      owner: _owner,
      icon: Icons.library_add_outlined,
      label: 'Cargar',
      route: '/otra',
      menu: [
        CenterMenuItem(
            icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: _nada),
      ],
    );
  }

  @override
  void dispose() {
    releaseCenterAction(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('otra pantalla');
}
```

⚠️ El `_TakesCenter` que ya vive en ese archivo usa la firma vieja de `takeCenterAction`:
actualizarlo a la nombrada (`owner:`, `icon:`, `label: 'Añadir foto'`, `route: kCreateRequestRoute`,
`action:`) o el archivo no compila.

- [ ] **Step 2: Correr para verificar que fallan**

Run: `flutter test test/center_action_shell_test.dart`
Expected: FAIL de compilación — `No named parameter with the name 'centerMenuItems'`.

- [ ] **Step 3: Implementar**

`app/lib/features/shell/floating_nav_bar.dart` — en el constructor de `FloatingNavBar` (línea 66-75)
añadir `this.centerMenuItems,` y junto a los campos (tras `centerLabelOverride`, línea 101):

```dart
  /// Destinos que el centro DESPLIEGA en arco al tocarlo, o `null` para el
  /// comportamiento de siempre (un toque = un `onSelected`). La barra sigue sin
  /// saber qué hace cada ítem: solo lo pinta y lo avisa, igual que con los
  /// badges. Quien lo dibuja es `center_arc_menu.dart`.
  final List<CenterMenuItem>? centerMenuItems;
```

con `import '../../core/center_action.dart';` arriba.

`app/lib/features/shell/home_shell.dart`:

1. En el `Listenable.merge` (líneas 204-209) añadir los tres notifiers que el builder va a LEER —
   **la regla que este mismo archivo dejó escrita tras el bug del 2026-07-30 es "si el builder LEE un
   notifier, lo escucha"**, y saltársela reproduce ese bug exacto:

```dart
                listenable: Listenable.merge([
                  solicitudesBadge,
                  messagesBadge,
                  centerAction,
                  centerActionIcon,
                  centerActionRoute,
                  centerActionLabel,
                  centerActionMenu,
                ]),
```

2. Justo antes del `return FloatingNavBar(...)` del builder, un único local (el guard de ruta que
   evita el parpadeo se conserva: solo cambia contra qué compara):

```dart
                builder: (context, _) {
                  // El guard por ubicación sigue existiendo por la misma razón
                  // de siempre: el `dispose()` de la pantalla saliente corre
                  // DESPUÉS de que el shell se reconstruya con la ruta nueva,
                  // así que los notifiers pueden traer el valor viejo por un
                  // frame. Lo que cambia es que ya no compara contra una
                  // constante: cualquier pantalla puede tomar el botón.
                  final tomado = loc == centerActionRoute.value;
                  return FloatingNavBar(
                    ...
                    centerIconOverride: tomado ? centerActionIcon.value : null,
                    centerLabelOverride: tomado ? centerActionLabel.value : null,
                    centerMenuItems: tomado ? centerActionMenu.value : null,
```

3. En la rama del centro de `onSelected` (líneas 250-273), sustituir la comparación cableada:

```dart
                    if (d.isCenter) {
                      final tomado = loc == centerActionRoute.value;
                      // Con menú, la barra ya abrió el arco por su cuenta y
                      // nunca llega hasta aquí. La guarda es defensiva: sin
                      // ella, un toque que se colara empujaría crear-solicitud
                      // encima de la oferta a medio llenar, que es justo el bug
                      // que esta feature viene a eliminar.
                      if (tomado && centerActionMenu.value != null) return;
                      final taken = centerAction.value;
                      if (taken != null && tomado) {
                        taken();
                      } else {
                        assert(d.route == kCreateRequestRoute, ...);  // sin cambios
                        pushCreateRequestOnce(context);
                      }
                    } else { ... }                                    // sin cambios
```

4. Borrar el literal `'Añadir foto'` de la línea 229 (ahora lo registra la pantalla).

- [ ] **Step 4: Correr los tests**

Run: `flutter test test/center_action_shell_test.dart test/center_action_test.dart test/home_shell_test.dart test/home_shell_nav_visibility_test.dart`
Expected: PASS todo, incluidos los dos tests viejos de "dentro de crear solicitud el ＋ se vuelve
CÁMARA" y "al salir vuelve a ser ＋".

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shell/home_shell.dart app/lib/features/shell/floating_nav_bar.dart app/test/center_action_shell_test.dart
git commit -m "feat(app): la compuerta del boton central mira la ruta del store, no una constante"
```

---

### Task 3: El arco y la gota, como widget suelto

**Files:**
- Create: `app/lib/features/shell/center_arc_menu.dart`
- Test: `app/test/center_arc_menu_test.dart` (nuevo)

**Interfaces:**
- Consumes: `CenterMenuItem` (Task 1), `JayaloMotion` (`core/motion.dart`).
- Produces:
  - `const double kArcRadius = 96;`
  - `const double kSatelliteSize = 44;`
  - `const double kSatelliteSlot = 76;`
  - `const double kArcBoxSize = 260;`
  - `class CenterArcMenu extends StatelessWidget` — `const CenterArcMenu({required Animation<double> animation, required List<CenterMenuItem> items, required double centerRadius, required ValueChanged<CenterMenuItem> onPick})`
  - `class ArcBlobPainter extends CustomPainter` — `ArcBlobPainter({required Color color, required Offset center, required double centerRadius, required List<Offset> satellites, required double satelliteRadius})`
  - `List<Offset> arcOffsets(int count, double distance)` — posiciones **relativas al centro**, en
    coordenadas de pantalla (y crece hacia abajo, así que están todas con `dy` negativo).

Nada de este archivo sabe de la barra ni del store: recibe ítems y avisa qué se eligió.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/center_arc_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/features/shell/center_arc_menu.dart';

void main() {
  group('geometría', () {
    test('los cuatro satélites quedan por ENCIMA del centro y simétricos', () {
      final p = arcOffsets(4, kArcRadius);
      expect(p, hasLength(4));
      for (final o in p) {
        expect(o.dy, lessThan(0), reason: 'el arco se abre hacia arriba');
        expect(o.distance, closeTo(kArcRadius, 0.01));
      }
      // Simetría respecto del eje vertical: el primero y el último son espejo.
      expect(p.first.dx, closeTo(-p.last.dx, 0.01));
      // Y sus ETIQUETAS no se solapan — que es la cuenta que de verdad manda,
      // no la de los círculos. Este test es lo que ata el radio al arco: bajar
      // uno sin subir el otro lo pone rojo.
      for (var i = 1; i < p.length; i++) {
        expect((p[i] - p[i - 1]).distance, greaterThan(kSatelliteSlot));
      }
    });

    test('a distancia 0 todos nacen dentro del centro', () {
      for (final o in arcOffsets(4, 0)) {
        expect(o.distance, closeTo(0, 0.01));
      }
    });
  });

  group('widget', () {
    late List<String> elegidos;

    List<CenterMenuItem> items({bool tiendaViva = true}) => [
          CenterMenuItem(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: () {}),
          CenterMenuItem(icon: Icons.photo_library_outlined, label: 'Galería', onTap: () {}),
          CenterMenuItem(
              icon: Icons.storefront_outlined,
              label: 'Mi tienda',
              onTap: () {},
              enabled: tiendaViva),
          CenterMenuItem(
              icon: Icons.collections_bookmark_outlined, label: 'Trabajos', onTap: () {}),
        ];

    Widget host(List<CenterMenuItem> its) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: CenterArcMenu(
                animation: const AlwaysStoppedAnimation(1),
                items: its,
                centerRadius: 28,
                onPick: (it) => elegidos.add(it.label),
              ),
            ),
          ),
        );

    setUp(() => elegidos = []);

    testWidgets('pinta los cuatro íconos y sus cuatro etiquetas', (tester) async {
      await tester.pumpWidget(host(items()));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Mi tienda'), findsOneWidget);
      expect(find.text('Trabajos'), findsOneWidget);
    });

    testWidgets('elegir uno avisa por onPick', (tester) async {
      await tester.pumpWidget(host(items()));
      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await tester.pump();
      expect(elegidos, ['Mi tienda']);
    });

    testWidgets('un ítem deshabilitado NO avisa', (tester) async {
      await tester.pumpWidget(host(items(tiendaViva: false)));
      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await tester.pump();
      expect(elegidos, isEmpty);
    });

    testWidgets('con la animación en 0 no hay nada tocable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CenterArcMenu(
              animation: const AlwaysStoppedAnimation(0),
              items: items(),
              centerRadius: 28,
              onPick: (it) => elegidos.add(it.label),
            ),
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.storefront_outlined), warnIfMissed: false);
      await tester.pump();
      expect(elegidos, isEmpty, reason: 'cerrado, los satélites están dentro del centro');
    });
  });
}
```

- [ ] **Step 2: Correr para verificar que falla**

Run: `flutter test test/center_arc_menu_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'center_arc_menu.dart'`.

- [ ] **Step 3: Implementar el widget**

Crear `app/lib/features/shell/center_arc_menu.dart`:

```dart
/// El menú en arco que despliega el botón central de la barra flotante.
///
/// No sabe de rutas, ni de roles, ni de qué hace cada ítem: recibe una lista y
/// avisa cuál se eligió — el mismo trato que `floating_nav_bar.dart` le da a
/// los badges. Vive en su propio archivo porque la barra ya tiene un solo
/// trabajo (dibujar la píldora) y 467 líneas para hacerlo.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/center_action.dart';
import '../../core/motion.dart';

/// Distancia del centro de cada satélite al del círculo central, abierto.
const double kArcRadius = 96;

/// Diámetro de cada satélite.
const double kSatelliteSize = 44;

/// Ancho reservado a cada satélite CON su etiqueta. Es lo que fija el radio:
/// con cuatro repartidos de 170° a 10°, dos vecinos quedan a
/// `2 · 96 · sin(26,67°) ≈ 86 px`, holgado sobre estos 76. Bajar el radio o
/// estrechar el arco los solapa — es la cuenta que hay que rehacer si alguno
/// de los dos se toca.
const double kSatelliteSlot = 76;

/// Lado de la caja cuadrada que el arco ocupa, centrada en el botón. Da de
/// sobra para el satélite más lejano (96 + 38 de slot/2 = 134) y su etiqueta.
const double kArcBoxSize = 260;

/// Escalonado entre satélites: el arco se despliega, no aparece de golpe.
const _stagger = Duration(milliseconds: 30);

/// Posiciones de los satélites RELATIVAS al centro, a una `distance` dada.
///
/// Se reparten de 170° a 10° (medidos desde el eje X positivo, subiendo por
/// encima), así que en coordenadas de pantalla —donde la Y crece hacia abajo—
/// todas salen con `dy` negativo. Con `count == 1` va uno solo, arriba.
List<Offset> arcOffsets(int count, double distance) {
  if (count <= 0) return const [];
  if (count == 1) return [Offset(0, -distance)];
  const from = 170.0, to = 10.0;
  final step = (to - from) / (count - 1);
  return [
    for (var i = 0; i < count; i++)
      () {
        final rad = (from + step * i) * math.pi / 180;
        return Offset(math.cos(rad) * distance, -math.sin(rad) * distance);
      }(),
  ];
}

class CenterArcMenu extends StatelessWidget {
  const CenterArcMenu({
    super.key,
    required this.animation,
    required this.items,
    required this.centerRadius,
    required this.onPick,
  });

  /// 0 = cerrado (todos dentro del centro), 1 = abierto.
  final Animation<double> animation;
  final List<CenterMenuItem> items;

  /// Radio del círculo central de la barra — la gota nace de él.
  final double centerRadius;
  final ValueChanged<CenterMenuItem> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);
    const half = kArcBoxSize / 2;

    return SizedBox(
      width: kArcBoxSize,
      height: kArcBoxSize,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Con "reducir animaciones" no hay escalonado: todos a la vez.
          double tFor(int i) {
            if (reduced) return animation.value;
            final delay = (_stagger.inMilliseconds * i) /
                JayaloMotion.base.inMilliseconds;
            final span = 1 - delay;
            if (span <= 0) return animation.value;
            return ((animation.value - delay) / span).clamp(0.0, 1.0);
          }

          final posiciones = [
            for (var i = 0; i < items.length; i++)
              arcOffsets(items.length, kArcRadius * tFor(i))[i],
          ];

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ArcBlobPainter(
                    color: cs.primary,
                    center: const Offset(half, half),
                    centerRadius: centerRadius,
                    satellites: [
                      for (final p in posiciones) const Offset(half, half) + p,
                    ],
                    satelliteRadius: kSatelliteSize / 2,
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _Satellite(
                  item: items[i],
                  at: const Offset(half, half) + posiciones[i],
                  t: tFor(i),
                  onPick: onPick,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.item,
    required this.at,
    required this.t,
    required this.onPick,
  });

  final CenterMenuItem item;
  final Offset at;
  final double t;
  final ValueChanged<CenterMenuItem> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Atenuado, no de otro color: sigue siendo el mismo botón, apagado.
    final fg = item.enabled ? cs.onPrimary : cs.onPrimary.withValues(alpha: .38);
    // ⚠️ El `left` se descuenta con el ancho del SLOT, no con el del círculo.
    // La columna la ensancha su ETIQUETA ("Mi tienda" mide más que los 44 del
    // círculo), así que restar `kSatelliteSize / 2` dejaría cada satélite
    // corrido a la derecha en media etiqueta — y corrido DISTINTO en cada uno,
    // porque las cuatro etiquetas miden distinto. El `SizedBox` de abajo fija
    // el ancho para que la cuenta valga.
    return Positioned(
      left: at.dx - kSatelliteSlot / 2,
      top: at.dy - kSatelliteSize / 2,
      width: kSatelliteSlot,
      // `t` manda también en lo tocable: cerrado, los satélites están DENTRO
      // del centro y no deben interceptar nada.
      child: IgnorePointer(
        ignoring: t < .5,
        child: Opacity(
          opacity: t,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: item.label,
                button: true,
                enabled: item.enabled,
                excludeSemantics: true,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: item.enabled ? () => onPick(item) : null,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: kSatelliteSize,
                      height: kSatelliteSize,
                      child: Icon(item.icon, color: fg, size: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: kSatelliteSlot,
                child: Text(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

/// La "gota": el centro y sus satélites unidos por puentes de cintura fina.
///
/// No se usa `Path.combine(union)` ni el truco de blur + umbral de color. Con
/// un relleno OPACO y de un solo color, pintar los círculos y los puentes uno
/// encima de otro se ve exactamente igual que su unión, y cuesta una fracción
/// — importa porque esto repinta en cada frame de la animación y el suelo de
/// gama baja de Android es el que manda. El día que la gota lleve borde o
/// sombra propia, esto deja de valer y hay que unir de verdad.
///
/// La curva es de la misma familia que `buildPillNotchPath`
/// (`floating_nav_bar.dart`): una cintura cóncava entre un círculo y otra
/// silueta.
class ArcBlobPainter extends CustomPainter {
  const ArcBlobPainter({
    required this.color,
    required this.center,
    required this.centerRadius,
    required this.satellites,
    required this.satelliteRadius,
  });

  final Color color;
  final Offset center;
  final double centerRadius;
  final List<Offset> satellites;
  final double satelliteRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawCircle(center, centerRadius, paint);
    for (final s in satellites) {
      final bridge = _bridge(center, centerRadius, s, satelliteRadius);
      if (bridge != null) canvas.drawPath(bridge, paint);
      canvas.drawCircle(s, satelliteRadius, paint);
    }
  }

  /// Puente entre dos círculos. `null` cuando están tan pegados que el puente
  /// quedaría dentro de ellos, o tan lejos que la gota ya se rompió.
  Path? _bridge(Offset a, double ra, Offset b, double rb) {
    final v = b - a;
    final d = v.distance;
    if (d <= ra || d >= (ra + rb) * 2.2) return null;

    final dir = v / d;
    final perp = Offset(-dir.dy, dir.dx);
    // Cuanto más lejos, más fino el puente: así se estira y termina rompiendo.
    final k = (1 - (d - ra) / ((ra + rb) * 1.2)).clamp(0.0, 1.0);
    final a1 = a + perp * ra * k, a2 = a - perp * ra * k;
    final b1 = b + perp * rb * k, b2 = b - perp * rb * k;
    final mid = a + dir * (d / 2);
    // La cintura queda MÁS CERCA del eje que los extremos: eso es lo que la
    // hace cóncava en vez de un simple trapecio.
    final waist = (ra + rb) / 2 * k * .6;

    return Path()
      ..moveTo(a1.dx, a1.dy)
      ..quadraticBezierTo(
          mid.dx + perp.dx * waist, mid.dy + perp.dy * waist, b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..quadraticBezierTo(
          mid.dx - perp.dx * waist, mid.dy - perp.dy * waist, a2.dx, a2.dy)
      ..close();
  }

  @override
  bool shouldRepaint(covariant ArcBlobPainter old) =>
      old.color != color ||
      old.center != center ||
      old.centerRadius != centerRadius ||
      old.satelliteRadius != satelliteRadius ||
      !listEquals(old.satellites, satellites);
}
```

con `import 'package:flutter/foundation.dart' show listEquals;` arriba.

**Los tres números que son gusto y no ingeniería** —`2.2` (cuándo se rompe el puente), `1.2` (cómo
adelgaza) y `.6` (lo fina que queda la cintura)— son el mando estético de la gota. Se dejan como
están y se calibran en device (Task 7), **no** peleando contra un test.

- [ ] **Step 4: Correr los tests**

Run: `flutter test test/center_arc_menu_test.dart`
Expected: PASS los 6.

Run: `flutter analyze lib/features/shell/center_arc_menu.dart`
Expected: sin errores.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shell/center_arc_menu.dart app/test/center_arc_menu_test.dart
git commit -m "feat(app): arco de satelites y gota para el boton central"
```

---

### Task 4: El botón central se abre

**Files:**
- Modify: `app/lib/features/shell/floating_nav_bar.dart:392-467` (`_CenterButton`)
- Test: `app/test/floating_nav_bar_test.dart` (existe — se amplía)

**Interfaces:**
- Consumes: `CenterArcMenu`, `kArcBoxSize` (Task 3); `centerMenuItems` (Task 2).
- Produces: nada nuevo hacia fuera. `_CenterButton` pasa de `StatelessWidget` a `StatefulWidget` con
  `SingleTickerProviderStateMixin`.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `app/test/floating_nav_bar_test.dart`:

```dart
  group('menú en arco', () {
    List<CenterMenuItem> items(void Function(String) log) => [
          CenterMenuItem(
              icon: Icons.photo_camera_outlined,
              label: 'Cámara',
              onTap: () => log('Cámara')),
          CenterMenuItem(
              icon: Icons.storefront_outlined,
              label: 'Mi tienda',
              onTap: () => log('Mi tienda')),
        ];

    Widget host(List<CenterMenuItem>? menu, {VoidCallback? onCenter}) => MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(
            bottomNavigationBar: FloatingNavBar(
              destinations: destinationsFor(RoleState.provider),
              currentIndex: kCenterIndex,
              centerMenuItems: menu,
              centerIconOverride: Icons.library_add_outlined,
              centerLabelOverride: 'Cargar',
              onSelected: (i) { if (i == kCenterIndex) onCenter?.call(); },
            ),
          ),
        );

    testWidgets('sin menú, el centro sigue avisando por onSelected', (tester) async {
      var toques = 0;
      await tester.pumpWidget(host(null, onCenter: () => toques++));
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();
      expect(toques, 1);
      expect(find.byType(CenterArcMenu), findsNothing);
    });

    testWidgets('con menú, tocarlo ABRE el arco y NO avisa por onSelected',
        (tester) async {
      var toques = 0;
      final log = <String>[];
      await tester.pumpWidget(host(items(log.add), onCenter: () => toques++));

      expect(find.byType(CenterArcMenu), findsNothing);
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(CenterArcMenu), findsOneWidget);
      expect(find.text('Mi tienda'), findsOneWidget);
      expect(toques, 0, reason: 'la barra se queda el toque: no debe navegar');
    });

    testWidgets('abierto, el ícono del centro es una ✕', (tester) async {
      await tester.pumpWidget(host(items((_) {})));
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.library_add_outlined), findsNothing);
    });

    testWidgets('elegir un satélite dispara su onTap y cierra el arco',
        (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(items(log.add)));
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await tester.pumpAndSettle();

      expect(log, ['Mi tienda']);
      expect(find.byType(CenterArcMenu), findsNothing);
    });

    testWidgets('el velo cierra sin elegir nada', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(items(log.add)));
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CenterArcMenu), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('el ATRÁS del sistema cierra el arco en vez de salir de la '
        'pantalla', (tester) async {
      // ⚠️ Este test NO puede usar el `host()` de arriba. `BackButtonListener`
      // se cuelga del `backButtonDispatcher` de un `Router` ANCESTRO
      // (`Router.maybeOf`); con un `MaterialApp` pelado no hay Router, el
      // listener no se registra y el test daría un falso NEGATIVO silencioso.
      // En la app real siempre hay uno: `MaterialApp.router` + go_router.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              bottomNavigationBar: FloatingNavBar(
                destinations: destinationsFor(RoleState.provider),
                currentIndex: kCenterIndex,
                centerMenuItems: items((_) {}),
                centerIconOverride: Icons.library_add_outlined,
                centerLabelOverride: 'Cargar',
                onSelected: (_) {},
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
          theme: jayaloTheme(Brightness.light), routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(CenterArcMenu), findsOneWidget);

      final atendido = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(atendido, isTrue, reason: 'el arco debe consumir el atrás');
      expect(find.byType(CenterArcMenu), findsNothing);
    });

    testWidgets('si el menú desaparece con el arco abierto, se cierra solo',
        (tester) async {
      await tester.pumpWidget(host(items((_) {})));
      await tester.tap(find.byIcon(Icons.library_add_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(CenterArcMenu), findsOneWidget);

      // La pantalla soltó el botón (envió la oferta) mientras estaba abierto.
      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();
      expect(find.byType(CenterArcMenu), findsNothing);
    });
  });
```

Añadir los imports que falten al principio del archivo: `center_action.dart`, `center_arc_menu.dart`,
`session_state.dart` y `package:go_router/go_router.dart`.

**Y este aviso para el implementador:** si el test del atrás del sistema sale verde de primeras,
comprobar que de verdad se está ejerciendo el camino — quitar el `BackButtonListener` de la
implementación debe ponerlo ROJO. Un listener que nunca se registra da exactamente el mismo verde que
uno que funciona.

- [ ] **Step 2: Correr para verificar que fallan**

Run: `flutter test test/floating_nav_bar_test.dart`
Expected: FAIL — el grupo nuevo entero; el resto del archivo en verde.

- [ ] **Step 3: Implementar**

En `app/lib/features/shell/floating_nav_bar.dart`, pasar `centerMenuItems` a `_CenterButton` (línea
157) y reescribir `_CenterButton` como `StatefulWidget`:

```dart
class _CenterButton extends StatefulWidget {
  const _CenterButton({
    required this.destination,
    required this.active,
    required this.onTap,
    this.iconOverride,
    this.labelOverride,
    this.menuItems,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;
  final IconData? iconOverride;
  final String? labelOverride;

  /// No-nulo = tocar el botón DESPLIEGA en vez de avisar por [onTap].
  final List<CenterMenuItem>? menuItems;

  @override
  State<_CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<_CenterButton>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: JayaloMotion.base,
    reverseDuration: JayaloMotion.base,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _anim,
    curve: JayaloMotion.enter,
    reverseCurve: JayaloMotion.exit,
  );

  bool get _open => _portal.isShowing;

  @override
  void didUpdateWidget(_CenterButton old) {
    super.didUpdateWidget(old);
    // La pantalla soltó el botón (envió la oferta, salió) con el arco abierto:
    // cerrarlo sin animación, porque lo que lo justificaba ya no existe.
    if (widget.menuItems == null && _open) {
      _anim.value = 0;
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    final items = widget.menuItems;
    if (items == null || items.isEmpty) {
      widget.onTap();
      return;
    }
    if (_open) {
      _close();
    } else {
      JayaloHaptics.tabChange();
      _portal.show();
      if (JayaloMotion.reduced(context)) {
        _anim.value = 1;
      } else {
        _anim.forward(from: 0);
      }
      setState(() {});
    }
  }

  void _close() {
    if (!_open) return;
    if (JayaloMotion.reduced(context)) {
      _anim.value = 0;
      _portal.hide();
      setState(() {});
      return;
    }
    _anim.reverse().whenComplete(() {
      if (!mounted) return;
      _portal.hide();
      setState(() {});
    });
    setState(() {});
  }

  void _pick(CenterMenuItem item) {
    _close();
    item.onTap();
  }
  ...
}
```

El `build` conserva **exactamente** el `Stack`/`Positioned` de hoy (el `Stack` con la etiqueta
posicionada existe para que el círculo no se mueva ni un píxel al activarse — regresión C1, hay un
test que la vigila). Los cambios son tres:

1. Envolver el `Material` del círculo en `CompositedTransformTarget(link: _link, child: ...)`.
2. El `InkWell.onTap` pasa de `widget.onTap` a `_toggle`.
3. El ícono: `_open ? Icons.close : (widget.iconOverride ?? widget.destination.icon)`, dentro de un
   `AnimatedRotation(turns: _open ? .125 : 0, duration: ..., curve: JayaloMotion.enter)` — 45°, que
   es el giro que convierte un ＋ en una ✕ y hace de puente cuando el ícono en reposo no es un ＋.
4. Envolver todo el `Stack` en el portal:

```dart
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => BackButtonListener(
        // El arco NO es una ruta: sin esto el atrás del sistema saldría de la
        // pantalla dejándolo abierto. Los hijos de `OverlayPortal` siguen en el
        // árbol lógico, así que este listener los alcanza. NO se toca
        // `BackGuard` ni se añade un `PopScope`: con predictive back ahí hay un
        // gotcha conocido (ver `back_guard.dart`).
        onBackButtonPressed: () async {
          if (!_open) return false;
          _close();
          return true;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: Semantics(
                  label: 'Cerrar menú',
                  button: true,
                  child: FadeTransition(
                    opacity: _curved,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.scrim.withValues(alpha: .32),
                    ),
                  ),
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.center,
              followerAnchor: Alignment.center,
              child: CenterArcMenu(
                animation: _curved,
                items: widget.menuItems ?? const [],
                centerRadius: _centerSize / 2,
                onPick: _pick,
              ),
            ),
          ],
        ),
      ),
      child: /* el Stack de hoy, con el CompositedTransformTarget dentro */,
    );
```

⚠️ El velo va **debajo** del `CompositedTransformFollower` en el `Stack`, y la caja del arco no
declara `HitTestBehavior.opaque`: así los toques en su parte vacía caen al velo y cierran, en vez de
morir en un cuadrado invisible de 240×240.

Añadir arriba `import '../../core/center_action.dart';` y `import 'center_arc_menu.dart';`.

- [ ] **Step 4: Correr los tests**

Run: `flutter test test/floating_nav_bar_test.dart test/center_action_shell_test.dart test/nav_bar_reserved_space_test.dart`
Expected: PASS. Especial atención a los tests viejos de la muesca y de "el círculo central no se sale
de la muesca al activarse": si alguno se pone rojo, el `Stack` del `build` se tocó de más.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shell/floating_nav_bar.dart app/test/floating_nav_bar_test.dart
git commit -m "feat(app): el boton central despliega el arco cuando hay menu registrado"
```

---

### Task 5: Una sola compuerta para "formulario o tarjeta"

Refactor puro: **cero cambio de comportamiento**. Va en su propio commit para que se pueda revisar y
revertir sin arrastrar la feature.

**Files:**
- Create: `app/lib/domain/offer_form_gate.dart`
- Modify: `app/lib/features/provider/request_detail_screen.dart:1728-1750`
- Modify: `app/lib/domain/offer_edit.dart` (solo el comentario de mantenimiento)
- Test: `app/test/domain/offer_form_gate_test.dart` (nuevo)

**Interfaces:**
- Produces:
  - `bool offerFormVisible({required bool editing, required String? businessId, required bool offerChecked, required Map<String, dynamic>? existingOffer})` en `lib/domain/offer_form_gate.dart` — función pura, sin `BuildContext`.
  - `bool get _offerFormVisible` en `_ProviderRequestDetailScreenState`, que **delega** en ella
    (privado; lo consume la Task 6 desde dentro de la misma clase).

**Por qué la regla sale a `lib/domain/`:** un test que reimplementa la condición para compararla
consigo misma no prueba nada — pasaría igual con el getter roto. `lib/domain/offer_edit.dart` ya es
exactamente este patrón (regla pura extraída de esta misma pantalla), así que la casa ya tiene sitio
para esto.

**El porqué:** la decisión está repartida en una cadena `if / else if / else if / else`. Duplicarla
en la Task 6 para saber si registrar el menú es exactamente el duplicado que `domain/offer_edit.dart`
ya sufre — su comentario apunta a `request_detail_screen.dart:1559-1560`, líneas que ya se movieron.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/domain/offer_form_gate_test.dart`. Importa la función **real** — no una copia:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_form_gate.dart';

void main() {
  const bid = 'b-1';

  test('sin negocio y sin editar: no hay formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: null, offerChecked: true, existingOffer: null),
        isFalse);
  });

  test('mientras se comprueba si ya ofertó: no hay formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: bid, offerChecked: false, existingOffer: null),
        isFalse);
  });

  test('sin oferta previa: formulario', () {
    expect(
        offerFormVisible(
            editing: false, businessId: bid, offerChecked: true, existingOffer: null),
        isTrue);
  });

  test('con oferta ya enviada: tarjeta, no formulario', () {
    expect(
        offerFormVisible(
            editing: false,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'pending'}),
        isFalse);
  });

  test('editando una PENDIENTE: formulario', () {
    expect(
        offerFormVisible(
            editing: true,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'pending'}),
        isTrue);
  });

  test('una ACEPTADA no se edita nunca: tarjeta', () {
    expect(
        offerFormVisible(
            editing: true,
            businessId: bid,
            offerChecked: true,
            existingOffer: {'status': 'accepted'}),
        isFalse);
  });
}
```

- [ ] **Step 2: Correrlo para verificar que falla**

Run: `flutter test test/domain/offer_form_gate_test.dart`
Expected: FAIL de compilación — no existe `lib/domain/offer_form_gate.dart`.

- [ ] **Step 3: Extraer la regla y delegar**

Crear `app/lib/domain/offer_form_gate.dart`:

```dart
/// ¿El detalle de solicitud del proveedor pinta el FORMULARIO de la oferta, o
/// una de las tres cosas que lo sustituyen?
///
/// Regla pura, sin `BuildContext` ni estado: así se prueba de verdad, sin montar
/// una pantalla que necesita red y sesión. Mismo patrón que `offer_edit.dart`.
///
/// Es la negación EXACTA de las tres ramas que la preceden en la cadena del
/// `build` (`request_detail_screen.dart`):
///   1. `!editing && businessId == null` → CTA "completa tu negocio en la web"
///   2. `!offerChecked`                  → spinner
///   3. oferta existente que no sea edición de una PENDIENTE → tarjeta de estado
///
/// MANTENIMIENTO: `offer_edit.dart` (`canEditOfferInPlace`) reproduce la TERCERA
/// de esas condiciones para decidir si "Ver mi oferta" hace algo. Si tocas esta
/// regla, actualiza también aquella o el botón vuelve a quedar muerto.
bool offerFormVisible({
  required bool editing,
  required String? businessId,
  required bool offerChecked,
  required Map<String, dynamic>? existingOffer,
}) =>
    !(!editing && businessId == null) &&
    offerChecked &&
    !(existingOffer != null &&
        (!editing || existingOffer['status'] != 'pending'));
```

En `app/lib/features/provider/request_detail_screen.dart`, junto a `_editing` (línea 171), un getter
que **delega** (nada de reimplementar la condición):

```dart
  /// ¿Se está pintando el FORMULARIO de la oferta (y no la tarjeta, el spinner
  /// o el CTA de completar el negocio)?
  ///
  /// Única fuente de verdad de esa decisión: la cadena del `build` la consume y
  /// el registro del menú del botón central también (ver `_syncCenterAction`).
  bool get _offerFormVisible => offerFormVisible(
        editing: _editing,
        businessId: _businessId,
        offerChecked: _offerChecked,
        existingOffer: _existingOffer,
      );
```

con `import '../../domain/offer_form_gate.dart';` arriba.

En la cadena del `build` (línea 1750), la última rama pasa de `else ...[` a
`else if (_offerFormVisible) ...[`. Las tres ramas previas **no se tocan**: si algún día divergieran,
el fallo sería "no se pinta el formulario" —ruidoso e inmediato— y nunca un menú fantasma sobre una
tarjeta.

En `app/lib/domain/offer_edit.dart`, corregir la referencia obsoleta del comentario: donde dice
`request_detail_screen.dart:1559-1560`, poner `` `_offerFormVisible` en
`request_detail_screen.dart` ``.

- [ ] **Step 4: Correr la suite del proveedor**

Run: `flutter test test/domain/ test/inbox_screen_test.dart test/improve_offer_error_test.dart test/finalist_slots_test.dart`
Expected: PASS.

Run: `flutter analyze lib/features/provider/request_detail_screen.dart lib/domain/`
Expected: sin errores.

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/offer_form_gate.dart app/lib/features/provider/request_detail_screen.dart app/lib/domain/offer_edit.dart app/test/domain/offer_form_gate_test.dart
git commit -m "refactor(app): una sola compuerta para formulario-vs-tarjeta en el detalle de solicitud"
```

---

### Task 6: La oferta registra su menú

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
- Test: `app/test/provider_center_menu_test.dart` (nuevo)

**Interfaces:**
- Consumes: `takeCenterAction`, `releaseCenterAction`, `CenterMenuItem` (Task 1);
  `_offerFormVisible` (Task 5).
- Produces: nada hacia fuera.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/provider_center_menu_test.dart`. Montar la pantalla entera pide red y sesión, así que
se prueba **la regla de armado del menú**, que es donde vive el riesgo real (qué se deshabilita y
cuándo). Extraer esa regla a una función libre y probarla:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/features/provider/offer_center_menu.dart';

void main() {
  void nada() {}

  List<CenterMenuItem> menu({required bool busy, required int fotos}) =>
      buildOfferCenterMenu(
        busy: busy,
        photoCount: fotos,
        maxPhotos: 5,
        onCamera: nada,
        onGallery: nada,
        onStore: nada,
        onPortfolio: nada,
      );

  bool viva(List<CenterMenuItem> m, String label) =>
      m.firstWhere((i) => i.label == label).enabled;

  test('los cuatro destinos, siempre, y en este orden', () {
    expect(menu(busy: false, fotos: 0).map((i) => i.label).toList(),
        ['Cámara', 'Galería', 'Mi tienda', 'Trabajos']);
  });

  test('con sitio para fotos, los cuatro vivos', () {
    final m = menu(busy: false, fotos: 2);
    expect(m.every((i) => i.enabled), isTrue);
  });

  test('al tope de fotos se apagan los tres de FOTO, pero "Mi tienda" sigue '
      'vivo: además autocompleta precio, color, envío y estado', () {
    final m = menu(busy: false, fotos: 5);
    expect(viva(m, 'Cámara'), isFalse);
    expect(viva(m, 'Galería'), isFalse);
    expect(viva(m, 'Trabajos'), isFalse);
    expect(viva(m, 'Mi tienda'), isTrue);
  });

  test('enviando la oferta, todo apagado', () {
    expect(menu(busy: true, fotos: 0).any((i) => i.enabled), isFalse);
  });

  test('el menú es igual POR VALOR entre reconstrucciones equivalentes: el '
      'formulario se rearma con cada tecla del campo de precio', () {
    expect(menu(busy: false, fotos: 1), equals(menu(busy: false, fotos: 1)));
    expect(menu(busy: false, fotos: 1), isNot(equals(menu(busy: false, fotos: 5))));
  });
}
```

- [ ] **Step 2: Correr para verificar que falla**

Run: `flutter test test/provider_center_menu_test.dart`
Expected: FAIL — no existe `offer_center_menu.dart`.

- [ ] **Step 3: La regla, en su propio archivo**

Crear `app/lib/features/provider/offer_center_menu.dart`:

```dart
/// Qué destinos ofrece el botón central mientras se redacta una oferta, y
/// cuáles están vivos.
///
/// Función libre y sin `BuildContext` a propósito: es la única parte de esta
/// feature con reglas propias, y así se prueba sin montar una pantalla que
/// necesita red y sesión.
library;

import 'package:flutter/material.dart';

import '../../core/center_action.dart';

/// Los cuatro son atajos a botones que YA existen en el formulario; aquí no se
/// inventa ningún camino nuevo.
///
/// Con el álbum lleno se APAGAN los tres que solo sirven para traer fotos, pero
/// **"Mi tienda" sigue vivo**: además de fotos autocompleta precio, color,
/// envío, instalación y estado, y eso vale igual con las cinco fotos puestas.
///
/// No se esconde ninguno: un arco que pasa de cuatro satélites a uno se lee
/// como un fallo. (Diverge a propósito del formulario, donde los botones
/// desaparecen al llegar al tope.)
List<CenterMenuItem> buildOfferCenterMenu({
  required bool busy,
  required int photoCount,
  required int maxPhotos,
  required VoidCallback onCamera,
  required VoidCallback onGallery,
  required VoidCallback onStore,
  required VoidCallback onPortfolio,
}) {
  final haySitio = photoCount < maxPhotos;
  return [
    CenterMenuItem(
        icon: Icons.photo_camera_outlined,
        label: 'Cámara',
        onTap: onCamera,
        enabled: !busy && haySitio),
    CenterMenuItem(
        icon: Icons.photo_library_outlined,
        label: 'Galería',
        onTap: onGallery,
        enabled: !busy && haySitio),
    CenterMenuItem(
        icon: Icons.storefront_outlined,
        label: 'Mi tienda',
        onTap: onStore,
        enabled: !busy),
    CenterMenuItem(
        icon: Icons.collections_bookmark_outlined,
        label: 'Trabajos',
        onTap: onPortfolio,
        enabled: !busy && haySitio),
  ];
}
```

- [ ] **Step 4: Cablearlo en la pantalla**

En `app/lib/features/provider/request_detail_screen.dart`, junto a los demás campos del `State`:

```dart
  /// Identidad de esta pantalla ante el store del botón central. Un `Object()`
  /// pelado basta: lo único que se le pide es no ser igual al de nadie más.
  final Object _centerOwner = Object();

  /// La ruta que el shell compara. Se compone de lo que la pantalla ya sabe, sin
  /// leer inherited widgets (`GoRouterState.of` no se puede usar en `initState`).
  /// El shell compara contra `uri.path`, SIN query, así que entrar en edición
  /// con `?edit=<id>` no rompe la igualdad.
  String get _centerRoute => '/provider/request/${widget.requestId}';

  /// Tear-offs guardados UNA vez: `CenterMenuItem` compara sus `onTap` por
  /// igualdad, y un `() => _pickPhoto(...)` nuevo en cada build rompería la
  /// comparación por valor y repintaría la barra con cada tecla.
  late final VoidCallback _menuCamera = () => _pickPhoto(ImageSource.camera);
  late final VoidCallback _menuGallery = () => _pickPhoto(ImageSource.gallery);
  late final VoidCallback _menuStore = _pickFromStore;
  late final VoidCallback _menuPortfolio = _pickFromPortfolio;
```

Y el sincronizador:

```dart
  /// Pone al día el botón central de la barra según el estado de ESTA pantalla.
  ///
  /// ⚠️ Se llama desde `build`, y eso es deliberado. `CreateRequestScreen`
  /// registra en `initState` y suelta en `dispose`, y le basta porque su estado
  /// no cambia. Aquí el formulario aparece y desaparece DENTRO de la misma
  /// pantalla: al enviar la oferta, al entrar en edición en sitio, al
  /// cancelarla, al borrar. Registrar en esos cuatro sitios funciona hoy y se
  /// rompe en silencio la primera vez que alguien añada un quinto camino;
  /// desde `build` no se puede desincronizar.
  ///
  /// Escribir notifiers desde `build` es seguro PRECISAMENTE porque
  /// `_applySafely` (en `core/center_action.dart`) aplaza al final del frame:
  /// ese es el caso para el que se escribió. Y no realimenta: el
  /// `ListenableBuilder` del shell envuelve solo la barra, no el `child` del
  /// Navigator anidado.
  void _syncCenterAction() {
    if (!_offerFormVisible) {
      releaseCenterAction(_centerOwner);
      return;
    }
    takeCenterAction(
      owner: _centerOwner,
      icon: Icons.library_add_outlined,
      label: 'Cargar',
      route: _centerRoute,
      menu: buildOfferCenterMenu(
        busy: _busy,
        photoCount: _photoCount,
        maxPhotos: _maxOfferPhotos,
        onCamera: _menuCamera,
        onGallery: _menuGallery,
        onStore: _menuStore,
        onPortfolio: _menuPortfolio,
      ),
    );
  }
```

Llamarlo como **primera línea del `build`** (línea 1579), y soltar en `dispose`:

```dart
  @override
  void dispose() {
    // Salir de la pantalla no siempre pasa por un `build` con el formulario ya
    // cerrado. La guarda de identidad del store hace que esto sea inofensivo si
    // la pantalla entrante ya tomó el botón.
    releaseCenterAction(_centerOwner);
    ...  // lo que ya hubiera
  }
```

Si `dispose` no existía en esa clase, crearlo llamando a `super.dispose()` al final y disponiendo los
`TextEditingController` que ya se disponen (comprobar antes con
`grep -n "void dispose" lib/features/provider/request_detail_screen.dart`).

Añadir el aviso al tope de fotos: en `_pickPhoto`, antes del `guardedPick`, cortar temprano si ya no
cabe (hoy el formulario esconde los botones, así que ese camino no se daba; con el menú sí):

```dart
    if (_photoCount >= _maxOfferPhotos) {
      _toast('Ya tienes 5 fotos');
      return;
    }
```

- [ ] **Step 5: Correr los tests**

Run: `flutter test test/provider_center_menu_test.dart test/domain/offer_form_gate_test.dart`
Expected: PASS.

Run: `flutter analyze lib/features/provider/`
Expected: sin errores.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/provider/offer_center_menu.dart app/lib/features/provider/request_detail_screen.dart app/test/provider_center_menu_test.dart
git commit -m "feat(app): la pantalla de la oferta registra el menu del boton central"
```

---

### Task 7: Suite entera y guion de smoke

**Files:**
- Create: `app/../docs/qa/2026-08-05-smoke-menu-arco-oferta.md`

- [ ] **Step 1: Suite completa**

Run: `flutter analyze`
Expected: sin errores **nuevos** respecto de la rama base.

Run: `flutter test`
Expected: todo verde. La rama base traía **742** tests; este plan suma ~24. Si algo se pone rojo en
`floating_nav_bar_test.dart`, `nav_bar_reserved_space_test.dart` o `center_action_shell_test.dart`,
**parar**: son las tres redes que protegen la barra y la cámara de crear-solicitud.

- [ ] **Step 2: Escribir el guion de smoke**

Crear `docs/qa/2026-08-05-smoke-menu-arco-oferta.md` siguiendo el formato de
`docs/qa/2026-08-04-smoke-correcciones-ui.md`, con estas casillas:

1. Proveedor entra a una solicitud **sin ofertar** → el centro dice "Cargar", no "Crear solicitud".
2. Tocarlo → arco de cuatro con la gota; el centro es una ✕.
3. Cierra por ✕. Cierra por velo. Cierra por **atrás del sistema** (y no sale de la pantalla).
4. Cada satélite hace lo mismo que su botón gemelo del formulario (los cuatro).
5. "Mi tienda" autocompleta y lo autocompletado **queda editable**.
6. Con 5 fotos: Cámara, Galería y Trabajos atenuados y avisan "Ya tienes 5 fotos"; "Mi tienda" vivo.
7. **Enviar la oferta → aparece la tarjeta y el centro vuelve a "Crear solicitud".** Es la casilla
   con más probabilidad de fallar: hay un desfase de un frame entre el `dispose`/`release` y el
   rebuild del shell que `home_shell.dart` ya documenta. Si parpadea, el arreglo va en el guard de
   ruta del shell, no en la pantalla.
8. Volver a entrar → "Ver mi oferta" → edición en sitio → el menú vuelve.
9. **No regresión:** dentro de crear solicitud el ＋ sigue siendo la cámara y sigue añadiendo fotos.
10. Con "reducir animaciones" del sistema: el arco aparece sin escalonar, y el háptico **sigue**.
11. **Las cuatro etiquetas caben** en la pantalla más estrecha disponible, sin solaparse. Los tests
    no pueden firmarlo: en `flutter test` el texto mide ~2× lo real.
12. La gota se ve como en la referencia del PO. Si queda sosa, los tres mandos son `2.2`, `1.2` y
    `.6` en `_bridge` (`center_arc_menu.dart`) — no hay ningún test peleando contra ellos.

Conducir el device por `adb` según `docs/` de convenciones (memoria
`jayalo-conducir-device-por-adb`): factor ×1.36 en las capturas, sondeo por tamaño de PNG.

- [ ] **Step 3: Commit**

```bash
git add docs/qa/2026-08-05-smoke-menu-arco-oferta.md
git commit -m "docs(qa): guion de smoke del menu en arco del boton central"
```

---

## Estado final esperado

- 6 commits de código + 1 de QA sobre `feat/menu-arco-oferta`.
- Archivos nuevos: `center_arc_menu.dart`, `offer_center_menu.dart` y cuatro de test.
- **Nada pusheado, ningún PR abierto, cero migraciones.** El smoke de la Task 7 es el único gate real.
