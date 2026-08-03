# "Ver mi oferta" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el botón de la tarjeta "Ya enviaste tu oferta" diga "Ver mi oferta" y abra ESA oferta
en la misma pantalla, sin sacar al proveedor de la solicitud.

**Architecture:** La pantalla no navega: entra en modo edición sobre sí misma. `_editing` deja de
derivarse del widget (`widget.editOfferId`) y pasa a un campo de estado (`_editOfferId`), más una
bandera `_editingInPlace` que distingue esta entrada de la que llega por ruta desde "Mis ofertas".
La compuerta que elige tarjeta-vs-formulario ya lee `_editing`, así que un `setState` basta. La
condición "¿es editable en sitio?" se extrae a una regla pura en `domain/` para poder probarla.

**Tech Stack:** Flutter / Dart, go_router, Supabase (`supabase_flutter`), `flutter_test`.

**Repo y rama:** `jayalo-app`, rama `feat/detalle-cliente-plegable`. Todos los comandos se ejecutan
desde el subdirectorio `app/` salvo los `git`, que van desde la raíz del repo.

**Spec:** `docs/superpowers/specs/2026-08-03-ver-mi-oferta-design.md`

## Global Constraints

- **Copy exacto, en singular:** el botón dice `Ver mi oferta`. No "Ver mis ofertas", no "Ver oferta".
- **Copy exacto del fallback:** cuando la oferta no es editable en sitio, el botón sigue diciendo
  `Ver mis ofertas` y sigue yendo a `/provider/offers`.
- **Copy exacto del botón nuevo:** `Cancelar`.
- **Copy exacto del toast al guardar:** `Oferta actualizada` (ya existe, no se cambia).
- **La ruta `?edit=` no cambia de comportamiento.** Entrar desde "Mis ofertas" tiene que seguir
  guardando y saliendo a `/provider/offers` exactamente como hoy. Es la ruta que estuvo 5 días rota
  y se arregló con la migración `20260803120000`.
- **Solo la app.** No se toca la web (allí el literal solo vive en CTAs de correo, donde llevar a la
  lista es correcto).
- **`app/lib/features/provider/request_detail_screen.dart` no tiene costura de tests.** Ningún test
  instancia esa pantalla. Lo que se cablee ahí se verifica en device (Task 5); el gate automatizable
  es `flutter analyze` limpio y `flutter test` sin regresiones.
- **Baseline de tests:** el último recuento verde conocido es 724 tests (commit `6f3fc19`). Anota el
  número real que veas en Task 1 y compáralo al final: la suite solo debe crecer con los tests
  nuevos de este plan.

---

## File Structure

- **Crear** `app/lib/domain/offer_edit.dart` — una regla pura: ¿esta oferta se puede editar en sitio?
  Va en `domain/` porque es el sitio del repo para las reglas sin Flutter (`back_intent.dart`,
  `improve_offer_error.dart`, `finalist_slots.dart`), y es la única parte de este cambio que se puede
  probar automáticamente.
- **Crear** `app/test/domain/offer_edit_test.dart` — sus tests.
- **Modificar** `app/lib/features/provider/request_detail_screen.dart` — el estado, el botón, el
  guardado y el "Cancelar". Es un fichero de 1743 líneas: **no lo reestructures**. Este plan hace
  cambios quirúrgicos en sitios concretos y nada más.
- **Crear** `docs/qa/2026-08-03-smoke-ver-mi-oferta.md` — el guion de smoke en device (Task 5).

---

### Task 1: La regla pura `canEditOfferInPlace`

**Files:**
- Create: `app/lib/domain/offer_edit.dart`
- Test: `app/test/domain/offer_edit_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `bool canEditOfferInPlace(Map<String, dynamic> offer)` — `true` solo si la oferta está
  `pending` y sin desbloquear. Task 2 la importa desde
  `package:jayalo_app/domain/offer_edit.dart`.

**Por qué esta regla y no un `if` suelto:** la tarjeta lee el status con default
(`o['status'] as String? ?? 'pending'`, `request_detail_screen.dart:898`) pero la compuerta que
decide si se pinta el formulario compara en crudo (`_existingOffer!['status'] != 'pending'`, `:1560`).
Con `status` nulo la tarjeta diría "Ya enviaste tu oferta" y la compuerta se negaría a abrir el
formulario: un botón muerto. La regla reproduce la compuerta, **sin default**.

- [ ] **Step 1: Anota el baseline, antes de tocar nada**

Run: `cd app && flutter analyze`
Expected: `No issues found!`. Si ya sale algo, **apúntalo literal**: ese es tu baseline y los pasos
posteriores exigen "ni uno más", no "cero".

Run: `cd app && flutter test`
Expected: PASS. Apunta el número de tests que reporta (referencia: 724 en `6f3fc19`). Si algo ya
falla antes de tocar nada, **para y avisa** — no es de este plan.

- [ ] **Step 2: Escribe el test que falla**

Create `app/test/domain/offer_edit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_edit.dart';

/// Regla del botón "Ver mi oferta" (pedido PO 2026-08-03): el detalle entra en
/// modo edición SOBRE SÍ MISMO. Tiene que decir que sí exactamente cuando la
/// compuerta de `request_detail_screen.dart:1559-1560` va a pintar el
/// formulario; si no, el botón queda muerto.
void main() {
  group('canEditOfferInPlace', () {
    test('pendiente y sin desbloquear: sí', () {
      expect(
        canEditOfferInPlace({'status': 'pending', 'unlocked_at': null}),
        isTrue,
      );
    });

    test('aceptada: no (nunca se edita una aceptada, pedido PO)', () {
      expect(
        canEditOfferInPlace({'status': 'accepted', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('rechazada: no', () {
      expect(
        canEditOfferInPlace({'status': 'rejected', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('completada: no', () {
      expect(
        canEditOfferInPlace({'status': 'completed', 'unlocked_at': null}),
        isFalse,
      );
    });

    test('desbloqueada gana sobre el status: no, aunque siga pending', () {
      // Mismo criterio que la tarjeta: `unlocked_at` manda (bug PO 2026-07-23).
      expect(
        canEditOfferInPlace({
          'status': 'pending',
          'unlocked_at': '2026-08-03T10:00:00Z',
        }),
        isFalse,
      );
    });

    test('status nulo: NO, aunque la tarjeta lo trate como pending', () {
      // Este es el caso que justifica la regla. La tarjeta defaultea a
      // 'pending' y mostraría "Ya enviaste tu oferta", pero la compuerta
      // compara en crudo y no abriría el formulario. Decir que sí aquí sería
      // ofrecer un botón que no hace nada.
      expect(
        canEditOfferInPlace({'status': null, 'unlocked_at': null}),
        isFalse,
      );
    });

    test('sin la clave status: no', () {
      expect(canEditOfferInPlace({'unlocked_at': null}), isFalse);
    });

    test('un status inesperado del futuro: no', () {
      expect(
        canEditOfferInPlace({'status': 'expired', 'unlocked_at': null}),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 3: Ejecútalo y comprueba que falla**

Run: `cd app && flutter test test/domain/offer_edit_test.dart`
Expected: FAIL al compilar — `Error: Couldn't resolve the package 'jayalo_app/domain/offer_edit.dart'`
o `Method not found: 'canEditOfferInPlace'`.

- [ ] **Step 4: Escribe la implementación mínima**

Create `app/lib/domain/offer_edit.dart`:

```dart
/// ¿Se puede editar esta oferta EN SITIO, desde la propia tarjeta del detalle
/// de la solicitud? (pedido PO 2026-08-03: "Ver mi oferta").
///
/// Reproduce, sin defaults, la compuerta de
/// `request_detail_screen.dart:1559-1560`, que es la que decide si se pinta el
/// formulario en vez de la tarjeta. Si esta función dijera que sí donde la
/// compuerta dice que no, el botón quedaría muerto.
///
/// `unlocked_at` gana sobre el status, igual que en la tarjeta (bug PO
/// 2026-07-23): una oferta con el contacto ya desbloqueado no se edita aunque
/// su status siguiera en 'pending'.
bool canEditOfferInPlace(Map<String, dynamic> offer) =>
    offer['unlocked_at'] == null && offer['status'] == 'pending';
```

- [ ] **Step 5: Ejecuta los tests y comprueba que pasan**

Run: `cd app && flutter test test/domain/offer_edit_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 6: Analiza**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/domain/offer_edit.dart app/test/domain/offer_edit_test.dart
git commit -m "feat(app): regla pura de si una oferta se puede editar en sitio"
```

---

### Task 2: El estado deja de ser del widget, y el botón

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart` (imports, `:132`, `initState :147-149`,
  `:600`, `:834`, `:942-950`)

**Interfaces:**
- Consumes: `canEditOfferInPlace(Map<String, dynamic>)` de Task 1.
- Produces: los campos de estado `String? _editOfferId` y `bool _editingInPlace`, y el método
  `void _editInPlace(Map<String, dynamic> o)`. Task 3 y Task 4 los usan.

**Regla de oro de esta tarea:** al terminarla, entrar por `?edit=` desde "Mis ofertas" tiene que
comportarse **exactamente** igual que antes. `_editOfferId` nace de `widget.editOfferId`, así que
`_editing` vale lo mismo que valía en todos los sitios donde ya se usaba.

- [ ] **Step 1: Sustituye el getter derivado del widget**

En `app/lib/features/provider/request_detail_screen.dart`, línea 132, cambia:

```dart
  bool get _editing => widget.editOfferId != null;
```

por:

```dart
  /// Id de la oferta en edición. Nace de `widget.editOfferId` (ruta `?edit=`,
  /// desde "Mis ofertas") y TAMBIÉN puede activarse en sitio, desde la tarjeta
  /// "Ya enviaste tu oferta" (pedido PO 2026-08-03). Por eso es estado y no un
  /// getter del widget.
  String? _editOfferId;

  /// True solo cuando la edición se activó desde ESTA pantalla. Distingue las
  /// dos entradas: la de ruta sale a la lista de ofertas al guardar; la de
  /// aquí vuelve a la tarjeta, sin salir de la solicitud.
  bool _editingInPlace = false;

  bool get _editing => _editOfferId != null;
```

- [ ] **Step 2: Inicializa `_editOfferId` antes de cualquier uso de `_editing`**

En `initState` (línea ~147), añade la asignación como **primera** línea tras `super.initState()`:

```dart
  @override
  void initState() {
    super.initState();
    // Antes que nada: `_editing` se consulta más abajo, en esta misma función.
    _editOfferId = widget.editOfferId;
    requestById(widget.requestId).then((r) {
```

- [ ] **Step 3: Reapunta los dos usos restantes de `widget.editOfferId!`**

Línea ~600, dentro de `_submit`:

```dart
        await updateOffer(
          offerId: _editOfferId!,
```

Línea ~834, dentro de `_deleteOffer`:

```dart
      await deleteOffer(_editOfferId!);
```

Los dos están dentro de guardas de `_editing`, así que el `!` sigue siendo seguro.

Comprueba que no queda ninguno más:

Run: `cd app && grep -n "widget.editOfferId" lib/features/provider/request_detail_screen.dart`
Expected: una sola línea, la de `initState` del Step 2.

- [ ] **Step 4: Añade el import de la regla**

En el bloque de imports de `request_detail_screen.dart`, junto a los otros `../../domain/...`:

```dart
import '../../domain/offer_edit.dart';
```

- [ ] **Step 5: Añade `_editInPlace`**

Justo encima de `Widget _alreadyOfferedCard(BuildContext context) {` (línea ~896):

```dart
  /// Entra en modo edición SOBRE ESTA MISMA PANTALLA (pedido PO 2026-08-03).
  /// No navega: la ruta de destino (`/provider/request/<id>?edit=<offerId>`)
  /// es la que ya se está mostrando, y apilarla dejaría dos copias.
  ///
  /// No hace falta ninguna consulta: [_existingOffer] viene de
  /// `myOfferForRequest`, que selecciona `offerCols` (`repos.dart:272-289`), y
  /// esas columnas cubren todo lo que lee [_prefillFromOffer].
  void _editInPlace(Map<String, dynamic> o) {
    setState(() {
      _editOfferId = o['id'] as String;
      _editingInPlace = true;
      _prefillFromOffer(o);
    });
  }
```

- [ ] **Step 6: Cambia el brazo comodín del switch**

Líneas 942-950. Sustituye:

```dart
      _ => (
          dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
          Icons.check_circle,
          'Ya enviaste tu oferta',
          'Solo puedes ofertar una vez por solicitud. Tu oferta: $label. '
              'Si el cliente la acepta, te avisaremos para desbloquear el contacto.',
          'Ver mis ofertas',
          () => context.go('/provider/offers'),
        ),
```

por:

```dart
      _ => (
          dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
          Icons.check_circle,
          'Ya enviaste tu oferta',
          'Solo puedes ofertar una vez por solicitud. Tu oferta: $label. '
              'Si el cliente la acepta, te avisaremos para desbloquear el contacto.',
          // Pedido PO 2026-08-03: en singular y a ESA oferta, sin salir de la
          // solicitud. Este brazo es el COMODÍN del switch: si cae aquí una
          // fila que la compuerta de abajo no dejaría editar, se conserva el
          // CTA viejo en vez de ofrecer un botón que no hace nada.
          canEditOfferInPlace(o) ? 'Ver mi oferta' : 'Ver mis ofertas',
          canEditOfferInPlace(o)
              ? () => _editInPlace(o)
              : () => context.go('/provider/offers'),
        ),
```

Los otros tres brazos (`rejected`, desbloqueada/completada, `accepted`) **no se tocan**.

- [ ] **Step 7: Analiza y pasa la suite entera**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: PASS, mismo número de tests que anotaste en Task 1 Step 1, más los 8 de Task 1. Cero
fallos. Ningún test cubre esta pantalla, así que esto solo demuestra que no rompiste a un vecino.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): \"Ver mi oferta\" entra en edicion sobre la misma pantalla"
```

---

### Task 3: Al guardar en sitio, volver a la tarjeta

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart:622-625`

**Interfaces:**
- Consumes: `_editingInPlace` y `_editOfferId` de Task 2; `_reloadOffer()` (ya existe, `:883-890`).
- Produces: nada nuevo.

- [ ] **Step 1: Condiciona la salida del guardado**

Dentro de `_submit`, en el bloque `if (_editing) { await updateOffer(...); ... }`, sustituye:

```dart
        if (!mounted) return;
        _toast('Oferta actualizada');
        context.go('/provider/offers');
        return;
```

por:

```dart
        if (!mounted) return;
        _toast('Oferta actualizada');
        // Entrada en sitio (pedido PO 2026-08-03): no se sale de la solicitud.
        // Se relee la fila para que la tarjeta reaparezca con el precio nuevo y
        // se vuelve a modo lectura. `_busy` lo repone el `finally` de abajo,
        // que también corre con este `return`.
        if (_editingInPlace) {
          await _reloadOffer();
          if (!mounted) return;
          setState(() {
            _editOfferId = null;
            _editingInPlace = false;
          });
          return;
        }
        // Entrada por ruta, desde "Mis ofertas": sale a la lista, como siempre.
        context.go('/provider/offers');
        return;
```

`_reloadOffer` relee por `_existingOffer?['id']`, que sigue siendo el id correcto: `_editInPlace` no
tocó `_existingOffer`.

- [ ] **Step 2: Analiza y pasa la suite**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: PASS, sin cambios en el recuento respecto a Task 2.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): guardar en sitio devuelve a la tarjeta, sin salir de la solicitud"
```

---

### Task 4: El botón "Cancelar"

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart` (método nuevo junto a `_editInPlace`;
  bloque de botones `:1702-1711`)

**Interfaces:**
- Consumes: `_editOfferId`, `_editingInPlace` de Task 2.
- Produces: `void _cancelInPlaceEdit()`.

**El detalle que no se puede olvidar:** volver a entrar en edición llama a `_prefillFromOffer`, que
reasigna los 13 controladores y vacía y rellena `_keptUrls` (`:256-259`). Lo que **no** toca son las
fotos recién elegidas (`_photos`) y `_condition` — que no es restaurable desde la oferta por diseño,
porque la web solo lo guarda dentro del mensaje. Esos dos hay que limpiarlos a mano o cancelar
dejaría restos.

- [ ] **Step 1: Añade `_cancelInPlaceEdit`**

Justo debajo de `_editInPlace` (el método de Task 2 Step 5):

```dart
  /// Sale del modo edición en sitio SIN guardar y devuelve la tarjeta.
  ///
  /// Limpia lo único que [_prefillFromOffer] no reasigna al volver a entrar:
  /// las fotos recién elegidas y `_condition` (que la oferta no guarda en
  /// columna propia). Sin esto, cancelar y reabrir arrastraría fotos y un
  /// "Nuevo/Usado" que el proveedor creía descartados.
  void _cancelInPlaceEdit() {
    setState(() {
      _editOfferId = null;
      _editingInPlace = false;
      _photos.clear();
      _condition = '';
    });
  }
```

- [ ] **Step 2: Añade el botón, encima de "Eliminar oferta"**

Líneas ~1702-1711. Sustituye:

```dart
          if (_editing) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _deleteOffer,
```

por:

```dart
          if (_editing) ...[
            // Salida sin guardar. Solo en la entrada EN SITIO: quien llega
            // desde "Mis ofertas" ya tiene su camino de vuelta. No se toca la
            // flecha flotante ni el PopScope de BackGuard.
            if (_editingInPlace)
              TextButton(
                onPressed: _busy ? null : _cancelInPlaceEdit,
                child: const Text('Cancelar'),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _deleteOffer,
```

- [ ] **Step 3: Analiza y pasa la suite**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: PASS, sin cambios en el recuento respecto a Task 3.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): \"Cancelar\" sale del modo edicion en sitio sin dejar restos"
```

---

### Task 5: Smoke en device

**Files:**
- Create: `docs/qa/2026-08-03-smoke-ver-mi-oferta.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el guion ejecutado, con el resultado real anotado.

**Esto no es opcional.** `request_detail_screen.dart` no tiene costura de tests: ningún test de la
suite instancia esa pantalla. Los pasos 1-4 no han demostrado que el cableado funcione, solo que
compila y que no rompió a un vecino. Hace falta un proveedor con sesión y una oferta `pending`.

**Gotcha conocido:** un APK debug **no** instala encima de un release. Si el device tiene el release
firmado, desinstala primero.

- [ ] **Step 1: Escribe el guion**

Create `docs/qa/2026-08-03-smoke-ver-mi-oferta.md`:

```markdown
# Smoke — "Ver mi oferta" (2026-08-03)

Requisitos: proveedor con sesión, una solicitud suya con oferta en `pending` y sin desbloquear.
Gotcha: un APK debug no instala encima del release; desinstala primero.

## 1. Camino principal
- [ ] Entrar a la solicitud ya ofertada.
- [ ] La tarjeta dice "Ya enviaste tu oferta" y el botón dice **"Ver mi oferta"** (singular).
- [ ] Pulsarlo: aparece el formulario EN LA MISMA PANTALLA, con los datos de la oferta cargados
      (precio, y según el tipo: envío/instalación/evaluación, marca, garantía, colores, fotos).
- [ ] No se apiló otra pantalla: no hay una segunda flecha ni un salto visual de navegación.
- [ ] Cambiar el precio y pulsar "Guardar cambios".
- [ ] Sale el toast "Oferta actualizada" y **vuelve la tarjeta, con el precio nuevo**, sin salir de
      la solicitud.

## 2. Cancelar
- [ ] "Ver mi oferta" → cambiar el precio y añadir una foto → "Cancelar".
- [ ] Vuelve la tarjeta con el precio ORIGINAL.
- [ ] "Ver mi oferta" otra vez: la foto añadida no está, y "Nuevo/Usado" no quedó premarcado.

## 3. Regresión: la ruta que estuvo rota
- [ ] Ir a "Mis ofertas" → tocar la misma oferta → editar el precio → "Guardar cambios".
- [ ] Guarda y **sale a la lista de ofertas**, como siempre. NO se queda en el detalle.
- [ ] En esa entrada NO aparece el botón "Cancelar".
- [ ] "Mejorar oferta" sigue guardando (la ruta de la migración `20260803120000`).

## 4. Regresión: los otros estados de la tarjeta
- [ ] Oferta ACEPTADA sin desbloquear: sigue "🏆 ¡Te aceptaron!" con "Desbloquear contacto".
- [ ] Oferta DESBLOQUEADA o completada: sigue "Contacto desbloqueado" con "Ver contacto".
- [ ] Oferta RECHAZADA: sigue "El cliente eligió otra oferta", sin botón.

## 5. Eliminar
- [ ] Desde "Ver mi oferta" → "Eliminar oferta" → confirmar: va a la lista de ofertas.
- [ ] La oferta ya no está en la lista.

## Resultado
(anotar aquí lo que pasó de verdad, incluidos los fallos)
```

- [ ] **Step 2: Compila e instala**

Run: `cd app && flutter run` (o `flutter install` sobre el device conectado)
Expected: la app arranca en el device.

- [ ] **Step 3: Ejecuta el guion entero**

Marca cada casilla con lo que pasó **de verdad**. Si algo falla, anótalo en "Resultado", **no**
marques la casilla, y para: el arreglo es parte de este plan, no de otro.

- [ ] **Step 4: Commit del guion con el resultado**

```bash
git add docs/qa/2026-08-03-smoke-ver-mi-oferta.md
git commit -m "test(app): smoke en device de \"Ver mi oferta\""
```

---

## Cierre

- [ ] `cd app && flutter analyze` → `No issues found!`
- [ ] `cd app && flutter test` → verde, con el recuento del baseline + 8.
- [ ] Las 5 secciones del smoke ejecutadas en device y anotadas.
- [ ] Los commits están en `feat/detalle-cliente-plegable`. **No se pushea ni se mergea sin decisión
      del PO** — es la convención de esta rama.
