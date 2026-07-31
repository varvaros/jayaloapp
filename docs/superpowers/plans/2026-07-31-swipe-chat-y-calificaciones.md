# Swipe explicado, acciones en la lista de chats y calificaciones que cuentan — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el swipe de solicitudes ceda y explique por qué no aplica, que la lista de chats
tenga acciones por swipe (no concretado / archivar), que las calificaciones muevan de verdad la
reputación del proveedor, y que el botón de mensajes preguardados deje de parecer de IA.

**Architecture:** Cuatro tandas independientes. La A extiende el widget compartido
`SwipeToActions` con un modo "bloqueado" y una pista de descubrimiento; la B reusa ese mismo
widget en la lista de chats y añade columnas de archivado en Postgres; la C arregla que la
calificación del chat escriba en la tabla que sí alimenta la reputación y añade dos superficies
más; la D es un cambio de ícono en app y web. Única dependencia: B necesita el widget de A.

**Tech Stack:** Flutter (Dart 3, `flutter_test`), Supabase/Postgres (migraciones SQL,
RLS + grants por columna), React 19 + TanStack Start + lucide-react en la web.

**Spec:** `docs/superpowers/specs/2026-07-31-swipe-chat-y-calificaciones-design.md`

## Global Constraints

- **Repo de la app:** `C:\Users\ac\Downloads\jayalo-app`, rama `feat/error-tracking`. El
  proyecto Flutter vive en `app/`; todos los comandos `flutter` se corren desde `app/`.
- **Repo web:** `C:\Users\ac\Downloads\jayalo-main\jayalo-main`, rama `master`.
- **Gates obligatorios antes de cada commit:** `flutter analyze` en **0** issues y
  `flutter test` en verde (baseline actual: **550** tests). En la web, `npx tsc --noEmit` en
  **0** y `npm test` en verde (baseline: **423**).
- **Las migraciones se aplican a producción vía MCP de Supabase** (`project_id`
  `mfaiklvobnvgusbcssbx`), **verificadas antes en `BEGIN`/`ROLLBACK`**. El fichero SQL se
  commitea en `supabase/migrations/` de **los dos repos** (ambos la tienen).
- **Gotcha de RPC:** cambiar el *return type* de una función exige `DROP FUNCTION` antes del
  `CREATE` (error 42P13), y **el `DROP` borra los grants** → el
  `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated` al final es
  obligatorio.
- **Gotcha de Supabase Cloud:** al crear una función se auto-otorga `EXECUTE` a
  `anon`/`authenticated`. Toda función *trigger-only* lleva `REVOKE EXECUTE ... FROM PUBLIC,
  anon, authenticated`.
- **Tipos de la web:** tras aplicar una migración, `src/integrations/supabase/types.ts` se
  **regenera desde la BD real** con el MCP `generate_typescript_types`. Nunca se parchea a mano
  ni se añaden overrides en `database.ts`.
- **Escalas de calificación (no convertir):** `business_reviews.rating` y
  `conversation_ratings.overall` son **1-10** (migración `20260619014535`).
  `customer_reviews.rating` es **1-5**.
- **Toast en la app:** `showJayaloToast(context, '…')`. Nunca `alert` ni `print`.
- **Commits:** estilo `feat:`/`fix:`/`docs:`, mensaje en español, terminados en
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Copy en español** con tuteo, exactamente como aparece en cada tarea (son textos de producto
  ya aprobados por el PO — no reescribirlos).

---

## Estructura de ficheros

**Tanda A — swipe**
- Modificar: `app/lib/features/shared/swipe_to_actions.dart` — el widget compartido gana modo
  bloqueado y pista de descubrimiento. Sigue siendo el único responsable del gesto.
- Modificar: `app/lib/features/client/my_requests_screen.dart:584-648` — decide el motivo por
  fase y pide la pista en la primera tarjeta no bloqueada.
- Modificar: `app/test/swipe_to_actions_test.dart` — contrato del widget.

**Tanda B — chats**
- Crear: `supabase/migrations/20260801100000_conversation_archive.sql` (en los dos repos).
- Modificar: `app/lib/data/repos.dart` — `setConversationArchived`.
- Modificar: `app/lib/features/chat/conversations_screen.dart` — swipe, cuarta píldora,
  filtrado.
- Crear: `app/lib/features/chat/widgets/conversation_actions.dart` — el diálogo de confirmación
  de "No concretado", compartido entre la lista y el ⋮ del chat. Vive aparte porque lo usan dos
  pantallas y ninguna de las dos debe ser dueña del copy.
- Modificar: `app/lib/features/chat/chat_screen.dart:1084-1093` — el ⋮ abre "perdido" a ambos
  roles y usa el diálogo compartido.
- Crear: `app/test/conversation_archive_test.dart`.
- Modificar: `app/test/conversations_screen_test.dart`.

**Tanda C — calificaciones**
- Modificar: `app/lib/data/repos.dart` — `interestBusinessId`, `myBusinessReview`,
  `customerReviewsFor`, y `customer_id` en el select de `_fetchMyOffers`.
- Modificar: `app/lib/features/chat/widgets/rating_form.dart` — `RatingPanel` acepta
  `businessId` y escribe también `business_reviews`; nace `BusinessReviewPanel`.
- Modificar: `app/lib/features/chat/chat_screen.dart` — `_loadReviewContext` resuelve el negocio
  para los dos lados.
- Modificar: `app/lib/features/client/request_status_screen.dart` — panel en fase completada.
- Modificar: `app/lib/features/provider/my_offers_screen.dart` — "Calificar al cliente".
- Crear: `app/test/business_review_panel_test.dart`, `app/test/needs_customer_review_test.dart`.

**Tanda D — ícono**
- Modificar: `app/lib/features/chat/widgets/composer.dart:188`.
- Modificar: `jayalo-main/src/routes/messages.$conversationId.tsx:16,1394`.

---

## Task 1: `SwipeToActions` — modo bloqueado

**Files:**
- Modify: `app/lib/features/shared/swipe_to_actions.dart`
- Test: `app/test/swipe_to_actions_test.dart`

**Interfaces:**
- Consumes: nada (primera tarea).
- Produces: `SwipeToActions({..., String? blockedReason})`. Cuando `blockedReason != null`, el
  widget revela una franja gris de **140 px** con `Icons.lock_outline` + ese texto, aplica goma
  desde el primer píxel, **nunca hace snap abierto** y **nunca escribe en `group`**. Las tareas
  3 y 6 lo consumen.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `app/test/swipe_to_actions_test.dart`, dentro de `main()`:

```dart
  Widget blockedHost(String reason) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SwipeToActions(
                id: 'b',
                group: ValueNotifier<Object?>(null),
                actions: const [],
                blockedReason: reason,
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Text('card'),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('bloqueado: arrastrar revela el motivo', (tester) async {
    await tester.pumpWidget(blockedHost('Ya aceptaste una oferta'));
    expect(find.text('Ya aceptaste una oferta'), findsNothing);
    // El movimiento va en DOS tramos con un pump entre medias: el host envuelve
    // el widget en un ListView, así que el reconocedor horizontal compite en la
    // arena con el scroll vertical y el evento que RESUELVE la arena no se
    // entrega como update. Es lo mismo que hace `tester.drag` por dentro con su
    // `touchSlopX`. Con un solo `moveBy`, `_dx` se queda en 0.
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('card')));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(find.text('Ya aceptaste una oferta'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('bloqueado: al soltar SIEMPRE vuelve a cero', (tester) async {
    await tester.pumpWidget(blockedHost('Solicitud completada'));
    await tester.drag(find.text('card'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud completada'), findsNothing,
        reason: 'la franja bloqueada no puede quedarse abierta');
  });

  testWidgets('bloqueado: no reclama el slot del group', (tester) async {
    final group = ValueNotifier<Object?>(null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          SwipeToActions(
            id: 'b',
            group: group,
            actions: const [],
            blockedReason: 'Solicitud completada',
            child: const SizedBox(
                height: 80, width: double.infinity, child: Text('card')),
          ),
        ]),
      ),
    ));
    await tester.drag(find.text('card'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(group.value, isNull,
        reason: 'un row que nunca se queda abierto no debe cerrar a los demás');
  });
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run (desde `app/`): `flutter test test/swipe_to_actions_test.dart`
Expected: FAIL — `No named parameter with the name 'blockedReason'`.

- [ ] **Step 3: Implementar el modo bloqueado**

En `app/lib/features/shared/swipe_to_actions.dart`:

3a. Añadir el parámetro al constructor y el campo (tras `this.margin = ...`):

```dart
    this.blockedReason,
  }) : assert(actions.length > 0 || blockedReason != null,
            'un row sin acciones necesita un blockedReason que explicar');
```

y con los demás campos finales:

```dart
  /// Si no es null, el row NO ejecuta acciones: revela UNA franja gris con
  /// candado + este texto y SIEMPRE vuelve a cero al soltar. Es la respuesta
  /// al dedo cuando la fila existe pero sus acciones no aplican — antes la
  /// tarjeta quedaba inerte y el gesto no producía nada.
  final String? blockedReason;
```

3b. En `_SwipeToActionsState`, reemplazar el getter `_revealW` por:

```dart
  bool get _blocked => widget.blockedReason != null;

  /// Bloqueado: una sola franja con texto de una línea, no N íconos de 88.
  double get _revealW =>
      _blocked ? 140 : widget.actions.length * widget.actionWidth;
```

3c. Reemplazar `_resist` por:

```dart
  double _resist(double raw) {
    if (raw <= 0) return -_rubber(-raw, _maxOver * 0.6);
    // Bloqueado: goma desde el PRIMER píxel. Cede y muestra el motivo, pero
    // nunca se siente como un cajón a punto de quedarse abierto.
    if (_blocked) return _rubber(raw, _revealW);
    if (raw <= _revealW) return raw; // dentro del rango: 1:1
    return _revealW + _rubber(raw - _revealW, _maxOver);
  }
```

3d. En `onHorizontalDragEnd`, insertar como primera instrucción tras leer `v`:

```dart
          // Bloqueado: no hay snap abierto ni reclamo del group — la franja es
          // una revelación momentánea.
          if (_blocked) {
            _springTo(0, v);
            return;
          }
```

3e. En `build`, el guard de pintado de la franja pasa de `if (_dx > 0)` a **`if (_dx > 0.5)`**.

> **Por qué:** `_dx` viene de una `SpringSimulation`, que termina dentro de una tolerancia
> (~1e-3), así que puede asentar en +0.0009 y `> 0` se queda en true para siempre — la franja
> nunca se recoge. Depende de la fase con la que el resorte llegue al final, por eso el camino
> no-bloqueado venía pasando por suerte. Medio píxel es invisible y quita la dependencia de la
> tolerancia. El `if (_dx > 2)` de la capa que captura el tap NO se toca.

3e-bis. Sustituir el hijo del `ClipRRect` por una bifurcación:

```dart
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.radius),
                  child: _blocked ? _blockedStrip(context) : _actionsRow(),
                ),
```

3f. Extraer el `Row` de acciones actual (el que ya existe, sin cambios) a un método
`Widget _actionsRow()` y añadir el nuevo:

```dart
  /// Franja de "esto no aplica aquí": gris de superficie, candado y el motivo.
  Widget _blockedStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _revealW,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(
                  widget.blockedReason!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `flutter test test/swipe_to_actions_test.dart`
Expected: PASS — los 4 tests viejos y los 3 nuevos.

- [ ] **Step 5: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/features/shared/swipe_to_actions.dart app/test/swipe_to_actions_test.dart
git commit -m "feat(app): el swipe cede y explica cuando la accion no aplica

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: `SwipeToActions` — pista de descubrimiento (auto-peek)

**Files:**
- Modify: `app/lib/features/shared/swipe_to_actions.dart`
- Test: `app/test/swipe_to_actions_test.dart`

**Interfaces:**
- Consumes: `SwipeToActions` de la Task 1.
- Produces: `SwipeToActions({..., String? peekKey})`. Si `peekKey` no es null y
  `onboardingStore.isDone(peekKey)` es false, la tarjeta se asoma 28 px y vuelve, una sola vez,
  y marca la clave. La Task 3 lo consume con `'requests.swipe.v1'`.

> **Por qué `peekKey` y no `peekOnce`:** el widget es compartido (solicitudes y, tras la Task 6,
> chats). Hornear la clave `requests.swipe.v1` dentro del widget lo ataría a una pantalla.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir a `app/test/swipe_to_actions_test.dart`. Nota los imports nuevos al inicio del fichero:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
```

y dentro de `main()`:

```dart
  group('auto-peek', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onboardingStore.reset(); // el store es un singleton: aislar cada test
    });

    Widget peekHost() => MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SwipeToActions(
                  id: 'p',
                  group: ValueNotifier<Object?>(null),
                  peekKey: 'requests.swipe.v1',
                  actions: [
                    SwipeAction(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      color: Colors.red,
                      onTap: () async {},
                    ),
                  ],
                  child: const SizedBox(
                      height: 80, width: double.infinity, child: Text('card')),
                ),
              ],
            ),
          ),
        );

    testWidgets('la primera vez se asoma y marca la clave', (tester) async {
      await tester.pumpWidget(peekHost());
      await tester.pump(); // post-frame que dispara _maybePeek
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsOneWidget,
          reason: 'al asomarse, la franja debe verse');
      await tester.pumpAndSettle();
      expect(find.text('Eliminar'), findsNothing,
          reason: 'la pista se recoge sola');
      expect(onboardingStore.isDone('requests.swipe.v1'), isTrue);
    });

    testWidgets('con la clave ya marcada NO se asoma', (tester) async {
      await onboardingStore.markDone('requests.swipe.v1');
      await tester.pumpWidget(peekHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsNothing);
    });

    testWidgets('sin peekKey no se asoma nunca', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            SwipeToActions(
              id: 'q',
              group: ValueNotifier<Object?>(null),
              actions: [
                SwipeAction(
                  icon: Icons.delete_outline,
                  label: 'Eliminar',
                  color: Colors.red,
                  onTap: () async {},
                ),
              ],
              child: const SizedBox(
                  height: 80, width: double.infinity, child: Text('card')),
            ),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Eliminar'), findsNothing);
    });
  });
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `flutter test test/swipe_to_actions_test.dart`
Expected: FAIL — `No named parameter with the name 'peekKey'`.

- [ ] **Step 3: Implementar el auto-peek**

3a. Import nuevo al inicio de `swipe_to_actions.dart`:

```dart
import 'onboarding_store.dart';
```

3b. Parámetro y campo (junto a `blockedReason`):

```dart
    this.peekKey,
```

```dart
  /// Clave de onboarding con la que enseñar el gesto UNA sola vez: la tarjeta
  /// se asoma y vuelve (patrón iOS Mail). Null = sin pista. Se pasa solo en la
  /// PRIMERA fila no bloqueada de una lista.
  final String? peekKey;
```

3c. En `initState`, tras `widget.group.addListener(_onGroupChanged);`:

```dart
    // Post-frame: `_maybePeek` lee el MediaQuery, que no está disponible en
    // initState, y la pista solo tiene sentido con la lista ya pintada.
    if (widget.peekKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePeek(widget.peekKey!);
      });
    }
```

3d. Método nuevo:

```dart
  /// Enseña el gesto una sola vez por usuario: la tarjeta se asoma 28 px y
  /// vuelve. Best-effort de principio a fin — una pista que falla nunca puede
  /// tumbar una lista.
  Future<void> _maybePeek(String key) async {
    try {
      await onboardingStore.ensureLoaded();
    } catch (_) {
      // Sin backend de guías la pista se muestra igual: es inocua.
    }
    if (!mounted || onboardingStore.isDone(key)) return;
    // Reduce motion: se marca como enseñada IGUAL, para no dejar una pista
    // pendiente para siempre en un dispositivo que no anima.
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // Si el usuario ya arrastró por su cuenta, no interrumpirlo.
      if (!mounted || _dx != 0) return;
      _springTo(28, 0);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      _springTo(0, 0);
    }
    await onboardingStore.markDone(key);
  }
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `flutter test test/swipe_to_actions_test.dart`
Expected: PASS — 10 tests.

- [ ] **Step 5: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/features/shared/swipe_to_actions.dart app/test/swipe_to_actions_test.dart
git commit -m "feat(app): la lista ensena el gesto de swipe una sola vez

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Cablear el swipe explicado en la lista de solicitudes

**Files:**
- Modify: `app/lib/features/client/my_requests_screen.dart:584-648`
- Test: `app/test/my_requests_swipe_test.dart` (crear)

**Interfaces:**
- Consumes: `SwipeToActions({blockedReason, peekKey})` de las Tasks 1 y 2.
- Produces: `String? blockedReasonForPhase(RequestPhase)` — función pura pública, testeable sin
  montar la pantalla.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/my_requests_swipe_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

/// El swipe (Eliminar/Editar) solo aplica mientras la solicitud está viva. En
/// el resto de fases la tarjeta ya NO se queda inerte: cede y dice por qué.
void main() {
  test('las fases vivas no llevan motivo (swipe normal)', () {
    expect(blockedReasonForPhase(RequestPhase.waiting), isNull);
    expect(blockedReasonForPhase(RequestPhase.withOffers), isNull);
  });

  test('las fases cerradas explican el motivo', () {
    expect(blockedReasonForPhase(RequestPhase.accepted),
        'Ya aceptaste una oferta: no puede editarse');
    expect(blockedReasonForPhase(RequestPhase.unlocked),
        'Ya están en contacto: no puede editarse');
    expect(
        blockedReasonForPhase(RequestPhase.completed), 'Solicitud completada');
  });

  test('toda fase de RequestPhase está cubierta', () {
    for (final p in RequestPhase.values) {
      blockedReasonForPhase(p); // no debe lanzar por un case olvidado
    }
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/my_requests_swipe_test.dart`
Expected: FAIL — `Undefined name 'blockedReasonForPhase'`.

- [ ] **Step 3: Implementar**

3a. En `my_requests_screen.dart`, junto a `phaseChip` (tras la línea 46), añadir:

```dart
/// Motivo por el que una solicitud NO se puede editar/eliminar, o null si sí.
/// El swipe pasa esto a [SwipeToActions] para que el gesto ceda y explique en
/// vez de quedar inerte (antes la tarjeta ni siquiera llevaba detector).
String? blockedReasonForPhase(RequestPhase p) => switch (p) {
  RequestPhase.waiting || RequestPhase.withOffers => null,
  RequestPhase.accepted => 'Ya aceptaste una oferta: no puede editarse',
  RequestPhase.unlocked => 'Ya están en contacto: no puede editarse',
  RequestPhase.completed => 'Solicitud completada',
};
```

3b. Reemplazar el bloque de las líneas 584-648 (desde el comentario
`// El swipe (eliminar/editar) solo tiene sentido` hasta el `).cascadeIn(i);` final) por:

```dart
                                    // El swipe (eliminar/editar) solo aplica
                                    // mientras la solicitud está viva. En el
                                    // resto de fases la tarjeta YA NO queda
                                    // inerte: cede con goma y dice por qué (la
                                    // RPC de borrar solo permite `open`, y
                                    // editar una aceptada no aplica).
                                    final blocked =
                                        blockedReasonForPhase(phase);
                                    // La pista se enseña en la PRIMERA tarjeta
                                    // que de verdad se puede deslizar: hacerlo
                                    // en una bloqueada enseñaría el gesto
                                    // donde no funciona.
                                    final firstOpen = items.indexWhere(
                                        (r) =>
                                            blockedReasonForPhase(r.$2) == null);
                                    final card = _RequestCard(
                                      title: r['title'] as String,
                                      createdAt: DateTime.parse(
                                        r['created_at'] as String,
                                      ),
                                      phase: phase,
                                      offerCount: offerCount,
                                      imageUrl: _firstImage(r),
                                      kind: r['kind'] as String?,
                                      wholesale: r['is_wholesale'] == true,
                                      unseen: unseen,
                                      onTap: open,
                                      // Sin margen propio: lo aplica el swipe.
                                      margin: EdgeInsets.zero,
                                    );
                                    return SwipeToActions(
                                      id: id,
                                      group: _openRow,
                                      blockedReason: blocked,
                                      peekKey: (blocked == null && i == firstOpen)
                                          ? 'requests.swipe.v1'
                                          : null,
                                      actions: blocked != null
                                          ? const []
                                          : [
                                              SwipeAction(
                                                icon: Icons.delete_outline,
                                                label: 'Eliminar',
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                                onTap: () => _deleteRequest(
                                                    id, offerCount),
                                              ),
                                              SwipeAction(
                                                icon: Icons.edit_outlined,
                                                label: 'Editar',
                                                color: const Color(0xFF378ADD),
                                                // Editar llega en una sesión
                                                // próxima (decisión PO).
                                                onTap: () async =>
                                                    showJayaloToast(
                                                  context,
                                                  'Editar solicitud: próximamente.',
                                                ),
                                              ),
                                            ],
                                      child: card,
                                    ).cascadeIn(i);
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `flutter test test/my_requests_swipe_test.dart test/my_requests_onboarding_test.dart test/request_rows_order_test.dart`
Expected: PASS. Los tests existentes de la pantalla no deben romperse.

- [ ] **Step 5: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/features/client/my_requests_screen.dart app/test/my_requests_swipe_test.dart
git commit -m "feat(app): las solicitudes cerradas explican por que no se editan

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Migración de archivado de conversaciones

**Files:**
- Create: `supabase/migrations/20260801100000_conversation_archive.sql` (en **los dos** repos,
  fichero idéntico)

**Interfaces:**
- Consumes: nada.
- Produces: columnas `conversations.archived_by_customer` / `archived_by_provider` (bool, NOT
  NULL, default false), con `UPDATE` por columna para `authenticated` y un trigger que impide
  tocar la columna ajena; y `get_my_conversations_list()` devolviendo una columna nueva
  **`archived boolean`** al final. Las Tasks 5 y 6 lo consumen.

- [ ] **Step 1: Escribir la migración**

Crear el fichero con este contenido:

```sql
-- Archivar una conversación: ocultarla de la bandeja SIN borrarla.
--
-- Por qué columnas y no un store local: archivar que no sobrevive a un
-- reinstall o a otro dispositivo se lee como un bug. Y por qué DOS columnas:
-- la fila es compartida por los dos participantes, y archivar es una decisión
-- privada de cada uno.
--
-- NO existe borrado de conversaciones, a propósito: la conversación es el
-- registro de un lead que el proveedor pagó con créditos.

-- 1) Columnas.
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS archived_by_customer boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_by_provider boolean NOT NULL DEFAULT false;

-- 2) Grant por columna, SUMÁNDOSE al existente (status, agreed_price,
--    agreed_hourly_rate, agreed_estimated_hours, updated_at — migración
--    20260615032752). Un GRANT por columna es aditivo: no pisa al anterior.
GRANT UPDATE (archived_by_customer, archived_by_provider)
  ON public.conversations TO authenticated;

-- 3) Guard: cada participante solo puede tocar SU columna. La política RLS
--    `Participants can update status` es simétrica (cualquiera de los dos
--    pasa el USING/WITH CHECK), así que sin este trigger el cliente podría
--    archivar del lado del proveedor. Mismo patrón que
--    enforce_agreed_price_provider_only (20260729210000): SECURITY INVOKER,
--    BEFORE UPDATE, y exención para admin/service_role.
CREATE OR REPLACE FUNCTION public.enforce_archive_own_side()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- service_role no tiene auth.uid(): se deja pasar (backfills, soporte).
  IF (select auth.uid()) IS NULL
     OR (select public.has_role((select auth.uid()), 'admin'::app_role)) THEN
    RETURN NEW;
  END IF;

  IF NEW.archived_by_provider IS DISTINCT FROM OLD.archived_by_provider
     AND (select auth.uid()) <> OLD.provider_user_id THEN
    RAISE EXCEPTION 'Only the provider can archive the provider side'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.archived_by_customer IS DISTINCT FROM OLD.archived_by_customer
     AND (select auth.uid()) <> OLD.customer_id THEN
    RAISE EXCEPTION 'Only the customer can archive the customer side'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger-only → sin EXECUTE directo (Supabase Cloud lo auto-otorga al crear).
REVOKE EXECUTE ON FUNCTION public.enforce_archive_own_side()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_archive_own_side ON public.conversations;
CREATE TRIGGER trg_enforce_archive_own_side
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_archive_own_side();

-- 4) La RPC de la lista devuelve `archived` YA RESUELTO para quien llama.
--    Sigue devolviendo TODAS las filas: el filtrado es del cliente, para que
--    la píldora "Archivados N" cuente sin un viaje extra.
--
--    ⚠️ Cambia el return type → DROP obligatorio (42P13), y el DROP BORRA LOS
--    GRANTS: el REVOKE/GRANT del final no es opcional.
DROP FUNCTION IF EXISTS public.get_my_conversations_list();
CREATE FUNCTION public.get_my_conversations_list()
RETURNS TABLE(
  id uuid, kind text, customer_id uuid, provider_user_id uuid,
  product_name text, agreed_price numeric, agreed_hourly_rate numeric,
  product_image_url text, status text, updated_at timestamptz,
  peer_name text, peer_avatar_url text,
  last_kind text, last_body text, last_created_at timestamptz,
  unread_count integer, archived boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    c.id, c.kind::text, c.customer_id, c.provider_user_id,
    c.product_name, c.agreed_price, c.agreed_hourly_rate,
    c.product_image_url, c.status::text, c.updated_at,
    CASE
      WHEN c.customer_id = auth.uid() THEN
        COALESCE(NULLIF(b.name,''), NULLIF(p.business_name,''),
                 NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)),''), 'Proveedor')
      ELSE
        COALESCE(NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)),''),
                 NULLIF(p.business_name,''), 'Cliente')
    END AS peer_name,
    CASE
      WHEN c.customer_id = auth.uid() THEN NULLIF(b.logo_url,'')
      ELSE COALESCE(NULLIF(p.avatar_url,''), NULLIF(cp.photo_url,''))
    END AS peer_avatar_url,
    lm.kind::text, lm.body, lm.created_at,
    COALESCE(un.cnt, 0) AS unread_count,
    CASE WHEN c.customer_id = auth.uid()
         THEN c.archived_by_customer ELSE c.archived_by_provider END AS archived
  FROM public.conversations c
  JOIN public.profiles p ON p.user_id =
    CASE WHEN c.customer_id = auth.uid() THEN c.provider_user_id ELSE c.customer_id END
  LEFT JOIN LATERAL (
    SELECT pb.name, pb.logo_url FROM public.provider_businesses pb
    WHERE pb.user_id = c.provider_user_id
    ORDER BY pb.created_at ASC LIMIT 1
  ) b ON c.customer_id = auth.uid()
  LEFT JOIN LATERAL (
    SELECT cp1.photo_url FROM public.candidate_profiles cp1
    WHERE cp1.user_id = c.customer_id LIMIT 1
  ) cp ON c.provider_user_id = auth.uid()
  LEFT JOIN LATERAL (
    SELECT m.kind, m.body, m.created_at
    FROM public.conversation_messages m
    WHERE m.conversation_id = c.id
    ORDER BY m.created_at DESC, m.id DESC LIMIT 1
  ) lm ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::int AS cnt FROM public.notifications n
    WHERE n.user_id = auth.uid() AND n.kind = 'message_new' AND n.read_at IS NULL
      AND (n.link = '/messages?c=' || c.id::text OR n.link = '/messages/' || c.id::text)
  ) un ON true
  WHERE c.customer_id = auth.uid() OR c.provider_user_id = auth.uid()
  ORDER BY c.last_message_at DESC, c.updated_at DESC, c.id DESC;
$$;

-- OBLIGATORIO tras el DROP: los grants se fueron con la función vieja.
REVOKE ALL ON FUNCTION public.get_my_conversations_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_conversations_list() TO authenticated;
```

- [ ] **Step 2: Verificar en `BEGIN`/`ROLLBACK` contra producción**

Con el MCP de Supabase (`execute_sql`, `project_id` `mfaiklvobnvgusbcssbx`), correr el fichero
completo envuelto en `BEGIN; … ` y **antes** del `ROLLBACK;` estas comprobaciones:

```sql
-- (a) La RPC devuelve la columna nueva.
SELECT archived FROM public.get_my_conversations_list() LIMIT 1;

-- (b) Los grants sobrevivieron al DROP (debe devolver 1 fila).
SELECT 1 FROM information_schema.role_routine_grants
 WHERE routine_name = 'get_my_conversations_list'
   AND grantee = 'authenticated' AND privilege_type = 'EXECUTE';

-- (c) El grant por columna del status SIGUE vivo (no lo pisamos).
SELECT column_name FROM information_schema.column_privileges
 WHERE table_name = 'conversations' AND grantee = 'authenticated'
   AND privilege_type = 'UPDATE' ORDER BY column_name;
-- Esperado: agreed_estimated_hours, agreed_hourly_rate, agreed_price,
--           archived_by_customer, archived_by_provider, status, updated_at
```

Expected: (a) corre sin error, (b) 1 fila, (c) las 7 columnas.
Terminar con `ROLLBACK;`.

- [ ] **Step 3: Aplicar a producción**

Con el MCP `apply_migration`, nombre `conversation_archive`, el mismo SQL.
Después, **re-correr las tres comprobaciones (a)(b)(c)** ya en vivo.

- [ ] **Step 4: Probar el guard del trigger con datos reales**

```sql
-- Tomar una conversación cualquiera y confirmar que el trigger existe y está
-- activo (el ataque real se prueba en la Task 6 desde la app con sesión).
SELECT tgname, tgenabled FROM pg_trigger
 WHERE tgrelid = 'public.conversations'::regclass
   AND tgname = 'trg_enforce_archive_own_side';
```

Expected: 1 fila, `tgenabled = 'O'`.

- [ ] **Step 5: Regenerar los tipos de la web**

Con el MCP `generate_typescript_types(project_id='mfaiklvobnvgusbcssbx')`, volcar el resultado
completo a `jayalo-main/src/integrations/supabase/types.ts`. No editar a mano.

Run (en el repo web): `npx tsc --noEmit`
Expected: 0 errores.

- [ ] **Step 6: Commit en los dos repos**

En `jayalo-app`:
```bash
git add supabase/migrations/20260801100000_conversation_archive.sql
git commit -m "feat(db): archivado de conversaciones por participante

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

En `jayalo-main`:
```bash
git add supabase/migrations/20260801100000_conversation_archive.sql src/integrations/supabase/types.ts
git commit -m "feat(db): archivado de conversaciones por participante + types regenerados

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: Repo de la app — archivar

**Files:**
- Modify: `app/lib/data/repos.dart` (junto a `markConversationLost`, línea ~1543)
- Test: `app/test/conversation_archive_test.dart` (crear)

**Interfaces:**
- Consumes: las columnas de la Task 4.
- Produces:
  - `Future<void> setConversationArchived(String convId, bool archived, {required bool asProvider})`
  - `bool conversationArchived(Map<String, dynamic> c)` — lector puro de la fila de la RPC,
    tolerante a que `archived` no venga (tests y cachés viejos).

  La Task 6 los consume.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/conversation_archive_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// Lectura del flag `archived` que la RPC `get_my_conversations_list` resuelve
/// para quien llama. Tolerante a su ausencia: una caché escrita antes de la
/// migración no puede hacer desaparecer conversaciones de la bandeja.
void main() {
  test('archived true/false se lee tal cual', () {
    expect(conversationArchived({'id': 'c1', 'archived': true}), isTrue);
    expect(conversationArchived({'id': 'c1', 'archived': false}), isFalse);
  });

  test('sin la clave, la conversación NO se considera archivada', () {
    expect(conversationArchived({'id': 'c1'}), isFalse);
    expect(conversationArchived({'id': 'c1', 'archived': null}), isFalse);
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/conversation_archive_test.dart`
Expected: FAIL — `Undefined name 'conversationArchived'`.

- [ ] **Step 3: Implementar**

En `app/lib/data/repos.dart`, justo después de `markConversationLost` (línea ~1544):

```dart
/// Archiva/desarchiva la conversación por MI lado. La otra columna es del otro
/// participante y el trigger `trg_enforce_archive_own_side` lo impone en la BD.
/// Archivar OCULTA de la bandeja; nunca borra (la conversación es el registro
/// de un lead pagado).
Future<void> setConversationArchived(
  String convId,
  bool archived, {
  required bool asProvider,
}) async {
  await supa
      .from('conversations')
      .update({
        asProvider ? 'archived_by_provider' : 'archived_by_customer': archived,
      })
      .eq('id', convId);
  AppCaches.conversations.clear();
}

/// `archived` tal como lo resuelve `get_my_conversations_list` para quien
/// llama. Ausente = no archivada: una caché escrita antes de la migración no
/// puede hacer desaparecer conversaciones de la bandeja.
bool conversationArchived(Map<String, dynamic> c) => c['archived'] == true;
```

> `AppCaches.conversations` es un `TtlCache` (`repos.dart:135`) y su método de vaciado es
> `.clear()` — el mismo que usa `invalidateRequestLists()` sobre `myRequests`/`myOffers`. Sin
> vaciarlo, archivar y volver a la pestaña mostraría la lista vieja durante 20 s.

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `flutter test test/conversation_archive_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/data/repos.dart app/test/conversation_archive_test.dart
git commit -m "feat(app): repo de archivado de conversaciones

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Swipe y acciones en la lista de chats

**Files:**
- Create: `app/lib/features/chat/widgets/conversation_actions.dart`
- Modify: `app/lib/features/chat/conversations_screen.dart`
- Test: `app/test/conversations_screen_test.dart`

**Interfaces:**
- Consumes: `SwipeToActions({blockedReason, peekKey})` (Tasks 1-2),
  `setConversationArchived` / `conversationArchived` (Task 5), `markConversationLost`
  (ya existía, `repos.dart:1543`).
- Produces: `Future<bool> confirmMarkLost(BuildContext)` en
  `widgets/conversation_actions.dart` — devuelve true si el usuario confirma. La Task 7 lo
  consume.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir a `app/test/conversations_screen_test.dart`, dentro de `main()`. Nota el helper de
filas — la pantalla ya acepta `loadConversations` inyectable:

```dart
  Map<String, dynamic> conv(String id,
          {String status = 'abierto', bool archived = false}) =>
      {
        'id': id,
        'status': status,
        'archived': archived,
        'customer_id': 'me',
        'provider_user_id': 'peer',
        'peer_name': 'Peer $id',
        'product_name': 'Asunto $id',
        'unread_count': 0,
        'last_kind': 'text',
        'last_body': 'hola',
        'last_created_at': '2026-07-31T10:00:00Z',
        'updated_at': '2026-07-31T10:00:00Z',
      };

  Future<void> mount(
          WidgetTester tester, List<Map<String, dynamic>> rows) async {
    await tester.pumpWidget(MaterialApp(
      home: ConversationsScreen(
        leading: const SizedBox(),
        actions: const [SizedBox()],
        loadConversations: () async => rows,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('la píldora Archivados NO aparece sin conversaciones archivadas',
      (tester) async {
    await mount(tester, [conv('a')]);
    expect(find.textContaining('Archivados'), findsNothing);
  });

  testWidgets('la píldora Archivados aparece con al menos una', (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.textContaining('Archivados'), findsOneWidget);
  });

  testWidgets('las archivadas NO salen en la pestaña Abierto', (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.text('Peer a'), findsOneWidget);
    expect(find.text('Peer b'), findsNothing,
        reason: 'archivar oculta de la bandeja');
  });

  testWidgets('las archivadas no cuentan en la píldora de su estado',
      (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.text('Abierto 1'), findsOneWidget,
        reason: 'el conteo debe excluir las archivadas');
  });

  testWidgets('deslizar una conversación abierta revela No concretado y '
      'Archivar', (tester) async {
    await mount(tester, [conv('a')]);
    await tester.drag(find.text('Peer a'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('No concretado'), findsOneWidget);
    expect(find.text('Archivar'), findsOneWidget);
  });

  testWidgets('en la pestaña Archivados la acción es Desarchivar',
      (tester) async {
    await mount(tester, [conv('b', archived: true)]);
    await tester.tap(find.textContaining('Archivados'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Peer b'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Desarchivar'), findsOneWidget);
    expect(find.text('No concretado'), findsNothing);
  });

  testWidgets('No concretado pide confirmación y cancelar no hace nada',
      (tester) async {
    await mount(tester, [conv('a')]);
    await tester.drag(find.text('Peer a'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No concretado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se puede reabrir'), findsOneWidget,
        reason: 'marcar perdido es irreversible: hay que decirlo');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Peer a'), findsOneWidget);
  });
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `flutter test test/conversations_screen_test.dart`
Expected: FAIL — los tres primeros por `findsNothing`/`findsOneWidget` invertidos, los de swipe
porque no hay `SwipeToActions` en la pantalla.

- [ ] **Step 3: Crear el diálogo compartido**

Crear `app/lib/features/chat/widgets/conversation_actions.dart`:

```dart
import 'package:flutter/material.dart';

/// Confirmación de "marcar como no concretado". Vive aparte porque la usan DOS
/// pantallas (la lista de chats y el ⋮ del chat) y ninguna debe ser dueña del
/// copy: es una acción IRREVERSIBLE y el aviso tiene que decir lo mismo en los
/// dos sitios.
///
/// El copy es el que ya estaba EN PRODUCCIÓN en el ⋮ del chat
/// (`chat_screen.dart:1034-1048`), con una frase más: ahora que los dos
/// participantes pueden marcarlo, hay que decir que el otro también lo verá.
///
/// Devuelve true solo si el usuario confirma.
Future<bool> confirmMarkLost(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Marcar como no concretado?'),
      content: const Text(
        'Esta acción es definitiva, la conversación no se puede reabrir. '
        'La otra persona también la verá como no concretada.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sí, marcar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 4: Cablear la lista de chats**

En `app/lib/features/chat/conversations_screen.dart`:

4a. Imports nuevos:

```dart
import '../shared/swipe_to_actions.dart';
import 'widgets/conversation_actions.dart';
```

4b. En `_ConversationsScreenState`, campo nuevo junto a `_tab`:

```dart
  /// Un solo row de swipe abierto a la vez (mismo patrón que Solicitudes).
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);
```

y en `dispose()`, antes de `super.dispose();`:

```dart
    _openRow.dispose();
```

4c. En `_body`, reemplazar el cálculo de `counts` y `filtered` por una versión que separe los
archivados:

```dart
  Widget _body(List<Map<String, dynamic>> all) {
    // Los archivados salen de las tres pestañas normales y de sus conteos:
    // archivar es "quítamelo de la bandeja".
    final archived = all.where(conversationArchived).toList();
    final live = all.where((c) => !conversationArchived(c)).toList();
    final counts = <String, int>{};
    for (final c in live) {
      counts[c['status'] as String] = (counts[c['status'] as String] ?? 0) + 1;
    }
    // La cuarta píldora solo existe si hay algo que mostrar en ella.
    final tabs = [
      ..._tabs,
      if (archived.isNotEmpty) ('archivados', 'Archivados'),
    ];
    // Si la píldora desaparece (se desarchivó el último), volver a Abierto.
    final tabIndex = tabs.indexWhere((t) => t.$1 == _tab);
    final safeIndex = tabIndex == -1 ? 0 : tabIndex;
    final term = _q.trim().toLowerCase();
    final source = _tab == 'archivados'
        ? archived
        : live.where((c) => c['status'] == _tab);
    final filtered = source
        .where((c) =>
            term.isEmpty ||
            ((c['product_name'] as String?) ?? '').toLowerCase().contains(term) ||
            ((c['peer_name'] as String?) ?? '').toLowerCase().contains(term))
        .toList();
```

4d. En el `PillSegmented`, usar la lista dinámica:

```dart
        child: PillSegmented(
          options: [
            for (final (v, label) in tabs)
              v == 'archivados'
                  ? '$label ${archived.length}'
                  : counts[v] == null
                      ? label
                      : '$label ${counts[v]}',
          ],
          index: safeIndex,
          onChanged: (i) => setState(() => _tab = tabs[i].$1),
        ),
```

4e. El vacío de la pestaña nueva — añadir al `EmptyState` la rama de archivados:

```dart
            ? EmptyState(
                message: _tab == 'archivados'
                    ? 'Sin conversaciones archivadas.'
                    : _tab == 'abierto'
                        ? 'Sin conversaciones abiertas.\nLas conversaciones empiezan cuando contactas a un proveedor.'
                        : _tab == 'cerrado'
                            ? 'Sin conversaciones completadas.'
                            : 'Sin conversaciones no concretadas.',
              )
```

4f. En el `itemBuilder`, envolver la fila en el swipe. Reemplazar el `return _ConversationRow(…)`
por:

```dart
                    final convId = c['id'] as String;
                    final asProvider = c['provider_user_id'] == _uid;
                    final row = _ConversationRow(
                      c: c,
                      onOpen: _open,
                      isNew: !openedConversationsStore.contains(convId),
                      // Estado de embudo SOLO donde soy el proveedor.
                      funnel: c['provider_user_id'] == _uid
                          ? funnelStatusByKey(
                              funnelStatusStore.statusKey(convId))
                          : null,
                      badge: peerId != null ? _badges[peerId] : null,
                    );
                    return SwipeToActions(
                      id: convId,
                      group: _openRow,
                      // La lista de chats es PLANA (filas con divisor, no
                      // tarjetas): sin radio ni margen propio.
                      radius: 0,
                      margin: EdgeInsets.zero,
                      actions: [
                        // "No concretado" solo tiene sentido en un chat vivo.
                        if (_tab == 'abierto')
                          SwipeAction(
                            icon: Icons.cancel_outlined,
                            label: 'No concretado',
                            color: Theme.of(context).colorScheme.error,
                            onTap: () => _markLost(convId),
                          ),
                        SwipeAction(
                          icon: _tab == 'archivados'
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          label: _tab == 'archivados'
                              ? 'Desarchivar'
                              : 'Archivar',
                          color: Theme.of(context).colorScheme.outline,
                          onTap: () => _setArchived(
                            convId,
                            _tab != 'archivados',
                            asProvider,
                          ),
                        ),
                      ],
                      child: row,
                    ).cascadeIn(i);
```

4g. Los dos manejadores, en `_ConversationsScreenState`:

```dart
  /// Marcar no concretado: IRREVERSIBLE, así que siempre pasa por confirmación.
  Future<void> _markLost(String convId) async {
    if (!await confirmMarkLost(context)) return;
    try {
      await markConversationLost(convId);
    } catch (_) {
      if (mounted) showJayaloToast(context, 'No se pudo marcar. Intenta de nuevo.');
      return;
    }
    if (mounted) await _load();
  }

  Future<void> _setArchived(
      String convId, bool archived, bool asProvider) async {
    try {
      await setConversationArchived(convId, archived, asProvider: asProvider);
    } catch (_) {
      if (mounted) showJayaloToast(context, 'No se pudo archivar. Intenta de nuevo.');
      return;
    }
    if (mounted) await _load();
  }
```

> **Notas:**
> - `showJayaloToast` viene de `../../core/brand.dart` (ya importado en la pantalla). Si no lo
>   estuviera, añade el import.
> - **No se toca `_load()`.** Su `messagesBadge.set(...)` (línea ~160) suma sobre `rows`
>   completas, así que el badge de la barra **sigue contando los mensajes sin leer de las
>   conversaciones archivadas** — archivar organiza la bandeja, no silencia avisos. Es decisión
>   del spec: si el PO lo quiere al revés, es cambiar `rows` por `rows.where((c) =>
>   !conversationArchived(c))` en esa línea.

- [ ] **Step 5: Correr los tests para verificar que pasan**

Run: `flutter test test/conversations_screen_test.dart test/conversations_refresh_on_return_test.dart`
Expected: PASS — los tests viejos siguen verdes y los 7 nuevos pasan.

- [ ] **Step 6: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/features/chat/conversations_screen.dart app/lib/features/chat/widgets/conversation_actions.dart app/test/conversations_screen_test.dart
git commit -m "feat(app): swipe en la lista de chats con no concretado y archivar

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: "Marcar como perdido" para ambos roles en el ⋮ del chat

**Files:**
- Modify: `app/lib/features/chat/chat_screen.dart:1084-1093` (itemBuilder del `PopupMenuButton`)
  y el `case 'lost'` de su `onSelected`
- Test: `app/test/chat_menu_roles_test.dart` (crear)

**Interfaces:**
- Consumes: `confirmMarkLost(BuildContext)` de la Task 6.
- Produces: `List<String> chatMenuValues({required bool isProvider, required bool isOpen})` —
  función pura pública en `chat_screen.dart`, para poder probar el contrato del menú sin montar
  el chat (que toca Supabase en su `initState`).

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/chat_menu_roles_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

/// Marcar "no concretado" ya NO es privilegio del proveedor: la RLS
/// (`Participants can update status`) y el grant por columna sobre `status`
/// siempre permitieron a los dos participantes; el gate era solo de UI.
/// "Marcar como completado" sí sigue siendo del proveedor: cierra el trato y
/// dispara la calificación.
void main() {
  test('el cliente puede marcar perdido pero no completado', () {
    final v = chatMenuValues(isProvider: false, isOpen: true);
    expect(v, contains('lost'));
    expect(v, isNot(contains('complete')));
  });

  test('el proveedor puede marcar perdido y completado', () {
    final v = chatMenuValues(isProvider: true, isOpen: true);
    expect(v, contains('lost'));
    expect(v, contains('complete'));
  });

  test('con el chat cerrado no hay cambios de estado', () {
    for (final isProvider in [true, false]) {
      final v = chatMenuValues(isProvider: isProvider, isOpen: false);
      expect(v, isNot(contains('lost')));
      expect(v, isNot(contains('complete')));
    }
  });

  test('denunciar está siempre disponible', () {
    for (final isProvider in [true, false]) {
      for (final isOpen in [true, false]) {
        expect(chatMenuValues(isProvider: isProvider, isOpen: isOpen),
            contains('report'));
      }
    }
  });

  test('el estado de embudo es solo del proveedor', () {
    expect(chatMenuValues(isProvider: true, isOpen: true), contains('funnel'));
    expect(chatMenuValues(isProvider: false, isOpen: true),
        isNot(contains('funnel')));
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/chat_menu_roles_test.dart`
Expected: FAIL — `Undefined name 'chatMenuValues'`.

- [ ] **Step 3: Implementar**

3a. En `chat_screen.dart`, a nivel de fichero (fuera de la clase, junto a los demás helpers de
arriba), añadir:

```dart
/// Qué opciones ofrece el ⋮ del chat. Pura y pública para poder probar el
/// contrato sin montar la pantalla (su initState toca Supabase).
///
/// "No concretado" es de AMBOS participantes: la RLS y el grant por columna
/// sobre `status` siempre lo permitieron y el gate era solo de UI. "Completado"
/// sigue siendo del proveedor — cierra el trato y dispara la calificación.
List<String> chatMenuValues({required bool isProvider, required bool isOpen}) =>
    [
      if (isProvider && isOpen) 'complete',
      if (isOpen) 'lost',
      if (isProvider) 'funnel',
      'report',
    ];
```

3b. Reemplazar el `itemBuilder` (líneas 1084-1093) por uno derivado de esa lista:

```dart
          itemBuilder: (_) => [
            for (final v in chatMenuValues(
                isProvider: _isProvider, isOpen: _isOpen))
              PopupMenuItem(
                value: v,
                child: Text(switch (v) {
                  'complete' => 'Marcar como completado',
                  'lost' => 'Marcar como no concretado',
                  'funnel' => 'Estado del cliente',
                  _ => 'Denunciar cuenta',
                }),
              ),
          ],
```

> El copy pasa de "Marcar como perdido" a **"Marcar como no concretado"**, que es como se llama
> el estado en la lista de chats. Mismo estado (`perdido`), mismo nombre en los dos sitios.

3c. El `case 'lost'` **ya tenía su propio diálogo inline** (líneas 1031-1060). No se le añade
confirmación: se le QUITA la suya y se usa la compartida, para que la lista de chats y el ⋮
digan exactamente lo mismo. Reemplazar las líneas **1031-1060** completas por:

```dart
              case 'lost':
                // El diálogo vive en `widgets/conversation_actions.dart`: la
                // lista de chats ofrece la misma acción y el aviso de que es
                // irreversible tiene que ser idéntico en los dos sitios.
                if (!await confirmMarkLost(context)) return;
                if (!mounted) return;
                try {
                  await markConversationLost(widget.conversationId);
                  if (!mounted) return;
                  _snack('Marcado como no concretado.');
                  await _reload();
                } catch (_) {
                  if (mounted) _snack('No se pudo marcar. Intenta de nuevo.');
                }
```

El recargador es `_reload()` (`chat_screen.dart:274`), y `_snack` ya existe en la clase. El
comportamiento visible no cambia salvo la frase extra del diálogo ("La otra persona también la
verá como no concretada"), que hace falta ahora que los dos roles pueden marcarlo.

3d. Import nuevo:

```dart
import 'widgets/conversation_actions.dart';
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `flutter test test/chat_menu_roles_test.dart test/chat_test.dart test/chat_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/features/chat/chat_screen.dart app/test/chat_menu_roles_test.dart
git commit -m "feat(app): el cliente tambien puede marcar un chat como no concretado

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: La calificación del chat pasa a contar

**Files:**
- Modify: `app/lib/data/repos.dart` (nueva `interestBusinessId`; limpiar el comentario obsoleto
  de `submitReview`, líneas 561-566)
- Modify: `app/lib/features/chat/widgets/rating_form.dart` (`RatingPanel` acepta `businessId`)
- Modify: `app/lib/features/chat/chat_screen.dart` (`_maybeLoadProviderReview` →
  `_loadReviewContext`, y el `RatingPanel` de la línea ~1103 recibe el negocio)
- Test: `app/test/rating_writes_business_review_test.dart` (crear)

**Interfaces:**
- Consumes: `submitReview({businessId, rating, comment})` (ya existe, `repos.dart:556`),
  `offerBusinessId(offerId)` (ya existe, `repos.dart:1612`).
- Produces:
  - `Future<String?> interestBusinessId(String interestId)`
  - `RatingPanel({..., String? businessId})` — si viene, tras guardar en
    `conversation_ratings` escribe también `business_reviews`.
  - `Future<void> Function(String businessId, int rating, String comment)?` inyectable como
    `submitBusinessReview` en `RatingPanel`, para poder testear sin red.

> **Escala:** `_overall` es 1-10 y `business_reviews.rating` es 1-10 desde la migración
> `20260619014535`. **No convertir.**

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/rating_writes_business_review_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/widgets/rating_form.dart';

/// La nota que el cliente da en el chat se guardaba SOLO en
/// `conversation_ratings`, tabla que nadie promedia: la reputación pública del
/// proveedor sale de `business_reviews`. Es decir, calificar desde la app no
/// movía las estrellas. Este test fija que ahora escribe en las dos.
void main() {
  testWidgets('al enviar, escribe también la reseña del negocio', (
    tester,
  ) async {
    final escritas = <(String, int, String)>[];
    var convGuardada = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          businessId: 'biz1',
          onDone: () {},
          submitConversation: (_) async => convGuardada = true,
          submitBusinessReview: (b, r, c) async => escritas.add((b, r, c)),
        ),
      ),
    ));
    await tester.tap(find.text('9')); // nota 9 sobre 10
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    expect(convGuardada, isTrue);
    expect(escritas, hasLength(1));
    expect(escritas.single.$1, 'biz1');
    expect(escritas.single.$2, 9,
        reason: 'business_reviews.rating es 1-10 desde 20260619014535: '
            'la nota va TAL CUAL, sin convertir de escala');
  });

  testWidgets('si la reseña del negocio falla, la calificación igual se '
      'reporta como enviada', (tester) async {
    var terminado = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          businessId: 'biz1',
          onDone: () => terminado = true,
          submitConversation: (_) async {},
          submitBusinessReview: (_, _, _) async => throw Exception('red'),
        ),
      ),
    ));
    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(terminado, isTrue,
        reason: 'la nota ya quedó guardada: no se rompe el flujo del usuario');
  });

  testWidgets('sin businessId no intenta escribir la reseña del negocio', (
    tester,
  ) async {
    var intentos = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingPanel(
          convId: 'c1',
          customerId: 'cli',
          providerUserId: 'prov',
          onDone: () {},
          submitConversation: (_) async {},
          submitBusinessReview: (_, _, _) async => intentos++,
        ),
      ),
    ));
    await tester.tap(find.text('8'));
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(intentos, 0);
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/rating_writes_business_review_test.dart`
Expected: FAIL — `No named parameter with the name 'businessId'`.

- [ ] **Step 3: Implementar el repo**

3a. En `repos.dart`, reemplazar el comentario obsoleto de `submitReview` (líneas 561-566) por:

```dart
  // upsert (no insert): una reseña VIGENTE por (negocio, reseñador). Re-reseñar
  // EDITA la existente en vez de acumular filas que sesgarían el promedio de
  // reputación (`get_business_ratings`), apoyado en el índice UNIQUE
  // `uq_business_reviews_one_per_reviewer` (migración 20260722180100, ya en
  // prod). La escribe la web (detalle de solicitud) y, desde 2026-07-31,
  // también la app: el chat y el detalle de solicitud completada.
```

3b. Junto a `offerBusinessId` (línea ~1612), añadir:

```dart
/// `business_id` de un interés de producto — el otro tipo de conversación
/// (`get_or_create_conversation` solo acepta 'offer' y 'product_interest').
/// `product_interests` lleva `business_id` propio, así que no hace falta pasar
/// por `provider_products`.
Future<String?> interestBusinessId(String interestId) async {
  final row = await supa
      .from('product_interests')
      .select('business_id')
      .eq('id', interestId)
      .maybeSingle();
  return row?['business_id'] as String?;
}
```

- [ ] **Step 4: Implementar `RatingPanel`**

En `rating_form.dart`, `RatingPanel` gana tres parámetros y su `_submit` la segunda escritura:

```dart
class RatingPanel extends StatefulWidget {
  const RatingPanel({
    super.key,
    required this.convId,
    required this.customerId,
    required this.providerUserId,
    required this.onDone,
    this.businessId,
    this.submitConversation,
    this.submitBusinessReview,
  });
  final String convId;
  final String customerId;
  final String providerUserId;
  final VoidCallback onDone;

  /// Negocio al que pertenece esta conversación. Si viene, la nota se escribe
  /// TAMBIÉN en `business_reviews` — la tabla que de verdad alimenta la
  /// reputación pública. Sin ella la nota solo vive en `conversation_ratings`,
  /// que nadie promedia.
  final String? businessId;

  /// Inyectables para los tests (los reales tocan Supabase).
  final Future<void> Function(int overall)? submitConversation;
  final Future<void> Function(String businessId, int rating, String comment)?
      submitBusinessReview;

  @override
  State<RatingPanel> createState() => _RatingPanelState();
}
```

y en `_RatingPanelState._submit`, reemplazar el bloque `try` por:

```dart
    setState(() => _submitting = true);
    try {
      final saveConv = widget.submitConversation ??
          (int overall) => submitConversationRating(
              convId: widget.convId,
              customerId: widget.customerId,
              providerUserId: widget.providerUserId,
              overall: overall,
              quality: _quality,
              fulfillment: _fulfillment,
              service: _service,
              condition: _condition,
              comment: _comment.text);
      await saveConv(_overall);

      // Segunda escritura: la que MUEVE las estrellas. Best-effort a
      // propósito — la nota ya quedó guardada arriba, así que un fallo aquí no
      // puede tumbar el flujo ni hacer que el usuario recalifique.
      //
      // Escala: `_overall` y `business_reviews.rating` son ambos 1-10
      // (migración 20260619014535). NO convertir.
      final bizId = widget.businessId;
      if (bizId != null) {
        final saveBiz = widget.submitBusinessReview ??
            (String b, int r, String c) =>
                submitReview(businessId: b, rating: r, comment: c);
        try {
          await saveBiz(bizId, _overall, _comment.text);
        } catch (_) {
          // Silencioso: ver arriba.
        }
      }

      if (!mounted) return;
      await showRatingThanks(context); // ⭐ estrella + "Gracias por tu calificación"
      if (mounted) widget.onDone();
    } catch (_) {
```

- [ ] **Step 5: Correr los tests para verificar que pasan**

Run: `flutter test test/rating_writes_business_review_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 6: Resolver el negocio para los dos lados en el chat**

En `chat_screen.dart`:

6a. Renombrar `_maybeLoadProviderReview` a `_loadReviewContext` (y su llamada en la línea 278) y
reemplazar su cuerpo:

```dart
  /// Resuelve el contexto de calificación de ESTA conversación para el rol que
  /// la mira:
  /// - proveedor en chat de oferta: si ya calificó al cliente (panel bilateral);
  /// - siempre: el `business_id`, que el panel del CLIENTE necesita para que su
  ///   nota llegue a `business_reviews` (la que alimenta la reputación).
  ///
  /// Best-effort de punta a punta: si falla, el panel aparece igual y como
  /// mucho se pierde la segunda escritura.
  Future<void> _loadReviewContext(Map<String, dynamic> conv) async {
    final isProvider = conv['provider_user_id'] == _uid;
    final sourceId = conv['source_id'] as String?;
    final kind = conv['kind'] as String?;
    if (sourceId == null) return;
    try {
      // Los dos únicos tipos que crea `get_or_create_conversation`.
      final bizId = kind == 'offer'
          ? await offerBusinessId(sourceId)
          : kind == 'product_interest'
              ? await interestBusinessId(sourceId)
              : null;
      final reviewed = (isProvider && kind == 'offer')
          ? await hasCustomerReview(sourceId)
          : false;
      if (!mounted) return;
      setState(() {
        _reviewBusinessId = bizId;
        _customerReviewed = reviewed;
      });
    } catch (_) {
      // El panel no se rompe; a lo sumo no hay segunda escritura.
    }
  }
```

6b. En `_buildBottom` (línea ~1103), pasar el negocio al panel del cliente:

```dart
    if (!_isProvider && conv['status'] == 'cerrado' && !_hasRating) {
      return RatingPanel(
          convId: widget.conversationId,
          customerId: conv['customer_id'] as String,
          providerUserId: conv['provider_user_id'] as String,
          businessId: _reviewBusinessId,
          onDone: () => setState(() => _hasRating = true));
    }
```

- [ ] **Step 7: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/data/repos.dart app/lib/features/chat/widgets/rating_form.dart app/lib/features/chat/chat_screen.dart app/test/rating_writes_business_review_test.dart
git commit -m "fix(app): la calificacion del chat ahora si mueve la reputacion

Escribia solo en conversation_ratings, que nadie promedia. Ahora tambien en
business_reviews, que es de donde salen las estrellas.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: Calificar desde el detalle de solicitud completada

**Files:**
- Modify: `app/lib/data/repos.dart` (`myBusinessReview`)
- Modify: `app/lib/features/chat/widgets/rating_form.dart` (`BusinessReviewPanel`)
- Modify: `app/lib/features/client/request_status_screen.dart` (montarlo en fase completada)
- Test: `app/test/business_review_panel_test.dart` (crear)

**Interfaces:**
- Consumes: `submitReview` (repo), `blockedReasonForPhase` no aplica aquí.
- Produces:
  - `Future<({int rating, String? comment})?> myBusinessReview(String businessId)`
  - `BusinessReviewPanel({required businessId, onSaved, loadExisting, submit})` — **se carga a
    sí mismo** en su `initState`. No recibe `existing` del padre ni le pide nada: así el
    detalle de solicitud solo lo monta, sin estado nuevo ni efectos durante el `build`.

> **Por qué no se reusa `RatingPanel`:** su escritura a `conversation_ratings` tiene una RLS que
> exige una conversación con `status='cerrado'` y el reseñador como `customer_id`
> (`20260709204110:195`). En el detalle de solicitud no hay garantía de que exista. El panel
> nuevo escribe **solo** `business_reviews`, igual que la web en `$requestId.tsx:2212`.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/business_review_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/widgets/rating_form.dart';

/// El detalle de solicitud completada PROMETÍA "Califica al proveedor para
/// ayudar a la comunidad" y no tenía ningún control para hacerlo. Este panel
/// cierra esa promesa. Escala 1-10, igual que la web.
void main() {
  testWidgets('sin reseña previa muestra el formulario y guarda la nota', (
    tester,
  ) async {
    final guardadas = <(String, int, String)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async => null,
          submit: (b, r, c) async => guardadas.add((b, r, c)),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // el panel se carga a sí mismo
    expect(find.text('Califica al proveedor'), findsOneWidget);
    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();
    expect(guardadas.single.$1, 'biz1');
    expect(guardadas.single.$2, 10);
  });

  testWidgets('con reseña previa muestra la nota dada, no el formulario', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async => (rating: 8, comment: 'Todo bien'),
          submit: (_, _, _) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Califica al proveedor'), findsNothing);
    expect(find.textContaining('8'), findsOneWidget);
    expect(find.text('Todo bien'), findsOneWidget);
    expect(find.text('Enviar calificación'), findsNothing);
  });

  testWidgets('mientras no sabe si hay reseña, no pinta nada', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessReviewPanel(
          businessId: 'biz1',
          loadExisting: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return (rating: 8, comment: null);
          },
          submit: (_, _, _) async {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Califica al proveedor'), findsNothing,
        reason: 'pintar el formulario y luego reemplazarlo por la nota ya '
            'dada sería un parpadeo');
    await tester.pumpAndSettle();
    expect(find.textContaining('8'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/business_review_panel_test.dart`
Expected: FAIL — `Undefined name 'BusinessReviewPanel'`.

- [ ] **Step 3: Implementar el repo**

En `repos.dart`, junto a `businessReviews` (línea ~2365):

```dart
/// MI reseña vigente de este negocio (o null). La RLS de `business_reviews`
/// permite al reseñador leer la suya; el índice único
/// `uq_business_reviews_one_per_reviewer` garantiza que haya como mucho una.
Future<({int rating, String? comment})?> myBusinessReview(
  String businessId,
) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await supa
      .from('business_reviews')
      .select('rating,comment')
      .eq('business_id', businessId)
      .eq('reviewer_id', uid)
      .maybeSingle();
  if (row == null) return null;
  final c = (row['comment'] as String?)?.trim() ?? '';
  return (
    rating: (row['rating'] as num).toInt(),
    comment: c.isEmpty ? null : c,
  );
}
```

- [ ] **Step 4: Implementar `BusinessReviewPanel`**

Al final de `rating_form.dart`:

```dart
/// Calificación del CLIENTE al PROVEEDOR fuera del chat (detalle de solicitud
/// completada). Escribe SOLO `business_reviews` — que es la tabla de la que
/// salen las estrellas — porque `conversation_ratings` exige una conversación
/// cerrada y aquí no hay garantía de que exista.
///
/// Escala 1-10, igual que la web (`$requestId.tsx`) y que
/// `business_reviews.rating` desde la migración 20260619014535.
class BusinessReviewPanel extends StatefulWidget {
  const BusinessReviewPanel({
    super.key,
    required this.businessId,
    this.onSaved,
    this.loadExisting,
    this.submit,
  });
  final String businessId;

  /// Aviso opcional al padre de que se guardó (para refrescar lo suyo).
  final VoidCallback? onSaved;

  /// Inyectables para los tests (los reales tocan Supabase).
  final Future<({int rating, String? comment})?> Function(String businessId)?
      loadExisting;
  final Future<void> Function(String businessId, int rating, String comment)?
      submit;

  @override
  State<BusinessReviewPanel> createState() => _BusinessReviewPanelState();
}

class _BusinessReviewPanelState extends State<BusinessReviewPanel> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _submitting = false;

  /// Mi reseña vigente, si ya califiqué. El panel se carga A SÍ MISMO: así el
  /// detalle de solicitud solo lo monta, sin estado nuevo ni efectos durante
  /// su `build`.
  ({int rating, String? comment})? _existing;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Best-effort: si falla, se muestra el formulario. Reseñar de nuevo hace
  /// upsert (`uq_business_reviews_one_per_reviewer`), así que no duplica.
  Future<void> _load() async {
    final loader = widget.loadExisting ?? myBusinessReview;
    ({int rating, String? comment})? r;
    try {
      r = await loader(widget.businessId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _existing = r;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una calificación.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final save = widget.submit ??
          (String b, int r, String c) =>
              submitReview(businessId: b, rating: r, comment: c);
      await save(widget.businessId, _rating, _comment.text);
      if (!mounted) return;
      await showRatingThanks(context);
      if (!mounted) return;
      final c = _comment.text.trim();
      setState(() => _existing =
          (rating: _rating, comment: c.isEmpty ? null : c));
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo enviar. Intenta de nuevo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Hasta saber si ya califiqué, no se pinta nada: mostrar el formulario y
    // reemplazarlo un instante después por "ya calificaste" es un parpadeo.
    if (!_loaded) return const SizedBox.shrink();
    final existing = _existing;
    if (existing != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.star, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text('Calificaste al proveedor: ${existing.rating}/10',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          if (existing.comment != null) ...[
            const SizedBox(height: 4),
            Text(existing.comment!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Califica al proveedor',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text('Tu opinión ayuda a la comunidad. Escala de 1 a 10.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var n = 1; n <= 10; n++)
            InkWell(
                onTap: () => setState(() => _rating = n),
                child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color:
                                n <= _rating ? cs.primary : cs.outlineVariant),
                        color: n <= _rating ? cs.primary : null),
                    child: Text('$n',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: n <= _rating
                                ? cs.onPrimary
                                : cs.onSurfaceVariant)))),
        ]),
        if (_rating > 0) ...[
          const SizedBox(height: 6),
          Text('${ratingWord10(_rating)} · $_rating/10',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
        ],
        const SizedBox(height: 8),
        TextField(
            controller: _comment,
            maxLines: 2,
            decoration:
                const InputDecoration(hintText: 'Comentario (opcional)…')),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const JayaloSpinner(size: 16)
                    : const Text('Enviar calificación'))),
      ]),
    );
  }
}
```

- [ ] **Step 5: Correr el test para verificar que pasa**

Run: `flutter test test/business_review_panel_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 6: Montarlo en el detalle de solicitud**

En `request_status_screen.dart`:

6a. Import: `import '../chat/widgets/rating_form.dart';`

6b. Dentro de `_DetailSheet`, en la rama de fase `completed`, montar el panel. **Eso es todo**:
`_DetailSheet` no gana parámetros y `_RequestStatusScreenState` no gana estado — el panel se
carga solo. El negocio sale de la oferta aceptada, que la pantalla ya tiene en `offers`
(`offerCols` incluye `business_id`):

```dart
              // Fase completada: cerrar la promesa del copy de `_phaseCopy`
              // ("Califica al proveedor para ayudar a la comunidad"), que hasta
              // ahora no tenía ningún control detrás.
              if (phase == RequestPhase.completed)
                ...() {
                  final accepted = offers.where((o) =>
                      o['status'] == 'accepted' || o['status'] == 'completed');
                  final bizId = accepted.isEmpty
                      ? null
                      : accepted.first['business_id'] as String?;
                  return [
                    if (bizId != null)
                      BusinessReviewPanel(
                        // Key por negocio: si la oferta aceptada cambiara, el
                        // panel se re-crea y vuelve a cargar SU reseña.
                        key: ValueKey('review-$bizId'),
                        businessId: bizId,
                      ),
                  ];
                }(),
```

> **Por qué así:** la versión anterior de este plan pasaba la reseña desde el padre y disparaba
> su carga **durante el `build`** — un efecto secundario en el sitio donde Flutter menos lo
> perdona. El panel cargándose a sí mismo (Step 4) elimina el estado del padre, los tres
> parámetros de `_DetailSheet` y el efecto en build de una vez.
>
> Si el `Column`/`ListView` donde va esto no admite spread de lista, monta el `Builder`
> equivalente — lo que NO debe reaparecer es una llamada de carga dentro del `build`.

- [ ] **Step 7: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/data/repos.dart app/lib/features/chat/widgets/rating_form.dart app/lib/features/client/request_status_screen.dart app/test/business_review_panel_test.dart
git commit -m "feat(app): calificar al proveedor desde la solicitud completada

La pantalla decia 'Califica al proveedor' y no habia como hacerlo.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 10: Calificar al cliente desde "Mis ofertas"

**Files:**
- Modify: `app/lib/data/repos.dart` (`customer_id` en `_fetchMyOffers`; `customerReviewsFor`)
- Modify: `app/lib/features/provider/my_offers_screen.dart`
- Test: `app/test/needs_customer_review_test.dart` (crear)

**Interfaces:**
- Consumes: `CustomerRatingPanel` (ya existe, `rating_form.dart:31`), `hasCustomerReview` y
  `offerBusinessId` (ya existen).
- Produces:
  - `Future<Set<String>> customerReviewsFor(List<String> offerIds)` — ids de ofertas YA
    reseñadas, en **una** consulta.
  - `bool needsCustomerReview(Map<String, dynamic> offer, Set<String> reviewed)` — función pura.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/needs_customer_review_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';

/// Paridad EXACTA con la web (`ProviderOffersSection.tsx:705`): el proveedor
/// califica al cliente solo en ofertas completadas, con compra confirmada,
/// con cliente conocido y sin reseña previa.
void main() {
  Map<String, dynamic> offer({
    String status = 'completed',
    bool? purchase = true,
    String? customerId = 'cli',
  }) =>
      {
        'id': 'o1',
        'status': status,
        'purchase_completed': purchase,
        'customer_id': customerId,
      };

  test('caso feliz: completada, comprada, con cliente y sin reseña', () {
    expect(needsCustomerReview(offer(), const {}), isTrue);
  });

  test('no aplica si ya hay reseña', () {
    expect(needsCustomerReview(offer(), const {'o1'}), isFalse);
  });

  test('no aplica si la oferta no está completada', () {
    expect(needsCustomerReview(offer(status: 'accepted'), const {}), isFalse);
  });

  test('no aplica si la compra no se confirmó', () {
    expect(needsCustomerReview(offer(purchase: null), const {}), isFalse);
    expect(needsCustomerReview(offer(purchase: false), const {}), isFalse);
  });

  test('no aplica sin customer_id', () {
    expect(needsCustomerReview(offer(customerId: null), const {}), isFalse);
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/needs_customer_review_test.dart`
Expected: FAIL — `Undefined name 'needsCustomerReview'`.

- [ ] **Step 3: Implementar el repo**

3a. En `repos.dart`, `_fetchMyOffers` (línea ~844) — añadir `customer_id` al select.
`offerCols` NO se toca: cambiarlo afectaría a todas las pantallas que lo consumen.

```dart
        .select('$offerCols,request_title,points_charged,purchase_completed,customer_id')
```

3b. Junto a `hasCustomerReview` (línea ~1604), añadir:

```dart
/// Ids de las ofertas de esta tanda que YA tienen reseña del cliente. Una sola
/// consulta para toda la lista (mismo patrón que la web en
/// `ProviderOffersSection.tsx:208`): por tarjeta serían N viajes.
Future<Set<String>> customerReviewsFor(List<String> offerIds) async {
  if (offerIds.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_reviews')
        .select('offer_id')
        .inFilter('offer_id', offerIds),
  );
  return rows.map((r) => r['offer_id'] as String).toSet();
}
```

- [ ] **Step 4: Implementar la pantalla**

En `my_offers_screen.dart`:

4a. A nivel de fichero, la función pura:

```dart
/// ¿Toca calificar al cliente por esta oferta? Paridad exacta con la web
/// (`ProviderOffersSection.tsx:705`): completada + compra confirmada + cliente
/// conocido + sin reseña previa.
bool needsCustomerReview(
  Map<String, dynamic> offer,
  Set<String> reviewed,
) =>
    offer['status'] == 'completed' &&
    offer['purchase_completed'] == true &&
    offer['customer_id'] != null &&
    !reviewed.contains(offer['id']);
```

4b. En `_MyOffersScreenState`, estado nuevo y carga en lote dentro de `_refetch`:

```dart
  /// Ofertas de esta tanda que ya tienen reseña del cliente (una sola consulta).
  Set<String> _reviewed = {};
```

```dart
  Future<void> _refetch() async {
    final results = await Future.wait([myOffers(), walletBalance()]);
    final offers = results[0] as List<Map<String, dynamic>>;
    // En lote, no por tarjeta. Best-effort: sin esto solo se pierde el botón.
    var reviewed = <String>{};
    try {
      reviewed = await customerReviewsFor(
        offers.map((o) => o['id'] as String).toList(),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _offers = offers;
      _balance = results[1] as int?;
      _reviewed = reviewed;
      _loading = false;
    });
  }
```

4c. En `_offerCard`, tras el `Row` existente, añadir el botón cuando toque. Reemplazar el
`child: Row(` del `JayaloCard` por una `Column` que lo envuelva:

```dart
    return JayaloCard(
      onTap: () => _openOffer(o),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // … el contenido actual del Row, SIN cambios …
            ],
          ),
          if (needsCustomerReview(o, _reviewed)) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _rateCustomer(o),
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('Calificar al cliente'),
              ),
            ),
          ],
        ],
      ),
    );
```

4d. El manejador, en `_MyOffersScreenState`:

```dart
  /// Abre el calificador bilateral en una hoja. No se toca
  /// `showOfferContactSheet`: el PO retiró de esa hoja el cierre de venta el
  /// 2026-07-23 y volver a meterle una acción de cierre iría contra eso.
  Future<void> _rateCustomer(Map<String, dynamic> o) async {
    final businessId = o['business_id'] as String?;
    final customerId = o['customer_id'] as String?;
    if (businessId == null || customerId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: CustomerRatingPanel(
          offerId: o['id'] as String,
          businessId: businessId,
          customerId: customerId,
          onDone: () => Navigator.pop(ctx),
        ),
      ),
    );
    if (mounted) await _refetch();
  }
```

4e. Import: `import '../chat/widgets/rating_form.dart';`

- [ ] **Step 5: Correr los tests para verificar que pasan**

Run: `flutter test test/needs_customer_review_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 6: Gates y commit**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/data/repos.dart app/lib/features/provider/my_offers_screen.dart app/test/needs_customer_review_test.dart
git commit -m "feat(app): el proveedor califica al cliente desde Mis ofertas

Paridad con ProviderOffersSection de la web.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 11: El ícono de mensajes preguardados deja de parecer de IA

**Files:**
- Modify: `app/lib/features/chat/widgets/composer.dart:188`
- Modify: `jayalo-main/src/routes/messages.$conversationId.tsx:16,1394`

**Interfaces:**
- Consumes: nada. Tarea independiente — se puede hacer en cualquier orden.
- Produces: nada que otra tarea use.

> `Icons.auto_awesome` (las chispitas) y `Sparkles` son **el** ícono de IA en toda la industria.
> El botón abre mensajes preguardados, no una IA.
> `Icons.psychology_outlined` se descarta pese a significar "pensamiento": es un cerebro y
> leería como IA *más* que las chispitas. Lucide no tiene la burbuja-con-rayo de Material, así
> que app y web **no** quedarán idénticos, y es aceptado.

- [ ] **Step 1: Cambiar el ícono en la app**

En `app/lib/features/chat/widgets/composer.dart`, línea 188:

```dart
          child: IconButton(
              onPressed: _openQuickList,
              // Burbuja con rayo = respuestas rápidas. NO `auto_awesome`: las
              // chispitas son el ícono universal de IA y este botón abre
              // mensajes preguardados, no una IA.
              icon: const Icon(Icons.quickreply_outlined)),
```

El copy de la guía (`onboarding_copy.dart:58`, *"Aquí eliges mensajes predefinidos para responder
rápido."*) **no se toca** y la clave `chat.quick_replies.v1` **no sube de versión**: el texto
sigue siendo correcto y quien ya vio la guía no necesita verla otra vez.

- [ ] **Step 2: Verificar la app**

Run (desde `app/`): `flutter analyze && flutter test test/quick_replies_test.dart`
Expected: 0 issues, tests en verde.

- [ ] **Step 3: Cambiar el ícono en la web**

En `jayalo-main/src/routes/messages.$conversationId.tsx`:

Línea 16 — en el bloque de imports de `lucide-react`, sustituir `Sparkles` por
`MessageSquareQuote` (mantén el orden alfabético del bloque si lo tiene).

Línea 1394:

```tsx
                  <MessageSquareQuote className="h-5 w-5" strokeWidth={1.75} />
```

Comprobar que `Sparkles` no quede importado sin usar (el lint lo marcaría) y que no se use en
otro punto del fichero:

```bash
grep -n "Sparkles" src/routes/messages.\$conversationId.tsx
```

Expected: sin resultados.

- [ ] **Step 4: Verificar la web**

Run (desde el repo web): `npx tsc --noEmit && npm run lint && npm test`
Expected: 0 errores de tipos, 0 de lint, 423 tests en verde.

- [ ] **Step 5: Commit en los dos repos**

En `jayalo-app`:
```bash
git add app/lib/features/chat/widgets/composer.dart
git commit -m "fix(app): el boton de mensajes preguardados ya no parece de IA

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

En `jayalo-main`:
```bash
git add src/routes/messages.\$conversationId.tsx
git commit -m "fix(web): el boton de mensajes preguardados ya no parece de IA

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## QA manual antes de cerrar

Estas comprobaciones **no** las cubre ningún test automatizado y son la condición de cierre:

1. **Dispositivo con navegación por gestos:** el swipe de la lista de chats no se pelea con el
   "atrás" del sistema (el gesto arranca desde la fila, no desde el borde).
2. **El guard del trigger, con sesión real:** desde la cuenta del cliente, intentar
   `UPDATE conversations SET archived_by_provider = true` por PostgREST sobre una conversación
   propia → debe fallar con `P0001`. Es el ataque exacto que el trigger existe para bloquear.
3. **Ida y vuelta del archivado:** archivar en un dispositivo, entrar desde otro → sigue
   archivada (es el motivo de haberlo puesto en BD y no en un store local).
4. **La calificación mueve las estrellas:** calificar a un proveedor desde el chat y confirmar
   que su promedio público cambia (antes no lo hacía — es el bug que cierra la Task 8).
5. **Pista de swipe:** en una cuenta que nunca la vio, la primera tarjeta deslizable se asoma una
   vez; al recargar la pantalla ya no.
6. **Los dos íconos**, en claro y oscuro, app y web.

## Push final

Con todo verde en los dos repos:

```bash
cd /c/Users/ac/Downloads/jayalo-app && git push origin feat/error-tracking
```

```bash
cd /c/Users/ac/Downloads/jayalo-main/jayalo-main && git push origin master
```

> El push a `master` de la web **despliega solo** (el job `deploy` del CI). Verificar
> jayalo.com después.
