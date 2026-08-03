# Capacidades del proveedor y aviso de cotejo — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el proveedor declare en su oferta si emite comprobante fiscal y si es suplidor del
Estado, que eso se coteje contra lo que el cliente pidió, y que un aviso no bloqueante se lo
advierta antes de enviar una oferta que se queda corta.

**Architecture:** El módulo puro `domain/request_requirements.dart` —creado en la tanda A— se
completa con las capacidades de la oferta y el cotejo. El aviso vive en su propio widget, testeable
aislado. `repos.dart` gana una lectura de las capacidades del negocio y dos campos en el `insert` de
la oferta, **nunca en el payload que comparte con la edición**. La pantalla del detalle cablea las
tres piezas. Ninguna migración: las columnas y los permisos ya existen.

**Tech Stack:** Flutter (Dart 3, records y patterns), Supabase (PostgREST vía `supabase_flutter`),
`flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-02-capacidades-proveedor-app-design.md`

## Global Constraints

- Repo: `C:\Users\ac\Downloads\jayalo-app`, rama `feat/requisitos-solicitud-app`. El código Flutter
  vive bajo `app/`; los comandos `flutter` se corren **desde `app/`**. `docs/` cuelga de la raíz.
- **Cero cambios de base de datos.** Las columnas `has_fiscal_receipt` / `is_state_supplier` ya
  existen en `provider_businesses` y en `provider_offers`, con sus permisos, desde las migraciones
  de la web del 2026-08-01 y 2026-08-02. Si una tarea parece necesitar una migración, parar y
  reportar.
- **⚠️ LA TRAMPA DE TODA LA TANDA.** `provider_offers` tiene `INSERT` a nivel de tabla pero el
  `UPDATE` de esas dos columnas está **denegado a propósito** (son una foto del momento de ofertar).
  El mapa de payload `_offerFields` lo **comparten** `makeOffer` y `updateOffer`. Si los dos campos
  entran ahí, el `UPDATE` los incluirá, PostgREST tumbará la fila entera por falta de permiso y
  **"mejorar oferta" dejará de funcionar del todo**. Los campos van SOLO en el `insert` de
  `makeOffer`.
- **La evaluación NUNCA entra en el cotejo.** En la solicitud significa "quiero que vengan a ver
  antes de cotizar"; en la oferta, "necesito ir a ver para dar precio". Que el proveedor no la marque
  significa precio en firme sin visita, que favorece al cliente.
- Orden canónico en todo: envío → instalación → evaluación → fiscal → Estado.
- Los textos de las etiquetas ya existen en el módulo de dominio y **no se reescriben**.
- Comentarios y mensajes de commit en español, estilo del repo (`feat(app):`, `test(app):`,
  `docs(app):`). Cada commit termina con `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- La suite parte de **688 tests en verde** (medido en `c61ab09`). Ningún commit puede dejarla en rojo
  ni bajar ese número.

## Estructura de ficheros

**Se crean:**

| Fichero | Responsabilidad |
|---|---|
| `app/lib/features/provider/offer_requirements_warning.dart` | El diálogo del aviso. Recibe la lista de requisitos sin cubrir, devuelve si continuar. |
| `app/test/offer_requirements_warning_test.dart` | Pruebas del diálogo. |
| `docs/qa/2026-08-02-smoke-capacidades-proveedor.md` | Guion de smoke en device. |

**Se modifican:**

| Fichero | Qué cambia |
|---|---|
| `app/lib/domain/request_requirements.dart` | `OfferCapabilities`, `verifiableRequirements`, `unmetRequirements`, `unmetRequirementsMessage`. |
| `app/test/domain/request_requirements_test.dart` | Pruebas del cotejo. |
| `app/lib/data/repos.dart` | `myBusinessForOffer()`, `offerFields` público, dos campos en el `insert`. |
| `app/test/repos_test.dart` | La prueba que blinda la trampa del payload compartido. |
| `app/lib/features/provider/request_detail_screen.dart` | Dos interruptores, prellenado, modo edición y el aviso en `_submit`. |

---

### Task 1: El cotejo en el módulo de dominio

**Files:**
- Modify: `app/lib/domain/request_requirements.dart`
- Test: `app/test/domain/request_requirements_test.dart`

**Interfaces:**
- Consumes: del propio módulo, `enum Requirement`, `class RequestRequirements` (con `bool has(Requirement)`),
  `activeRequirements(req, {keys})` y `requirementLabel(r)` que devuelve `({String chip, String short, String hint})`.
- Produces:
  - `class OfferCapabilities` con constructor const nombrado: `offersShipping`, `offersInstallation`,
    `hasFiscalReceipt`, `isStateSupplier`, todos `bool` con default `false`; y `static const none`.
  - `const List<Requirement> verifiableRequirements`
  - `List<Requirement> unmetRequirements(RequestRequirements req, OfferCapabilities cap)`
  - `String unmetRequirementsMessage(List<Requirement> keys)`

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `app/test/domain/request_requirements_test.dart`, antes del `}` que cierra `main()`:

```dart
  group('unmetRequirements', () {
    const pideTodo = RequestRequirements(
      withShipping: true,
      withInstallation: true,
      requiresEvaluation: true,
      requiresFiscalReceipt: true,
      requiresStateSupplier: true,
    );

    test('una oferta que no cubre nada incumple los cuatro cotejables', () {
      expect(unmetRequirements(pideTodo, OfferCapabilities.none), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('la evaluación NUNCA se reporta, aunque el cliente la pida y la oferta no la marque', () {
      // En la solicitud significa "quiero que vengan a ver antes de cotizar";
      // en la oferta, "necesito ir a ver para dar precio". Que el proveedor no
      // la marque significa precio en firme sin visita: favorece al cliente.
      expect(
        unmetRequirements(
          const RequestRequirements(requiresEvaluation: true),
          OfferCapabilities.none,
        ),
        isEmpty,
      );
    });

    test('una oferta que lo cubre todo no incumple nada', () {
      expect(
        unmetRequirements(
          pideTodo,
          const OfferCapabilities(
            offersShipping: true,
            offersInstallation: true,
            hasFiscalReceipt: true,
            isStateSupplier: true,
          ),
        ),
        isEmpty,
      );
    });

    test('ofrecer de más no cuenta como incumplimiento', () {
      expect(
        unmetRequirements(
          const RequestRequirements(requiresFiscalReceipt: true),
          const OfferCapabilities(
            offersShipping: true,
            offersInstallation: true,
            hasFiscalReceipt: true,
            isStateSupplier: true,
          ),
        ),
        isEmpty,
      );
    });

    test('solo reporta lo que el cliente pidió y la oferta no cubre', () {
      expect(
        unmetRequirements(
          const RequestRequirements(
            withShipping: true,
            requiresStateSupplier: true,
          ),
          const OfferCapabilities(offersShipping: true),
        ),
        [Requirement.state],
      );
    });

    test('el resultado sale en orden canónico', () {
      expect(
        unmetRequirements(
          const RequestRequirements(
            requiresStateSupplier: true,
            withShipping: true,
            requiresFiscalReceipt: true,
          ),
          OfferCapabilities.none,
        ),
        [Requirement.shipping, Requirement.fiscal, Requirement.state],
        reason: 'el orden lo fija la declaración del enum, no el de los campos',
      );
    });

    test('sin requisitos activos no hay nada que incumplir', () {
      expect(
        unmetRequirements(RequestRequirements.none, OfferCapabilities.none),
        isEmpty,
      );
    });
  });

  group('verifiableRequirements', () {
    test('son cuatro, en orden canónico, y la evaluación no está', () {
      expect(verifiableRequirements, [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
      expect(verifiableRequirements, isNot(contains(Requirement.evaluation)));
    });
  });

  group('unmetRequirementsMessage', () {
    test('lista vacía da cadena vacía', () {
      expect(unmetRequirementsMessage(const []), '');
    });

    test('uno solo va suelto', () {
      expect(unmetRequirementsMessage(const [Requirement.shipping]), 'envío');
    });

    test('dos se unen con "y"', () {
      expect(
        unmetRequirementsMessage(const [Requirement.shipping, Requirement.fiscal]),
        'envío y comprobante fiscal',
      );
    });

    test('tres llevan coma y la última con "y"', () {
      expect(
        unmetRequirementsMessage(const [
          Requirement.shipping,
          Requirement.fiscal,
          Requirement.state,
        ]),
        'envío, comprobante fiscal y suplidor del Estado',
      );
    });

    test('usa los textos cortos, no los de chip', () {
      expect(
        unmetRequirementsMessage(const [Requirement.state]),
        isNot(contains('Requiere')),
      );
    });
  });
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Desde `app/`:

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: FALLA en compilación — `Undefined name 'OfferCapabilities'`, `The function 'unmetRequirements' isn't defined`, `Undefined name 'verifiableRequirements'`.

- [ ] **Step 3: Escribir el cotejo**

En `app/lib/domain/request_requirements.dart`, **sustituir** el párrafo del doc de librería que dice
lo que falta:

```dart
/// Lo que NO está aquí, a propósito: `OfferCapabilities` y el cotejo contra lo
/// que declara una oferta (`unmetRequirements`). Eso lo necesita la tanda B
/// —declarar capacidades del proveedor y avisar antes de enviar la oferta— y
/// escribirlo ahora sería código muerto.
```

por:

```dart
/// Incluye también el lado del PROVEEDOR (`OfferCapabilities`) y el cotejo
/// entre ambos (`unmetRequirements`): qué pide el cliente, qué declara la
/// oferta, y qué falta. Las dos mitades viven juntas a propósito — separarlas
/// invitaría a que cada una redactara sus etiquetas por su cuenta.
```

Y añadir al final del fichero, después de `requirementLabel`:

```dart

/// Lo que el PROVEEDOR declara en su oferta (columnas de `provider_offers`).
class OfferCapabilities {
  const OfferCapabilities({
    this.offersShipping = false,
    this.offersInstallation = false,
    this.hasFiscalReceipt = false,
    this.isStateSupplier = false,
  });

  final bool offersShipping;
  final bool offersInstallation;
  final bool hasFiscalReceipt;
  final bool isStateSupplier;

  /// Oferta que no declara nada. Es el default seguro: si la lectura de las
  /// capacidades del negocio falla, se avisa de más (el proveedor lo marca y
  /// sigue) y nunca se afirma de menos en su nombre.
  static const none = OfferCapabilities();

  bool covers(Requirement r) => switch (r) {
    Requirement.shipping => offersShipping,
    Requirement.installation => offersInstallation,
    Requirement.fiscal => hasFiscalReceipt,
    Requirement.state => isStateSupplier,
    // La evaluación no es cotejable: ver `verifiableRequirements`. Nadie
    // debería preguntarlo, pero el `switch` tiene que ser exhaustivo y
    // responder algo honesto — "esta oferta no la cubre" es lo único cierto.
    Requirement.evaluation => false,
  };
}

/// Los cuatro requisitos que SÍ se pueden cotejar contra lo que declara una
/// oferta.
///
/// La evaluación queda fuera **a propósito**. En la solicitud significa "quiero
/// que vengan a ver antes de cotizar"; en la oferta, "necesito ir a ver para
/// poder dar precio". Que el proveedor NO la marque quiere decir que da precio
/// en firme sin visita — eso favorece al cliente. Avisarlo como incumplimiento
/// sería regañar al proveedor por hacerlo bien.
const verifiableRequirements = <Requirement>[
  Requirement.shipping,
  Requirement.installation,
  Requirement.fiscal,
  Requirement.state,
];

/// Los requisitos cotejables que el cliente pidió y esta oferta NO cubre, en
/// orden canónico. Nunca reporta la evaluación ni las capacidades que la oferta
/// ofrece de más.
List<Requirement> unmetRequirements(
  RequestRequirements req,
  OfferCapabilities cap,
) => [
  for (final r in activeRequirements(req, keys: verifiableRequirements))
    if (!cap.covers(r)) r,
];

/// "envío, comprobante fiscal y suplidor del Estado" — para el aviso previo al
/// envío. Usa los textos `short`, no los de chip: va dentro de una frase.
String unmetRequirementsMessage(List<Requirement> keys) {
  final partes = [for (final k in keys) requirementLabel(k).short];
  if (partes.isEmpty) return '';
  if (partes.length == 1) return partes.first;
  return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
}
```

- [ ] **Step 4: Correr los tests y verificar que pasan**

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: PASA, con los 13 casos nuevos.

- [ ] **Step 5: Analizar y correr la suite completa**

```bash
flutter analyze lib test
flutter test
```

Esperado: `No issues found!` y suite en verde con **701 tests** (688 + 13).

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/request_requirements.dart app/test/domain/request_requirements_test.dart
git commit -m "feat(app): el cotejo entre lo que pide el cliente y lo que declara la oferta

Completa el modulo puro con el hueco que la tanda A dejo preparado: el campo
short de las etiquetas se escribio para esta frase y hasta ahora no lo usaba
nadie. La evaluacion queda fuera del cotejo a proposito y con su motivo escrito:
que el proveedor no la marque significa precio en firme sin visita, que favorece
al cliente.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: El diálogo del aviso

**Files:**
- Create: `app/lib/features/provider/offer_requirements_warning.dart`
- Test: `app/test/offer_requirements_warning_test.dart`

**Interfaces:**
- Consumes: de la Task 1, `Requirement` y `unmetRequirementsMessage`; del módulo, `requirementLabel(r)`
  que devuelve `({String chip, String short, String hint})`.
- Produces:
  `Future<bool> showOfferRequirementsWarning(BuildContext context, List<Requirement> unmet)`
  — devuelve `true` si el proveedor eligió enviar de todos modos, `false` si eligió editar o
  descartó el diálogo tocando fuera.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/offer_requirements_warning_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/provider/offer_requirements_warning.dart';

void main() {
  /// Monta un botón que abre el aviso y guarda lo que devuelve. Sin esto no hay
  /// forma de probar un diálogo: necesita un `BuildContext` bajo un `Navigator`.
  Future<bool?> abrir(WidgetTester tester, List<Requirement> unmet) async {
    bool? resultado;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await showOfferRequirementsWarning(context, unmet);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  testWidgets('lista cada requisito sin cubrir con su etiqueta y su explicación',
      (tester) async {
    await abrir(tester, const [Requirement.fiscal, Requirement.state]);

    expect(find.text('El cliente pide algo que tu oferta no cubre'), findsOneWidget);
    expect(find.text('Requiere comprobante fiscal'), findsOneWidget);
    expect(
      find.text('El proveedor debe poder emitir comprobante fiscal (NCF).'),
      findsOneWidget,
    );
    expect(find.text('Requiere suplidor del Estado'), findsOneWidget);
    expect(find.textContaining('comprobante fiscal y suplidor del Estado'),
        findsOneWidget);
  });

  testWidgets('los requisitos salen en orden canónico', (tester) async {
    await abrir(tester, const [
      Requirement.shipping,
      Requirement.fiscal,
      Requirement.state,
    ]);

    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      textos.indexOf('Requiere envío') < textos.indexOf('Requiere comprobante fiscal'),
      isTrue,
    );
    expect(
      textos.indexOf('Requiere comprobante fiscal') <
          textos.indexOf('Requiere suplidor del Estado'),
      isTrue,
    );
  });

  testWidgets('devuelve true al enviar de todos modos y false al editar',
      (tester) async {
    bool? resultado;
    Future<void> montar(List<Requirement> unmet) async {
      await tester.pumpWidget(MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultado = await showOfferRequirementsWarning(context, unmet);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    await montar(const [Requirement.fiscal]);
    await tester.tap(find.text('Enviar de todos modos'));
    await tester.pumpAndSettle();
    expect(resultado, isTrue);

    await montar(const [Requirement.fiscal]);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(resultado, isFalse);
  });

  testWidgets('el copy no promete que el cliente lo verá', (tester) async {
    // Hoy nadie lee `provider_offers.has_fiscal_receipt`, ni en la app ni en la
    // web. El texto dice que queda registrado, no que el cliente lo verá: si
    // alguien lo cambia, que este test lo pare hasta que sea verdad.
    await abrir(tester, const [Requirement.fiscal]);
    expect(find.textContaining('quedará registrado'), findsOneWidget);
    expect(find.textContaining('el cliente verá'), findsNothing);
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/offer_requirements_warning_test.dart
```

Esperado: FALLA en compilación — `Target of URI doesn't exist: 'package:jayalo_app/features/provider/offer_requirements_warning.dart'`.

- [ ] **Step 3: Escribir el diálogo**

Crear `app/lib/features/provider/offer_requirements_warning.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/request_requirements.dart';

/// Aviso previo al envío cuando la oferta no cubre algo que el cliente marcó
/// como condición. **No bloquea nunca**: el proveedor decide.
///
/// Devuelve `true` si eligió enviar de todos modos; `false` si eligió editar o
/// descartó el diálogo. Se espera DENTRO del manejador de enviar, así que no
/// hay ningún "ya lo acusé" que guardar en el estado de la pantalla —ni que
/// reiniciar, ni que se pueda quedar pegado. La web sí lo guarda, y que ese
/// acuse sobreviviera a un cambio de negocio fue el único bug serio de aquella
/// rama.
Future<bool> showOfferRequirementsWarning(
  BuildContext context,
  List<Requirement> unmet,
) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('El cliente pide algo que tu oferta no cubre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Esta solicitud requiere ${unmetRequirementsMessage(unmet)} y no lo '
            'marcaste en tu oferta. Si sí lo cumples, edítalo antes de enviar; '
            'si no, quedará registrado en tu oferta que no lo cumples.',
          ),
          const SizedBox(height: 12),
          for (final k in unmet)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requirementLabel(k).chip,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    requirementLabel(k).hint,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Editar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Enviar de todos modos'),
        ),
      ],
    ),
  );
  // Descartar tocando fuera equivale a "no envíes todavía": el default seguro
  // es NO mandar una oferta que el proveedor quizá quería corregir.
  return ok ?? false;
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
flutter test test/offer_requirements_warning_test.dart
```

Esperado: PASA, 4 tests.

- [ ] **Step 5: Analizar y correr la suite completa**

```bash
flutter analyze lib test
flutter test
```

Esperado: `No issues found!` y suite en verde con **705 tests** (701 + 4).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/provider/offer_requirements_warning.dart app/test/offer_requirements_warning_test.dart
git commit -m "feat(app): el aviso de que la oferta no cubre lo que pide el cliente

Diálogo propio para poder probarlo aislado: la pantalla que lo va a usar tiene
1654 lineas y no tiene costura de tests. Se espera dentro del manejador de
enviar y devuelve un si o un no, asi que no hay acuse que guardar en el estado
—ni que reiniciar, ni que se quede pegado, que fue el unico bug serio de la
rama web.

El copy dice que queda registrado, no que el cliente lo vera: hoy nadie lee ese
dato y un test lo blinda.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Las capacidades del negocio y el guardado en la oferta

**Files:**
- Modify: `app/lib/data/repos.dart`
- Test: `app/test/repos_test.dart`

**Interfaces:**
- Consumes: de la Task 1, `OfferCapabilities`.
- Produces:
  - `Future<({String id, bool hasFiscalReceipt, bool isStateSupplier})?> myBusinessForOffer()`
  - `offerFields(...)` — el antiguo `_offerFields`, ahora público, con la misma firma.
  - `makeOffer(...)` con dos parámetros nuevos: `bool hasFiscalReceipt = false`,
    `bool isStateSupplier = false`.

- [ ] **Step 1: Verificar los permisos ANTES de tocar código**

El spec afirma que las columnas existen con `INSERT` a nivel de tabla en `provider_offers`, `SELECT`
en `provider_businesses`, y `UPDATE` **denegado** en las dos columnas de la oferta. Confirmarlo
contra la base, no contra el comentario de la migración: dar un grant por bueno desde un comentario
ya costó una migración de corrección en la web, y dos revisiones no lo vieron.

Correr contra el proyecto `mfaiklvobnvgusbcssbx` con la herramienta `execute_sql` del MCP de
Supabase (las herramientas MCP están diferidas: cargarlas con `ToolSearch` usando
`select:mcp__7fa4466f-3373-4476-92ea-8f676a125d5b__execute_sql`):

```sql
SELECT table_name, column_name, grantee, privilege_type
FROM information_schema.role_column_grants
WHERE table_schema = 'public'
  AND table_name IN ('provider_businesses','provider_offers')
  AND column_name IN ('has_fiscal_receipt','is_state_supplier')
  AND grantee = 'authenticated'
ORDER BY table_name, column_name, privilege_type;
```

Esperado, y hay que comprobar las tres cosas:
1. `provider_businesses` — `SELECT` presente en las dos columnas.
2. `provider_offers` — `INSERT` presente en las dos columnas.
3. `provider_offers` — **`UPDATE` AUSENTE** en las dos columnas.

Si el `UPDATE` apareciera, **parar y reportar**: significaría que alguien concedió ese permiso
después, y el diseño de esta tanda (campos congelados, casillas apagadas al editar) habría dejado de
corresponder con la base. Si faltara el `INSERT` o el `SELECT`, parar igual.

- [ ] **Step 2: Escribir los tests que fallan**

En `app/test/repos_test.dart`, añadir al final de `main()`:

```dart
  group('offerFields', () {
    // El mapa lo COMPARTEN makeOffer y updateOffer. El UPDATE de estas dos
    // columnas está denegado en la base a propósito (son una foto del momento
    // de ofertar), así que si se colaran aquí, PostgREST tumbaría la fila
    // entera y "mejorar oferta" dejaría de funcionar del todo — un fallo que
    // no aparece hasta que alguien edita una oferta. Este test es la única
    // barrera automática que existe contra eso.
    test('NO lleva las capacidades del proveedor', () {
      final fields = offerFields(price: 100.0, message: 'hola');
      expect(fields.containsKey('has_fiscal_receipt'), isFalse);
      expect(fields.containsKey('is_state_supplier'), isFalse);
    });

    test('sigue llevando lo que sí es editable', () {
      final fields = offerFields(price: 100.0, message: 'hola');
      expect(fields['price'], 100.0);
      expect(fields['message'], 'hola');
      expect(fields.containsKey('offers_shipping'), isTrue);
    });
  });
```

- [ ] **Step 3: Correr los tests y verificar que fallan**

```bash
flutter test test/repos_test.dart
```

Esperado: FALLA en compilación — `The function 'offerFields' isn't defined` (hoy se llama
`_offerFields` y es privada).

- [ ] **Step 4: Hacer público el mapa compartido**

En `app/lib/data/repos.dart`, renombrar `_offerFields` a `offerFields` en su declaración y en los
dos sitios que lo llaman (`makeOffer` y `updateOffer`). Y ampliar su doc con la advertencia,
añadiendo este párrafo al final del comentario que ya tiene encima:

```dart
/// ⚠️ **Este mapa lo comparten CREAR y EDITAR, y eso restringe qué puede
/// llevar.** `provider_offers` tiene el `UPDATE` de `has_fiscal_receipt` e
/// `is_state_supplier` DENEGADO a propósito (son una foto de lo que el negocio
/// declaraba al ofertar). Si esas dos columnas entraran aquí, el `UPDATE` las
/// incluiría, PostgREST tumbaría la fila ENTERA por falta de permiso y
/// "mejorar oferta" dejaría de funcionar del todo. Van solo en el `insert` de
/// [makeOffer]. Lo vigila un test en `repos_test.dart`.
///
/// Es público solo para que ese test pueda mirar dentro; no lo llames desde
/// una pantalla.
```

- [ ] **Step 5: Correr los tests y verificar que pasan**

```bash
flutter test test/repos_test.dart
```

Esperado: PASA, con los 2 casos nuevos.

- [ ] **Step 6: Añadir la lectura de las capacidades del negocio**

En `app/lib/data/repos.dart`, justo **debajo** de `myBusinessId()`:

```dart

/// El negocio con el que se oferta, **y** las capacidades que tiene declaradas.
///
/// Existe aparte de [myBusinessId] a propósito: esa la llaman también el estado
/// de sesión, el chat y ajustes, que solo necesitan el id y no deben pagar
/// columnas de más.
///
/// El proveedor declara estas capacidades en la WEB (en la app "Mi tienda" es
/// solo lectura y editar va por magic link). Aquí solo se leen, para premarcar
/// las casillas de la oferta.
Future<({String id, bool hasFiscalReceipt, bool isStateSupplier})?>
myBusinessForOffer() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_businesses')
      .select('id,has_fiscal_receipt,is_state_supplier')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  if (row == null) return null;
  return (
    id: row['id'] as String,
    hasFiscalReceipt: row['has_fiscal_receipt'] == true,
    isStateSupplier: row['is_state_supplier'] == true,
  );
}
```

- [ ] **Step 7: Añadir los dos campos al `insert` de la oferta**

En `makeOffer`, añadir dos parámetros al final de la lista de parámetros nombrados, después de
`String deliveryTime = '',`:

```dart
  // Capacidades declaradas para ESTA oferta. Van aquí y NO en `offerFields`
  // porque su UPDATE está denegado: ver la advertencia de ese mapa.
  bool hasFiscalReceipt = false,
  bool isStateSupplier = false,
```

Y en el `insert`, añadirlos junto a los demás campos de nivel superior, **después** de
`'status': 'pending',` y **antes** de `...fields,`:

```dart
      'has_fiscal_receipt': hasFiscalReceipt,
      'is_state_supplier': isStateSupplier,
```

`updateOffer` **no cambia**.

- [ ] **Step 8: Analizar y correr la suite completa**

```bash
flutter analyze lib test
flutter test
```

Esperado: `No issues found!` y suite en verde con **707 tests** (705 + 2).

- [ ] **Step 9: Commit**

```bash
git add app/lib/data/repos.dart app/test/repos_test.dart
git commit -m "feat(app): leer las capacidades del negocio y guardarlas en la oferta

Los dos campos van SOLO en el insert de makeOffer. El mapa de payload lo
comparte updateOffer, y el UPDATE de esas columnas esta denegado a proposito:
si se colaran ahi, PostgREST tumbaria la fila entera y "mejorar oferta" dejaria
de funcionar, un fallo que no se ve hasta que alguien edita. El mapa pasa a ser
publico solo para que un test pueda comprobar que siguen fuera.

myBusinessForOffer va aparte de myBusinessId porque a esa la llaman tambien la
sesion, el chat y ajustes, que solo quieren el id.

Permisos verificados contra information_schema antes de tocar codigo, incluida
la AUSENCIA del UPDATE.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Los interruptores y el aviso en la pantalla

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
- Modify: `app/lib/data/repos.dart` (solo la constante `offerCols`, en el Step 3)

**Interfaces:**
- Consumes: de la Task 1, `OfferCapabilities`, `unmetRequirements` y `requirementsFromRow`; de la
  Task 2, `showOfferRequirementsWarning`; de la Task 3, `myBusinessForOffer()` y los dos parámetros
  nuevos de `makeOffer`.
- Produces: nada que consuman otras tareas.

**Sin tests.** Este fichero son 1654 líneas y carga con `requestById` directo en `initState`, sin
fuente inyectable: no tiene costura y esta tanda **no la abre**. Las tres piezas que cablea ya están
probadas cada una por su lado; el cableado se verifica en device (Task 5).

- [ ] **Step 1: Importar lo que hace falta**

En la cabecera de `app/lib/features/provider/request_detail_screen.dart`, añadir:

```dart
import '../../domain/request_requirements.dart';
import 'offer_requirements_warning.dart';
```

- [ ] **Step 2: Añadir el estado de las dos capacidades**

En `_ProviderRequestDetailScreenState`, junto a `bool _requiresEvaluation = false;`:

```dart
  // Capacidades transversales (producto Y servicio): se premarcan con lo que el
  // negocio tenga declarado y el proveedor las ajusta para esta oferta.
  bool _hasFiscalReceipt = false;
  bool _isStateSupplier = false;
```

- [ ] **Step 3: Premarcarlas desde el negocio**

En `initState` hay dos llamadas a `myBusinessId()` (una en cada rama: la de edición y la normal).
Sustituir **ambas** por `myBusinessForOffer()`, guardando el id igual que antes y premarcando las
capacidades. El patrón, en los dos sitios:

```dart
      myBusinessForOffer().then((b) {
        if (!mounted) return;
        setState(() {
          _businessId = b?.id;
          // Premarcado, NO imposición: el proveedor puede desmarcarlas para
          // esta oferta. Si la lectura falla, `b` es null y quedan apagadas —
          // el default seguro: se avisa de más, nunca se afirma de menos en
          // nombre del proveedor.
          _hasFiscalReceipt = b?.hasFiscalReceipt ?? false;
          _isStateSupplier = b?.isStateSupplier ?? false;
        });
      });
```

En la rama de EDICIÓN, el premarcado desde el negocio **no aplica**: ahí los valores son los que
quedaron guardados en la oferta. Después de que se cargue la oferta existente (donde ya se leen
campos como `o['requires_evaluation']`), fijar:

```dart
    _hasFiscalReceipt = o['has_fiscal_receipt'] == true;
    _isStateSupplier = o['is_state_supplier'] == true;
```

Para que esos valores lleguen, añadir las dos columnas a la constante `offerCols` de `repos.dart`
(la lista de columnas de `provider_offers` que ya se lee), al final de la cadena:
`',has_fiscal_receipt,is_state_supplier'`.

- [ ] **Step 4: Permitir que `_toggleRow` funcione sin costo y apagado**

`_toggleRow` hoy exige `cost` y `costLabel`, y estas dos capacidades no tienen precio. Cambiar su
firma para que los dos sean opcionales y añadir un `enabled`:

```dart
  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    TextEditingController? cost,
    String? costLabel,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final free = cost != null && (double.tryParse(cost.text) ?? 0) <= 0;
```

En el `Switch`, respetar `enabled`:

```dart
          Switch(
            value: value,
            onChanged: (_busy || !enabled) ? null : onChanged,
          ),
```

Y el bloque del costo solo cuando hay controlador:

```dart
        if (value && cost != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              Expanded(child: _numField(cost, costLabel ?? '')),
```

Las tres llamadas existentes en `_productExtras` siguen pasando `cost` y `costLabel` con nombre, así
que no cambian.

- [ ] **Step 5: Pintar los dos interruptores**

En el `build`, dentro del bloque del formulario, **fuera** del `if (_isService) ... else ...` —es
decir, justo después del `],` que cierra la rama `else` con `_productExtras` y `_productDetails`, y
antes del `const SizedBox(height: 16),` que precede al título de las fotos— insertar:

```dart
          // Transversales: aplican a producto Y servicio, así que van FUERA del
          // bloque de producto. Meterlas dentro las haría invisibles en
          // servicios, que es la trampa que en la web mordió dos veces con los
          // chips del detalle.
          const SizedBox(height: 14),
          _sectionLabel('Lo que puedes cumplir'),
          const SizedBox(height: 8),
          _toggleRow(
            title: 'Emito comprobante fiscal',
            subtitle: _editing
                ? 'Quedó fijado al enviar tu oferta.'
                : 'Puedes emitir comprobante fiscal (NCF).',
            value: _hasFiscalReceipt,
            onChanged: (v) => setState(() => _hasFiscalReceipt = v),
            enabled: !_editing,
          ),
          _toggleRow(
            title: 'Soy suplidor del Estado',
            subtitle: _editing
                ? 'Quedó fijado al enviar tu oferta.'
                : 'Estás registrado como suplidor del Estado.',
            value: _isStateSupplier,
            onChanged: (v) => setState(() => _isStateSupplier = v),
            enabled: !_editing,
          ),
```

- [ ] **Step 6: Disparar el aviso al enviar**

En `_submit()`, después del `switch (mode)` que valida los precios y **antes** de
`final evalOn = ...` (es decir, antes de componer el mensaje y de subir fotos, para que "Editar" no
desperdicie una subida):

```dart
    // Cotejo contra lo que el cliente marcó. Solo al CREAR: en edición las dos
    // capacidades están congeladas (su UPDATE está denegado), así que no habría
    // nada que corregir y el aviso solo estorbaría.
    if (!_editing) {
      final unmet = unmetRequirements(
        requirementsFromRow(req),
        OfferCapabilities(
          offersShipping: _offersShipping,
          offersInstallation: _offersInstallation,
          hasFiscalReceipt: _hasFiscalReceipt,
          isStateSupplier: _isStateSupplier,
        ),
      );
      if (unmet.isNotEmpty) {
        final seguir = await showOfferRequirementsWarning(context, unmet);
        if (!mounted) return;
        if (!seguir) return;
      }
    }
```

Nota: `requirementsFromRow(req)` funciona porque `requestById` ya trae las cinco columnas desde la
tanda A.

- [ ] **Step 7: Pasar las capacidades al `makeOffer`**

En la llamada a `makeOffer` dentro de `_submit`, añadir los dos argumentos:

```dart
        hasFiscalReceipt: _hasFiscalReceipt,
        isStateSupplier: _isStateSupplier,
```

La llamada a `updateOffer` **no cambia**.

- [ ] **Step 8: Analizar y correr la suite completa**

```bash
flutter analyze lib
flutter test
```

Esperado: `No issues found!` y suite en verde con **707 tests** (esta tarea no añade ninguno).

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart app/lib/data/repos.dart
git commit -m "feat(app): declarar comprobante fiscal y suplidor del Estado al ofertar

Los dos interruptores van FUERA del bloque de producto: son transversales, y
meterlos dentro los haria invisibles en servicios — la trampa que en la web
mordio dos veces con los chips. Se premarcan con lo que el negocio declaro y el
proveedor los ajusta para esa oferta.

Al editar salen apagados y con una nota: su UPDATE esta denegado en la base
porque son una foto del momento de ofertar. Y el aviso solo salta al crear,
antes de componer el mensaje y de subir fotos, para que "Editar" no desperdicie
una subida.

Sin tests: este fichero no tiene costura y esta tanda no la abre. Las tres
piezas que cablea si estan probadas por separado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Verificación y guion de smoke

**Files:**
- Create: `docs/qa/2026-08-02-smoke-capacidades-proveedor.md` (ruta desde la raíz del repo, no desde `app/`)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el guion que se ejecuta en device.

- [ ] **Step 1: Analizar todo el proyecto**

Desde `app/`:

```bash
flutter analyze
```

Esperado: `No issues found!`. Cualquier issue es regresión de esta tanda.

- [ ] **Step 2: Correr la suite completa**

```bash
flutter test
```

Esperado: verde, **707 tests**. Si el número es menor, falta algún caso de alguna tarea.

- [ ] **Step 3: Verificar que el release compila**

```bash
flutter build apk --release
```

Esperado: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Puede tardar varios minutos; no
abandonarlo por lentitud. Si falla, reportar la salida real sin intentar arreglarlo moviendo
dependencias.

- [ ] **Step 4: Escribir el guion de smoke**

Crear `docs/qa/2026-08-02-smoke-capacidades-proveedor.md`:

```markdown
# Smoke — capacidades del proveedor y aviso de cotejo (2026-08-02)

Un APK de debug **no se instala encima de un release**: desinstalar primero.

Nada de esto está cubierto por tests. `request_detail_screen.dart` no tiene costura, así que el
cableado entero —premarcado, interruptores, aviso y guardado— solo se verifica aquí.

## 1. Lo que más puede romperse: "mejorar oferta"

Se comprueba PRIMERO porque es lo que se rompería si los dos campos nuevos se colaran en el payload
compartido, y el fallo no se ve por ningún otro lado.

- [ ] Enviar una oferta cualquiera desde la app.
- [ ] Entrar a esa oferta y editarla: cambiar el precio y guardar.
- [ ] **Tiene que guardar sin error.** Si aparece un error de permisos, parar: los campos se
      colaron en el payload de edición.

## 2. Premarcado desde el negocio

- [ ] En la web, en el negocio de la cuenta de proveedor de prueba, marcar "emite comprobante
      fiscal" y dejar sin marcar "suplidor del Estado".
- [ ] En la app, abrir una solicitud y mirar el formulario de oferta: "Emito comprobante fiscal"
      aparece encendido y "Soy suplidor del Estado" apagado.
- [ ] Desmarcar el primero y comprobar que se deja desmarcar: es premarcado, no imposición.

## 3. El aviso

- [ ] Crear una solicitud (con la cuenta de cliente) marcando "requiere comprobante fiscal" y
      "requiere ser suplidor del estado".
- [ ] Con la cuenta de proveedor, ofertar en ella **sin** marcar ninguna de las dos capacidades y
      pulsar enviar.
- [ ] Sale el aviso, con los dos requisitos, cada uno con su explicación, y la frase que los
      enumera ("comprobante fiscal y suplidor del Estado").
- [ ] **Editar** cierra el aviso, no envía nada y deja ver los interruptores.
- [ ] Marcar las dos capacidades y enviar: **no sale ningún aviso** y la oferta se envía.

## 4. La evaluación no dispara el aviso

- [ ] Una solicitud de producto que pida SOLO "requiere evaluación". Ofertar sin marcar evaluación.
- [ ] **No debe salir ningún aviso.** Que el proveedor no la marque significa que da precio en
      firme sin visita, y eso favorece al cliente.

## 5. Servicios

- [ ] Una solicitud de SERVICIO que pida comprobante fiscal. Ofertar en ella.
- [ ] Los dos interruptores están presentes (son transversales; envío e instalación no aparecen en
      servicios, y eso es correcto).
- [ ] Sin marcar comprobante fiscal, al enviar sale el aviso mencionando solo ese requisito.

## 6. Modo edición

- [ ] Entrar a "mejorar oferta" de una oferta ya enviada.
- [ ] Los dos interruptores se ven, **apagados y no tocables**, con la nota "Quedó fijado al enviar
      tu oferta", y muestran lo que se declaró al enviarla.
- [ ] Al guardar cambios **no sale el aviso de cotejo**.

## 7. Fallo de red al abrir

- [ ] Poner el teléfono en modo avión justo antes de abrir el detalle de una solicitud, y volver a
      conectarlo.
- [ ] Los interruptores quedan apagados, no encendidos. Falla del lado seguro: se avisa de más,
      nunca se afirma algo que el proveedor no declaró.

## 8. Modo oscuro

- [ ] Los dos interruptores y el diálogo del aviso, en oscuro.
```

- [ ] **Step 5: Commit**

```bash
git add docs/qa/2026-08-02-smoke-capacidades-proveedor.md
git commit -m "docs(app): guion de smoke de las capacidades del proveedor

Empieza por "mejorar oferta" a proposito: es lo que se rompe si los dos campos
se cuelan en el payload compartido, y ese fallo no se ve por ningun otro lado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Reportar el estado**

Informar: número final de tests, resultado de `flutter analyze`, si el APK de release compiló, y qué
puntos del smoke quedan pendientes. **No** dar el trabajo por cerrado hasta que el smoke se haya
ejecutado: el cableado de la pantalla no lo cubre ningún test, y el punto 1 vigila una regresión que
no se manifiesta hasta que un proveedor edita una oferta.
