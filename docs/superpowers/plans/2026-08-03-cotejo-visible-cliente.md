# El cliente ve si la oferta cubre sus condiciones (tanda C) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el cliente, en cada oferta que recibe, vea cuáles de sus condiciones cubre y cuáles no
declaró el proveedor — en la app y en la web.

**Architecture:** Una función pura nueva por frente, `requirementCoverage`, con el mismo nombre y la
misma forma en los dos módulos de dominio que ya existen. Devuelve las filas ya compuestas (clave, si
la cubre, y el texto a pintar), así que el copy —lo único nuevo de la tanda— queda probado en los dos
lados y los componentes de presentación no deciden nada. Encima, un componente tonto por frente.
Ninguna migración, ninguna regla de negocio nueva.

**Tech Stack:** Flutter (Dart 3, records y patterns), React + TypeScript (TanStack Router, Tailwind),
Supabase (PostgREST), `flutter_test` y `vitest`.

**Spec:** `docs/superpowers/specs/2026-08-03-cotejo-visible-cliente-design.md`

## Global Constraints

- **Son DOS repos de git independientes**, cada uno con sus propios commits:

  | Frente | Raíz | Comandos |
  |---|---|---|
  | App | `C:\Users\ac\Downloads\jayalo-app` | `flutter` **desde `app/`**; `docs/` cuelga de la raíz |
  | Web | `C:\Users\ac\Downloads\jayalo-main\jayalo-main` | desde esa raíz — **va anidada** dentro de otra carpeta del mismo nombre |

- **Cero cambios de base de datos.** Ni migraciones ni grants. Verificado contra
  `information_schema` el 2026-08-03: `anon` **y** `authenticated` tienen `SELECT` sobre las 45
  columnas de `provider_offers`, `has_fiscal_receipt` e `is_state_supplier` incluidas. Si una tarea
  parece necesitar una migración, **parar y reportar**.
- **La evaluación NUNCA entra en el cotejo.** Ya lo resuelve `verifiableRequirements` /
  `VERIFIABLE_KEYS`; ninguna tarea filtra nada por su cuenta.
- Orden canónico de la serie: envío → instalación → evaluación → fiscal → Estado. En este cotejo
  salen esas mismas, en ese mismo orden, **menos la evaluación**.
- **Las etiquetas existentes no se reescriben.** Todo texto sale de `requirementLabel(k).short` /
  `REQUIREMENT_LABEL[k].short`.
- **El copy negativo es "no lo declaró".** Nunca "no cumple", nunca "no emite". Un test lo blinda en
  los dos frentes. Motivo: las columnas son `NOT NULL DEFAULT false` y a fecha de hoy 33 de las 34
  ofertas existentes son anteriores a que la pregunta existiera; afirmar un negativo sería mentir
  sobre proveedores reales.
- **La lista sale completa siempre**, aunque la oferta cubra todas las condiciones.
- Comentarios y mensajes de commit en español, estilo de cada repo (`feat(app):` / `feat:`). Cada
  commit termina con `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. **No hacer push** — lo
  decide el PO.
- **Verde obligatorio.** App: `flutter analyze lib test` en `No issues found!` y la suite en verde.
  Web: `npx tsc --noEmit`, `npm run lint` y `npm test` sin errores.
- **La app parte de 708 tests en verde** (medido en `c9ba377`). Los números que da este plan son
  aritmética de los casos que escribe; si una revisión añade un test, el número sube y eso está bien.
  Lo que nunca puede pasar es que baje o que la suite quede roja.
- **Fuera de alcance, a propósito** — no lo toques y no lo reportes como olvido:
  `src/components/marketplace/MyRequestsView.tsx` de la web, que también lee ofertas; el inbox del
  proveedor; el perfil público del negocio; y filtrar u ordenar ofertas por requisitos.
- **`app/test/offer_requirements_warning_test.dart` NO se toca.** Afirma que el copy del aviso al
  proveedor no contiene "el cliente verá". Esta tanda hace que el cliente lo vea, pero el copy del
  proveedor sigue sin prometerlo, y prometerlo abriría la puerta a que alguien lo cambiara sin
  comprobar que sigue siendo verdad. Si el test te falla, **para y reporta** — no lo actualices.

## Estructura de ficheros

**Se crean:**

| Fichero | Responsabilidad |
|---|---|
| `app/lib/features/client/offer_requirement_coverage.dart` | El bloque de la app. Recibe las filas ya cotejadas y las pinta. |
| `app/test/offer_requirement_coverage_test.dart` | Pruebas del bloque. |
| `src/components/marketplace/OfferRequirementCoverage.tsx` (web) | El bloque de la web. Un `map`, sin decisiones. |
| `docs/qa/2026-08-03-smoke-cotejo-visible-cliente.md` | Guion de smoke, los dos frentes. |

**Se modifican:**

| Fichero | Qué cambia |
|---|---|
| `app/lib/domain/request_requirements.dart` | `requirementCoverage`. |
| `app/test/domain/request_requirements_test.dart` | Pruebas del cotejo. |
| `app/lib/features/client/request_status_screen.dart` | `_OfferCard` recibe y pinta el bloque. |
| `src/lib/requestRequirements.ts` (web) | `requirementCoverage`. |
| `src/lib/requestRequirements.test.ts` (web) | Pruebas del cotejo. |
| `src/routes/requests/$requestId.tsx` (web) | Dos columnas al `select`, dos campos a `OfferExtras`, y el bloque en la tarjeta. |

---

### Task 1: El cotejo en el módulo de dominio de la app

**Repo:** app. **Files:**
- Modify: `app/lib/domain/request_requirements.dart`
- Test: `app/test/domain/request_requirements_test.dart`

**Interfaces:**
- Consumes: del propio módulo — `enum Requirement`, `class RequestRequirements`,
  `class OfferCapabilities` (con `bool covers(Requirement)`), `const verifiableRequirements`,
  `activeRequirements(req, {keys})`, y `requirementLabel(r)` que devuelve
  `({String chip, String short, String hint})`.
- Produces:
  `List<({Requirement key, bool covered, String label})> requirementCoverage(RequestRequirements req, OfferCapabilities cap)`

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `app/test/domain/request_requirements_test.dart`, antes del `}` que cierra
`main()`:

```dart
  group('requirementCoverage', () {
    const pideTodo = RequestRequirements(
      withShipping: true,
      withInstallation: true,
      requiresEvaluation: true,
      requiresFiscalReceipt: true,
      requiresStateSupplier: true,
    );

    test('sin condiciones marcadas no devuelve filas', () {
      expect(
        requirementCoverage(RequestRequirements.none, OfferCapabilities.none),
        isEmpty,
      );
    });

    test('solo evaluación tampoco devuelve filas: no es cotejable', () {
      expect(
        requirementCoverage(
          const RequestRequirements(requiresEvaluation: true),
          OfferCapabilities.none,
        ),
        isEmpty,
      );
    });

    test('conserva las cubiertas y las no cubiertas, no solo los fallos', () {
      final filas = requirementCoverage(
        const RequestRequirements(
          withShipping: true,
          requiresFiscalReceipt: true,
        ),
        const OfferCapabilities(offersShipping: true),
      );
      expect(filas.map((f) => f.key), [Requirement.shipping, Requirement.fiscal]);
      expect(filas.map((f) => f.covered), [true, false]);
    });

    test('las cuatro marcadas y la oferta sin declarar nada: cuatro filas en falso', () {
      final filas = requirementCoverage(pideTodo, OfferCapabilities.none);
      expect(filas.map((f) => f.key), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
      expect(filas.every((f) => !f.covered), isTrue);
    });

    test('ofrecer de más no añade filas', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresFiscalReceipt: true),
        const OfferCapabilities(
          offersShipping: true,
          offersInstallation: true,
          hasFiscalReceipt: true,
          isStateSupplier: true,
        ),
      );
      expect(filas.map((f) => f.key), [Requirement.fiscal]);
      expect(filas.single.covered, isTrue);
    });

    test('el orden lo fija la declaración del enum, no el de los campos', () {
      final filas = requirementCoverage(
        const RequestRequirements(
          requiresStateSupplier: true,
          withShipping: true,
          requiresFiscalReceipt: true,
        ),
        OfferCapabilities.none,
      );
      expect(filas.map((f) => f.key), [
        Requirement.shipping,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('la etiqueta cubierta empieza en mayúscula y no lleva coletilla', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresFiscalReceipt: true),
        const OfferCapabilities(hasFiscalReceipt: true),
      );
      expect(filas.single.label, 'Comprobante fiscal');
    });

    test('la etiqueta no cubierta dice "no lo declaró"', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresStateSupplier: true),
        OfferCapabilities.none,
      );
      expect(filas.single.label, 'Suplidor del Estado — no lo declaró');
    });

    test('el copy NUNCA afirma un negativo sobre el proveedor', () {
      // `false` significa hoy dos cosas: "lo vio y no lo marcó" y "ofertó antes
      // de que la pregunta existiera" — 33 de 34 ofertas son del segundo caso.
      // Decir "no cumple" o "no emite" sería mentir sobre un proveedor real.
      final filas = requirementCoverage(pideTodo, OfferCapabilities.none);
      for (final f in filas) {
        expect(f.label, isNot(contains('no cumple')));
        expect(f.label, isNot(contains('no emite')));
      }
    });
  });
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Desde `app/`:

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: FALLA en compilación — `The function 'requirementCoverage' isn't defined`.

- [ ] **Step 3: Escribir el cotejo**

Añadir al final de `app/lib/domain/request_requirements.dart`, después de
`unmetRequirementsMessage`:

```dart

/// Cada requisito cotejable que el cliente pidió, con si esta oferta lo cubre y
/// con el texto ya listo para pintar, en orden canónico.
///
/// Es el hermano de [unmetRequirements] para el OTRO lector. Aquel se queda solo
/// con los fallos porque el proveedor necesita saber qué corregir; este conserva
/// las dos mitades porque el cliente necesita ver también lo que SÍ cubre.
///
/// Devuelve el texto compuesto, y no solo la clave, a propósito: el copy es lo
/// único que la tanda C añade de verdad y lo único que puede divergir entre la
/// app y la web. Aquí se prueba con los mismos casos a los dos lados y los
/// componentes quedan sin decisiones. Mismo criterio que [unmetRequirementsMessage].
///
/// Nunca incluye la evaluación ni lo que la oferta ofrece de más.
List<({Requirement key, bool covered, String label})> requirementCoverage(
  RequestRequirements req,
  OfferCapabilities cap,
) => [
  for (final r in activeRequirements(req, keys: verifiableRequirements))
    (
      key: r,
      covered: cap.covers(r),
      label: _coverageLabel(r, cap.covers(r)),
    ),
];

/// "Comprobante fiscal" · "Comprobante fiscal — no lo declaró".
///
/// **"No lo declaró", nunca "no cumple" ni "no emite".** Las columnas son
/// `NOT NULL DEFAULT false`, así que un `false` puede significar que el
/// proveedor vio la casilla —y hasta el aviso de la tanda B— y no la marcó, o
/// que ofertó antes de que la pregunta existiera. Afirmar el negativo sería
/// mentir sobre proveedores reales.
String _coverageLabel(Requirement r, bool covered) {
  final s = requirementLabel(r).short;
  final capitalizado = '${s[0].toUpperCase()}${s.substring(1)}';
  return covered ? capitalizado : '$capitalizado — no lo declaró';
}
```

- [ ] **Step 4: Correr los tests y verificar que pasan**

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: PASA, con los 9 casos nuevos.

- [ ] **Step 5: Analizar y correr la suite completa**

```bash
flutter analyze lib test
flutter test
```

Esperado: `No issues found!` y verde con **717 tests** (708 + 9).

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/request_requirements.dart app/test/domain/request_requirements_test.dart
git commit -m "feat(app): el cotejo que ve el cliente, con el texto ya compuesto

Hermano de unmetRequirements para el otro lector: aquel se queda con los fallos
porque el proveedor necesita saber que corregir, este conserva las dos mitades
porque el cliente necesita ver tambien lo que SI cubre.

Devuelve el texto y no solo la clave a proposito. El copy es lo unico que esta
tanda anade de verdad y lo unico que puede divergir entre la app y la web; aqui
se prueba con los mismos casos a los dos lados. Dice \"no lo declaro\" y nunca
\"no cumple\": las columnas son NOT NULL DEFAULT false y 33 de las 34 ofertas
existentes son anteriores a que la pregunta existiera.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: El bloque en la app

**Repo:** app. **Files:**
- Create: `app/lib/features/client/offer_requirement_coverage.dart`
- Test: `app/test/offer_requirement_coverage_test.dart`

**Interfaces:**
- Consumes: de la Task 1, `requirementCoverage` y el tipo de sus filas
  `({Requirement key, bool covered, String label})`.
- Produces: `class OfferRequirementCoverage` — widget público sin estado, con constructor
  `const OfferRequirementCoverage({super.key, required this.coverage})`, donde `coverage` es
  `List<({Requirement key, bool covered, String label})>`.

**Por qué público:** `_OfferCard` es privado a `request_status_screen.dart`, así que un test de
widget no puede montarlo desde afuera. Este widget sí es importable y testeable aislado. Es el mismo
motivo por el que en ese fichero existe `OfferCardProviderHeader`, y su doc lo dice.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/offer_requirement_coverage_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/client/offer_requirement_coverage.dart';

void main() {
  Future<void> montar(
    WidgetTester tester,
    RequestRequirements req,
    OfferCapabilities cap, {
    Brightness brillo = Brightness.light,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(brillo),
      home: Scaffold(
        body: OfferRequirementCoverage(coverage: requirementCoverage(req, cap)),
      ),
    ));
  }

  testWidgets('sin condiciones cotejables no pinta nada', (tester) async {
    await montar(tester, RequestRequirements.none, OfferCapabilities.none);
    expect(find.text('Tus condiciones'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('solo evaluación tampoco pinta nada', (tester) async {
    await montar(
      tester,
      const RequestRequirements(requiresEvaluation: true),
      OfferCapabilities.none,
    );
    expect(find.text('Tus condiciones'), findsNothing);
  });

  testWidgets('la lista sale completa aunque la oferta lo cubra todo',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresFiscalReceipt: true,
      ),
      const OfferCapabilities(offersShipping: true, hasFiscalReceipt: true),
    );
    expect(find.text('Tus condiciones'), findsOneWidget);
    expect(find.text('Envío'), findsOneWidget);
    expect(find.text('Comprobante fiscal'), findsOneWidget);
  });

  testWidgets('lo no declarado lo dice, y no afirma un negativo', (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresStateSupplier: true,
      ),
      const OfferCapabilities(offersShipping: true),
    );
    expect(find.text('Envío'), findsOneWidget);
    expect(find.text('Suplidor del Estado — no lo declaró'), findsOneWidget);
    expect(find.textContaining('no cumple'), findsNothing);
    expect(find.textContaining('no emite'), findsNothing);
  });

  testWidgets('las filas salen en orden canónico', (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        requiresStateSupplier: true,
        withShipping: true,
        requiresFiscalReceipt: true,
      ),
      OfferCapabilities.none,
    );
    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final iEnvio = textos.indexWhere((t) => t.startsWith('Envío'));
    final iFiscal = textos.indexWhere((t) => t.startsWith('Comprobante fiscal'));
    final iEstado = textos.indexWhere((t) => t.startsWith('Suplidor del Estado'));
    expect(iEnvio < iFiscal, isTrue);
    expect(iFiscal < iEstado, isTrue);
  });

  testWidgets('en oscuro pinta sin reventar y con el mismo texto',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(requiresFiscalReceipt: true),
      OfferCapabilities.none,
      brillo: Brightness.dark,
    );
    expect(find.text('Comprobante fiscal — no lo declaró'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/offer_requirement_coverage_test.dart
```

Esperado: FALLA en compilación — `Target of URI doesn't exist: 'package:jayalo_app/features/client/offer_requirement_coverage.dart'`.

- [ ] **Step 3: Escribir el widget**

Crear `app/lib/features/client/offer_requirement_coverage.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/request_requirements.dart';

/// Lo que el cliente exigió en su solicitud y si ESTA oferta lo cubre, dentro de
/// su tarjeta.
///
/// Público y sin estado a propósito: `_OfferCard` es privado a
/// `request_status_screen.dart`, así que un test de widget no puede montarlo
/// desde afuera; este sí es importable y se prueba aislado. Mismo motivo por el
/// que en ese fichero existe `OfferCardProviderHeader`.
///
/// **No decide nada.** Recibe las filas ya cotejadas y con el texto compuesto
/// por `requirementCoverage`. Si la lista viene vacía —el cliente no exigió nada
/// cotejable, o solo exigió evaluación— no pinta NADA: el ~60% de las
/// solicitudes no pide condiciones y sus tarjetas no deben crecer ni un píxel.
class OfferRequirementCoverage extends StatelessWidget {
  const OfferRequirementCoverage({super.key, required this.coverage});

  final List<({Requirement key, bool covered, String label})> coverage;

  @override
  Widget build(BuildContext context) {
    if (coverage.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'Tus condiciones',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        for (final c in coverage)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tono neutro también en el negativo (decisión PO): sin ámbar ni
                // ícono de alarma. El cliente ve el hueco y decide; no se acusa
                // a un proveedor que quizá cumple y solo no lo declaró.
                Icon(
                  c.covered
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                  size: 13,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    c.label,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
flutter test test/offer_requirement_coverage_test.dart
```

Esperado: PASA, 6 tests. Si alguno falla por `RenderFlex overflowed`, **no reformes el layout**: en
`flutter test` el texto mide ~2× lo real sobre la superficie por defecto. Reporta el caso.

- [ ] **Step 5: Analizar y correr la suite completa**

```bash
flutter analyze lib test
flutter test
```

Esperado: `No issues found!` y verde con **723 tests** (717 + 6).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/client/offer_requirement_coverage.dart app/test/offer_requirement_coverage_test.dart
git commit -m "feat(app): el bloque que le muestra al cliente si la oferta cubre sus condiciones

Widget publico y sin decisiones: recibe las filas ya cotejadas. Es publico
porque _OfferCard es privado a request_status_screen.dart y un test no puede
montarlo desde afuera — el mismo motivo por el que ahi vive
OfferCardProviderHeader.

Con la lista vacia no pinta nada: el 60% de las solicitudes no pide condiciones
y sus tarjetas no deben crecer. El negativo va en tono neutro por decision del
PO: no se acusa a un proveedor que quiza cumple y solo no lo declaro.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Enchufarlo en la tarjeta de oferta de la app

**Repo:** app. **Files:**
- Modify: `app/lib/features/client/request_status_screen.dart`

**Interfaces:**
- Consumes: de la Task 1, `requirementCoverage`, `OfferCapabilities` y `requirementsFromRow`; de la
  Task 2, `OfferRequirementCoverage`.
- Produces: nada que consuman otras tareas.

**Sin tests.** `RequestStatusScreen` recibe solo un `requestId` y carga en `initState` sin fuente
inyectable: **no tiene costura**, y esta tanda no la abre. Las dos piezas que cablea ya están
probadas por su lado; el cableado se verifica en el smoke (Task 6). No inventes una costura ni
refactorices la pantalla.

- [ ] **Step 1: Importar lo que hace falta**

En la cabecera de `app/lib/features/client/request_status_screen.dart`, añadir junto a los demás
imports relativos:

```dart
import '../../domain/request_requirements.dart';
import 'offer_requirement_coverage.dart';
```

Si `request_requirements.dart` ya estuviera importado, no lo dupliques.

- [ ] **Step 2: Calcular los requisitos de la solicitud una sola vez**

En `_OffersSheetState.build`, **antes** del `ListView.separated`/`ListView.builder` cuyo
`itemBuilder` construye los `_OfferCard` (el que está alrededor de la línea 486), añadir:

```dart
    // Los requisitos son de la SOLICITUD: se calculan una vez, no por oferta.
    final reqs = requirementsFromRow(widget.request);
```

Confirma antes que `widget.request` es el `Map<String, dynamic>` de `customer_requests` — lo carga
`initState` con `$requestRequirementCols` incluido desde la tanda A, así que las cinco columnas ya
vienen. Si no fuera un `Map<String, dynamic>`, **para y reporta**.

- [ ] **Step 3: Pasarle el cotejo a la tarjeta**

En el `itemBuilder`, en la llamada a `_OfferCard`, añadir un argumento más:

```dart
                        coverage: requirementCoverage(
                          reqs,
                          OfferCapabilities(
                            offersShipping: o['offers_shipping'] == true,
                            offersInstallation: o['offers_installation'] == true,
                            hasFiscalReceipt: o['has_fiscal_receipt'] == true,
                            isStateSupplier: o['is_state_supplier'] == true,
                          ),
                        ),
```

Las cuatro columnas ya vienen en `offerCols`; las dos capacidades se añadieron ahí en la tanda B
precisamente para esto, y el comentario de `repos.dart` lo dice. **No hace falta tocar ninguna
lectura.**

- [ ] **Step 4: Recibirlo en `_OfferCard`**

En el constructor de `_OfferCard` (alrededor de la línea 689), añadir el parámetro:

```dart
    required this.coverage,
```

Y el campo, junto a los demás, con su doc:

```dart
  /// Lo que el cliente exigió en la solicitud y si esta oferta lo cubre, ya
  /// cotejado por `requirementCoverage`. Vacío = no exigió nada cotejable, y
  /// entonces el bloque no se pinta.
  final List<({Requirement key, bool covered, String label})> coverage;
```

- [ ] **Step 5: Pintarlo**

En el `build` de `_OfferCard`, dentro de la `Column` interna (la que está en el `Expanded`),
**después** del bloque `if (message.isNotEmpty) ...[ ... ],` y antes del `]` que cierra esa
`Column`:

```dart
                OfferRequirementCoverage(coverage: coverage),
```

Va al final a propósito: precio, sellos y mensaje son lo que el cliente escanea primero; el cotejo
es lo que mira cuando ya se fijó en una oferta.

- [ ] **Step 6: Analizar y correr la suite completa**

```bash
flutter analyze lib
flutter test
```

Esperado: `No issues found!` y verde con **723 tests** (esta tarea no añade ninguno).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/client/request_status_screen.dart
git commit -m "feat(app): el cliente ve en cada oferta si cubre sus condiciones

Los requisitos son de la solicitud, asi que se calculan una vez fuera del
itemBuilder y no por oferta. Las cuatro columnas que hacen falta ya venian en
offerCols: las dos capacidades se dejaron ahi en la tanda B justo para esto, y
no hizo falta tocar ninguna lectura.

El bloque va al final de la tarjeta: precio, sellos y mensaje son lo que el
cliente escanea; el cotejo es lo que mira cuando ya se fijo en una oferta.

Sin tests: esta pantalla recibe solo un requestId y carga en initState sin
fuente inyectable, no tiene costura y la tanda no la abre. Las dos piezas que
cablea si estan probadas por separado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: El cotejo en el módulo de dominio de la web

**Repo: WEB** — `C:\Users\ac\Downloads\jayalo-main\jayalo-main`. **Files:**
- Modify: `src/lib/requestRequirements.ts`
- Test: `src/lib/requestRequirements.test.ts`

**Interfaces:**
- Consumes: del propio módulo — `RequirementKey`, `VerifiableKey`, `RequestRequirements`,
  `OfferCapabilities`, `VERIFIABLE_KEYS`, `REQUIREMENT_LABEL`, y los mapas internos `REQUIRED_BY` /
  `COVERED_BY`.
- Produces:
  ```ts
  export type RequirementCoverageRow = {
    key: VerifiableKey;
    covered: boolean;
    label: string;
  };
  export function requirementCoverage(
    req: RequestRequirements,
    cap: OfferCapabilities,
  ): RequirementCoverageRow[];
  ```

**Espejo exacto de la Task 1.** Mismo nombre, misma forma, mismos casos de prueba. Si te desvías,
los dos frentes divergen y ningún test lo va a notar.

- [ ] **Step 1: Anotar la línea base de la suite**

```bash
npm test
```

Apunta el número de tests que hay **antes** de tocar nada; lo necesitas para el Step 5 y para el
informe. Si la suite ya estuviera roja antes de tu cambio, **para y reporta** — no es tuyo.

- [ ] **Step 2: Escribir los tests que fallan**

Añadir al final de `src/lib/requestRequirements.test.ts`. Sigue el estilo del fichero (mismo
`describe`/`it`, mismos helpers si los hay); si el fichero ya construye objetos
`RequestRequirements` / `OfferCapabilities` con un helper, **úsalo en vez de escribir literales a
mano**. Este es el conjunto de casos, espejo del de la app:

```ts
describe("requirementCoverage", () => {
  const pideTodo: RequestRequirements = {
    withShipping: true,
    withInstallation: true,
    requiresEvaluation: true,
    requiresFiscalReceipt: true,
    requiresStateSupplier: true,
  };
  const nada: OfferCapabilities = {
    offersShipping: false,
    offersInstallation: false,
    hasFiscalReceipt: false,
    isStateSupplier: false,
  };
  const todo: OfferCapabilities = {
    offersShipping: true,
    offersInstallation: true,
    hasFiscalReceipt: true,
    isStateSupplier: true,
  };
  const sinNada: RequestRequirements = {
    withShipping: false,
    withInstallation: false,
    requiresEvaluation: false,
    requiresFiscalReceipt: false,
    requiresStateSupplier: false,
  };

  it("sin condiciones marcadas no devuelve filas", () => {
    expect(requirementCoverage(sinNada, nada)).toEqual([]);
  });

  it("solo evaluación tampoco devuelve filas: no es cotejable", () => {
    expect(
      requirementCoverage({ ...sinNada, requiresEvaluation: true }, nada),
    ).toEqual([]);
  });

  it("conserva las cubiertas y las no cubiertas, no solo los fallos", () => {
    const filas = requirementCoverage(
      { ...sinNada, withShipping: true, requiresFiscalReceipt: true },
      { ...nada, offersShipping: true },
    );
    expect(filas.map((f) => f.key)).toEqual(["shipping", "fiscal"]);
    expect(filas.map((f) => f.covered)).toEqual([true, false]);
  });

  it("las cuatro marcadas y la oferta sin declarar nada: cuatro filas en falso", () => {
    const filas = requirementCoverage(pideTodo, nada);
    expect(filas.map((f) => f.key)).toEqual([
      "shipping",
      "installation",
      "fiscal",
      "state",
    ]);
    expect(filas.every((f) => !f.covered)).toBe(true);
  });

  it("ofrecer de más no añade filas", () => {
    const filas = requirementCoverage(
      { ...sinNada, requiresFiscalReceipt: true },
      todo,
    );
    expect(filas.map((f) => f.key)).toEqual(["fiscal"]);
    expect(filas[0]!.covered).toBe(true);
  });

  it("el orden lo fija VERIFIABLE_KEYS, no el de los campos", () => {
    const filas = requirementCoverage(
      {
        ...sinNada,
        requiresStateSupplier: true,
        withShipping: true,
        requiresFiscalReceipt: true,
      },
      nada,
    );
    expect(filas.map((f) => f.key)).toEqual(["shipping", "fiscal", "state"]);
  });

  it("la etiqueta cubierta empieza en mayúscula y no lleva coletilla", () => {
    const filas = requirementCoverage(
      { ...sinNada, requiresFiscalReceipt: true },
      { ...nada, hasFiscalReceipt: true },
    );
    expect(filas[0]!.label).toBe("Comprobante fiscal");
  });

  it('la etiqueta no cubierta dice "no lo declaró"', () => {
    const filas = requirementCoverage(
      { ...sinNada, requiresStateSupplier: true },
      nada,
    );
    expect(filas[0]!.label).toBe("Suplidor del Estado — no lo declaró");
  });

  it("el copy NUNCA afirma un negativo sobre el proveedor", () => {
    // `false` significa hoy dos cosas: "lo vio y no lo marcó" y "ofertó antes de
    // que la pregunta existiera" — 33 de 34 ofertas son del segundo caso.
    for (const f of requirementCoverage(pideTodo, nada)) {
      expect(f.label).not.toContain("no cumple");
      expect(f.label).not.toContain("no emite");
    }
  });

  it("dice exactamente lo mismo que la app", () => {
    // El copy es lo único que puede divergir entre los dos frentes y nada más
    // lo vigila. Si cambias uno, cambia el otro:
    // app/lib/domain/request_requirements.dart → `_coverageLabel`.
    const filas = requirementCoverage(pideTodo, { ...nada, offersShipping: true });
    expect(filas.map((f) => f.label)).toEqual([
      "Envío",
      "Instalación — no lo declaró",
      "Comprobante fiscal — no lo declaró",
      "Suplidor del Estado — no lo declaró",
    ]);
  });
});
```

Añade `requirementCoverage` (y `RequirementCoverageRow` si el fichero tipa los imports) al `import`
que ya existe al principio del test.

⚠️ Antes de dar por buenos los literales `"Envío"`, `"Instalación"`, `"Comprobante fiscal"` y
`"Suplidor del Estado"`, **léelos de `REQUIREMENT_LABEL` en `src/lib/requestRequirements.ts`** y usa
los `short` reales capitalizados. Si alguno no coincide exactamente, **para y reporta**: significaría
que los dos módulos ya divergían antes de esta tanda.

- [ ] **Step 3: Correr los tests y verificar que fallan**

```bash
npx vitest run src/lib/requestRequirements.test.ts
```

Esperado: FALLA — `requirementCoverage is not a function` o error de TypeScript por el import.

- [ ] **Step 4: Escribir el cotejo**

Añadir al final de `src/lib/requestRequirements.ts`:

```ts
export type RequirementCoverageRow = {
  key: VerifiableKey;
  covered: boolean;
  /** Ya listo para pintar. El componente no compone nada. */
  label: string;
};

/**
 * "Comprobante fiscal" · "Comprobante fiscal — no lo declaró".
 *
 * **"No lo declaró", nunca "no cumple" ni "no emite".** Las columnas son
 * NOT NULL DEFAULT false, así que un `false` puede significar que el proveedor
 * vio la casilla —y hasta el aviso previo a enviar— y no la marcó, o que ofertó
 * antes de que la pregunta existiera. Afirmar el negativo sería mentir sobre
 * proveedores reales.
 */
function coverageLabel(key: VerifiableKey, covered: boolean): string {
  const s = REQUIREMENT_LABEL[key].short;
  const capitalizado = s.charAt(0).toUpperCase() + s.slice(1);
  return covered ? capitalizado : `${capitalizado} — no lo declaró`;
}

/**
 * Cada requisito cotejable que el cliente pidió, con si esta oferta lo cubre y
 * con el texto ya compuesto, en orden canónico.
 *
 * Es el hermano de `unmetRequirements` para el OTRO lector. Aquel se queda solo
 * con los fallos porque el proveedor necesita saber qué corregir; este conserva
 * las dos mitades porque el cliente necesita ver también lo que SÍ cubre.
 *
 * Devuelve el texto, y no solo la clave, a propósito: es lo único que puede
 * divergir entre la web y la app, aquí se prueba, y así el `.tsx` queda sin
 * decisiones — que importa porque este repo no tiene tests de componente.
 *
 * Espejo de `requirementCoverage` en
 * `jayalo-app/app/lib/domain/request_requirements.dart`. Si cambias uno, cambia
 * el otro.
 */
export function requirementCoverage(
  req: RequestRequirements,
  cap: OfferCapabilities,
): RequirementCoverageRow[] {
  return VERIFIABLE_KEYS.filter((k) => REQUIRED_BY[k](req)).map((k) => {
    const covered = COVERED_BY[k](cap);
    return { key: k, covered, label: coverageLabel(k, covered) };
  });
}
```

Si `REQUIRED_BY` o `COVERED_BY` estuvieran tipados solo para `RequirementKey`, indexarlos con una
`VerifiableKey` compila igual porque `VerifiableKey` es un subconjunto. Si `tsc` se queja, **no
metas un `as any`**: reporta el error exacto.

- [ ] **Step 5: Verde completo de la web**

```bash
npx vitest run src/lib/requestRequirements.test.ts
npx tsc --noEmit
npm run lint
npm test
```

Esperado: los 10 casos nuevos en verde, `tsc` y `lint` sin errores, y la suite completa en la línea
base del Step 1 **+10**.

- [ ] **Step 6: Commit** (en el repo de la web)

```bash
git add src/lib/requestRequirements.ts src/lib/requestRequirements.test.ts
git commit -m "feat: el cotejo que ve el cliente, con el texto ya compuesto

Espejo exacto de requirementCoverage en la app. Devuelve el texto y no solo la
clave a proposito: es lo unico que puede divergir entre los dos frentes, aqui se
prueba, y asi el .tsx queda sin decisiones — que importa porque este repo no
tiene tests de componente (vitest corre en environment node, sin jsdom).

Un test compara los cuatro textos literales contra los de la app, que es lo
unico que vigila que no divergan.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: El cliente lo ve en la web

**Repo: WEB.** **Files:**
- Create: `src/components/marketplace/OfferRequirementCoverage.tsx`
- Modify: `src/routes/requests/$requestId.tsx`

**Interfaces:**
- Consumes: de la Task 4, `requirementCoverage` y `RequirementCoverageRow`; del módulo,
  `requirementsFromRow` (ya importado en el fichero, línea ~90).
- Produces: nada que consuman otras tareas.

**Sin tests**, y no por pereza: este repo no tiene infraestructura para probar componentes —
`vitest.config.ts` corre con `environment: "node"`, no hay `jsdom` ni `@testing-library/react`, y
ningún `.tsx` del repo tiene test, ni siquiera `RequestRequirementBadges.tsx`. Montarla se descartó
por decisión del PO. Por eso el componente **no puede tener ni una decisión dentro**: todo lo que
podría estar mal ya se probó en la Task 4. Se verifica en el navegador (Task 6).

- [ ] **Step 1: Traer las dos columnas**

En `src/routes/requests/$requestId.tsx`, en el `select` de la carga inicial de ofertas (~línea 388,
el que empieza por `"id,business_id,price,...`), añadir al final de la cadena, antes de la comilla de
cierre:

```
,has_fiscal_receipt,is_state_supplier
```

El otro `provider_offers` de este fichero (~línea 822) es un `update` de rechazo: **no se toca**.

Sin riesgo de permisos: verificado contra `information_schema` que `anon` y `authenticated` tienen
`SELECT` sobre las dos columnas. Si aun así la consulta empezara a devolver 42501, **para y
reporta** — significaría que alguien cambió los grants después del 2026-08-03.

- [ ] **Step 2: Llevarlas hasta la tarjeta**

En el tipo `OfferExtras` (~línea 263), añadir al final:

```ts
  has_fiscal_receipt: boolean | null;
  is_state_supplier: boolean | null;
```

Y en el `extrasMap` que se construye con esas filas (~línea 405-414), junto a los demás campos:

```ts
          has_fiscal_receipt: o.has_fiscal_receipt,
          is_state_supplier: o.is_state_supplier,
```

`OfferExtras` es el sitio correcto y no el objeto normalizado de `realOffers`: ese tiene forma
compartida con los mocks, y estos dos campos son crudos de la fila.

- [ ] **Step 3: Escribir el componente**

Crear `src/components/marketplace/OfferRequirementCoverage.tsx`:

```tsx
import { Check, Minus } from "lucide-react";
import { cn } from "@/lib/utils";
import type { RequirementCoverageRow } from "@/lib/requestRequirements";

type Props = {
  rows: RequirementCoverageRow[];
  className?: string;
};

/**
 * Lo que el cliente exigió en su solicitud y si ESTA oferta lo cubre.
 *
 * **Sin una sola decisión dentro**: recibe las filas ya cotejadas y con el texto
 * compuesto por `requirementCoverage`, que es donde se prueba todo. Este repo no
 * tiene tests de componente (vitest corre en `environment: "node"`), así que
 * cualquier lógica que se cuele aquí queda sin cubrir.
 *
 * Lista vacía → no pinta nada. El ~60% de las solicitudes no pide condiciones y
 * sus tarjetas no deben crecer.
 *
 * Tono neutro también en el negativo (decisión PO): sin ámbar ni alarma. Un
 * `false` puede ser una oferta anterior a que la pregunta existiera.
 */
export function OfferRequirementCoverage({ rows, className }: Props) {
  if (rows.length === 0) return null;
  return (
    <div className={cn("mt-2", className)}>
      <p className="text-[11px] font-semibold text-muted-foreground">Tus condiciones</p>
      <ul className="mt-0.5 space-y-0.5">
        {rows.map((r) => (
          <li key={r.key} className="flex items-start gap-1.5 text-[11.5px] text-muted-foreground">
            {r.covered ? (
              <Check className="mt-0.5 h-3 w-3 shrink-0" aria-hidden />
            ) : (
              <Minus className="mt-0.5 h-3 w-3 shrink-0" aria-hidden />
            )}
            <span>{r.label}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

- [ ] **Step 4: Enchufarlo en la tarjeta**

En `src/routes/requests/$requestId.tsx`, importarlo junto a los demás componentes:

```ts
import { OfferRequirementCoverage } from "@/components/marketplace/OfferRequirementCoverage";
```

Dentro del `sortedOffers.map((o) => { ... })` (~línea 1373), junto a las demás constantes que ya se
calculan ahí (`const ex = offerExtras[o.id];` y compañía), añadir:

```ts
                    // Los requisitos son de la SOLICITUD; las capacidades, de
                    // ESTA oferta. `real` es la fila de customer_requests que ya
                    // usa `requirementsFromRow` más arriba en este mismo fichero.
                    const coverage = requirementCoverage(requirementsFromRow(real), {
                      offersShipping: !!o.offersShipping,
                      offersInstallation: !!o.offersInstallation,
                      hasFiscalReceipt: !!ex?.has_fiscal_receipt,
                      isStateSupplier: !!ex?.is_state_supplier,
                    });
```

Añade `requirementCoverage` al import que ya trae `requirementsFromRow` (~línea 90).

Si la variable de la solicitud no se llamara `real` en ese ámbito, usa la que sí — es la misma que
alimenta `requirementsFromRow(real)` en la línea ~1135. Compruébalo, **no lo asumas**.

Y pintarlo dentro de la tarjeta, al final del bloque de contenido de la derecha (el que muestra
precio, nombre y comentario), después del comentario de la oferta:

```tsx
                            <OfferRequirementCoverage rows={coverage} />
```

Va al final a propósito: precio y nombre son lo que el cliente escanea; el cotejo es lo que mira
cuando ya se fijó en una oferta. Si la estructura de esa tarjeta no deja un sitio evidente,
**para y reporta con el fragmento** en vez de reorganizarla.

- [ ] **Step 5: Verde completo de la web**

```bash
npx tsc --noEmit
npm run lint
npm test
```

Esperado: los tres sin errores y la suite en el mismo número que dejó la Task 4.

- [ ] **Step 6: Commit** (repo de la web)

```bash
git add src/components/marketplace/OfferRequirementCoverage.tsx "src/routes/requests/\$requestId.tsx"
git commit -m "feat: el cliente ve en cada oferta si cubre sus condiciones

Cierra el circuito: el cliente marcaba condiciones, el proveedor declaraba si
las cumplia, y ese dato no lo leia nadie.

Las dos columnas viajan por OfferExtras y no por el objeto normalizado de
realOffers, que comparte forma con los mocks. El componente no tiene ni una
decision dentro porque este repo no puede probar componentes: todo lo que podria
estar mal vive en requirementCoverage, que si esta probado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Verificación y guion de smoke

**Repos: los dos.** **Files:**
- Create: `docs/qa/2026-08-03-smoke-cotejo-visible-cliente.md` (en el repo de la **app**, desde su
  raíz)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el guion que se ejecuta a mano.

- [ ] **Step 1: Verde final de la app**

Desde `app/`:

```bash
flutter analyze
flutter test
```

Esperado: `No issues found!` y verde con **723 tests**. Si el número no cuadra, dilo con el número
real en vez de buscar por qué.

- [ ] **Step 2: Verde final de la web**

Desde la raíz de la web:

```bash
npx tsc --noEmit
npm run lint
npm test
```

Esperado: los tres limpios.

- [ ] **Step 3: Verificar que el release de la app compila**

Desde `app/`:

```bash
flutter build apk --release
```

Esperado: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Tarda varios minutos; **no lo
abandones por lento**. Si falla, reporta la salida real sin intentar arreglarlo moviendo
dependencias.

- [ ] **Step 4: Escribir el guion de smoke**

Crear `docs/qa/2026-08-03-smoke-cotejo-visible-cliente.md` en el repo de la app:

```markdown
# Smoke — el cliente ve si la oferta cubre sus condiciones (2026-08-03)

Un APK de debug **no se instala encima de un release**: desinstalar primero.

Nada del cableado está cubierto por tests, en ninguno de los dos frentes: en la app porque
`request_status_screen` no tiene costura, en la web porque el repo no tiene tests de componente.
Todo lo que sigue solo se verifica aquí.

## 0. Los datos, primero

**Sin esto, todo lo demás sale en negativo y parecerá roto.** De las 34 ofertas que existían al
escribir esto, 33 son anteriores a que la pregunta existiera y llevan `false` en las dos columnas.

- [ ] Con la cuenta de cliente, crear una solicitud marcando **"requiere comprobante fiscal"** y
      **"requiere ser suplidor del Estado"**.
- [ ] Con la cuenta de proveedor, ofertar en ella **marcando comprobante fiscal y NO Estado**.
- [ ] Con otra cuenta de proveedor (o tras cambiar el negocio), ofertar **sin marcar ninguna** —
      saldrá el aviso de la tanda B; pulsar "Enviar de todos modos".

## 1. La app

- [ ] Como cliente, abrir la solicitud y ver las ofertas.
- [ ] La primera oferta muestra "Tus condiciones" con **"Comprobante fiscal"** en positivo y
      **"Suplidor del Estado — no lo declaró"**.
- [ ] La segunda muestra las dos en "no lo declaró".
- [ ] **En ninguna aparecen las palabras "no cumple" ni "no emite".**
- [ ] Las filas salen en orden: comprobante fiscal antes que suplidor del Estado.

## 2. La app, sin condiciones

- [ ] Abrir una solicitud que **no** pidiera nada (o crear una sin marcar ninguna casilla) y ver sus
      ofertas.
- [ ] **No aparece el bloque "Tus condiciones" por ningún lado.** La tarjeta se ve como antes.

## 3. La app, solo evaluación

- [ ] Una solicitud que pida **solo** "requiere evaluación", con una oferta cualquiera.
- [ ] **Tampoco aparece el bloque.** La evaluación no es cotejable: que el proveedor no la marque
      significa precio en firme sin visita, y eso favorece al cliente.

## 4. La web, las mismas cuatro comprobaciones

- [ ] Abrir la misma solicitud del punto 0 en el detalle de la web, como cliente.
- [ ] Los textos son **exactamente los mismos** que en la app, palabra por palabra. Cualquier
      diferencia es una divergencia entre los dos módulos y hay que reportarla.
- [ ] Solicitud sin condiciones → no aparece el bloque.
- [ ] Solicitud con solo evaluación → no aparece el bloque.

## 5. La web sin sesión

- [ ] Abrir el detalle de esa solicitud en una ventana privada, **sin iniciar sesión**.
- [ ] La página carga y las ofertas se ven. Si diera un error de permisos, parar: significaría que
      `anon` perdió el `SELECT` sobre las dos columnas nuevas.

## 6. Una oferta vieja

- [ ] Abrir una solicitud anterior al 1 de agosto que pidiera comprobante fiscal.
- [ ] Sus ofertas dicen "no lo declaró", **nunca** que el proveedor no lo emite. Es justo el caso por
      el que el copy está redactado así.

## 7. Modo oscuro

- [ ] El bloque en oscuro, en la app y en la web.
```

- [ ] **Step 5: Commit** (repo de la app)

```bash
git add docs/qa/2026-08-03-smoke-cotejo-visible-cliente.md
git commit -m "docs(app): guion de smoke del cotejo visible para el cliente

Empieza por crear los datos a proposito: 33 de las 34 ofertas que existen son
anteriores a que la pregunta existiera y llevan false, asi que un smoke que solo
mire ofertas viejas veria todo en negativo y pareceria roto.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Reportar el estado**

Informar: número final de tests de la app, resultado de `flutter analyze`, resultado de `tsc`, `lint`
y `npm test` de la web, si el APK compiló, y qué puntos del smoke quedan pendientes. **No** dar el
trabajo por cerrado hasta que el smoke se haya ejecutado: el cableado no lo cubre ningún test en
ninguno de los dos frentes.
