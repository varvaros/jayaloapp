# Detalle de solicitud del cliente: foto plegable y orden de secciones — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar T3 (foto plegable) y T4 (orden de secciones) del spec del 2026-08-01 a `lib/features/client/request_status_screen.dart`, que quedó fuera de aquella tanda.

**Architecture:** La pantalla del cliente conserva el patrón que T3 vino a eliminar: `Column(panel de alto fijo, Expanded(lista))`. Se sustituye por `CustomScrollView(slivers: [CollapsingPhotoPanel, SliverFillRemaining(hoja)])`, espejando al proveedor. El contenido de la hoja se reordena a identidad → ESTADO → INFORMACIÓN → acción. Dos extracciones habilitan el trabajo: la hoja sale a su propio fichero (crea el seam de tests que hoy no existe) y el helper de rótulos sube a `shared/` (hoy es privado del proveedor).

**Tech Stack:** Flutter 3.44.6 · Dart · `flutter_test` (widget tests) · Supabase para datos.

**Spec:** `docs/superpowers/specs/2026-08-02-detalle-solicitud-cliente-design.md`

## Global Constraints

- Idioma: **español** en comentarios y en todo texto visible al usuario.
- `flutter analyze` sin errores nuevos.
- `flutter test` verde. **Baseline verificado antes de empezar: 649 tests, todos pasando.** Cualquier caída es una regresión.
- Los mensajes de commit van en español y terminan con:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- **Un "movimiento puro" es exactamente eso**: cortar y pegar sin tocar una línea de lógica ni de estilo. Si al mover algo te dan ganas de mejorarlo, no lo hagas en esa tarea.
- Los tests de widget viven en `app/test/` con nombre `<tema>_test.dart`, siguiendo el patrón de `test/collapsing_photo_panel_test.dart`: un helper `host(...)` que monta el widget dentro de `MaterialApp(theme: jayaloTheme(Brightness.light))`.
- **No tocar** la hoja de ofertas (`_OffersSheet`), `_showOffers`, ni el flujo de aceptar/rechazar.

---

## File Structure

**Nuevos:**

| Archivo | Responsabilidad |
|---|---|
| `app/lib/features/client/request_detail_sheet.dart` | La hoja blanca del detalle del cliente, extraída de `request_status_screen.dart`. Pública, para que los tests puedan montarla. |
| `app/lib/features/shared/section_heading.dart` | `sectionHeading(BuildContext, String)` — el rótulo de sección en versalita, hoy privado del proveedor. |
| `app/test/client_request_detail_sheet_test.dart` | Tests de la hoja: hipótesis del título recortado, orden de secciones, CTA fijo. |
| `app/test/client_request_photo_panel_test.dart` | Tests del panel plegable en la pantalla del cliente. |

**Modificados:**

| Archivo | Cambio |
|---|---|
| `app/lib/features/client/request_status_screen.dart` | Sale `_DetailSheet` (a su fichero) y muere `_AmberPanel`. La estructura pasa a `CustomScrollView`. |
| `app/lib/features/provider/request_detail_screen.dart` | `_sectionHeading` se retira y sus dos llamadas pasan al helper compartido. Sin cambio visual. |

---

## Task 1: Extraer la hoja a su propio fichero

**Files:**
- Create: `app/lib/features/client/request_detail_sheet.dart`
- Modify: `app/lib/features/client/request_status_screen.dart`

**Interfaces:**
- Consumes: nada nuevo.
- Produces: `class RequestDetailSheet extends StatelessWidget` con el constructor
  `const RequestDetailSheet({super.key, required Map<String, dynamic> request, required RequestPhase phase, required List<Map<String, dynamic>> offers, required int unreadCount, required VoidCallback onSeeOffers})`.

**Por qué esta tarea existe:** `request_status_screen.dart` tiene 1128 líneas y la hoja es una unidad coherente de ~250. Pero la razón operativa es otra: `_DetailSheet` es privado, así que **hoy no hay forma de montarlo en un test**. Sin este seam, la Task 2 no se puede escribir. La extracción se justifica sola aunque la hipótesis de la Task 2 resulte falsa.

- [ ] **Step 1: Mover la clase**

Cortar `class _DetailSheet extends StatelessWidget { … }` de `request_status_screen.dart` (empieza en la línea 649 con su docstring `/// Hoja blanca del detalle: …`) y pegarla en el fichero nuevo. Renombrar a `RequestDetailSheet` y quitar el guion bajo del constructor.

Llevar también los imports que necesite. Mirar qué usa: `fmtRD`, `jayaloHead`, `formatDayLabel`, `formatTimeHM`, `requestBudgetLabel`, `clientSlotsMessage`, `_phaseCopy`, `toneFor`, `offerEffectivePrice`, `RequestPhase`, `_ProviderDots`.

**`_phaseCopy` y `_ProviderDots` son privados del fichero original.** Decidir por cada uno:
- Si solo lo usa la hoja, muévelo también al fichero nuevo (y déjalo privado ahí).
- Si lo usan hoja y pantalla, hazlo público y déjalo donde está, importándolo.

Comprueba cuál es el caso con `grep -n "_phaseCopy\|_ProviderDots" lib/features/client/request_status_screen.dart` **antes** de mover nada, y di en tu reporte qué encontraste y qué hiciste.

- [ ] **Step 2: Actualizar la llamada**

En `request_status_screen.dart`, cambiar `_DetailSheet(` por `RequestDetailSheet(` y añadir el import del fichero nuevo.

- [ ] **Step 3: Verificar que es un movimiento puro**

Run: `cd app && flutter analyze`
Expected: sin errores nuevos.

Run: `cd app && flutter test`
Expected: **649 passed**, ni uno menos.

Además, confirma tú mismo con `git diff --stat` que el número de líneas borradas en `request_status_screen.dart` es aproximadamente igual al de líneas creadas en el fichero nuevo. Si hay una diferencia grande, revisa qué cambiaste sin querer.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/client/request_detail_sheet.dart app/lib/features/client/request_status_screen.dart
git commit -m "refactor(app): la hoja del detalle del cliente sale a su fichero

Movimiento puro para crear el seam de tests: _DetailSheet era privado y no
habia forma de montarlo. request_status_screen.dart baja de 1128 lineas.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: El test de la hipótesis (test de caracterización)

**Files:**
- Create: `app/test/client_request_detail_sheet_test.dart`

**Interfaces:**
- Consumes: `RequestDetailSheet` (Task 1).
- Produces: nada que consuman otras tareas.

**Lee esto antes de escribir una línea, porque esta tarea no funciona como las demás.**

**No es un RED de TDD.** No estás escribiendo un test que falla para luego hacerlo pasar. Estás escribiendo un **test de caracterización**: uno que documenta lo que el código hace HOY, para decidir si el diagnóstico del spec es cierto.

El spec afirma que el título se ve recortado por el panel fijo. **Es una hipótesis a partir de una captura de pantalla, no un hecho verificado.** Esta tarea existe para probarla o tumbarla.

Lecturas del resultado:

- **El test PASA** → la hipótesis queda **confirmada**: el título sí se mete bajo el panel al scrollear. Sigue adelante; el plan se sostiene.
- **El test FALLA** → la hipótesis es **falsa**: el título no se comporta como se creía. **PARA.** No lo "arregles" para que pase, y no toques las Tasks 4 ni 5. Reporta `DONE_WITH_CONCERNS` con la geometría real que observaste y deja que el controlador decida.

Un plan construido sobre un diagnóstico falso hace más daño que no tener plan. Que el test falle es un resultado perfectamente válido de esta tarea, y reportarlo es hacerlo bien.

- [ ] **Step 1: Escribir el test**

Crear `app/test/client_request_detail_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/request_phase.dart';
import 'package:jayalo_app/features/client/request_detail_sheet.dart';

/// El PO reportó (2026-08-02, captura de device) que en el detalle de su
/// solicitud la primera línea del título aparece cortada por el borde inferior
/// de la foto. La hipótesis del spec es que la causa es el panel de alto FIJO:
/// la lista scrollea y su contenido se recorta contra él.
///
/// Este test reproduce la estructura actual para confirmarlo. Si pasa, la
/// hipótesis es falsa y hay que investigar de nuevo.
void main() {
  final request = <String, dynamic>{
    'id': 'req-1',
    'user_id': 'user-1',
    'title': 'Teclado Inalámbrico Klip Xtreme con receptor USB y teclado numérico',
    'bullets': <String>['Marca: Klip Xtreme'],
    'created_at': DateTime.now().toIso8601String(),
    'status': 'open',
    'is_wholesale': false,
    'budget_min': null,
    'budget_max': null,
    'image_urls': <String>[],
  };

  /// Réplica de la estructura ACTUAL: panel de alto fijo + hoja en un Expanded.
  Widget hostActual() => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              Container(height: 300, color: const Color(0xFFF0C48C)),
              Expanded(
                child: RequestDetailSheet(
                  request: request,
                  phase: RequestPhase.responded,
                  offers: const [],
                  unreadCount: 0,
                  onSeeOffers: () {},
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('HIPÓTESIS: al scrollear, el título queda recortado por el panel fijo',
      (tester) async {
    await tester.pumpWidget(hostActual());
    await tester.pumpAndSettle();

    final titulo = find.text(request['title'] as String);
    expect(titulo, findsOneWidget);

    // Arriba del todo el título se ve entero, por debajo del panel.
    final antes = tester.getRect(titulo);
    expect(antes.top, greaterThanOrEqualTo(300.0),
        reason: 'en reposo el título debe empezar por debajo del panel');

    // Scrollear la lista hacia arriba.
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    final despues = tester.getRect(titulo);

    // Si el título sube por encima del borde inferior del panel, está siendo
    // tapado: eso es el recorte que reportó el PO.
    expect(despues.top, lessThan(300.0),
        reason: 'HIPÓTESIS CONFIRMADA si el título se mete bajo el panel fijo');
  });
}
```

> Los valores de `request` son los mínimos que la hoja necesita para construirse. Si al correrlo falta alguna clave, **añádela con un valor realista** y anótalo en tu reporte — no cambies la aserción.

- [ ] **Step 2: Correr el test**

Run: `cd app && flutter test test/client_request_detail_sheet_test.dart`

Los dos resultados son válidos. Lo que NO es válido es tocar la aserción para forzar uno.

- **PASA** → hipótesis confirmada, el título se mete bajo el panel. Sigue.
- **FALLA** → hipótesis falsa. **PARA** y reporta `DONE_WITH_CONCERNS` con la geometría real: `antes.top`, `despues.top` y el alto del viewport de la lista. Esos tres números son lo que el controlador necesita para replantear.

En ambos casos, **deja el test commiteado**: documenta el comportamiento real, que es más de lo que había antes. Si falló, ajústalo para que refleje lo que de verdad ocurre (invirtiendo la aserción y explicándolo en el comentario), no lo borres — un test que dice la verdad vale aunque la verdad no fuera la esperada.

- [ ] **Step 3: Commit**

```bash
git add app/test/client_request_detail_sheet_test.dart
git commit -m "test(app): fijar el comportamiento del titulo bajo el panel fijo

Reproduce la estructura actual del detalle del cliente para verificar la
hipotesis del spec sobre el titulo recortado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Extraer el rótulo de sección a `shared/`

**Files:**
- Create: `app/lib/features/shared/section_heading.dart`
- Modify: `app/lib/features/provider/request_detail_screen.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `Widget sectionHeading(BuildContext context, String t)` — la Task 5 lo usa.

- [ ] **Step 1: Crear el helper compartido**

Crear `app/lib/features/shared/section_heading.dart` con el cuerpo **exacto** del privado del proveedor (`request_detail_screen.dart:1063-1072`), sin cambiar un solo valor:

```dart
import 'package:flutter/material.dart';

/// Rótulo de sección en versalita discreta. Nació privado en el detalle de
/// solicitud del proveedor (T4, 2026-08-01) y sube aquí al aparecer el segundo
/// consumidor: el detalle del lado del cliente. Mismo criterio que se siguió
/// con `CollapsingPhotoPanel`.
Widget sectionHeading(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 2),
      child: Text(t.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
    );
```

- [ ] **Step 2: Migrar al proveedor**

En `request_detail_screen.dart`:
- Borrar el método privado `_sectionHeading` (líneas 1063-1072).
- Añadir `import '../shared/section_heading.dart';`.
- Cambiar las dos llamadas: `_sectionHeading(context, 'Datos del cliente')` → `sectionHeading(context, 'Datos del cliente')` (línea ~1419) y lo mismo con `'Información'` (línea ~1432).

- [ ] **Step 3: Verificar que no cambió nada visualmente**

Run: `cd app && flutter analyze`
Expected: sin errores nuevos.

Run: `cd app && flutter test`
Expected: **649 passed**. Los tests de T4 del proveedor deben seguir verdes sin tocarlos — si alguno cae, el helper no es idéntico al original.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/shared/section_heading.dart app/lib/features/provider/request_detail_screen.dart
git commit -m "refactor(app): el rotulo de seccion sube a shared

Segundo consumidor a la vista (detalle del cliente). Cuerpo identico al
privado del proveedor; sin cambio visual.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Portar el panel plegable

**Files:**
- Modify: `app/lib/features/client/request_status_screen.dart`
- Create: `app/test/client_request_photo_panel_test.dart`

**Interfaces:**
- Consumes: `CollapsingPhotoPanel` de `features/shared/collapsing_photo_panel.dart`, `RequestDetailSheet` (Task 1).
- Produces: nada.

**No hagas esta tarea si la Task 2 tumbó la hipótesis.** Si el controlador te dispachó igualmente, pregunta antes de empezar.

- [ ] **Step 1: Sustituir la estructura**

En el `build` de `_RequestStatusScreenState` (alrededor de la línea 219), el `Column` con `_AmberPanel` y `Expanded` pasa a:

```dart
      body: CustomScrollView(slivers: [
        CollapsingPhotoPanel(
          images: images,
          fallbackIcon: phaseChip(phase, 0).$1,
          leading: _CornerFab(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: _goBack,
          ),
          onOpenViewer: (i) => showPhotoViewer(context, images, initialIndex: i),
        ),
        SliverFillRemaining(
          child: RequestDetailSheet(
            request: req,
            phase: phase,
            offers: offers,
            unreadCount: unreadCount,
            onSeeOffers: () => _showOffers(context, req, offers),
          ),
        ),
      ]),
```

`images` se calcula igual que lo hacía `_AmberPanel`:

```dart
final images =
    ((req['image_urls'] as List?)?.cast<String>() ?? const <String>[])
        .where((u) => u.isNotEmpty)
        .toList();
```

Añadir los imports de `CollapsingPhotoPanel` y lo que haga falta.

- [ ] **Step 2: Borrar `_AmberPanel`**

Eliminar la clase completa (líneas 556-648). El widget compartido cubre sus cuatro responsabilidades: foto a `cover` con visor, ícono de respaldo, miniatura de la 2ª foto y botón atrás como `leading`.

Si al borrarla queda algún helper huérfano (`_amber`, por ejemplo), bórralo también — pero **comprueba con grep que nadie más lo usa** antes.

- [ ] **Step 3: Escribir los tests del panel**

Crear `app/test/client_request_photo_panel_test.dart` siguiendo el patrón de `test/collapsing_photo_panel_test.dart` (helper `host(...)`, `panelHeight(tester)` midiendo `FlexibleSpaceBar`).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/collapsing_photo_panel.dart';

void main() {
  Widget host(Widget panel) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: CustomScrollView(slivers: [
            panel,
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('fila $i')),
            ),
          ]),
        ),
      );

  double alto(WidgetTester t) => t.getSize(find.byType(FlexibleSpaceBar)).height;

  testWidgets('en reposo ocupa el alto expandido', (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.inventory_2_outlined,
    )));
    await tester.pumpAndSettle();
    expect(alto(tester), closeTo(300, 1));
  });

  testWidgets('al bajar se encoge de verdad', (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.inventory_2_outlined,
    )));
    await tester.pumpAndSettle();
    final inicial = alto(tester);

    await tester.drag(find.text('fila 3'), const Offset(0, -250));
    await tester.pumpAndSettle();

    expect(alto(tester), lessThan(inicial - 100));
  });

  testWidgets('el botón atrás sigue tocable con el panel plegado',
      (tester) async {
    var pulsado = false;
    await tester.pumpWidget(host(CollapsingPhotoPanel(
      images: const [],
      fallbackIcon: Icons.inventory_2_outlined,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new),
        onPressed: () => pulsado = true,
      ),
    )));
    await tester.pumpAndSettle();

    await tester.drag(find.text('fila 3'), const Offset(0, -250));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(pulsado, isTrue);
  });

  testWidgets('sin fotos sale el ícono de fase y no hay miniatura',
      (tester) async {
    await tester.pumpWidget(host(const CollapsingPhotoPanel(
      images: [],
      fallbackIcon: Icons.hourglass_top_outlined,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);
    // La miniatura es un cuadro de 76: sin segunda foto no debe existir.
    expect(
      find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 76 && w.height == 76),
      findsNothing,
    );
  });
}
```

> El test de la miniatura tocable con dos fotos queda fuera: `JayaloNetworkImage` pide red y en `flutter_test` toda petición HTTP devuelve 400, así que la imagen nunca se monta. Verificar ese caso a mano en el Step 3 de la Task 6 (punto 8) y **decirlo en el reporte** en vez de simular la red.

- [ ] **Step 4: Verificar el riesgo del sliver**

El spec lo marca como el primer punto que puede salir mal: `SliverFillRemaining` con `hasScrollBody: true` da al hijo el alto del viewport y le deja scrollear por dentro. **Hay que confirmar que el scroll de la lista interna arrastra el plegado del panel externo** y no queda aislado.

El test 2 del Step 3 es justo esa comprobación, pero hazlo también sobre la composición real (panel + `SliverFillRemaining` con la hoja), no solo sobre el panel con una lista de juguete.

Si el panel no se pliega al arrastrar la lista interna, **para y repórtalo**: la solución pasa por `NestedScrollView` o por que la hoja deje de tener su propio scroll, y eso es un cambio de diseño que no está en este plan.

- [ ] **Step 5: Correr todo**

Run: `cd app && flutter analyze && flutter test`
Expected: sin errores nuevos; 649 + los tests nuevos, todos verdes.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/client/request_status_screen.dart app/test/client_request_photo_panel_test.dart
git commit -m "feat(app): la foto del detalle del cliente se pliega al hacer scroll

Portado de T3, que solo habia aterrizado del lado del proveedor. _AmberPanel
muere: CollapsingPhotoPanel ya cubre sus cuatro responsabilidades.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: Reordenar las secciones

**Files:**
- Modify: `app/lib/features/client/request_detail_sheet.dart`
- Modify: `app/test/client_request_detail_sheet_test.dart`

**Interfaces:**
- Consumes: `sectionHeading` (Task 3).
- Produces: nada.

**Orden pactado con el PO (2026-08-02):**

| Bloque | Rótulo | Contenido |
|---|---|---|
| Identidad | *ninguno* | título · chip "Al por mayor" · fila "Desde: RD$X" + `_ProviderDots` |
| 1 | **ESTADO** | "Publicada …" · copy de fase · cupos restantes · paneles de calificar |
| 2 | **INFORMACIÓN** | `'Detalles'` (chips de bullets) · presupuesto estimado |
| Acción | *ninguno* | CTA "Ver N ofertas", fijo abajo (no se toca) |

- [ ] **Step 1: Mover los bloques**

Dentro del `ListView` de la hoja, reordenar los `children` a: identidad → `sectionHeading(context, 'Estado')` + bloques de estado → `sectionHeading(context, 'Información')` + bloques de información.

Los bloques se mueven **enteros y sin editar su contenido**, incluidos sus `SizedBox` de separación y sus condicionales (`if (bullets.isNotEmpty) …`, `if (requestBudgetLabel(...) != null) …`, `if (offers.isNotEmpty && phase != RequestPhase.completed) …`).

**El `Text('Detalles')` se borra.** Hoy es el único rótulo de la hoja; al entrar INFORMACIÓN encima quedarían dos etiquetas anidadas diciendo casi lo mismo. Los chips de bullets van directamente bajo INFORMACIÓN, sin sub-rótulo.

- [ ] **Step 2: No dejar rótulos huérfanos**

El proveedor aprendió esto en device el 2026-08-01: una solicitud sin bullets ni presupuesto dejaba "INFORMACIÓN" flotando sobre un divisor. Por eso su llamada va envuelta en `if (_hasInfo(req, bullets))`.

Aplica el mismo criterio:

```dart
final hayInfo = bullets.isNotEmpty ||
    requestBudgetLabel(request['budget_min'] as num?,
            request['budget_max'] as num?) !=
        null;
…
if (hayInfo) sectionHeading(context, 'Información'),
```

ESTADO siempre tiene contenido ("Publicada …" y el copy de fase se pintan siempre), así que su rótulo no necesita guardia. **Confírmalo leyendo el código** antes de darlo por bueno; si encuentras un camino en que ESTADO queda vacío, ponle su guardia también y dilo en el reporte.

- [ ] **Step 3: Añadir los tests de orden**

En `app/test/client_request_detail_sheet_test.dart`, añadir:

Los rótulos se buscan en mayúsculas, porque `sectionHeading` hace `toUpperCase()`.

```dart
  Map<String, dynamic> req({bool conInfo = true}) => <String, dynamic>{
        'id': 'req-1',
        'user_id': 'user-1',
        'title': 'Teclado Inalámbrico Klip Xtreme',
        'bullets': conInfo ? <String>['Marca: Klip Xtreme'] : <String>[],
        'created_at': DateTime.now().toIso8601String(),
        'status': 'open',
        'is_wholesale': false,
        'budget_min': conInfo ? 5000 : null,
        'budget_max': conInfo ? 12000 : null,
        'image_urls': <String>[],
      };

  Widget host(Map<String, dynamic> r) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: RequestDetailSheet(
            request: r,
            phase: RequestPhase.responded,
            offers: const [],
            unreadCount: 0,
            onSeeOffers: () {},
          ),
        ),
      );

  testWidgets('el orden es identidad → ESTADO → INFORMACIÓN', (tester) async {
    await tester.pumpWidget(host(req()));
    await tester.pumpAndSettle();

    final titulo = tester.getRect(find.text('Teclado Inalámbrico Klip Xtreme')).top;
    final estado = tester.getRect(find.text('ESTADO')).top;
    final info = tester.getRect(find.text('INFORMACIÓN')).top;

    expect(titulo, lessThan(estado));
    expect(estado, lessThan(info));
  });

  testWidgets('sin bullets ni presupuesto no queda INFORMACIÓN huérfano',
      (tester) async {
    await tester.pumpWidget(host(req(conInfo: false)));
    await tester.pumpAndSettle();

    expect(find.text('ESTADO'), findsOneWidget);
    expect(find.text('INFORMACIÓN'), findsNothing);
  });

  testWidgets('el CTA sigue visible tras scrollear la lista', (tester) async {
    await tester.pumpWidget(host(req()));
    await tester.pumpAndSettle();

    final cta = find.textContaining('Ver');
    expect(cta, findsWidgets);
    final antes = tester.getRect(cta.first);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // El CTA vive FUERA del ListView, en el Column de la hoja: no se mueve.
    expect(tester.getRect(cta.first).top, closeTo(antes.top, 1));
  });
```

> Si `find.textContaining('Ver')` resulta ambiguo con el contenido real, acótalo con `find.descendant(of: find.byType(FilledButton), matching: …)` y dilo en tu reporte.

- [ ] **Step 4: Correr todo**

Run: `cd app && flutter analyze && flutter test`
Expected: sin errores nuevos; todo verde.

El test de la hipótesis de la Task 2 **va a cambiar de resultado** al desaparecer el panel fijo. Actualízalo para que refleje el comportamiento nuevo (el título ya no puede quedar tapado porque el panel se pliega) y **explica el cambio en el reporte** — no lo borres sin más.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/client/request_detail_sheet.dart app/test/client_request_detail_sheet_test.dart
git commit -m "feat(app): el detalle del cliente se ordena en estado / informacion

Portado de T4, adaptado: aqui no hay 'datos del cliente' porque el cliente
mira su propia solicitud. El precio 'Desde' se queda pegado al titulo como
titular (decision PO 2026-08-02).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Verificación en device y cierre

**Files:**
- Ninguno. Es verificación.

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: evidencia de que funciona en un teléfono real.

- [ ] **Step 1: Suite completa**

Run: `cd app && flutter analyze && flutter test`
Expected: sin errores; 649 + los nuevos, todos verdes.

- [ ] **Step 2: Construir e instalar**

```bash
cd app && flutter build apk --release
```

Instalar con el `adb` del SDK (no está en el PATH):

```bash
"$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe" install -r app/build/app/outputs/flutter-apk/app-release.apk
```

> El `versionCode` sigue en 8. Se sobrescribe la instalación anterior; los datos se conservan porque la firma es la misma.

- [ ] **Step 3: Checklist manual — FUERA DE ALCANCE del subagente**

Requiere sesión iniciada. Es del PO:

1. Abrir una solicitud propia **con foto**. Al bajar, la foto se pliega hasta una barra fina y el contenido gana pantalla.
2. El título ya **no** se corta contra el borde de la foto.
3. Con el panel plegado, el botón atrás sigue tocable.
4. Aparecen los rótulos **ESTADO** e **INFORMACIÓN**, en ese orden, y el precio "Desde" sigue pegado al título.
5. El botón "Ver N ofertas" se queda fijo abajo mientras se scrollea.
6. Una solicitud **sin** bullets ni presupuesto no muestra el rótulo INFORMACIÓN huérfano.
7. Una solicitud **sin foto**: sale el ícono de fase sobre lila y el panel se comporta igual.
8. Con dos fotos, la miniatura de la derecha abre el visor en la segunda.

---

## Recomendaciones (fuera del alcance de este plan)

1. **`request_status_screen.dart` sigue grande** tras sacar la hoja (~870 líneas). `_OffersSheet` y `_OfferCard` son los siguientes candidatos naturales a fichero propio, y por el mismo motivo: hoy tampoco se pueden testear.
2. **El detalle del cliente no muestra los requisitos** (comprobante fiscal, suplidor del Estado, envío) que la web ya pinta como chips desde el 2026-08-02. Es la misma brecha de paridad que motivó este plan, un nivel más arriba.
3. **`_ProviderDots` vive en la fila del precio.** Al quedar en el bloque de identidad, convive con el titular. Si el PO ve ruido ahí, moverlo a ESTADO es un cambio de una línea.
