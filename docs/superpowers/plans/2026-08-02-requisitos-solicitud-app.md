# Requisitos de la solicitud visibles en la app — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que los cinco requisitos que el cliente marca al crear una solicitud —envío, instalación,
evaluación previa, comprobante fiscal y suplidor del Estado— se vean en las seis pantallas de la app
que muestran una solicitud, con chips en los detalles y símbolos en los listados.

**Architecture:** Un módulo puro de dominio (`domain/request_requirements.dart`) espejo del de la
web concentra los flags y sus etiquetas; un widget (`features/shared/request_requirement_badges.dart`)
los pinta en dos variantes; cuatro `select()` de `repos.dart` ganan las columnas que ya existen en la
base; y la bandeja del proveedor —cuya RPC no devuelve esas columnas— las recibe por una tercera
llamada en la oleada B de `loadInboxData`. Ninguna migración.

**Tech Stack:** Flutter (Dart 3, records y patterns), Supabase (PostgREST vía `supabase_flutter`),
`flutter_test` para pruebas de dominio y de widget.

**Spec:** `docs/superpowers/specs/2026-08-02-requisitos-solicitud-app-design.md`

## Global Constraints

- Repo: `C:\Users\ac\Downloads\jayalo-app`. Todo el código Flutter vive bajo `app/`. Los comandos
  de test y análisis se corren **desde `app/`**.
- **Cero cambios de base de datos.** Ni migraciones, ni tocar `get_provider_inbox_unified`. Si una
  tarea parece necesitarlos, es señal de que algo se entendió mal: parar y reportar.
- Las cinco columnas de `customer_requests` son, textualmente: `with_shipping`,
  `with_installation`, `requires_evaluation`, `requires_fiscal_receipt`, `requires_state_supplier`.
- Los textos de las etiquetas se copian **literalmente** de `REQUIREMENT_LABEL` en
  `src/lib/requestRequirements.ts` de la web. No reescribirlos, no "mejorarlos".
- Orden canónico de presentación, en todas las variantes: envío → instalación → evaluación →
  fiscal → Estado.
- En la app **los chips del detalle llevan los cinco requisitos**, incluida la evaluación. La web
  la excluye porque allí ya tiene un chip ámbar propio; la app no lo tiene.
- Comentarios y mensajes de commit en español, siguiendo el estilo del repo (`feat(app):`,
  `fix(app):`, `test(app):`, `docs(app):`).
- Cada commit termina con `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- La suite parte de **656 tests en verde** (medido en `739b3fe`, no tomado de memoria). Ningún
  commit puede dejarla en rojo ni bajar ese número.

## Estructura de ficheros

**Se crean:**

| Fichero | Responsabilidad |
|---|---|
| `app/lib/domain/request_requirements.dart` | Enum, modelo, mapeo desde fila y etiquetas. Puro: sin Flutter, sin Supabase. |
| `app/lib/features/shared/request_requirement_badges.dart` | El widget, dos variantes. Único sitio que sabe de íconos y colores. |
| `app/test/domain/request_requirements_test.dart` | Pruebas del módulo puro. |
| `app/test/request_requirement_badges_test.dart` | Pruebas del widget. |

**Se modifican:**

| Fichero | Qué cambia |
|---|---|
| `app/lib/core/brand.dart` | Dos tonos teal nuevos en `JayaloStatus`. |
| `app/lib/data/repos.dart` | La constante de columnas, tres `select()` y `requirementsForRequests`. |
| `app/lib/domain/inbox_load.dart` | Tercera llamada en la oleada B. |
| `app/lib/features/provider/inbox_screen.dart` | Símbolos en `_InboxCard`. |
| `app/lib/features/provider/request_detail_screen.dart` | Chips bajo el título. |
| `app/lib/features/client/other_request_screen.dart` | Chips bajo el título. |
| `app/lib/features/client/request_detail_sheet.dart` | Chips bajo el título. |
| `app/lib/features/client/request_status_screen.dart` | Las cinco columnas en su `select`. |
| `app/lib/features/client/my_requests_screen.dart` | Símbolos en las dos tarjetas. |
| `app/test/repos_test.dart`, `inbox_load_test.dart`, `inbox_screen_test.dart`, `other_request_screen_test.dart`, `client_request_detail_sheet_test.dart`, `my_requests_others_test.dart` | Casos nuevos. |

---

### Task 1: El módulo puro de dominio

**Files:**
- Create: `app/lib/domain/request_requirements.dart`
- Test: `app/test/domain/request_requirements_test.dart`

**Interfaces:**
- Consumes: nada. Es la base de todo lo demás.
- Produces:
  - `enum Requirement { shipping, installation, evaluation, fiscal, state }`
  - `typedef RequirementLabel = ({String chip, String short, String hint})`
  - `class RequestRequirements` con constructor const nombrado (`withShipping`, `withInstallation`,
    `requiresEvaluation`, `requiresFiscalReceipt`, `requiresStateSupplier`, todos `bool` con
    default `false`), `static const none`, y `bool has(Requirement r)`
  - `RequestRequirements requirementsFromRow(Map<String, dynamic> row)`
  - `List<Requirement> activeRequirements(RequestRequirements req, {Iterable<Requirement> keys})`
  - `RequirementLabel requirementLabel(Requirement r)`

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/domain/request_requirements_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_requirements.dart';

/// Espejo de `src/lib/requestRequirements.test.ts` de la web. El módulo es puro
/// a propósito: la web dejó su máquina de estados de cotejo sin test y el único
/// bug serio de aquella rama vivía justo ahí.
void main() {
  group('requirementsFromRow', () {
    test('una fila con las cinco en true las marca todas', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'with_installation': true,
        'requires_evaluation': true,
        'requires_fiscal_receipt': true,
        'requires_state_supplier': true,
      });
      expect(r.withShipping, isTrue);
      expect(r.withInstallation, isTrue);
      expect(r.requiresEvaluation, isTrue);
      expect(r.requiresFiscalReceipt, isTrue);
      expect(r.requiresStateSupplier, isTrue);
    });

    test('clave ausente, null y false son lo mismo: no lo pide', () {
      final ausente = requirementsFromRow(<String, dynamic>{});
      final nulo = requirementsFromRow({
        'with_shipping': null,
        'requires_fiscal_receipt': null,
      });
      final falso = requirementsFromRow({
        'with_shipping': false,
        'requires_fiscal_receipt': false,
      });
      for (final r in [ausente, nulo, falso]) {
        expect(activeRequirements(r), isEmpty);
      }
    });

    test('un tipo inesperado no lanza y cae en false', () {
      // PostgREST no debería mandar esto, pero un `== true` es más barato que
      // un crash en la pantalla del proveedor.
      final r = requirementsFromRow({'with_shipping': 'true', 'requires_evaluation': 1});
      expect(r.withShipping, isFalse);
      expect(r.requiresEvaluation, isFalse);
    });
  });

  group('activeRequirements', () {
    test('devuelve los activos en orden canónico', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'with_installation': true,
        'requires_evaluation': true,
        'requires_fiscal_receipt': true,
        'requires_state_supplier': true,
      });
      expect(activeRequirements(r), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.evaluation,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('un subconjunto salteado conserva el orden', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_state_supplier': true,
      });
      expect(activeRequirements(r), [Requirement.shipping, Requirement.state]);
    });

    test('sin nada activo devuelve lista vacía', () {
      expect(activeRequirements(RequestRequirements.none), isEmpty);
    });

    test('`keys` acota: no devuelve nada fuera del conjunto pedido', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_fiscal_receipt': true,
      });
      expect(
        activeRequirements(r, keys: const [Requirement.fiscal]),
        [Requirement.fiscal],
      );
    });

    test('`keys` desordenado NO altera el orden de salida', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_state_supplier': true,
      });
      expect(
        activeRequirements(r, keys: const [Requirement.state, Requirement.shipping]),
        [Requirement.shipping, Requirement.state],
        reason: 'el orden lo fija la declaración del enum, no quien llama',
      );
    });
  });

  group('requirementLabel', () {
    test('las cinco tienen los tres textos y ninguno vacío', () {
      for (final r in Requirement.values) {
        final l = requirementLabel(r);
        expect(l.chip, isNotEmpty, reason: '$r sin texto de chip');
        expect(l.short, isNotEmpty, reason: '$r sin texto corto');
        expect(l.hint, isNotEmpty, reason: '$r sin explicación');
      }
    });

    test('los textos son los de la web, literales', () {
      expect(requirementLabel(Requirement.fiscal).chip, 'Requiere comprobante fiscal');
      expect(requirementLabel(Requirement.fiscal).short, 'comprobante fiscal');
      expect(
        requirementLabel(Requirement.fiscal).hint,
        'El proveedor debe poder emitir comprobante fiscal (NCF).',
      );
      expect(requirementLabel(Requirement.state).chip, 'Requiere suplidor del Estado');
      expect(requirementLabel(Requirement.evaluation).chip, 'Requiere evaluación previa');
      expect(requirementLabel(Requirement.shipping).chip, 'Requiere envío');
      expect(requirementLabel(Requirement.installation).chip, 'Requiere instalación');
    });
  });

  group('has', () {
    test('cubre las cinco sin lanzar por un case olvidado', () {
      for (final r in Requirement.values) {
        RequestRequirements.none.has(r);
      }
    });
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Desde `app/`:

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: FALLA en compilación — `Error: Couldn't resolve the package 'jayalo_app' ... request_requirements.dart` o
`Target of URI doesn't exist`. El fichero de dominio todavía no existe.

- [ ] **Step 3: Escribir el módulo**

Crear `app/lib/domain/request_requirements.dart`:

```dart
/// Los requisitos que el CLIENTE marca al crear una solicitud, y sus etiquetas.
///
/// Módulo PURO a propósito: sin Flutter y sin Supabase, para que "qué exige
/// esta solicitud" se pueda probar sin montar ninguna pantalla. Espejo de
/// `src/lib/requestRequirements.ts` de la web; los textos se copian LITERALES
/// para que el mismo requisito se lea igual en los dos frentes.
///
/// Lo que NO está aquí, a propósito: `OfferCapabilities` y el cotejo contra lo
/// que declara una oferta (`unmetRequirements`). Eso lo necesita la tanda B
/// —declarar capacidades del proveedor y avisar antes de enviar la oferta— y
/// escribirlo ahora sería código muerto.
library;

/// El orden de declaración ES el orden canónico de presentación: lo respetan
/// los chips del detalle y los símbolos del listado, en las seis pantallas.
enum Requirement { shipping, installation, evaluation, fiscal, state }

/// `chip` = texto completo, el que se lee en el detalle.
/// `short` = la misma idea suelta, para armar una frase enumerando varios.
/// `hint` = la explicación larga, para el tooltip.
typedef RequirementLabel = ({String chip, String short, String hint});

/// Lo que el cliente pide, tal como está en las columnas de `customer_requests`.
class RequestRequirements {
  const RequestRequirements({
    this.withShipping = false,
    this.withInstallation = false,
    this.requiresEvaluation = false,
    this.requiresFiscalReceipt = false,
    this.requiresStateSupplier = false,
  });

  final bool withShipping;
  final bool withInstallation;
  final bool requiresEvaluation;
  final bool requiresFiscalReceipt;
  final bool requiresStateSupplier;

  /// Solicitud que no exige nada. Es el valor por defecto donde el dato aún no
  /// llegó, y el default seguro: no se le reclama al proveedor algo que el
  /// cliente nunca marcó.
  static const none = RequestRequirements();

  bool has(Requirement r) => switch (r) {
    Requirement.shipping => withShipping,
    Requirement.installation => withInstallation,
    Requirement.evaluation => requiresEvaluation,
    Requirement.fiscal => requiresFiscalReceipt,
    Requirement.state => requiresStateSupplier,
  };
}

/// Mapea una fila de `customer_requests`. NUNCA lanza: la clave ausente, el
/// `null` y cualquier tipo inesperado caen todos en "no lo pide" gracias al
/// `== true`. Una fila de la RPC del inbox —que no trae estas columnas— da
/// `none`, que es exactamente lo que se quiere hasta que llegue la oleada B.
RequestRequirements requirementsFromRow(Map<String, dynamic> row) =>
    RequestRequirements(
      withShipping: row['with_shipping'] == true,
      withInstallation: row['with_installation'] == true,
      requiresEvaluation: row['requires_evaluation'] == true,
      requiresFiscalReceipt: row['requires_fiscal_receipt'] == true,
      requiresStateSupplier: row['requires_state_supplier'] == true,
    );

/// Los requisitos activos, SIEMPRE en orden canónico. [keys] acota el conjunto
/// (por defecto, los cinco). Se itera `Requirement.values` y se filtra por
/// [keys], no al revés: así el orden lo fija la declaración del enum y no el
/// orden en que quien llama pasó las claves.
List<Requirement> activeRequirements(
  RequestRequirements req, {
  Iterable<Requirement> keys = Requirement.values,
}) => [
  for (final r in Requirement.values)
    if (keys.contains(r) && req.has(r)) r,
];

const _labels = <Requirement, RequirementLabel>{
  Requirement.shipping: (
    chip: 'Requiere envío',
    short: 'envío',
    hint: 'El cliente necesita que le lleven el producto.',
  ),
  Requirement.installation: (
    chip: 'Requiere instalación',
    short: 'instalación',
    hint: 'El cliente necesita que se lo instalen.',
  ),
  Requirement.evaluation: (
    chip: 'Requiere evaluación previa',
    short: 'evaluación previa',
    hint: 'El cliente pide una visita para cotizar antes.',
  ),
  Requirement.fiscal: (
    chip: 'Requiere comprobante fiscal',
    short: 'comprobante fiscal',
    hint: 'El proveedor debe poder emitir comprobante fiscal (NCF).',
  ),
  Requirement.state: (
    chip: 'Requiere suplidor del Estado',
    short: 'suplidor del Estado',
    hint: 'El proveedor debe estar registrado como suplidor del Estado.',
  ),
};

RequirementLabel requirementLabel(Requirement r) => _labels[r]!;
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
flutter test test/domain/request_requirements_test.dart
```

Esperado: PASA, 11 tests.

- [ ] **Step 5: Correr el analizador**

```bash
flutter analyze lib/domain/request_requirements.dart test/domain/request_requirements_test.dart
```

Esperado: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/request_requirements.dart app/test/domain/request_requirements_test.dart
git commit -m "feat(app): modulo puro de los requisitos de la solicitud

Espejo de src/lib/requestRequirements.ts de la web, con sus textos literales.
Sin Flutter y sin Supabase para que se pueda probar sin montar pantalla: la web
dejo su maquina de estados sin test y ahi vivia el unico bug serio de aquella
rama. Sin OfferCapabilities ni unmetRequirements: eso es la tanda B.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: El tono teal y el widget de badges

**Files:**
- Modify: `app/lib/core/brand.dart` (añadir tras `reviewDark`, línea 127, dentro de `JayaloStatus`)
- Create: `app/lib/features/shared/request_requirement_badges.dart`
- Test: `app/test/request_requirement_badges_test.dart`

**Interfaces:**
- Consumes: de Task 1, `Requirement`, `RequestRequirements`, `activeRequirements`,
  `requirementLabel`. De `features/shared/brand_kit.dart`, el widget `StatusChip`
  (`StatusChip({required String label, required StatusTone tone, IconData? icon})`).
- Produces:
  - `JayaloStatus.requisitoLight` y `JayaloStatus.requisitoDark`, records `(bg:, ink:)`
  - `enum RequirementBadgeVariant { symbols, chips }`
  - `class RequestRequirementBadges` con
    `RequestRequirementBadges({Key? key, required RequestRequirements req, required RequirementBadgeVariant variant, EdgeInsetsGeometry? padding})`

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/request_requirement_badges_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/shared/request_requirement_badges.dart';

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: jayaloTheme(brightness),
        home: Scaffold(body: child),
      );

  const todos = RequestRequirements(
    withShipping: true,
    withInstallation: true,
    requiresEvaluation: true,
    requiresFiscalReceipt: true,
    requiresStateSupplier: true,
  );

  testWidgets('sin requisitos no dibuja nada', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    expect(find.textContaining('Requiere'), findsNothing);
  });

  testWidgets('el padding NO se aplica cuando no hay nada que pintar',
      (tester) async {
    // Si el padding se aplicara igual, cada detalle sin requisitos quedaría con
    // un hueco vertical fantasma bajo el título.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements.none,
      variant: RequirementBadgeVariant.chips,
      padding: EdgeInsets.only(top: 40),
    )));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(RequestRequirementBadges)).height,
      0,
      reason: 'sin requisitos el widget debe ocupar cero',
    );
  });

  testWidgets('chips: los cinco textos, en orden canónico', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    final textos = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(RequestRequirementBadges),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .toList();
    expect(textos, [
      'Requiere envío',
      'Requiere instalación',
      'Requiere evaluación previa',
      'Requiere comprobante fiscal',
      'Requiere suplidor del Estado',
    ]);
  });

  testWidgets('chips: la evaluación SÍ aparece (divergencia con la web)',
      (tester) async {
    // La web la excluye del detalle porque allí ya tiene su chip ámbar propio.
    // La app no lo tiene: si se copiara la exclusión, el requisito quedaría
    // invisible en los tres detalles.
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresEvaluation: true),
      variant: RequirementBadgeVariant.chips,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Requiere evaluación previa'), findsOneWidget);
  });

  testWidgets('symbols: cinco íconos y ningún texto', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: todos,
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RequestRequirementBadges),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: 'en el listado los símbolos son mudos: el texto vive en el detalle',
    );
  });

  testWidgets('symbols: solo pinta los activos', (tester) async {
    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });

  testWidgets('el tono cambia entre claro y oscuro', (tester) async {
    Color colorDelIcono() => tester
        .widget<Icon>(find.byIcon(Icons.receipt_long_outlined))
        .color!;

    await tester.pumpWidget(host(const RequestRequirementBadges(
      req: RequestRequirements(requiresFiscalReceipt: true),
      variant: RequirementBadgeVariant.symbols,
    )));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoLight.ink);

    await tester.pumpWidget(host(
      const RequestRequirementBadges(
        req: RequestRequirements(requiresFiscalReceipt: true),
        variant: RequirementBadgeVariant.symbols,
      ),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    expect(colorDelIcono(), JayaloStatus.requisitoDark.ink);
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/request_requirement_badges_test.dart
```

Esperado: FALLA en compilación — `Target of URI doesn't exist: 'package:jayalo_app/features/shared/request_requirement_badges.dart'`.

- [ ] **Step 3: Añadir el tono teal**

En `app/lib/core/brand.dart`, dentro de `abstract final class JayaloStatus`, justo **después** de la
línea `static const reviewDark = (bg: Color(0xFF492537), ink: Color(0xFFFFB3D7));` y antes del `}`
que cierra la clase:

```dart

  /// Requisitos que el CLIENTE exige en su solicitud (comprobante fiscal,
  /// suplidor del Estado, envío, instalación, evaluación previa). Teal propio,
  /// y no uno de los tonos de arriba, porque no es un estado de la oferta del
  /// proveedor: es una condición del cliente. El ámbar en esta app ya significa
  /// dinero o espera ("Ya ofertaste", el costo del desbloqueo, la wallet), y
  /// confundir las dos cosas sería peor que no pintar nada.
  ///
  /// Portado del token `--requisito` de la web: `oklch(0.94 0.06 200)` /
  /// `oklch(0.4 0.12 200)` en claro, `oklch(0.3 0.07 200)` /
  /// `oklch(0.87 0.11 200)` en oscuro. La conversión oklch→sRGB se calibró
  /// contra `--status-pending`, que da exactamente el `pendingLight` de arriba.
  static const requisitoLight = (bg: Color(0xFFBCF8FB), ink: Color(0xFF005961));
  static const requisitoDark = (bg: Color(0xFF00383C), ink: Color(0xFF6FEAF1));
```

- [ ] **Step 4: Escribir el widget**

Crear `app/lib/features/shared/request_requirement_badges.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/request_requirements.dart';
import 'brand_kit.dart';

/// `symbols` → listado: círculo mudo con el ícono. `chips` → detalle: píldora
/// con ícono y texto completo.
enum RequirementBadgeVariant { symbols, chips }

/// Equivalentes Material de los íconos lucide que usa la web
/// (`RequestRequirementBadges.tsx`): Truck, Wrench, ClipboardCheck,
/// ReceiptText, Landmark.
const _icons = <Requirement, IconData>{
  Requirement.shipping: Icons.local_shipping_outlined,
  Requirement.installation: Icons.handyman_outlined,
  Requirement.evaluation: Icons.fact_check_outlined,
  Requirement.fiscal: Icons.receipt_long_outlined,
  Requirement.state: Icons.account_balance_outlined,
};

/// Lo que el cliente exige en esta solicitud.
///
/// Sin requisitos activos no dibuja NADA —ni el [padding]—, así que quien lo
/// usa no necesita envolverlo en un condicional ni le queda un hueco vertical
/// fantasma cuando la solicitud no exige nada.
class RequestRequirementBadges extends StatelessWidget {
  const RequestRequirementBadges({
    super.key,
    required this.req,
    required this.variant,
    this.padding,
  });

  final RequestRequirements req;
  final RequirementBadgeVariant variant;

  /// Separación con lo de arriba, aplicada SOLO cuando hay algo que pintar.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final keys = activeRequirements(req);
    if (keys.isEmpty) return const SizedBox.shrink();

    final tone = Theme.of(context).brightness == Brightness.dark
        ? JayaloStatus.requisitoDark
        : JayaloStatus.requisitoLight;

    final body = switch (variant) {
      RequirementBadgeVariant.symbols => Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final k in keys)
            Tooltip(
              // En el listado el símbolo es mudo: el tooltip es lo único que
              // dice qué significa, igual que el `title` de la web.
              message: requirementLabel(k).chip,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icons[k], size: 12, color: tone.ink),
              ),
            ),
        ],
      ),
      RequirementBadgeVariant.chips => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in keys)
            Tooltip(
              message: requirementLabel(k).hint,
              // `StatusChip` en vez de otra píldora propia: misma geometría que
              // "Al por mayor" y "Ya ofertaste", que es justo al lado de donde
              // van estos chips.
              child: StatusChip(
                label: requirementLabel(k).chip,
                icon: _icons[k],
                tone: tone,
              ),
            ),
        ],
      ),
    };

    final p = padding;
    return p == null ? body : Padding(padding: p, child: body);
  }
}
```

- [ ] **Step 5: Correr el test y verificar que pasa**

```bash
flutter test test/request_requirement_badges_test.dart
```

Esperado: PASA, 7 tests.

Si el test del tono falla porque `Icon.color` viene `null`, es que el `Icon` está heredando del
`IconTheme` en vez de recibir el color: revisar que `color: tone.ink` esté puesto en los dos sitios.

- [ ] **Step 6: Correr el analizador y la suite completa**

```bash
flutter analyze lib/core/brand.dart lib/features/shared/request_requirement_badges.dart test/request_requirement_badges_test.dart
flutter test
```

Esperado: `No issues found!` y la suite en verde con 656 + 11 + 7 = 674 tests.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/brand.dart app/lib/features/shared/request_requirement_badges.dart app/test/request_requirement_badges_test.dart
git commit -m "feat(app): badges de requisitos y el tono teal que los pinta

Dos variantes: simbolos mudos para los listados y chips con texto para los
detalles. El teal se porta del token --requisito de la web; no se reusa el ambar
porque en esta app ya significa dinero o espera. Sin requisitos no dibuja nada,
ni el padding, para que ningun detalle quede con un hueco fantasma.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Las lecturas de `repos.dart`

**Files:**
- Modify: `app/lib/data/repos.dart`
- Test: `app/test/repos_test.dart`

**Interfaces:**
- Consumes: de Task 1, `RequestRequirements` y `requirementsFromRow`.
- Produces:
  - `const String requestRequirementCols`
  - `Future<Map<String, RequestRequirements>> requirementsForRequests(List<String> ids)`
  - `requestById`, `allOpenRequests` y `_fetchMyRequests` devolviendo las cinco columnas.

- [ ] **Step 1: Verificar los grants ANTES de tocar código**

El spec afirma que las cinco columnas ya tienen `GRANT SELECT` porque la web las lee en producción.
Confirmarlo contra la base, no contra un comentario: dar un grant por bueno desde el comentario de
otra migración ya costó una migración de corrección en la web, y dos revisiones no lo vieron.

Correr contra el proyecto `mfaiklvobnvgusbcssbx` con la herramienta `execute_sql` del MCP de
Supabase:

```sql
SELECT column_name, grantee
FROM information_schema.role_column_grants
WHERE table_schema = 'public'
  AND table_name = 'customer_requests'
  AND column_name IN (
    'with_shipping','with_installation','requires_evaluation',
    'requires_fiscal_receipt','requires_state_supplier')
  AND grantee IN ('anon','authenticated')
  AND privilege_type = 'SELECT'
ORDER BY column_name, grantee;
```

Esperado: **10 filas** (cinco columnas × dos roles).

Si salen menos de 10, **PARAR**: no escribir código y reportar qué columnas faltan. Un `select()`
que pide una columna sin grant no falla solo en esa columna — PostgREST tumba la petición entera, y
la pantalla se queda sin datos.

- [ ] **Step 2: Escribir el test que falla**

En `app/test/repos_test.dart`, añadir el import de dominio arriba (junto a los que ya hay):

```dart
import 'package:jayalo_app/domain/request_requirements.dart';
```

y estos grupos al final de `main()`, antes del `}` que lo cierra:

```dart
  group('requestRequirementCols', () {
    test('nombra las cinco columnas de requisitos', () {
      for (final col in const [
        'with_shipping',
        'with_installation',
        'requires_evaluation',
        'requires_fiscal_receipt',
        'requires_state_supplier',
      ]) {
        expect(requestRequirementCols, contains(col), reason: 'falta $col');
      }
    });

    test('no lleva espacios: va concatenada dentro de un select de PostgREST', () {
      expect(requestRequirementCols, isNot(contains(' ')));
    });
  });

  group('requirementsForRequests', () {
    test('con lista vacía devuelve mapa vacío SIN tocar la red', () async {
      // Sin este corto‑circuito el test reventaría al tocar `supa`, que no está
      // inicializado en un test de unidad. Que pase es la prueba de que existe.
      expect(await requirementsForRequests(const []), isEmpty);
    });
  });
```

- [ ] **Step 3: Correr el test y verificar que falla**

```bash
flutter test test/repos_test.dart
```

Esperado: FALLA en compilación — `Undefined name 'requestRequirementCols'` y
`The method 'requirementsForRequests' isn't defined`.

- [ ] **Step 4: Añadir la constante y la función a `repos.dart`**

Primero, el import de dominio en la cabecera de `app/lib/data/repos.dart` (junto a los demás
imports de `../domain/`):

```dart
import '../domain/request_requirements.dart';
```

Después, justo **encima** de `Future<List<Map<String, dynamic>>> _fetchMyRequests()`:

```dart
/// Las cinco columnas de requisitos de `customer_requests`, juntas en una sola
/// constante para que no se separen nunca: las leen cuatro pantallas y la
/// bandeja, y añadir una sexta a un solo `select()` es exactamente el fallo que
/// dejó estos flags invisibles durante meses.
///
/// Sin espacios: se concatena dentro de un `select()` de PostgREST.
const requestRequirementCols =
    'with_shipping,with_installation,requires_evaluation,'
    'requires_fiscal_receipt,requires_state_supplier';

/// Los requisitos de un lote de solicitudes, por id.
///
/// Existe por la bandeja del proveedor: `get_provider_inbox_unified` tiene una
/// forma fija de trece columnas que no incluye ninguno de estos flags, y esa RPC
/// la comparte la web — extenderla obligaría a un DROP/CREATE con re-grants y
/// pondría en riesgo el inbox de los dos frentes a la vez. Sale más barato
/// pedirlos aparte: la llamada corre en la oleada B de `loadInboxData`, en
/// paralelo con los estados y los conteos, así que no cuesta latencia.
Future<Map<String, RequestRequirements>> requirementsForRequests(
  List<String> ids,
) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa
        .from('customer_requests')
        .select('id,$requestRequirementCols')
        .inFilter('id', ids),
  );
  return {
    for (final r in rows) r['id'] as String: requirementsFromRow(r),
  };
}
```

- [ ] **Step 5: Añadir las columnas a los tres `select()`**

En `_fetchMyRequests`, cambiar:

```dart
        .select(
          'id,title,kind,status,is_wholesale,created_at,image_url,image_urls',
        )
```

por:

```dart
        .select(
          'id,title,kind,status,is_wholesale,created_at,image_url,image_urls,'
          '$requestRequirementCols',
        )
```

En `allOpenRequests`, cambiar:

```dart
      .select(
        'id,title,description,kind,urgency,zone,is_wholesale,created_at,image_url',
      )
```

por:

```dart
      .select(
        'id,title,description,kind,urgency,zone,is_wholesale,created_at,'
        'image_url,$requestRequirementCols',
      )
```

En `requestById`, añadir al final de la cadena de columnas (justo antes de la comilla de cierre,
después de `accepted_offers_count`):

```dart
      ',$requestRequirementCols',
```

de modo que la línea quede así (una sola cadena adyacente más):

```dart
    .select(
      // image_url/image_urls: el detalle del proveedor pinta la foto del
      // cliente en el panel ámbar (igual que el detalle del cliente). Sin
      // estas columnas el panel SIEMPRE caía al ícono — "llegan sin imágenes".
      'id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at,image_url,image_urls,budget_min,budget_max,wholesale_quantity,wholesale_split,wholesale_packaging,wholesale_note,offers_count,accepted_offers_count'
      ',$requestRequirementCols',
    )
```

`myOfferedOpenRequests` **no se toca**: sus filas se mezclan en "Para ti" y la oleada B las cubre.

- [ ] **Step 6: Correr los tests y verificar que pasan**

```bash
flutter test test/repos_test.dart
```

Esperado: PASA, con los 3 casos nuevos.

- [ ] **Step 7: Analizar y correr la suite completa**

```bash
flutter analyze lib/data/repos.dart test/repos_test.dart
flutter test
```

Esperado: `No issues found!` y suite en verde (677 tests).

- [ ] **Step 8: Commit**

```bash
git add app/lib/data/repos.dart app/test/repos_test.dart
git commit -m "feat(app): las lecturas de solicitudes traen los requisitos del cliente

Los cinco flags se guardaban bien desde el formulario y no los leia nadie: ni
requestById, ni allOpenRequests, ni el listado de mis solicitudes. Una constante
los mantiene juntos, porque anadir una sexta columna a un solo select es
exactamente el fallo que los dejo invisibles. requirementsForRequests existe
para la bandeja, cuya RPC no los devuelve y la comparte la web.

Grants verificados contra information_schema antes de tocar codigo: 10 filas,
cinco columnas por dos roles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: La tercera llamada de la oleada B

**Files:**
- Modify: `app/lib/domain/inbox_load.dart`
- Test: `app/test/inbox_load_test.dart`

**Interfaces:**
- Consumes: de Task 1, `RequestRequirements`.
- Produces:
  - `InboxData` con un campo nuevo `Map<String, RequestRequirements> requirements`
  - `loadInboxData` con un parámetro nuevo, obligatorio y nombrado:
    `required Future<Map<String, RequestRequirements>> Function(List<String>) fetchRequirements`

- [ ] **Step 1: Escribir los tests que fallan**

En `app/test/inbox_load_test.dart`, añadir el import:

```dart
import 'package:jayalo_app/domain/request_requirements.dart';
```

Añadir estos tres casos. El primero va dentro del grupo `'loadInboxData — paralelismo'`, después de
`'oleada B: estados y conteos se piden A LA VEZ'`:

```dart
    test('oleada B: los requisitos se piden A LA VEZ que los estados', () async {
      final statusGate = Completer<Map<String, String>>();
      final reqGate = Completer<Map<String, RequestRequirements>>();
      var reqStarted = false;

      final future = loadInboxData(
        fetchItems: () async => [req('a')],
        fetchOfferedOpen: null,
        fetchStatuses: (_) => statusGate.future,
        fetchCounts: (_) async => {},
        fetchRequirements: (_) {
          reqStarted = true;
          return reqGate.future;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        reqStarted,
        isTrue,
        reason: 'no debe esperar a los estados para pedir los requisitos',
      );

      statusGate.complete({'a': 'pending'});
      reqGate.complete({'a': const RequestRequirements(withShipping: true)});
      final data = await future;
      expect(data.requirements['a']!.withShipping, isTrue);
    });
```

Los otros dos van dentro del grupo `'loadInboxData — best-effort'`, al final:

```dart
    test(
      'si fallan los requisitos, quedan vacíos y la bandeja sobrevive',
      () async {
        final data = await loadInboxData(
          fetchItems: () async => [req('a')],
          fetchOfferedOpen: null,
          fetchStatuses: (_) async => {},
          fetchCounts: (_) async => {},
          fetchRequirements: (_) async => throw StateError('boom'),
        );
        expect(data.items.map((r) => r['id']).toList(), ['a']);
        expect(data.requirements, isEmpty);
      },
    );

    test('los requisitos NO se piden para las filas de la tienda', () async {
      List<String>? vistos;
      await loadInboxData(
        fetchItems: () async => [req('a'), req('s', source: 'store')],
        fetchOfferedOpen: null,
        fetchStatuses: (_) async => {},
        fetchCounts: (_) async => {},
        fetchRequirements: (ids) async {
          vistos = ids;
          return {};
        },
      );
      expect(
        vistos,
        ['a'],
        reason: 'un interés de producto no es una solicitud: no tiene requisitos',
      );
    });
```

Y añadir `fetchRequirements: (_) async => {},` a **las diez llamadas existentes** de `loadInboxData`
en ese fichero (el parámetro es obligatorio, así que sin esto no compila ninguna).

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/inbox_load_test.dart
```

Esperado: FALLA en compilación — `No named parameter with the name 'fetchRequirements'`.

- [ ] **Step 3: Modificar `inbox_load.dart`**

El fichero abre con el doc de librería y su directiva `library;`. En Dart los imports van
**después** de esa directiva, así que el import se añade justo debajo:

```dart
library;

import 'request_requirements.dart';
```

Actualizar el doc de la librería: en la línea que dice

```dart
///   oleada B: fetchStatuses(ids) ‖ fetchCounts(ids)
```

poner

```dart
///   oleada B: fetchStatuses(ids) ‖ fetchCounts(ids) ‖ fetchRequirements(ids)
```

Añadir el campo al record:

```dart
typedef InboxData = ({
  List<Map<String, dynamic>> items,
  Map<String, String> statuses,
  Map<String, int> counts,
  Map<String, RequestRequirements> requirements,
  int badgeCount,
});
```

Añadir el parámetro a la firma, después de `fetchCounts`:

```dart
  required Future<Map<String, RequestRequirements>> Function(List<String>)
  fetchRequirements,
```

Lanzar el future junto a los otros dos de la oleada B, después de `countsFuture`:

```dart
  // Los requisitos que el cliente exige (comprobante fiscal, suplidor del
  // Estado, envío…). Se piden aparte porque `get_provider_inbox_unified` no los
  // devuelve; ver `requirementsForRequests` en repos.dart. Best-effort como sus
  // dos hermanas: sin ellos la tarjeta cae a los de su propia fila.
  final requirementsFuture = fetchRequirements(ids)
      .then<Map<String, RequestRequirements>>(
        (v) => v,
        onError: (Object _, StackTrace _) => <String, RequestRequirements>{},
      );
```

Y devolverlo:

```dart
  return (
    items: items,
    statuses: await statusesFuture,
    counts: await countsFuture,
    requirements: await requirementsFuture,
    badgeCount: badgeCount,
  );
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
flutter test test/inbox_load_test.dart
```

Esperado: PASA, 11 tests (8 de antes + 3 nuevos).

- [ ] **Step 5: Analizar**

```bash
flutter analyze lib/domain/inbox_load.dart test/inbox_load_test.dart
```

Esperado: `No issues found!`

Nota: `inbox_screen.dart` todavía no pasa `fetchRequirements` y por tanto **no compila**. Es
esperado y se arregla en la Task 5; por eso este paso analiza solo los dos ficheros de la tarea.

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/inbox_load.dart app/test/inbox_load_test.dart
git commit -m "feat(app): la oleada B de la bandeja tambien pide los requisitos

Tercera llamada en la oleada que ya existia, en paralelo con estados y conteos,
asi que no cuesta latencia. Best-effort como sus hermanas y solo para filas de
marketplace: un interes de producto no tiene requisitos.

inbox_screen.dart queda sin compilar hasta la siguiente tarea, que es la que lo
conecta.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Símbolos en la bandeja del proveedor

**Files:**
- Modify: `app/lib/features/provider/inbox_screen.dart`
- Test: `app/test/inbox_screen_test.dart`

**Interfaces:**
- Consumes: de Task 1 `RequestRequirements` y `requirementsFromRow`; de Task 2
  `RequestRequirementBadges` y `RequirementBadgeVariant`; de Task 3 `requirementsForRequests`; de
  Task 4 el campo `requirements` de `InboxData`.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Escribir el test que falla**

En `app/test/inbox_screen_test.dart`, añadir al final de `main()`, antes del `}` de cierre:

```dart
  testWidgets('la tarjeta pinta los símbolos de los requisitos del cliente',
      (tester) async {
    // Los requisitos salen de la oleada B, que en un test siempre falla
    // (`requirementsForRequests` toca `supa`) y `loadInboxData` se la traga por
    // diseño. Que los símbolos aparezcan igual es la prueba de que la tarjeta
    // cae a los de su propia fila.
    Future<List<Map<String, dynamic>>> conRequisitos(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-req',
                  'source': 'marketplace',
                  'title': 'Necesito 30 sillas',
                  'description': 'Para un salón',
                  'kind': 'producto',
                  'created_at': DateTime.now().toIso8601String(),
                  'with_shipping': true,
                  'requires_fiscal_receipt': true,
                },
              ];

    await tester.pumpWidget(host(ProviderInboxView(
        fetch: conRequisitos,
        leading: const SizedBox.shrink(),
        actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Necesito 30 sillas'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(
      find.byIcon(Icons.account_balance_outlined),
      findsNothing,
      reason: 'no marcó suplidor del Estado: no debe salir su símbolo',
    );
  });

  testWidgets('una solicitud sin requisitos no pinta ningún símbolo',
      (tester) async {
    Future<List<Map<String, dynamic>>> sinRequisitos(
            {String? kind, required bool todas}) async =>
        todas
            ? []
            : [
                {
                  'id': 'req-plano',
                  'source': 'marketplace',
                  'title': 'Necesito un plomero',
                  'description': 'Fuga de agua',
                  'kind': 'servicio',
                  'created_at': DateTime.now().toIso8601String(),
                },
              ];

    await tester.pumpWidget(host(ProviderInboxView(
        fetch: sinRequisitos,
        leading: const SizedBox.shrink(),
        actions: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Necesito un plomero'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
  });
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/inbox_screen_test.dart
```

Esperado: FALLA en compilación — `The parameter 'fetchRequirements' is required` en
`inbox_screen.dart` (la deuda que dejó la Task 4).

- [ ] **Step 3: Conectar la pantalla**

En `app/lib/features/provider/inbox_screen.dart`, añadir a los imports:

```dart
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
```

En `_ProviderInboxViewState`, junto a `_offerCounts`, añadir el campo:

```dart
  /// Requisitos que el cliente exige por solicitud (símbolos de la tarjeta).
  /// Sin entrada = los de la propia fila. Se recalcula en cada `_runFetch`.
  Map<String, RequestRequirements> _requirements = {};
```

En `_runFetch`, añadir la fuente a `loadInboxData` y volcar el resultado:

```dart
    final data = await loadInboxData(
      fetchItems: () => widget.fetch(kind: _kind, todas: _todas),
      fetchOfferedOpen: _todas
          ? null
          : () => myOfferedOpenRequests(kind: _kind),
      fetchStatuses: myOfferedRequestStatuses,
      fetchCounts: offerCountsForRequests,
      fetchRequirements: requirementsForRequests,
    );
    // En "Todas" no se toca el badge: ese conteo no es una alerta accionable,
    // es exploración.
    if (mounted && !_todas) solicitudesBadge.value = data.badgeCount;
    _offeredStatuses = data.statuses;
    _offerCounts = data.counts;
    _requirements = data.requirements;
    return data.items;
```

En el `itemBuilder`, en la construcción de `_InboxCard`, añadir el argumento después de
`offerCount`:

```dart
                          offerCount: _offerCounts[r['id']] ?? 0,
                          // La oleada B manda; si no trajo entrada (falló, o la
                          // fila ya venía completa desde `allOpenRequests`), se
                          // usan los de la propia fila. Las dos fuentes leen las
                          // mismas cinco columnas, así que no pueden discrepar.
                          requirements:
                              _requirements[r['id']] ?? requirementsFromRow(r),
```

En `_InboxCard`, añadir al constructor (después de `this.offerCount = 0,`):

```dart
    this.requirements = RequestRequirements.none,
```

y el campo, después de `offerCount`:

```dart
  /// Lo que el cliente EXIGE en esta solicitud (comprobante fiscal, suplidor
  /// del Estado, envío…). Se pintan como símbolos mudos junto a la hora; el
  /// texto completo vive en el detalle.
  final RequestRequirements requirements;
```

En el `build` de `_InboxCard`, dentro del `Wrap` que empieza con el `Text(timeAgo(createdAt))`,
añadir **justo después** de ese `Text` y **antes** del `if (offerCount > 0)`:

```dart
                    // Antes que los chips de estado a propósito: esto es lo que
                    // pide el cliente; "Ya ofertaste" es lo que hiciste tú.
                    RequestRequirementBadges(
                      req: requirements,
                      variant: RequirementBadgeVariant.symbols,
                    ),
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
flutter test test/inbox_screen_test.dart
```

Esperado: PASA, con los 2 casos nuevos.

- [ ] **Step 5: Analizar y correr la suite completa**

```bash
flutter analyze lib
flutter test
```

Esperado: `No issues found!` (ya compila todo) y suite en verde, 682 tests.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/provider/inbox_screen.dart app/test/inbox_screen_test.dart
git commit -m "feat(app): la bandeja del proveedor muestra los requisitos del cliente

Simbolos junto a la hora, antes de los chips de estado: esto es lo que pide el
cliente, "Ya ofertaste" es lo que hiciste tu. La oleada B manda y la propia fila
es el respaldo, que ademas es lo que hace la tarjeta testeable sin red.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Chips en los tres detalles

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
- Modify: `app/lib/features/client/other_request_screen.dart`
- Modify: `app/lib/features/client/request_detail_sheet.dart`
- Modify: `app/lib/features/client/request_status_screen.dart` (solo el `select`)
- Test: `app/test/other_request_screen_test.dart`, `app/test/client_request_detail_sheet_test.dart`

**Interfaces:**
- Consumes: de Task 1 `requirementsFromRow`; de Task 2 `RequestRequirementBadges` y
  `RequirementBadgeVariant`; de Task 3 `requestRequirementCols` y las columnas que ya llegan por
  `requestById`.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Escribir los tests que fallan**

En `app/test/other_request_screen_test.dart`, añadir dos claves al mapa `row` (después de
`'is_wholesale': true,`):

```dart
    'with_shipping': true,
    'requires_fiscal_receipt': true,
```

y este test al final de `main()`:

```dart
  testWidgets('muestra los requisitos que el cliente exige', (tester) async {
    await tester.pumpWidget(host(
      OtherRequestScreen(requestId: 'r1', fetch: () async => row),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Requiere envío'), findsOneWidget);
    expect(find.text('Requiere comprobante fiscal'), findsOneWidget);
    expect(find.text('Requiere instalación'), findsNothing);
  });
```

En `app/test/client_request_detail_sheet_test.dart`, añadir al mapa `request` (junto a las demás
claves):

```dart
    'requires_evaluation': true,
    'requires_state_supplier': true,
```

y este test al final de `main()`:

```dart
  testWidgets('el cliente ve en su solicitud los requisitos que marcó',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: RequestDetailSheet(
          request: request,
          phase: RequestPhase.waiting,
          offers: const [],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // La evaluación SÍ sale: la web la excluye del detalle porque allí tiene su
    // propio chip ámbar, y la app no lo tiene.
    expect(find.text('Requiere evaluación previa'), findsOneWidget);
    expect(find.text('Requiere suplidor del Estado'), findsOneWidget);
  });
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

```bash
flutter test test/other_request_screen_test.dart test/client_request_detail_sheet_test.dart
```

Esperado: FALLAN los dos casos nuevos con
`Expected: exactly one matching candidate / Actual: _TextWidgetFinder:<zero widgets with text "Requiere envío">`.

- [ ] **Step 3: Chips en el detalle del proveedor**

En `app/lib/features/provider/request_detail_screen.dart`, añadir a los imports:

```dart
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
```

En el `build`, justo **después** del bloque del chip "Al por mayor" y **antes** de
`_slotLadder(context)`:

```dart
                  // Lo que el cliente EXIGE. Va con el título y el chip de
                  // mayoreo, no bajo "Información": es identidad de la
                  // solicitud, y es lo que decide si a este proveedor le
                  // conviene ofertar (orden pedido por el PO 2026-08-01).
                  RequestRequirementBadges(
                    req: requirementsFromRow(req),
                    variant: RequirementBadgeVariant.chips,
                    padding: const EdgeInsets.only(top: 8),
                  ),
```

- [ ] **Step 4: Chips en el detalle de la solicitud ajena**

En `app/lib/features/client/other_request_screen.dart`, añadir a los imports:

```dart
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
```

En el `ListView`, justo **después** del bloque `if (r['is_wholesale'] == true) ...[ … ],` y
**antes** de `if (imgs.isNotEmpty) ...[`:

```dart
              RequestRequirementBadges(
                req: requirementsFromRow(r),
                variant: RequirementBadgeVariant.chips,
                padding: const EdgeInsets.only(top: 10),
              ),
```

- [ ] **Step 5: Chips en el detalle de mi solicitud**

En `app/lib/features/client/request_detail_sheet.dart`, añadir a los imports:

```dart
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
```

En el `Column`, justo **después** del bloque `if (request['is_wholesale'] == true) ...[ … ],` y
**antes** de `const SizedBox(height: 14),`:

```dart
          RequestRequirementBadges(
            req: requirementsFromRow(request),
            variant: RequirementBadgeVariant.chips,
            padding: const EdgeInsets.only(top: 8),
          ),
```

- [ ] **Step 6: Traer las columnas al detalle del cliente**

En `app/lib/features/client/request_status_screen.dart`, en el `select` de `initState`, cambiar:

```dart
        .select(
            'id,title,status,kind,bullets,user_id,created_at,image_urls,budget_min,budget_max,is_wholesale')
```

por:

```dart
        .select(
            'id,title,status,kind,bullets,user_id,created_at,image_urls,budget_min,budget_max,is_wholesale,$requestRequirementCols')
```

`requestRequirementCols` viene de `repos.dart`, que ese fichero ya importa en su línea 4
(`import '../../data/repos.dart';`, de donde saca `supa`). No hace falta ningún import nuevo.

- [ ] **Step 7: Correr los tests y verificar que pasan**

```bash
flutter test test/other_request_screen_test.dart test/client_request_detail_sheet_test.dart
```

Esperado: PASAN.

- [ ] **Step 8: Analizar y correr la suite completa**

```bash
flutter analyze lib
flutter test
```

Esperado: `No issues found!` y suite en verde, 684 tests.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart app/lib/features/client/other_request_screen.dart app/lib/features/client/request_detail_sheet.dart app/lib/features/client/request_status_screen.dart app/test/other_request_screen_test.dart app/test/client_request_detail_sheet_test.dart
git commit -m "feat(app): los tres detalles de solicitud muestran los requisitos

Chips teal bajo el titulo, junto al de mayoreo: son identidad de la solicitud,
no "informacion". Llevan los cinco, evaluacion incluida — la web la excluye del
detalle porque alli tiene su propio chip ambar y la app no lo tiene, asi que
copiar la exclusion la dejaria invisible.

El detalle del proveedor no tiene costura de tests (1654 lineas, carga con
requestById directo en initState); se prueban los otros dos y el widget.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Símbolos en los dos listados del cliente

**Files:**
- Modify: `app/lib/features/client/my_requests_screen.dart`
- Test: `app/test/my_requests_others_test.dart`

**Interfaces:**
- Consumes: de Task 1 `RequestRequirements` y `requirementsFromRow`; de Task 2
  `RequestRequirementBadges` y `RequirementBadgeVariant`; de Task 3, las columnas que ya llegan por
  `_fetchMyRequests` y `allOpenRequests`.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Escribir los tests que fallan**

En `app/test/my_requests_others_test.dart`, añadir al mapa dentro de `others` (después de
`'is_wholesale': false,`):

```dart
      'with_shipping': true,
      'requires_state_supplier': true,
```

y añadir este import arriba:

```dart
import 'package:jayalo_app/domain/phase.dart';
```

Después, estos dos tests al final de `main()`:

```dart
  testWidgets('la tarjeta "De otros" pinta los símbolos de los requisitos',
      (tester) async {
    await tester.pumpWidget(host(
      MyRequestsScreen(
        myFetch: () async => [],
        othersFetch: () async => others,
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver solicitudes de usuarios'));
    await tester.pumpAndSettle();

    expect(find.text('Busco 50 sillas plegables'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
  });

  testWidgets('la tarjeta de MI solicitud pinta sus propios requisitos',
      (tester) async {
    final mia = <(Map<String, dynamic>, RequestPhase, int)>[
      (
        {
          'id': 'm1',
          'title': 'Necesito 10 laptops',
          'kind': 'producto',
          'status': 'open',
          'is_wholesale': false,
          'image_url': null,
          'image_urls': <String>[],
          'created_at': DateTime.now().toIso8601String(),
          'requires_fiscal_receipt': true,
        },
        RequestPhase.waiting,
        0,
      ),
    ];

    await tester.pumpWidget(host(
      MyRequestsScreen(
        myFetch: () async => mia,
        othersFetch: () async => [],
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Necesito 10 laptops'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });
```

El texto del botón es exactamente `'Ver solicitudes de usuarios'`
(`my_requests_screen.dart:454`), el mismo que ya usa el test del toggle en este fichero.

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
flutter test test/my_requests_others_test.dart
```

Esperado: FALLAN los dos casos nuevos con `zero widgets with icon "IconData(U+0E1D5)"` o similar.

- [ ] **Step 3: Añadir el parámetro a las dos tarjetas**

En `app/lib/features/client/my_requests_screen.dart`, añadir a los imports:

```dart
import '../../domain/request_requirements.dart';
import '../shared/request_requirement_badges.dart';
```

En `_RequestCard`, añadir al constructor (después de `this.unseen = false,`):

```dart
    this.requirements = RequestRequirements.none,
```

y el campo (después del doc de `unseen`):

```dart
  /// Lo que el cliente exigió en esta solicitud: símbolos mudos junto a la
  /// hora. El texto completo vive en el detalle.
  final RequestRequirements requirements;
```

En `_OtherRequestCard`, añadir al constructor (después de `required this.wholesale,`):

```dart
    this.requirements = RequestRequirements.none,
```

y el campo (después de `final bool wholesale;`):

```dart
  /// Igual que en [_RequestCard]: símbolos mudos junto a la hora.
  final RequestRequirements requirements;
```

- [ ] **Step 4: Pintar los símbolos en las dos tarjetas**

En el `build` de `_RequestCard`, sustituir este bloque:

```dart
                    const SizedBox(height: 3),
                    Text(
                      timeAgo(createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: fg.withValues(alpha: .7),
                      ),
                    ),
```

por:

```dart
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeAgo(createdAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: fg.withValues(alpha: .7),
                          ),
                        ),
                        RequestRequirementBadges(
                          req: requirements,
                          variant: RequirementBadgeVariant.symbols,
                        ),
                      ],
                    ),
```

En el `build` de `_OtherRequestCard`, sustituir:

```dart
                const SizedBox(height: 3),
                Text(
                  timeAgo(createdAt),
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
```

por:

```dart
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeAgo(createdAt),
                      style:
                          TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                    RequestRequirementBadges(
                      req: requirements,
                      variant: RequirementBadgeVariant.symbols,
                    ),
                  ],
                ),
```

- [ ] **Step 5: Pasar los requisitos desde los dos sitios de construcción**

En la construcción de `_OtherRequestCard` (dentro del `itemBuilder` de la pestaña "De otros"),
añadir después de `wholesale: r['is_wholesale'] == true,`:

```dart
                              requirements: requirementsFromRow(r),
```

En la construcción de `_RequestCard`, añadir después de `unseen: unseen,`:

```dart
                                      requirements: requirementsFromRow(r),
```

- [ ] **Step 6: Correr el test y verificar que pasa**

```bash
flutter test test/my_requests_others_test.dart
```

Esperado: PASA.

- [ ] **Step 7: Analizar y correr la suite completa**

```bash
flutter analyze lib
flutter test
```

Esperado: `No issues found!` y suite en verde, 686 tests.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/client/my_requests_screen.dart app/test/my_requests_others_test.dart
git commit -m "feat(app): los listados del cliente muestran los requisitos

Simbolos junto a la hora en "Mis solicitudes" y en "De otros", con el mismo
lenguaje que la bandeja del proveedor. Los datos ya llegaban desde la tarea de
lecturas; aqui solo se pintan.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Verificación completa y guion de smoke

**Files:**
- Create: `docs/qa/2026-08-02-smoke-requisitos-app.md` (ruta desde la raíz del repo, no desde `app/`)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el guion que se ejecuta en device.

- [ ] **Step 1: Correr el analizador sobre todo el proyecto**

Desde `app/`:

```bash
flutter analyze
```

Esperado: `No issues found!`. Cualquier issue es regresión de este trabajo — arreglarla antes de
seguir, no anotarla.

- [ ] **Step 2: Correr la suite completa**

```bash
flutter test
```

Esperado: todos en verde, **686 tests** (656 de partida + 30 nuevos). Si el número es menor que 686,
falta algún caso de alguna tarea; si algún test falla, no continuar.

- [ ] **Step 3: Verificar que el release compila**

```bash
flutter build apk --release
```

Esperado: `✓ Built build/app/outputs/flutter-apk/app-release.apk`.

Este paso no es ceremonia: `integration_test` vive en `dependencies` (no en `dev_dependencies`) por
un fallo conocido del Gradle de Flutter, y el build de release es el único sitio donde eso muerde.

- [ ] **Step 4: Escribir el guion de smoke**

Crear `docs/qa/2026-08-02-smoke-requisitos-app.md`:

```markdown
# Smoke — requisitos de la solicitud en la app (2026-08-02)

Un APK de debug **no se instala encima de un release**: desinstalar primero, o el `install` falla
con `INSTALL_FAILED_UPDATE_INCOMPATIBLE` y se pierde media hora.

Nada de esto está cubierto por tests: el detalle del proveedor no tiene costura, y los símbolos en
device dependen de la oleada B, que en los tests siempre viene vacía.

## 1. El cliente marca y lo ve

- [ ] Crear una solicitud de PRODUCTO marcando "Requiere comprobante fiscal" y "Requiere ser
      suplidor del estado".
- [ ] En "Mis solicitudes", la tarjeta muestra dos símbolos teal junto a la hora.
- [ ] Al entrar al detalle, dos chips teal bajo el título: "Requiere comprobante fiscal" y
      "Requiere suplidor del Estado".

## 2. El proveedor se entera (el daño que esto arregla)

- [ ] Con sesión de proveedor del rubro que corresponda, esa solicitud aparece en **"Para ti"** con
      sus dos símbolos. Esta es la verificación clave: aquí los datos vienen de la oleada B, no de
      la fila, porque la RPC del inbox no trae las columnas.
- [ ] Cambiar a **"Todas"**: los símbolos siguen ahí.
- [ ] Entrar al detalle: los dos chips bajo el título, encima de la escalera de cupos.

## 3. Los cinco a la vez, evaluación incluida

- [ ] Crear una solicitud de producto marcando envío, instalación, evaluación, fiscal y Estado.
- [ ] Listado: cinco símbolos, en este orden — envío, instalación, evaluación, fiscal, Estado.
- [ ] Detalle: cinco chips, en el mismo orden. **"Requiere evaluación previa" tiene que estar**:
      es la divergencia deliberada con la web, y si falta, alguien copió la exclusión.

## 4. Sin requisitos, sin rastro

- [ ] Una solicitud sin ninguna casilla marcada: ni símbolos en la tarjeta, ni chips en el detalle,
      ni un hueco vertical de más entre el título y lo que sigue.

## 5. Solicitud ajena

- [ ] "Mis solicitudes" → "Ver solicitudes de usuarios" → tocar una con requisitos: símbolos en la
      tarjeta y chips en el detalle.

## 6. Modo oscuro

- [ ] Repasar las seis superficies en oscuro. El teal tiene que leerse sobre el fondo oscuro y no
      confundirse con el azul de "Oferta aceptada" ni con el verde de "Desbloqueado".
```

- [ ] **Step 5: Commit**

```bash
git add docs/qa/2026-08-02-smoke-requisitos-app.md
git commit -m "docs(app): guion de smoke de los requisitos en device

Cubre lo que ningun test alcanza: el detalle del proveedor (sin costura) y los
simbolos de "Para ti", cuyos datos vienen de la oleada B y en los tests siempre
llegan vacios.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Reportar el estado**

Informar: número final de tests, resultado de `flutter analyze`, si el APK de release compiló, y qué
puntos del smoke quedan pendientes de correr en device. **No** dar el trabajo por cerrado hasta que
el smoke se haya ejecutado: los símbolos de "Para ti" son el único camino que ningún test recorre.
