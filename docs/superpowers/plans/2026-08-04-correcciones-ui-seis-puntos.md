# Seis correcciones de UI — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplicar las seis correcciones de UI del spec
`2026-08-04-correcciones-ui-seis-puntos-design.md` en la app Flutter y en la
web, sin cambiar ningún contrato de base de datos.

**Architecture:** Los seis puntos son independientes entre sí. Cada uno que
tenga lógica se extrae a un módulo puro o a un widget aislado y se prueba ahí;
las pantallas grandes solo se cablean. Cero migraciones, cero cambios de RPC.

**Tech Stack:** Flutter 3 / Dart (app), React 19 + TanStack Router + Tailwind
(web), Supabase en ambos.

## Global Constraints

- **Dos repositorios distintos.** App: `C:\Users\ac\Downloads\jayalo-app`.
  Web: `C:\Users\ac\Downloads\jayalo-main\jayalo-main` (el interior, no el
  envoltorio).
- **El árbol de la web está sucio con trabajo de otra sesión**
  (`src/integrations/supabase/types.ts` modificado, una migración sin
  seguimiento, ficheros sueltos). **Nunca `git add -A` ni `git add .` en la
  web**: siempre `git add <ruta exacta>` de los ficheros de esta tanda.
- **Comentarios y mensajes de commit sin tildes** (convención del repo). El
  texto de interfaz que ve el usuario **sí lleva tildes**.
- Nada se pushea ni se mergea sin decisión del PO.
- Colores siempre desde `core/brand.dart` / `brand_kit.dart` en la app y desde
  los tokens de Tailwind en la web. Nunca un `Color(0x…)` ni un hex suelto.
- App: `flutter analyze` sin issues nuevos antes de cada commit.
- Web: `npx tsc --noEmit` en 0 errores (baseline del repo) antes de cada
  commit.
- «Nuevo/Usado» y «Garantía» son campos **solo de producto** en las dos
  superficies. En servicio no se muestran ni se validan.

## Ramas

- App: crear `feat/correcciones-ui-08-04` desde `feat/detalle-cliente-plegable`.
- Web: crear `feat/correcciones-ui-08-04` desde `feat/direccion-precisa`.
- **Excepción, solo la Task 15:** va sobre `feat/cotejo-visible-cliente`,
  porque el componente que toca únicamente existe en esa rama.

## Estructura de ficheros

**App — crear:**

| Fichero | Responsabilidad |
|---|---|
| `lib/features/shared/wholesale_card.dart` | Tarjeta de mayoreo. Sin decisiones: recibe los cuatro datos ya crudos y los pinta. |
| `lib/features/shared/location_coverage_picker.dart` | Cascada país → provincia → sector. Sin red, sin sesión, sin persistencia. |
| `lib/core/unsaved_guard.dart` | Registro de «hay cambios sin guardar». Un solo `bool Function()?`. |
| `test/wholesale_card_test.dart`, `test/location_coverage_picker_test.dart` | Tests de los dos widgets nuevos. |

**App — modificar:**

| Fichero | Cambio |
|---|---|
| `lib/domain/offer_message.dart` | `conditionFromOfferMessage`, inverso de la condición. |
| `lib/features/provider/request_detail_screen.dart` | Puntos 2, 3, 4 y 5. Es el fichero más tocado (1856 líneas); todo lo que se pueda sacar, se saca. |
| `lib/features/client/offer_requirement_coverage.dart` | Punto 6. |
| `lib/features/shell/back_guard.dart` | Consultar el registro antes de actuar. |
| `lib/features/onboarding/provider_onboarding_screen.dart` | Punto 1. |

**Web — modificar:**

| Fichero | Cambio |
|---|---|
| `src/components/provider/RequestRespondSection.tsx` | Puntos 2, 3, 4 y 5. |
| `src/components/marketplace/OfferRequirementCoverage.tsx` | Punto 6 (otra rama). |

---

# APP

## Task 1: `conditionFromOfferMessage` — inverso de la condición

Base del punto 5. Sin esto, hacer «Nuevo/Usado» obligatorio obliga al
proveedor a volver a marcarlo cada vez que edita una oferta.

**Files:**
- Modify: `app/lib/domain/offer_message.dart`
- Test: `app/test/offer_message_test.dart` (ya existe, se le añaden casos)

**Interfaces:**
- Consumes: `composeOfferMessage` (ya existe en el mismo fichero).
- Produces: `String conditionFromOfferMessage(String message)` → `'Nuevo'`,
  `'Usado'` o `''`. La Task 2 la usa desde `_prefillFromOffer`.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `app/test/offer_message_test.dart`, dentro del `main()`
existente. Si el fichero agrupa con `group(...)`, añadir un grupo nuevo:

```dart
  group('conditionFromOfferMessage', () {
    test('ida y vuelta con Nuevo', () {
      final m = composeOfferMessage(isService: false, condition: 'Nuevo');
      expect(conditionFromOfferMessage(m), 'Nuevo');
    });

    test('ida y vuelta con Usado', () {
      final m = composeOfferMessage(isService: false, condition: 'Usado');
      expect(conditionFromOfferMessage(m), 'Usado');
    });

    test('lo encuentra aunque no sea la primera parte', () {
      final m = composeOfferMessage(
        isService: false,
        condition: 'Usado',
        brand: 'Rimax',
        warranty: '7 días',
        offersShipping: true,
      );
      expect(conditionFromOfferMessage(m), 'Usado');
    });

    test('mensaje sin condicion devuelve vacio', () {
      final m = composeOfferMessage(isService: false, brand: 'Rimax');
      expect(conditionFromOfferMessage(m), '');
    });

    test('mensaje de servicio devuelve vacio', () {
      final m = composeOfferMessage(
          isService: true, availabilityNote: 'Lunes a viernes');
      expect(conditionFromOfferMessage(m), '');
    });

    test('mensaje vacio devuelve vacio', () {
      expect(conditionFromOfferMessage(''), '');
    });

    test('un valor que no es Nuevo ni Usado no se acepta', () {
      expect(conditionFromOfferMessage('Estado: Reacondicionado'), '');
    });

    test('el texto libre de la web no dispara falsos positivos', () {
      // La web todavia tiene caja de comentario y su texto acaba en la misma
      // columna `message`. Mencionar el estado en prosa no debe colar.
      expect(
        conditionFromOfferMessage(
            'Silla Rimax en buen estado: Nuevo modelo 2026'),
        '',
      );
      expect(conditionFromOfferMessage('El estado: nuevo, sin uso'), '');
    });
  });
```

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd app && flutter test test/offer_message_test.dart
```

Esperado: FAIL — `conditionFromOfferMessage` no está definida.

- [ ] **Step 3: Implementar**

Añadir al final de `app/lib/domain/offer_message.dart`:

```dart
/// Inverso de la condicion que escribe [composeOfferMessage].
///
/// La oferta NO guarda "Nuevo/Usado" en columna propia: viaja dentro de
/// `message` como la parte `Estado: <valor>`. Con el campo vuelto obligatorio,
/// editar una oferta sin esto obligaria al proveedor a volver a marcarlo en
/// cada pasada.
///
/// En la app el mensaje se arma solo con partes estructuradas unidas por
/// ' · ' (decision PO 2026-07-20, que quito la caja de texto libre). La WEB
/// todavia tiene esa caja y su texto acaba en la misma columna, asi que este
/// parser tiene que ser conservador y lo es: exige el prefijo 'Estado: '
/// exacto sobre una parte completa y solo acepta 'Nuevo' o 'Usado'. Un
/// proveedor tendria que escribir literalmente "Estado: Nuevo" como segmento
/// entre ' · ' para enganarlo, y el dano seria prellenar un valor plausible.
///
/// Devuelve '' si no reconoce nada: el peor caso deja el campo vacio y el
/// proveedor elige, que es exactamente lo que pasaba antes de esta funcion.
/// Nunca inventa un valor.
String conditionFromOfferMessage(String message) {
  const prefijo = 'Estado: ';
  for (final parte in message.split(' · ')) {
    final t = parte.trim();
    if (!t.startsWith(prefijo)) continue;
    final valor = t.substring(prefijo.length).trim();
    if (valor == 'Nuevo' || valor == 'Usado') return valor;
  }
  return '';
}
```

- [ ] **Step 4: Correr y verificar que pasa**

```bash
cd app && flutter test test/offer_message_test.dart
```

Esperado: PASS, todos los casos.

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/offer_message.dart app/test/offer_message_test.dart
git commit -m "feat(app): recuperar Nuevo/Usado del mensaje de la oferta"
```

---

## Task 2: Punto 5 app — estado y garantía obligatorios

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
  - `_prefillFromOffer` (`:242-274`)
  - `_submit`, tras la validación de precio (`:517-534`)
  - `_productDetails` (`:1289-1320`)

**Interfaces:**
- Consumes: `conditionFromOfferMessage` de la Task 1.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Restaurar la condición al editar**

En `_prefillFromOffer`, junto a las otras líneas de producto (después de
`_warranty.text = …`, sobre `:265`):

```dart
    _condition = conditionFromOfferMessage((o['message'] as String?) ?? '');
```

Comprobar que `message` viene en el `select` que carga la oferta a editar. Si
no está en la lista de columnas, añadirlo — sin él la línea devuelve siempre
`''` en silencio.

Y borrar la mentira del docstring de `_prefillFromOffer` (`:240-241`), que
dice que la condición es el «único no restaurable». Sustituir esas dos líneas
por:

```dart
  /// asi que la reconstruccion es directa. "Nuevo/Usado" no tiene columna
  /// propia y se recupera del mensaje con `conditionFromOfferMessage`.
```

- [ ] **Step 2: Marcar los campos como requeridos en la UI**

En `_productDetails` (`:1289`), cambiar el encabezado y los dos rótulos:

```dart
  List<Widget> _productDetails(BuildContext context) => [
        _sectionLabel('Detalles del producto'),
        const SizedBox(height: 8),
        _txtField(_brand, 'Marca'),
        const SizedBox(height: 14),
        _sectionLabel('Estado *'),
        const SizedBox(height: 8),
        _chipSelect(_conditionOptions, _condition,
            (v) => setState(() => _condition = v)),
        const SizedBox(height: 14),
        _sectionLabel('Color'),
        const SizedBox(height: 8),
        _colorSwatches(),
        const SizedBox(height: 14),
        _sectionLabel('Garantía *'),
```

El resto de `_productDetails` no cambia.

- [ ] **Step 3: Validar en el envío**

En `_submit`, justo después del `switch (mode)` que valida el precio (tras
`:534`) y **antes** del cotejo de requisitos:

```dart
    // Solo producto: en servicio estos dos campos ni se envian (ver los
    // `isService ? '' : ...` de composeOfferMessage mas abajo).
    if (!isService) {
      if (_condition.isEmpty) {
        return _toast('Elige si el producto es nuevo o usado.');
      }
      if (_warranty.text.trim().isEmpty) {
        // 'Sin garantia' es uno de los presets: exigir el campo no obliga a
        // nadie a prometer garantia, solo a decirlo.
        return _toast('Elige la garantía.');
      }
    }
```

- [ ] **Step 4: Analizar y probar**

```bash
cd app && flutter analyze && flutter test
```

Esperado: analyze sin issues nuevos, suite verde. Ningún test existente monta
este formulario, así que no debería romperse nada; si algo falla, es real.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): estado y garantia obligatorios en la oferta de producto"
```

---

## Task 3: Punto 2 app — borde violeta en el precio

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`,
  `_pricingFields` (`:1096-1124`)

**Interfaces:**
- Consumes: nada.
- Produces: nada.

- [ ] **Step 1: Envolver el bloque completo**

Reescribir `_pricingFields` entero. El envoltorio es uno solo y las dos ramas
van dentro, para no duplicarlo:

```dart
  /// Campos de precio, ramificados por kind: producto = fijo/rango; servicio =
  /// 4 modos (fijo/rango/por hora/a evaluar), paridad con la web.
  ///
  /// Todo el bloque va dentro de un marco violeta (pedido PO 2026-08-04). El
  /// selector de modo entra en el marco a proposito: elegir "Rango" o "Por
  /// hora" es parte de decir el precio, no un ajuste aparte.
  List<Widget> _pricingFields(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _isService
              ? _servicePricing(context)
              : _productPricing(context),
        ),
      ),
    ];
  }

  List<Widget> _productPricing(BuildContext context) => [
        PillSegmented(
          options: const ['Precio fijo', 'Rango'],
          index: _fixed ? 0 : 1,
          onChanged: (i) => setState(() => _fixed = i == 0),
        ),
        const SizedBox(height: 12),
        if (_fixed)
          _numField(_price, 'Precio (RD\$)')
        else
          Row(children: [
            Expanded(child: _numField(_min, 'Desde (RD\$)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_max, 'Hasta (RD\$)')),
          ]),
      ];

  List<Widget> _servicePricing(BuildContext context) => [
        PillSegmented(
          options: const ['Fijo', 'Rango', 'Por hora', 'A evaluar'],
          index: _svcMode,
          onChanged: (i) => setState(() => _svcMode = i),
        ),
        const SizedBox(height: 12),
        ..._svcModeFields(context),
      ];
```

`_svcModeFields` no se toca: su contenedor gris del modo «a evaluar» se queda
como está, es un aviso dentro del marco y no compite con él.

`cs.primary` ya resuelve al violeta correcto en cada tema
(`JayaloColors.primary` en claro, `dPrimary` en oscuro), así que no hace falta
ramificar por brillo.

- [ ] **Step 2: Verificar que el marco no se corta en oscuro**

```bash
cd app && flutter analyze && flutter test
```

Esperado: analyze limpio, suite verde. La comprobación visual real es del
smoke; aquí solo se confirma que nada compila mal.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): marco violeta alrededor del bloque de precio"
```

---

## Task 4: Punto 6 app — verde y gris en el cotejo

**Files:**
- Modify: `app/lib/features/client/offer_requirement_coverage.dart`
- Test: `app/test/offer_requirement_coverage_test.dart`

**Interfaces:**
- Consumes: `JayaloColors.success` / `JayaloColors.dSuccess` de
  `lib/core/brand.dart`.
- Produces: nada.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final del `main()` de
`app/test/offer_requirement_coverage_test.dart`. El helper `montar` ya existe
en ese fichero y acepta `brillo`:

```dart
  Color colorDeIcono(WidgetTester tester, IconData icono) =>
      tester.widget<Icon>(find.byIcon(icono)).color!;

  testWidgets('lo cumplido va en verde y lo no cumplido en gris (claro)',
      (tester) async {
    await montar(
      tester,
      const RequestRequirements(
        withShipping: true,
        requiresStateSupplier: true,
      ),
      const OfferCapabilities(offersShipping: true),
    );
    expect(colorDeIcono(tester, Icons.check_circle_outline),
        JayaloColors.success);
    expect(colorDeIcono(tester, Icons.remove_circle_outline),
        isNot(JayaloColors.success));
  });

  testWidgets('en oscuro el verde es el del tema oscuro', (tester) async {
    await montar(
      tester,
      const RequestRequirements(withShipping: true),
      const OfferCapabilities(offersShipping: true),
      brillo: Brightness.dark,
    );
    expect(colorDeIcono(tester, Icons.check_circle_outline),
        JayaloColors.dSuccess);
  });
```

Añadir el import que falta al principio del fichero:

```dart
import 'package:jayalo_app/core/brand.dart';
```

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd app && flutter test test/offer_requirement_coverage_test.dart
```

Esperado: FAIL — hoy los dos íconos son `onSurfaceVariant`.

- [ ] **Step 3: Implementar**

En `app/lib/features/client/offer_requirement_coverage.dart`, dentro del
`build`, sustituir el comentario obsoleto y el `Icon`/`Text` del bucle:

```dart
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final verde = dark ? JayaloColors.dSuccess : JayaloColors.success;
```

y dentro del `for`:

```dart
              children: [
                // Verde lo que esta oferta cubre, gris lo que no (pedido PO
                // 2026-08-04, que revierte la decision anterior de pintar los
                // dos estados en gris). El negativo sigue SIN ambar ni icono
                // de alarma: no se acusa a un proveedor que quiza cumple y
                // solo no lo declaro. El estado tampoco depende solo del
                // color: los dos iconos ya son distintos.
                Icon(
                  c.covered
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                  size: 13,
                  color: c.covered ? verde : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.covered ? verde : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
```

Añadir el import de `brand.dart` al fichero. Borrar el comentario viejo de
`:44-46` — el nuevo lo sustituye; dejar los dos haría que la próxima revisión
lo «arregle» de vuelta a gris.

- [ ] **Step 4: Correr y verificar que pasa**

```bash
cd app && flutter test test/offer_requirement_coverage_test.dart && flutter analyze
```

Esperado: PASS los seis tests del fichero (los cuatro viejos siguen verdes) y
analyze limpio.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/client/offer_requirement_coverage.dart app/test/offer_requirement_coverage_test.dart
git commit -m "feat(app): el cotejo pinta en verde lo que la oferta cumple"
```

---

## Task 5: `WholesaleCard` — la tarjeta de mayoreo

**Files:**
- Create: `app/lib/features/shared/wholesale_card.dart`
- Test: `app/test/wholesale_card_test.dart`

**Interfaces:**
- Consumes: `wholesaleSplitLabel`, `wholesalePackagingLabel` de
  `lib/domain/wholesale.dart`.
- Produces: `WholesaleCard({int? quantity, String? split, String? packaging,
  String? note})`. La Task 6 la monta.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/wholesale_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/wholesale_card.dart';

void main() {
  Future<void> montar(WidgetTester tester, WholesaleCard tarjeta,
      {Brightness brillo = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(brillo),
      home: Scaffold(body: tarjeta),
    ));
  }

  testWidgets('el rotulo es el encabezado y va grande', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500));
    final rotulo = tester.widget<Text>(find.text('Al por mayor'));
    expect(rotulo.style!.fontSize, 16);
  });

  testWidgets('solo pinta las filas que tienen dato', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500));
    expect(find.text('Cantidad'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('División'), findsNothing);
    expect(find.text('Empaque'), findsNothing);
    expect(find.text('Detalle'), findsNothing);
  });

  testWidgets('traduce los slugs de division y empaque', (tester) async {
    await montar(
      tester,
      const WholesaleCard(quantity: 500, split: 'yes', packaging: 'box'),
    );
    expect(find.text('División'), findsOneWidget);
    expect(find.text('Empaque'), findsOneWidget);
    // No se filtra el slug crudo a la pantalla.
    expect(find.text('yes'), findsNothing);
    expect(find.text('box'), findsNothing);
  });

  testWidgets('el detalle va aparte y completo', (tester) async {
    await montar(
      tester,
      const WholesaleCard(
          quantity: 500, note: 'Que sean apilables y del mismo color.'),
    );
    expect(find.text('Detalle'), findsOneWidget);
    expect(find.text('Que sean apilables y del mismo color.'), findsOneWidget);
  });

  testWidgets('sin ningun dato sigue mostrando el rotulo', (tester) async {
    // Una solicitud puede estar marcada como mayoreo sin haber rellenado
    // nada: el rotulo es la identidad y no puede desaparecer.
    await montar(tester, const WholesaleCard());
    expect(find.text('Al por mayor'), findsOneWidget);
  });

  testWidgets('en oscuro pinta sin reventar', (tester) async {
    await montar(tester, const WholesaleCard(quantity: 500),
        brillo: Brightness.dark);
    expect(find.text('Al por mayor'), findsOneWidget);
  });
}
```

Los slugs `'yes'` y `'box'` son ejemplos: abrir
`app/lib/domain/wholesale.dart` y usar dos slugs **reales** de
`kWholesaleSplitOptions` y `kWholesalePackagingOptions`, con sus etiquetas
reales en los `expect`.

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd app && flutter test test/wholesale_card_test.dart
```

Esperado: FAIL — el fichero `wholesale_card.dart` no existe.

- [ ] **Step 3: Implementar**

Crear `app/lib/features/shared/wholesale_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../domain/wholesale.dart';

/// Los datos de mayoreo de una solicitud, en una tarjeta cuyo encabezado ES el
/// rotulo "Al por mayor" (variante A aprobada por el PO 2026-08-04).
///
/// Antes eran un chip pequenito junto al titulo mas cuatro lineas de texto
/// plano perdidas bajo "Informacion", a dos secciones de distancia.
///
/// **No decide nada**: recibe los cuatro datos crudos de la fila y los pinta.
/// La traduccion de slugs la hacen `wholesaleSplitLabel` y
/// `wholesalePackagingLabel`, que ya tienen sus propios tests.
///
/// Se dibuja SIEMPRE que la solicitud sea de mayoreo, aunque no haya ni un
/// dato: el rotulo es identidad de la solicitud, no informacion opcional.
class WholesaleCard extends StatelessWidget {
  const WholesaleCard({
    super.key,
    this.quantity,
    this.split,
    this.packaging,
    this.note,
  });

  final int? quantity;
  final String? split;
  final String? packaging;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tono =
        dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight;
    final tieneNota = note != null && note!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tono.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.storefront_outlined, size: 19, color: tono.ink),
            const SizedBox(width: 7),
            Text('Al por mayor',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tono.ink)),
          ]),
          if (quantity != null) ...[
            const SizedBox(height: 10),
            _fila(context, 'Cantidad', '$quantity'),
          ],
          if (split != null) _fila(context, 'División', wholesaleSplitLabel(split)),
          if (packaging != null)
            _fila(context, 'Empaque', wholesalePackagingLabel(packaging)),
          if (tieneNota) ...[
            const SizedBox(height: 9),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.25)),
            const SizedBox(height: 8),
            Text('Detalle',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            // El detalle es texto libre del cliente y puede ser largo: va a
            // ancho completo, no en una fila de dos columnas.
            Text(note!.trim(),
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: cs.onSurface)),
          ],
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, String etiqueta, String valor) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(valor,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
```

Comprobar la firma real de `wholesaleSplitLabel` / `wholesalePackagingLabel`
en `lib/domain/wholesale.dart` (aceptan `String?`) y ajustar si difiere.

- [ ] **Step 4: Correr y verificar que pasa**

```bash
cd app && flutter test test/wholesale_card_test.dart && flutter analyze
```

Esperado: PASS los seis tests, analyze limpio.

**Cuidado conocido:** en `flutter test` el texto mide alrededor del doble de
lo real. Ninguna aserción de este fichero debe depender de anchos ni de que
algo «quepa» — si aparece un overflow en el test, comprobarlo en device antes
de tocar el diseño.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shared/wholesale_card.dart app/test/wholesale_card_test.dart
git commit -m "feat(app): tarjeta de mayoreo con el rotulo como encabezado"
```

---

## Task 6: Punto 3 app — cablear la tarjeta y arreglar `_hasInfo`

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
  - chip actual (`:1538-1547`)
  - bloque de texto plano (`:1582-1603`)
  - `_hasInfo` (`:1201-1205`)
- Test: `app/test/wholesale_card_test.dart` (se le añade el caso de `_hasInfo`
  si `_hasInfo` se hace testeable; ver Step 3)

**Interfaces:**
- Consumes: `WholesaleCard` de la Task 5.
- Produces: nada.

- [ ] **Step 1: Sustituir el chip por la tarjeta**

En `:1538-1547`, reemplazar el bloque del `StatusChip`:

```dart
                  if (req['is_wholesale'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: WholesaleCard(
                        quantity: (req['wholesale_quantity'] as num?)?.toInt(),
                        split: req['wholesale_split'] as String?,
                        packaging: req['wholesale_packaging'] as String?,
                        note: req['wholesale_note'] as String?,
                      ),
                    ),
```

Importar el widget nuevo. Si `StatusChip` deja de usarse en este fichero,
quitar también ese import; si sigue usándose en otro sitio del fichero,
dejarlo.

- [ ] **Step 2: Borrar el texto plano viejo**

Borrar entero el bloque `if (req['is_wholesale'] == true) ...[ … ]` de
`:1582-1603` — las cuatro líneas de `Text` con `Cantidad:`, `División:`,
`Empaque:` y `Detalle:`. Esos datos ya viven en la tarjeta.

- [ ] **Step 3: Arreglar `_hasInfo`**

Este es el paso que evita el bug: `_hasInfo` decide si se dibuja el encabezado
«Información», y si sigue contando `is_wholesale` una solicitud de mayoreo sin
bullets y sin presupuesto dejará «INFORMACIÓN» flotando sobre un divisor —
exactamente lo que se cazó en device el 2026-08-01.

```dart
  /// ¿La seccion "Informacion" tiene algo que ensenar? Es exactamente lo que
  /// se dibuja debajo del encabezado: bullets y presupuesto.
  ///
  /// `is_wholesale` NO cuenta desde 2026-08-04: los datos de mayoreo se
  /// mudaron a `WholesaleCard`, arriba con el titulo. Volver a sumarlo aqui
  /// deja "INFORMACION" flotando sobre un divisor sin nada debajo.
  static bool _hasInfo(Map<String, dynamic> req, List<String> bullets) =>
      bullets.isNotEmpty ||
      requestBudgetLabel(req['budget_min'] as num?, req['budget_max'] as num?) !=
          null;
```

`_hasInfo` es `static` y privada, así que ningún test puede llamarla sin abrir
la clase, y copiar su condición en un test sería un test que se prueba a sí
mismo. Este caso queda cubierto por el smoke (Task 16, casilla 6), que es
donde tiene que verificarse de todos modos: el bug es visual.

- [ ] **Step 4: Analizar y probar**

```bash
cd app && flutter analyze && flutter test
```

Esperado: analyze limpio (ojo a imports que quedaron sin usar tras borrar el
bloque viejo), suite verde.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): los datos de mayoreo suben a su tarjeta, fuera de Informacion"
```

---

## Task 7: `unsavedOfferGuard` + `BackGuard`

Infraestructura del punto 4. Sin pantalla que la use todavía: al terminar esta
tarea el comportamiento no cambia, y eso es correcto.

**Files:**
- Create: `app/lib/core/unsaved_guard.dart`
- Modify: `app/lib/features/shell/back_guard.dart`
- Test: `app/test/unsaved_guard_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `void setUnsavedGuard(bool Function()? check)` — registra o quita.
  - `bool hasUnsavedChanges()` — `false` si no hay nada registrado.
  - `Future<bool> confirmDiscard(BuildContext context)` — muestra el diálogo,
    devuelve `true` si el usuario acepta salir.
  La Task 8 usa las tres.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/unsaved_guard_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/unsaved_guard.dart';

void main() {
  tearDown(() => setUnsavedGuard(null));

  test('sin nada registrado no hay cambios sin guardar', () {
    expect(hasUnsavedChanges(), isFalse);
  });

  test('registrado y sucio dice que si', () {
    setUnsavedGuard(() => true);
    expect(hasUnsavedChanges(), isTrue);
  });

  test('registrado y limpio dice que no', () {
    setUnsavedGuard(() => false);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('quitar el registro lo deja en falso aunque estuviera sucio', () {
    setUnsavedGuard(() => true);
    setUnsavedGuard(null);
    expect(hasUnsavedChanges(), isFalse);
  });

  test('se consulta en cada llamada, no se cachea', () {
    var sucio = false;
    setUnsavedGuard(() => sucio);
    expect(hasUnsavedChanges(), isFalse);
    sucio = true;
    expect(hasUnsavedChanges(), isTrue);
  });

  testWidgets('el dialogo ofrece seguir editando y salir', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    expect(find.text('¿Salir y descartar los cambios?'), findsOneWidget);
    expect(find.text('Seguir editando'), findsOneWidget);
    await tester.tap(find.text('Salir y descartar'));
    await tester.pumpAndSettle();
    expect(await futuro, isTrue);
  });

  testWidgets('seguir editando devuelve false', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final futuro = confirmDiscard(ctx);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(await futuro, isFalse);
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd app && flutter test test/unsaved_guard_test.dart
```

Esperado: FAIL — `unsaved_guard.dart` no existe.

- [ ] **Step 3: Implementar el registro**

Crear `app/lib/core/unsaved_guard.dart`:

```dart
import 'package:flutter/material.dart';

/// Registro de "hay cambios sin guardar en la pantalla actual".
///
/// Existe porque `BackGuard` envuelve CADA pantalla del shell con
/// `PopScope(canPop: false)` e intercepta todo el atras del sistema, incluido
/// el predictive back de Android 13+ (ver back_guard.dart). Una pantalla no
/// puede poner su propio PopScope encima sin pelearse con el, asi que en vez
/// de competir, le da a BackGuard una forma de preguntar.
///
/// Guarda una FUNCION, no un booleano: la suciedad se calcula en el momento de
/// salir. El formulario de oferta tiene once controladores de texto y
/// mantenerlos sincronizados con listeners seria una fuente de bugs sin
/// ninguna ventaja, porque el valor solo hace falta una vez.
///
/// Patron igual al de `roleStore` y `homeScrollController`: singleton de
/// modulo, no InheritedWidget, porque quien pregunta (BackGuard) esta en otra
/// rama del arbol que quien responde.
bool Function()? _check;

/// Registra la comprobacion, o la quita con `null`. Quien registra DEBE quitar
/// en `dispose`, o una pantalla muerta seguira bloqueando el atras de la
/// siguiente.
void setUnsavedGuard(bool Function()? check) => _check = check;

/// `false` si no hay nada registrado. Se consulta en cada llamada.
bool hasUnsavedChanges() => _check?.call() ?? false;

/// Pregunta si se puede tirar el trabajo. `true` = el usuario quiere salir.
Future<bool> confirmDiscard(BuildContext context) async {
  final salir = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Salir y descartar los cambios?'),
      content: const Text('Perderás lo que escribiste en esta oferta.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Seguir editando'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('Salir y descartar',
              style: TextStyle(color: Theme.of(c).colorScheme.error)),
        ),
      ],
    ),
  );
  return salir == true;
}
```

- [ ] **Step 4: Consultarlo desde `BackGuard`**

En `app/lib/features/shell/back_guard.dart`, `_handleBack` pasa a ser `async`
y pregunta antes de resolver su acción:

```dart
  Future<void> _handleBack(BuildContext context) async {
    // Antes de cualquier navegacion: si la pantalla actual tiene trabajo sin
    // guardar, se pregunta. Vale para las cinco BackAction — la de irse a otra
    // pantalla y la de salir de la app.
    if (hasUnsavedChanges()) {
      final salir = await confirmDiscard(context);
      if (!salir) return;
      if (!context.mounted) return;
    }
    final loc = GoRouterState.of(context).matchedLocation;
```

El resto del cuerpo no cambia. Añadir el import de
`../../core/unsaved_guard.dart`.

`onPopInvokedWithResult` no espera futuros; la llamada se queda igual y el
análisis puede pedir un `unawaited` — usar el que ya use el repo, o dejar la
llamada como `_handleBack(context);` si `flutter analyze` no protesta.

- [ ] **Step 5: Correr y verificar que pasa**

```bash
cd app && flutter test test/unsaved_guard_test.dart test/back_intent_test.dart && flutter analyze
```

Esperado: PASS los siete tests nuevos, `back_intent_test.dart` sigue verde
(prueba `backActionFor`, que no se toca), analyze limpio.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/unsaved_guard.dart app/lib/features/shell/back_guard.dart app/test/unsaved_guard_test.dart
git commit -m "feat(app): registro de cambios sin guardar que BackGuard consulta"
```

---

## Task 8: Punto 4 app — cablear el formulario de oferta

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
  - estado de la pantalla: instantánea del prellenado
  - `_prefillFromOffer` (`:242`)
  - `initState` / `dispose` (`:276-286`)
  - `_submit`, tras el envío correcto
  - `_backButton` (`:1839-1855`)

**Interfaces:**
- Consumes: `setUnsavedGuard`, `hasUnsavedChanges`, `confirmDiscard` de la
  Task 7.
- Produces: nada.

- [ ] **Step 1: Tomar la instantánea del estado limpio**

Añadir un campo al estado de la pantalla y un método que serialice el
formulario. La comparación se hace contra la instantánea, **no contra vacío**:
si no, editar una oferta sin tocar nada pediría confirmación.

```dart
  /// Foto del formulario en su estado "limpio": vacio al crear, o lo que dejo
  /// `_prefillFromOffer` al editar. La suciedad se decide comparando contra
  /// esto, no contra cadenas vacias.
  String _cleanSnapshot = '';

  /// Serializa TODO lo que el proveedor puede cambiar. Si se anade un campo
  /// nuevo al formulario, hay que sumarlo aqui o el aviso de salida no lo vera.
  String _formSnapshot() => [
        _price.text, _min.text, _max.text, _hourly.text, _hours.text,
        _availability.text, _duration.text,
        _shipping.text, _installation.text, _evaluation.text,
        _brand.text, _warranty.text, _delivery.text,
        _condition,
        '$_fixed', '$_svcMode',
        '$_offersShipping', '$_offersInstallation', '$_requiresEvaluation',
        _colors.join(','),
        _photos.length.toString(),
        _keptUrls.join(','),
      ].join('\u0000');
```

- [ ] **Step 2: Registrar y quitar el guard**

Al final de `initState` (y al final de `_prefillFromOffer`, que corre después
en modo edición):

```dart
    _cleanSnapshot = _formSnapshot();
    setUnsavedGuard(() => _formSnapshot() != _cleanSnapshot);
```

En `_prefillFromOffer`, esas dos líneas van **al final del método**, después
de rellenar todo — si van antes, la instantánea guarda el formulario vacío y
la pantalla nace sucia.

En `dispose`, **antes** del `super.dispose()`:

```dart
    setUnsavedGuard(null);
```

- [ ] **Step 3: Limpiar tras enviar con éxito**

En `_submit`, en el punto donde el envío ya salió bien y antes de navegar
(justo antes del `context.pop()` o del `context.go(...)` de éxito):

```dart
      // Enviada: lo que hay en el formulario ya esta guardado, la navegacion
      // que viene no debe preguntar nada.
      setUnsavedGuard(null);
```

Hacerlo en **todos** los caminos de éxito de `_submit` — crear y guardar
cambios. Buscar cada salida exitosa del método antes de escribir.

- [ ] **Step 4: Preguntar también en la flecha flotante**

`_backButton` (`:1839`) llama a `context.pop()` sin pasar por `BackGuard`, así
que necesita la misma pregunta:

```dart
          child: InkWell(
            onTap: () async {
              // Mismo aviso que el atras del sistema: esta flecha no pasa por
              // BackGuard.
              if (hasUnsavedChanges()) {
                final salir = await confirmDiscard(context);
                if (!salir) return;
                if (!context.mounted) return;
              }
              context.pop();
            },
```

`_backButton` recibe `BuildContext` como parámetro, así que el `context` de
dentro es válido. Añadir el import de `../../core/unsaved_guard.dart`.

- [ ] **Step 5: Comprobar el otro camino de `_cancelInPlaceEdit`**

`_cancelInPlaceEdit` (usado por el botón «Cancelar» en edición en sitio, ver
`:1811-1814`) **no** debe preguntar: cancelar ya es la respuesta explícita del
usuario a esa pregunta. Verificar que ese método deja el formulario en un
estado que no dispare el aviso después — si restaura el prellenado, añadir al
final:

```dart
    _cleanSnapshot = _formSnapshot();
```

- [ ] **Step 6: Analizar y probar**

```bash
cd app && flutter analyze && flutter test
```

Esperado: analyze limpio, suite verde.

**Este punto no lo cubre ningún test automático.** El comportamiento real
depende de `PopScope` y del predictive back de Android 13+, que ya se
comprobó una vez que no se deduce del código. El gate es el smoke.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): avisar antes de salir de una oferta con cambios"
```

---

## Task 9: `LocationCoveragePicker` — la cascada de ubicación

**Files:**
- Create: `app/lib/features/shared/location_coverage_picker.dart`
- Test: `app/test/location_coverage_picker_test.dart`

**Interfaces:**
- Consumes: `kCountries`, `citiesFor`, `sectorsFor` de `lib/domain/locations.dart`.
- Produces: `LocationCoveragePicker({required String country, required
  List<String> cities, required List<String> sectors, required void
  Function({String country, List<String> cities, List<String> sectors})
  onChanged})`. La Task 10 lo monta.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/location_coverage_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/locations.dart';
import 'package:jayalo_app/features/shared/location_coverage_picker.dart';

void main() {
  // Estado que el widget no guarda: el test hace de pantalla anfitriona.
  late String pais;
  late List<String> provincias;
  late List<String> sectores;

  setUp(() {
    pais = kCountries.first;
    provincias = [];
    sectores = [];
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: StatefulBuilder(builder: (c, setLocal) {
        return Scaffold(
          body: SingleChildScrollView(
            child: LocationCoveragePicker(
              country: pais,
              cities: provincias,
              sectors: sectores,
              onChanged: ({required country, required cities, required sectors}) {
                setLocal(() {
                  pais = country;
                  provincias = cities;
                  sectores = sectors;
                });
              },
            ),
          ),
        );
      }),
    ));
  }

  testWidgets('los sectores son la union de las provincias elegidas',
      (tester) async {
    final dos = citiesFor(kCountries.first).take(2).toList();
    provincias = dos;
    await montar(tester);
    final esperados = <String>{
      ...sectorsFor(kCountries.first, dos[0]),
      ...sectorsFor(kCountries.first, dos[1]),
    };
    // El widget expone los sectores disponibles; comprobar contra su lista
    // interna via el callback de "Todos los sectores".
    await tester.tap(find.text('🗺️ Todos los sectores'));
    await tester.pumpAndSettle();
    expect(sectores.toSet(), esperados);
  });

  testWidgets('sin provincia elegida no hay sectores que ofrecer',
      (tester) async {
    await montar(tester);
    expect(find.text('🗺️ Todos los sectores'), findsNothing);
  });

  testWidgets('con todos seleccionados se colapsa a un solo chip',
      (tester) async {
    final una = citiesFor(kCountries.first)
        .firstWhere((c) => sectorsFor(kCountries.first, c).length > 1);
    provincias = [una];
    sectores = sectorsFor(kCountries.first, una).toList();
    await montar(tester);
    // Un unico chip resumen, no la lista entera.
    for (final s in sectores) {
      expect(find.widgetWithText(Chip, s), findsNothing);
    }
  });

  testWidgets('quitar una provincia se lleva sus sectores exclusivos',
      (tester) async {
    final ciudades = citiesFor(kCountries.first);
    final a = ciudades[0];
    provincias = [a];
    sectores = sectorsFor(kCountries.first, a).take(1).toList();
    await montar(tester);
    // Quitar la unica provincia deja los sectores vacios.
    await tester.tap(find.byTooltip('Quitar $a'));
    await tester.pumpAndSettle();
    expect(sectores, isEmpty);
  });

  testWidgets('un sector fuera del catalogo sobrevive', (tester) async {
    final una = citiesFor(kCountries.first).first;
    provincias = [una];
    sectores = ['Parque del Este'];
    await montar(tester);
    // Se ofrece y se mantiene seleccionado aunque kLocations no lo conozca.
    expect(find.text('Parque del Este'), findsWidgets);
  });
}
```

Estos tests dependen de la API exacta del widget (tooltips, tipos de chip). Al
implementar el Step 3, ajustar los `find` a lo que realmente se dibuje —
**sin aflojar lo que cada test comprueba**.

- [ ] **Step 2: Correr y verificar que falla**

```bash
cd app && flutter test test/location_coverage_picker_test.dart
```

Esperado: FAIL — el fichero no existe.

- [ ] **Step 3: Implementar**

Crear `app/lib/features/shared/location_coverage_picker.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/locations.dart';

const kAllSectorsLabel = '🗺️ Todos los sectores';

/// Cascada pais -> provincia -> sector para declarar DONDE trabaja un
/// proveedor. Multi-seleccion en provincia y sector, paridad con la web
/// (`ProviderSignupWizard.tsx:1682`).
///
/// **Sin estado propio**: recibe los tres valores y emite los tres en cada
/// cambio. Quien lo monta guarda. Es un widget aparte por la misma razon que
/// `OfferRequirementCoverage`: el alta de proveedor es una pantalla enorme y
/// un test no puede montarla, este si.
class LocationCoveragePicker extends StatelessWidget {
  const LocationCoveragePicker({
    super.key,
    required this.country,
    required this.cities,
    required this.sectors,
    required this.onChanged,
  });

  final String country;
  final List<String> cities;
  final List<String> sectors;
  final void Function({
    required String country,
    required List<String> cities,
    required List<String> sectors,
  }) onChanged;

  /// Sectores que se pueden ofrecer: la union de los de cada provincia
  /// elegida, en orden de catalogo y sin duplicados, MAS los ya seleccionados
  /// que el catalogo no conoce.
  ///
  /// Esa segunda mitad es la que salva el caso "Parque del Este": es un sector
  /// real que el geocodificador devuelve y que `kLocations` no tiene. Si solo
  /// ofrecieramos el catalogo, el valor desapareceria de la pantalla sin que
  /// el proveedor se entere.
  List<String> get availableSectors {
    final delCatalogo = <String>[];
    for (final ciudad in cities) {
      for (final s in sectorsFor(country, ciudad)) {
        if (!delCatalogo.contains(s)) delCatalogo.add(s);
      }
    }
    final extra = sectors.where((s) => !delCatalogo.contains(s));
    return [...delCatalogo, ...extra];
  }

  bool get _todosLosSectores =>
      availableSectors.length > 1 && sectors.length == availableSectors.length;

  void _setCountry(String c) => onChanged(
      country: c, cities: const [], sectors: const []);

  void _addCity(String c) {
    final next = [...cities, c];
    onChanged(country: country, cities: next, sectors: sectors);
  }

  void _removeCity(String c) {
    final next = cities.where((x) => x != c).toList();
    // Los sectores que solo pertenecian a esa provincia se van con ella. Los
    // que estan fuera de catalogo se quedan: no son de ninguna provincia.
    final quedan = <String>{};
    for (final ciudad in next) {
      quedan.addAll(sectorsFor(country, ciudad));
    }
    final delCatalogo = <String>{};
    for (final ciudad in cities) {
      delCatalogo.addAll(sectorsFor(country, ciudad));
    }
    final nextSectors = sectors
        .where((s) => quedan.contains(s) || !delCatalogo.contains(s))
        .toList();
    onChanged(country: country, cities: next, sectors: nextSectors);
  }

  void _addSector(String s) {
    final next = s == kAllSectorsLabel ? availableSectors : [...sectors, s];
    onChanged(country: country, cities: cities, sectors: next);
  }

  void _removeSector(String s) => onChanged(
        country: country,
        cities: cities,
        sectors: sectors.where((x) => x != s).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final sectoresLibres =
        availableSectors.where((s) => !sectors.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _adder(
          context,
          hint: 'País',
          // Se dibuja aunque kCountries tenga un solo elemento: paridad con la
          // web y el catalogo puede crecer.
          options: kCountries,
          onPick: _setCountry,
        ),
        if (country.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _chips([country], onRemove: null),
          ),
        const SizedBox(height: 12),
        _adder(
          context,
          hint: 'Provincia',
          options:
              citiesFor(country).where((c) => !cities.contains(c)).toList(),
          onPick: _addCity,
        ),
        if (cities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _chips(cities, onRemove: _removeCity),
          ),
        const SizedBox(height: 12),
        _adder(
          context,
          hint: 'Sector (opcional)',
          options: [
            if (sectoresLibres.isNotEmpty) kAllSectorsLabel,
            ...sectoresLibres,
          ],
          onPick: _addSector,
        ),
        if (sectors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            // Todos seleccionados: un solo chip resumen en vez de la lista
            // entera, igual que la web.
            child: _todosLosSectores
                ? _chips([kAllSectorsLabel],
                    onRemove: (_) => onChanged(
                        country: country, cities: cities, sectors: const []))
                : _chips(sectors, onRemove: _removeSector),
          ),
      ],
    );
  }

  /// Desplegable que ANADE (no que selecciona): al elegir, el valor pasa a los
  /// chips de abajo y sale de la lista.
  Widget _adder(
    BuildContext context, {
    required String hint,
    required List<String> options,
    required ValueChanged<String> onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: hint,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: options.isEmpty ? null : (v) => v == null ? null : onPick(v),
    );
  }

  Widget _chips(List<String> values, {required ValueChanged<String>? onRemove}) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            Chip(
              label: Text(v),
              onDeleted: onRemove == null ? null : () => onRemove(v),
              deleteButtonTooltipMessage: 'Quitar $v',
            ),
        ],
      );
}
```

Dos comprobaciones al escribirlo:

- `DropdownButtonFormField` cambió `value` por `initialValue` en Flutter
  reciente. Usar el que acepte la versión del repo — `flutter analyze` lo dirá
  de inmediato.
- Los `find` de los tests del Step 1 asumen `Chip` y
  `deleteButtonTooltipMessage`. Si se cambia el componente de chip, ajustar los
  tests **sin aflojar lo que comprueban**.

- [ ] **Step 4: Correr y verificar que pasa**

```bash
cd app && flutter test test/location_coverage_picker_test.dart && flutter analyze
```

Esperado: PASS los cinco tests, analyze limpio.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/shared/location_coverage_picker.dart app/test/location_coverage_picker_test.dart
git commit -m "feat(app): selector en cascada de pais, provincia y sector"
```

---

## Task 10: Punto 1 app — cablear el alta de proveedor

**Files:**
- Modify: `app/lib/features/onboarding/provider_onboarding_screen.dart`
  - sección «Dónde trabajas» (`:643-659`)
  - estado y `dispose` (`:56-58`, `:123`)
  - `_useLocation` (`:296-306`)
- Test: `app/test/onboarding_provider_test.dart` (ya existe)

**Interfaces:**
- Consumes: `LocationCoveragePicker` de la Task 9.
- Produces: nada.

- [ ] **Step 1: Sustituir los dos campos de texto libre**

En `:652-655`, reemplazar los dos `_chipField`:

```dart
      LocationCoveragePicker(
        country: _country,
        cities: _cities,
        sectors: _sectors,
        onChanged: ({required country, required cities, required sectors}) {
          setState(() {
            _country = country;
            _cities
              ..clear()
              ..addAll(cities);
            _sectors
              ..clear()
              ..addAll(sectors);
          });
        },
      ),
```

Añadir el campo `_country`, inicializado a `kCountries.first`:

```dart
  String _country = kCountries.first;
```

**El nivel de obligatoriedad no cambia**: el sector sigue siendo opcional (el
rótulo del picker ya dice «Sector (opcional)»). La web lo marca con asterisco,
pero endurecer la validación del alta no es lo que se pidió y arriesga
bloquear altas que hoy pasan.

- [ ] **Step 2: Limpiar lo que sobra**

- Borrar `_cityInput` y `_sectorInput` (`:56-58`) y sacarlos de la lista de
  `dispose` (`:123`).
- Si `_addChip` y `_chipField` se quedan sin uso tras el cambio, borrarlos
  también. Si los usa otro campo de la pantalla, dejarlos.

- [ ] **Step 3: Usar el país elegido al guardar**

En `:383`, cambiar el literal por el valor del selector:

```dart
          'country': _country,
```

Las dos líneas de abajo (`_cities.join(', ')` y `_sectors.join(', ')`) **no se
tocan**: ya es lo que hace hoy y coincide con la web.

- [ ] **Step 4: `_useLocation` no necesita cambios**

Verificar y dejar como está: `:296-306` ya añade a `_cities` y `_sectors` solo
si el valor no está presente, que es exactamente lo que hace falta. El
`LocationCoveragePicker` ofrece los valores fuera de catálogo (Task 9, Step 3),
así que un sector geocodificado desconocido queda seleccionado y visible sin
tocar este método.

Si el geocodificador devuelve una ciudad que **no** está en
`citiesFor(_country)`, esa provincia no se podrá dibujar como opción. Añadir
justo después del `setState` de `:296-306`:

```dart
        // La ciudad tiene que existir en el catalogo o el selector no puede
        // ofrecerla: si no coincide, se avisa y el proveedor la elige a mano.
        if (place.city.isNotEmpty && !citiesFor(_country).contains(place.city)) {
          _snack('No reconocimos "${place.city}" — elige tu provincia.');
        }
```

y no añadirla a `_cities` en ese caso.

- [ ] **Step 5: Analizar y probar**

```bash
cd app && flutter analyze && flutter test test/onboarding_provider_test.dart && flutter test
```

Esperado: analyze limpio y suite verde. Si `onboarding_provider_test.dart`
escribía en los campos de texto de ciudad/sector, hay que reescribir esos
tests contra el selector nuevo — **no** borrarlos.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/onboarding/provider_onboarding_screen.dart app/test/onboarding_provider_test.dart
git commit -m "feat(app): el alta de proveedor elige pais, provincia y sector del catalogo"
```

---

# WEB

Todas las tareas de esta sección corren en
`C:\Users\ac\Downloads\jayalo-main\jayalo-main`, rama
`feat/correcciones-ui-08-04` — salvo la Task 15.

**Recordatorio en cada commit:** `git add` con rutas exactas. El árbol tiene
cambios de otra sesión que no deben viajar.

## Task 11: Punto 2 web — borde violeta en el precio

**Files:**
- Modify: `src/components/provider/RequestRespondSection.tsx` (líneas 1772 y
  1988)

**Interfaces:**
- Consumes: nada. Produces: nada.

- [ ] **Step 1: Cambiar los dos contenedores**

Son exactamente dos y hoy son idénticos:

- `:1772` — servicio, «Modalidad de precio». Los campos de importe (fijo,
  rango, por hora) viven **dentro** de este mismo contenedor, así que uno
  basta para toda la rama de servicio.
- `:1988` — producto, «Precio (RD$)», dentro del `CoachTooltip` del paso
  `price`.

En los dos, sustituir:

```
className="rounded-xl border border-white/10 bg-[var(--provider-surface)] p-4"
```

por:

```
className="rounded-xl border-2 border-primary/60 bg-[var(--provider-surface)] p-4"
```

Comprobar con una búsqueda que no queda ningún otro contenedor de precio sin
cambiar:

```bash
grep -n "rounded-xl border border-white/10 bg-\[var(--provider-surface)\] p-4" src/components/provider/RequestRespondSection.tsx
```

Los resultados que queden deben ser bloques que **no** son de precio (detalles
del producto, etc.). Confirmar uno a uno antes de dar el paso por bueno.

- [ ] **Step 2: Typecheck y tests**

```bash
npx tsc --noEmit && npm run test
```

Esperado: 0 errores de tipos, suite verde.

- [ ] **Step 3: Commit**

```bash
git add src/components/provider/RequestRespondSection.tsx
git commit -m "feat(web): marco violeta alrededor del bloque de precio"
```

---

## Task 12: Punto 3 web — tarjeta de mayoreo

**Files:**
- Modify: `src/components/provider/RequestRespondSection.tsx` (`:1227-1243`)

**Interfaces:**
- Consumes: `wholesaleSplitLabel`, `wholesalePackagingLabel` de
  `@/lib/wholesale` (ya importados en `:94`).
- Produces: nada.

- [ ] **Step 1: Sustituir el chip y las cuatro líneas sueltas**

Reemplazar los dos bloques `{req.isWholesale && (…)}` de `:1227-1243` por uno
solo. Misma variante A que la app: el rótulo es el encabezado de la tarjeta.

```tsx
                  {req.isWholesale && (
                    <div className="mt-2 rounded-2xl bg-primary/10 p-3.5">
                      <div className="flex items-center gap-2">
                        <Store className="h-5 w-5 text-primary" strokeWidth={1.75} />
                        <span className="text-base font-bold text-primary">Al por mayor</span>
                      </div>
                      {req.wholesaleQuantity != null && (
                        <div className="mt-2.5 flex items-start justify-between gap-3 text-sm">
                          <span className="text-slate-400">Cantidad</span>
                          <span className="font-semibold">{req.wholesaleQuantity}</span>
                        </div>
                      )}
                      {req.wholesaleSplit && (
                        <div className="mt-0.5 flex items-start justify-between gap-3 text-sm">
                          <span className="text-slate-400">División</span>
                          <span className="font-semibold">
                            {wholesaleSplitLabel(req.wholesaleSplit)}
                          </span>
                        </div>
                      )}
                      {req.wholesalePackaging && (
                        <div className="mt-0.5 flex items-start justify-between gap-3 text-sm">
                          <span className="text-slate-400">Empaque</span>
                          <span className="font-semibold">
                            {wholesalePackagingLabel(req.wholesalePackaging)}
                          </span>
                        </div>
                      )}
                      {req.wholesaleNote && (
                        <div className="mt-2.5 border-t border-white/10 pt-2">
                          <p className="text-xs text-slate-400">Detalle</p>
                          <p className="text-sm">{req.wholesaleNote}</p>
                        </div>
                      )}
                    </div>
                  )}
```

Importar `Store` de `lucide-react` si no está ya importado en el fichero.

La tarjeta se dibuja aunque no haya ni un dato: el rótulo es identidad de la
solicitud, igual que en la app.

- [ ] **Step 2: Typecheck y tests**

```bash
npx tsc --noEmit && npm run test
```

Esperado: 0 errores, suite verde.

- [ ] **Step 3: Commit**

```bash
git add src/components/provider/RequestRespondSection.tsx
git commit -m "feat(web): tarjeta de mayoreo con el rotulo como encabezado"
```

---

## Task 13: Punto 5 web — «Nuevo/Usado» nuevo y garantía obligatoria

La más grande de la web. La web parte de otro sitio que la app: **el campo
«Nuevo/Usado» no existe** (lo que se ve en `:1246` es la condición que pidió
el *cliente*), y la garantía es hoy **opcional por diseño**, dentro del grupo
`activeDetails`.

**Files:**
- Modify: `src/components/provider/RequestRespondSection.tsx`
  - estado (`:365-372`)
  - `validateActiveDetails` (`:888-898`)
  - los dos caminos de guardado (`:987-993` y `:1099-1105`)
  - el grupo opt-in (`:2429-2452`)
  - la UI de garantía (`:2557-2580`)

**Interfaces:**
- Consumes: `WARRANTY_PRESETS` (ya existe en el fichero).
- Produces: nada.

- [ ] **Step 1: Sacar la garantía del grupo opt-in**

En `:365-372`, quitar `"warranty"` del tipo y del estado inicial de
`activeDetails`:

```tsx
  const [activeDetails, setActiveDetails] = useState<
    Record<"delivery" | "color" | "brand", boolean>
  >({
    delivery: false,
    color: false,
    brand: false,
  });
```

En el grupo de botones (`:2429-2438`), borrar la entrada
`{ k: "warranty", label: "Garantía" }`.

- [ ] **Step 2: Añadir el estado de la condición**

Junto a `productWarranty` (`:365`):

```tsx
  // Lo que OFRECE el proveedor, no lo que pidio el cliente (eso es
  // `req.condition`). No tiene columna en provider_offers: viaja dentro del
  // mensaje, igual que en la app.
  const [productCondition, setProductCondition] = useState("");
```

- [ ] **Step 3: Dibujar los dos campos como obligatorios**

Dentro del bloque de detalles del producto, **fuera** de cualquier
`activeDetails.*`, para que se vean siempre en ofertas de producto. La
garantía reutiliza el mismo marcado que hoy está bajo
`{activeDetails.warranty && (…)}` (`:2557-2580`), sin la condición:

```tsx
                      <div className="rounded-lg border border-white/10 bg-[var(--provider-surface)] p-3">
                        <div className="mb-2 text-xs font-medium text-slate-400">
                          Estado <span className="text-destructive">*</span>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          {["Nuevo", "Usado"].map((c) => {
                            const on = productCondition === c;
                            return (
                              <button
                                key={c}
                                type="button"
                                onClick={() => setProductCondition(on ? "" : c)}
                                className={`rounded-full border px-3 py-1.5 text-sm transition-all ${
                                  on
                                    ? "border-primary bg-primary/10 font-semibold text-primary"
                                    : "border-white/10 bg-white/5 text-slate-400 hover:border-primary/40"
                                }`}
                              >
                                {c}
                              </button>
                            );
                          })}
                        </div>
                      </div>
```

Y el bloque de garantía igual que el actual, pero con
`Garantía <span className="text-destructive">*</span>` como rótulo y sin el
envoltorio `{activeDetails.warranty && (…)}`.

Ajustar el texto del encabezado del grupo (`:2882` aprox., «Detalles del
producto (opcionales)»): los opcionales siguen siendo opcionales, pero estado
y garantía ya no están ahí. Dejar «(opcionales)» solo sobre los chips de
entrega/color/marca.

- [ ] **Step 4: Validar**

En `validateActiveDetails` (`:888`), quitar la regla vieja de garantía y
añadir las dos nuevas. Solo producto:

```tsx
  const validateActiveDetails = (): string | null => {
    if (!isService) {
      if (!productCondition) return "Elige si el producto es nuevo o usado.";
      // 'Sin garantia' es uno de los presets: exigir el campo no obliga a
      // nadie a prometer garantia, solo a decirlo.
      if (!productWarranty.trim()) return "Elige la garantía.";
    }
    if (activeDetails.brand && !productBrand.trim())
      return "Indica la marca o desactiva esa opción.";
    if (activeDetails.color && productColor.length === 0)
      return "Selecciona al menos un color o desactiva esa opción.";
    if (activeDetails.delivery && !deliveryTime.trim())
      return "Indica el tiempo de entrega o desactiva esa opción.";
    return null;
  };
```

Comprobar que `validateActiveDetails` se llama en los dos caminos de envío. Si
solo se llama en uno, llamarla también en el otro.

- [ ] **Step 5: Guardar los dos campos**

En `:990` y `:1102`, la garantía deja de depender del opt-in:

```tsx
        product_warranty: productWarranty.trim() || null,
```

Y la condición entra en el mensaje. **Aquí la web no funciona como la app.**
La app compone el mensaje entero desde datos estructurados; la web lo toma de
una caja de texto libre: `const finalMessage = comment.trim();` (`:964`) y
`const finalMessage2 = comment.trim();` (`:1074`). El resto de detalles del
producto (marca, color, garantía) viajan en columnas propias, no en el
mensaje — la condición es el único que no tiene columna.

Así que la condición se **antepone** al comentario, con el mismo separador
`" · "` y el mismo prefijo que usa `composeOfferMessage` en la app. El formato
tiene que coincidir **exacto** o `conditionFromOfferMessage` (Task 1) no lo
reconocerá cuando esa oferta se edite desde la app.

Definir un helper junto al componente y usarlo en **los dos** caminos:

```tsx
/** Antepone la condicion al comentario libre, con el formato que la app
 *  compone y sabe volver a leer (`Estado: Nuevo · resto`). */
const withCondition = (condition: string, comment: string) =>
  [condition ? `Estado: ${condition}` : "", comment.trim()]
    .filter(Boolean)
    .join(" · ");
```

En `:964`:

```tsx
      const finalMessage = withCondition(isService ? "" : productCondition, comment);
```

En `:1074`:

```tsx
    const finalMessage2 = withCondition(isService ? "" : productCondition, comment);
```

- [ ] **Step 6: Prellenar al editar SIN duplicar la condición**

Este paso es el que evita un bug de acumulación. Al editar, la web vuelca el
`message` guardado en `comment` (la caja de texto). Si se vuelca tal cual,
guardar otra vez produce `Estado: Nuevo · Estado: Nuevo · …`, y cada edición
añade una copia.

Hay que **partir** el mensaje en sus dos mitades: la condición va a
`productCondition` y el resto vuelve a `comment`.

```tsx
/** Inverso de `withCondition`: separa la condicion del comentario libre. */
const splitCondition = (message: string): { condition: string; comment: string } => {
  const partes = message.split(" · ");
  const i = partes.findIndex(
    (p) => p.trim() === "Estado: Nuevo" || p.trim() === "Estado: Usado",
  );
  if (i === -1) return { condition: "", comment: message };
  const condition = partes[i].trim().slice("Estado: ".length);
  return { condition, comment: partes.filter((_, j) => j !== i).join(" · ") };
};
```

Donde el componente carga una oferta existente (`:581` y alrededores; el
`select` de `:621` ya trae `message`), sustituir el volcado directo a
`comment` por:

```tsx
      const { condition, comment: resto } = splitCondition(existingOffer.message ?? "");
      setProductCondition(condition);
      setComment(resto);
```

**No** aplicar `splitCondition` en `loadFromProduct` (`:826-841`), que rellena
el comentario desde un producto del catálogo: ahí no hay condición que
extraer y el texto es del producto, no de una oferta.

- [ ] **Step 7: Typecheck y tests**

```bash
npx tsc --noEmit && npm run test
```

Esperado: 0 errores. El typecheck es aquí el que caza los usos de
`activeDetails.warranty` que hayan quedado sueltos — si compila en 0, no
queda ninguno.

- [ ] **Step 8: Commit**

```bash
git add src/components/provider/RequestRespondSection.tsx
git commit -m "feat(web): estado y garantia obligatorios en la oferta de producto"
```

---

## Task 14: Punto 4 web — aviso al salir

**Files:**
- Modify: `src/components/provider/RequestRespondSection.tsx`

**Interfaces:**
- Consumes: `useBlocker` de `@tanstack/react-router` (v1.170.17, ya instalado).
- Produces: nada.

- [ ] **Step 1: Calcular la suciedad**

Junto al resto de derivados del componente, con **todos** los campos que el
proveedor puede tocar — los mismos que la app enumera en `_formSnapshot`:

```tsx
  // Hay trabajo sin guardar si algun campo del formulario tiene contenido.
  // Se recalcula en cada render: no hay nada que sincronizar.
  const isDirty =
    price.trim() !== "" ||
    priceMin.trim() !== "" ||
    priceMax.trim() !== "" ||
    productBrand.trim() !== "" ||
    productWarranty.trim() !== "" ||
    productCondition !== "" ||
    deliveryTime.trim() !== "" ||
    productColor.length > 0 ||
    photos.length > 0;
```

Revisar el estado real del componente y **añadir cualquier campo que falte**:
si un campo no está en esta lista, salir con él relleno no avisará. En modo
edición, comparar contra los valores prellenados en vez de contra vacío, igual
que hace la app.

- [ ] **Step 2: Bloquear la navegación interna**

La firma está verificada contra la versión instalada
(`node_modules/@tanstack/react-router/dist/esm/useBlocker.d.ts`): la API viva
es `shouldBlockFn`, y su tipo de retorno es `boolean | Promise<boolean>`.
`blockerFn` y `condition` existen pero están marcadas `@deprecated` — no
usarlas.

Como `shouldBlockFn` acepta una promesa, se usa el diálogo del repo en vez de
`window.confirm`. Este mismo fichero ya usa `showAlert` para avisos; si existe
un helper de confirmación con dos botones que devuelva promesa, usarlo. Si
solo hay `showAlert` (un botón), montar la confirmación con el mismo
componente de diálogo que use `showAlert` — **no** introducir `window.confirm`,
que rompe el estilo del resto de la aplicación:

```tsx
  useBlocker({
    shouldBlockFn: async () => {
      if (!isDirty) return false;
      const salir = await confirmDiscard();
      return !salir;
    },
    enableBeforeUnload: false,
  });
```

donde `confirmDiscard()` resuelve a `true` si el usuario elige «Salir y
descartar» y a `false` si elige «Seguir editando» — los mismos dos textos que
la app, para que las dos superficies digan lo mismo.

`enableBeforeUnload: false` porque el aviso de cerrar pestaña se monta aparte
en el Step 3; dejarlo en `true` daría dos avisos encadenados.

- [ ] **Step 3: Avisar al cerrar la pestaña**

```tsx
  useEffect(() => {
    if (!isDirty) return;
    const onBeforeUnload = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [isDirty]);
```

- [ ] **Step 4: No avisar tras enviar**

Tras un envío correcto el componente pone `setSentAnim(true)` (`:1050`). El
aviso no debe dispararse en esa navegación: añadir el estado de envío a la
condición, por ejemplo `const isDirty = !sentAnim && (…)`.

- [ ] **Step 5: Typecheck y tests**

```bash
npx tsc --noEmit && npm run test
```

Esperado: 0 errores, suite verde.

- [ ] **Step 6: Commit**

```bash
git add src/components/provider/RequestRespondSection.tsx
git commit -m "feat(web): avisar antes de salir de una oferta con cambios"
```

---

## Task 15: Punto 6 web — verde y gris (rama `feat/cotejo-visible-cliente`)

**Esta tarea NO va en la rama de la tanda.** El componente solo existe en
`feat/cotejo-visible-cliente`, sin mergear. Decisión del PO: aplicarlo allí
para que viaje junto al componente.

**Files:**
- Modify: `src/components/marketplace/OfferRequirementCoverage.tsx`

**Interfaces:**
- Consumes: `RequirementCoverageRow` de `@/lib/requestRequirements`.
- Produces: nada.

- [ ] **Step 1: Cambiar de rama**

```bash
git checkout feat/cotejo-visible-cliente
```

Confirmar que el fichero existe antes de seguir:

```bash
ls src/components/marketplace/OfferRequirementCoverage.tsx
```

- [ ] **Step 2: Pintar el cumplido en verde**

El `<li>` de hoy aplica `text-muted-foreground` a la fila entera. Pasa a
depender de `r.covered`:

```tsx
        {rows.map((r) => (
          <li
            key={r.key}
            className={cn(
              "flex items-start gap-1.5 text-[11.5px]",
              r.covered ? "text-success" : "text-muted-foreground",
            )}
          >
```

Comprobar que `text-success` existe en el tema de Tailwind del repo — se usa
en `RequestRespondSection.tsx:1249` para el presupuesto del cliente, así que
debería. Si no, usar el token que allí se use.

- [ ] **Step 3: Reescribir el comentario obsoleto**

El docstring dice que el tono neutro en el negativo fue decisión del PO. Esa
decisión quedó revertida el 2026-08-04. Sustituir ese párrafo por:

```tsx
 * Verde lo que esta oferta cubre, gris lo que no (pedido PO 2026-08-04, que
 * revierte la decision anterior de pintar los dos estados en gris). El
 * negativo sigue SIN ambar ni alarma: un `false` puede ser una oferta anterior
 * a que la pregunta existiera, no un incumplimiento. Los dos iconos ya son
 * distintos, asi que el estado no depende solo del color.
```

Dejar los dos comentarios haría que la próxima revisión lo «arregle» de vuelta
a gris.

- [ ] **Step 4: Typecheck**

```bash
npx tsc --noEmit
```

Esperado: 0 errores. **Este repo no tiene tests de componente** — vitest corre
en `environment: "node"`, como dice el propio docstring del fichero. La
verificación real es visual.

- [ ] **Step 5: Commit y volver**

```bash
git add src/components/marketplace/OfferRequirementCoverage.tsx
git commit -m "feat(web): el cotejo pinta en verde lo que la oferta cumple"
git checkout feat/correcciones-ui-08-04
```

**Deuda que NO se salda aquí:** esa rama sigue debiendo su smoke, de la tanda
del 2026-08-03. No es de esta tanda, pero sigue pendiente.

---

## Task 16: Guion de smoke

Los tests cubren la lógica pura y los widgets aislados. **Nada automático
cubre lo que esta tanda realmente cambia**: cómo se ve en pantalla y el
cableado entre pantallas. El punto 4 depende de `PopScope` y del predictive
back de Android 13+, que ya se comprobó una vez que no se deduce del código.

**Files:**
- Create: `docs/qa/2026-08-04-smoke-correcciones-ui.md` (repo de la app)

- [ ] **Step 1: Escribir el guion**

Un paso por casilla, cada uno con qué tocar y qué debe pasar. Cubrir como
mínimo:

1. **Alta de proveedor**: elegir dos provincias, ver que los sectores son la
   unión; «Todos los sectores» colapsa a un chip; cambiar de país limpia todo;
   «Usar mi ubicación» con un sector que no esté en el catálogo lo conserva.
2. **Oferta de producto**: el marco violeta rodea modo y campos; enviar sin
   estado da «Elige si el producto es nuevo o usado.»; enviar sin garantía da
   «Elige la garantía.»; con «Sin garantía» marcado sí envía.
3. **Oferta de servicio**: el marco violeta también, en los cuatro modos; **no
   pide estado ni garantía** (regresión: si los pide, la validación se coló
   fuera del `if (!isService)`).
4. **Salir con cambios**: escribir un precio y pulsar (a) la flecha flotante y
   (b) el atrás del sistema — las dos preguntan; «Seguir editando» se queda;
   «Salir y descartar» sale. Sin tocar nada, ninguna de las dos pregunta.
   Enviar la oferta y comprobar que la navegación posterior **no** pregunta.
5. **Editar una oferta enviada**: «Nuevo/Usado» vuelve ya marcado. Entrar y
   salir sin tocar nada **no** pregunta.
6. **Solicitud de mayoreo**: la tarjeta sale con el rótulo grande y los datos
   dentro. Y el caso que rompe: una solicitud de mayoreo **sin bullets y sin
   presupuesto** no debe mostrar el encabezado «INFORMACIÓN» vacío.
7. **Tarjeta de oferta del cliente**: condiciones cumplidas en verde,
   incumplidas en gris, en tema claro y oscuro.

Pasos 1 a 6 en la app; el 7 en la app, y su equivalente web cuando
`feat/cotejo-visible-cliente` se integre.

Repetir 2, 3, 4 y 6 en el navegador para la web.

Usar la receta de `jayalo-conducir-device-por-adb` para no hacerle tocar el
teléfono al PO: factor ×1.36 en las capturas, sondeo por tamaño de PNG y el
gate de Producto/Servicio.

- [ ] **Step 2: Commit**

```bash
git add docs/qa/2026-08-04-smoke-correcciones-ui.md
git commit -m "docs(app): guion de smoke de las seis correcciones de UI"
```

- [ ] **Step 3: Correr el smoke**

Ejecutarlo y anotar el resultado de cada casilla en el propio fichero. **Este
es el único gate real de la tanda.** Si algo falla, arreglarlo y volver a
correr la casilla afectada antes de dar la tanda por cerrada.

---

## Cierre

Al terminar las 16 tareas:

```bash
cd /c/Users/ac/Downloads/jayalo-app/app && flutter analyze && flutter test
cd /c/Users/ac/Downloads/jayalo-main/jayalo-main && npx tsc --noEmit && npm run test
```

Nada se pushea ni se mergea sin decisión del PO. Estado esperado al cierre:
dos ramas nuevas sin pushear, un commit suelto en
`feat/cotejo-visible-cliente`, y el guion de smoke con sus casillas marcadas.
