# Cupos de finalista (1 → hasta 3) — Paridad app Flutter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar paridad en la app Flutter (`jayaloapp`) al cambio de modelo ya vivo en BD y web: el cliente acepta **hasta 3 finalistas** por solicitud (en vez de 1), con las señales de FOMO al proveedor.

**Architecture:** El contrato ya existe en producción (Supabase `mfaiklvobnvgusbcssbx`): columnas `customer_requests.offers_count` / `accepted_offers_count`, RPC `accept_offer(_offer_id)` con tope 3 atómico, gate `block_offer_when_full`, y el trigger de exclusividad relajado a máx 3. **La app NO requiere ningún cambio de BD.** Solo consume: reemplaza el `UPDATE status=accepted` directo por la RPC `accept_offer`, lee `accepted_offers_count` en el detalle del proveedor, y replica los textos exactos.

**Tech Stack:** Flutter (Dart), `supabase_flutter`, go_router. Repo root `C:\Users\ac\Downloads\jayalo-app`; proyecto Flutter en `app/`. Rama actual `feat/error-tracking` (el PO empuja; el clasificador bloquea el push de Claude a GitHub).

## Referencia

Spec y plan web: en el repo `jayalo-main`, `docs/superpowers/specs/2026-07-26-cupos-3-finalistas-design.md` y `docs/superpowers/plans/2026-07-26-cupos-3-finalistas.md`. La lógica pura de la web (`src/lib/finalistSlots.ts`) es el espejo directo de la Task 1 de aquí.

## Global Constraints

- **Tope de finalistas = 3**, como constante Dart `kMaxFinalists = 3` en `app/lib/domain/finalist_slots.dart`.
- Cupo = **aceptación** (estado `accepted`/`completed` de la oferta), no pago. El desbloqueo/pago del proveedor no cambia.
- **NINGÚN cambio de BD** en este plan (todo aplicado ya desde la sesión web/BD).
- `acceptOffer` deja de hacer `UPDATE` directo y llama la RPC `accept_offer` (que ya impone el tope 3 atómico y el guard de solicitud abierta).
- Copy EXACTO (no reformular):
  - Proveedor: `¡Sé el primero en ofertar!` · `3 lugares disponibles` · `1 de 3 seleccionado` · `2 de 3 seleccionados — ¡último lugar!` · `3 de 3 seleccionados — comparación completa`.
  - Cliente: `Puedes aceptar 2 más` · `Puedes aceptar 1 más` · `Completaste tu selección (3 de 3)`.
- Gates (correr desde `app/`): `flutter analyze` (0 issues) y `flutter test` (suite en verde) antes de cada commit.
- El PO empuja a GitHub. No hacer `git push`.

---

### Task 1: Helper puro `finalist_slots.dart` — TDD

**Files:**
- Create: `app/lib/domain/finalist_slots.dart`
- Test: `app/test/finalist_slots_test.dart`

**Interfaces:**
- Produces: `kMaxFinalists`, `canAcceptMore(int)`, `isClosedToOffers(int)`, `clientSlotsMessage(int)`, `enum SlotTone { green, yellow, orange, red }`, `class SlotSignal { SlotTone tone; String text; }`, `providerSlotSignal(int acceptedCount, int offersCount) -> SlotSignal`.

- [ ] **Step 1: Escribir el test que falla** (`app/test/finalist_slots_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/finalist_slots.dart';

void main() {
  test('kMaxFinalists es 3', () {
    expect(kMaxFinalists, 3);
  });

  test('canAcceptMore hasta llegar a 3', () {
    expect(canAcceptMore(0), true);
    expect(canAcceptMore(2), true);
    expect(canAcceptMore(3), false);
  });

  test('isClosedToOffers solo en 3', () {
    expect(isClosedToOffers(2), false);
    expect(isClosedToOffers(3), true);
  });

  test('clientSlotsMessage con copy exacto', () {
    expect(clientSlotsMessage(0), 'Puedes aceptar hasta 3');
    expect(clientSlotsMessage(1), 'Puedes aceptar 2 más');
    expect(clientSlotsMessage(2), 'Puedes aceptar 1 más');
    expect(clientSlotsMessage(3), 'Completaste tu selección (3 de 3)');
  });

  test('providerSlotSignal — escalera de color y copy exacto', () {
    expect(providerSlotSignal(0, 0).tone, SlotTone.green);
    expect(providerSlotSignal(0, 0).text, '¡Sé el primero en ofertar!');
    expect(providerSlotSignal(0, 4).text, '3 lugares disponibles');
    expect(providerSlotSignal(1, 5).tone, SlotTone.yellow);
    expect(providerSlotSignal(1, 5).text, '1 de 3 seleccionado');
    expect(providerSlotSignal(2, 5).tone, SlotTone.orange);
    expect(providerSlotSignal(2, 5).text, '2 de 3 seleccionados — ¡último lugar!');
    expect(providerSlotSignal(3, 6).tone, SlotTone.red);
    expect(providerSlotSignal(3, 6).text, '3 de 3 seleccionados — comparación completa');
  });
}
```

> El paquete es `jayalo_app` (confirmado en `app/pubspec.yaml`).

- [ ] **Step 2: Correr el test para verlo fallar**

Run (desde `app/`): `flutter test test/finalist_slots_test.dart`
Expected: FAIL (no existe el archivo).

- [ ] **Step 3: Implementar el helper** (`app/lib/domain/finalist_slots.dart`)

```dart
/// Lógica pura de los cupos de finalista. Espejo de la web
/// (jayalo-main/src/lib/finalistSlots.ts). Copy EXACTO — no reformular.
const int kMaxFinalists = 3;

/// ¿El cliente todavía puede aceptar otro finalista?
bool canAcceptMore(int acceptedCount) => acceptedCount < kMaxFinalists;

/// ¿La solicitud está cerrada a ofertas nuevas (3 finalistas)?
bool isClosedToOffers(int acceptedCount) => acceptedCount >= kMaxFinalists;

/// Mensaje de cupos restantes que ve el cliente.
String clientSlotsMessage(int acceptedCount) {
  final remaining = kMaxFinalists - acceptedCount;
  if (remaining <= 0) return 'Completaste tu selección (3 de 3)';
  if (acceptedCount == 0) return 'Puedes aceptar hasta 3';
  return 'Puedes aceptar $remaining más';
}

enum SlotTone { green, yellow, orange, red }

class SlotSignal {
  const SlotSignal(this.tone, this.text);
  final SlotTone tone;
  final String text;
}

/// Escalera de FOMO que ve el proveedor según finalistas seleccionados.
SlotSignal providerSlotSignal(int acceptedCount, int offersCount) {
  if (acceptedCount >= 3) {
    return const SlotSignal(
        SlotTone.red, '3 de 3 seleccionados — comparación completa');
  }
  if (acceptedCount == 2) {
    return const SlotSignal(
        SlotTone.orange, '2 de 3 seleccionados — ¡último lugar!');
  }
  if (acceptedCount == 1) {
    return const SlotSignal(SlotTone.yellow, '1 de 3 seleccionado');
  }
  if (offersCount == 0) {
    return const SlotSignal(SlotTone.green, '¡Sé el primero en ofertar!');
  }
  return const SlotSignal(SlotTone.green, '3 lugares disponibles');
}
```

- [ ] **Step 4: Correr el test para verlo pasar**

Run: `flutter test test/finalist_slots_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/finalist_slots.dart app/test/finalist_slots_test.dart
git commit -m "feat(app): helper puro de cupos de finalista"
```

---

### Task 2: `acceptOffer` usa la RPC `accept_offer`

**Files:**
- Modify: `app/lib/data/repos.dart` (función `acceptOffer`, ~líneas 391-401)

**Interfaces:**
- Consumes: RPC `accept_offer(_offer_id)` (ya en prod) → jsonb `{ ok, already, accepted_count, remaining }`.
- Produces: `Future<bool> acceptOffer({required String offerId})` (misma firma; devuelve `true` si `ok`).

- [ ] **Step 1: Reemplazar el UPDATE directo por la RPC**

Sustituir el cuerpo actual:
```dart
Future<bool> acceptOffer({required String offerId}) async {
  final uid = supa.auth.currentUser!.id;
  // Guard anti-doble-aceptación: mismo patrón que la web ($requestId.tsx L707-713).
  final rows = await supa
      .from('provider_offers')
      .update({'status': 'accepted', 'customer_id': uid})
      .eq('id', offerId)
      .eq('status', 'pending')
      .select('id');
  return rows.isNotEmpty;
}
```
por:
```dart
Future<bool> acceptOffer({required String offerId}) async {
  // Tope de 3 finalistas ATÓMICO server-side (RPC en prod). Reemplaza el UPDATE
  // directo. La RPC valida dueño, idempotencia, solicitud abierta y el cap.
  final res = await supa.rpc('accept_offer', params: {'_offer_id': offerId});
  return res is Map && res['ok'] == true;
}
```

> El caller (`offer_actions.dart` `_accept`) ya envuelve en `.catchError((_) => false)`, así que una excepción de la RPC ("La solicitud ya tiene 3 finalistas", "ya no está abierta") cae al snackbar genérico "Esta oferta ya no está disponible." — comportamiento aceptable.

- [ ] **Step 2: Gates**

Run (desde `app/`): `flutter analyze` (0) y `flutter test` (verde).

- [ ] **Step 3: Commit**

```bash
git add app/lib/data/repos.dart
git commit -m "feat(app): acceptOffer usa RPC accept_offer (tope 3 atomico)"
```

---

### Task 3: Cliente — aceptar hasta 3 + mensaje de cupos + copy

**Files:**
- Modify: `app/lib/features/client/request_status_screen.dart` (cálculo de `hasAccepted` ~L245, paso a la hoja ~L331-335, y el panel del detalle)
- Modify: `app/lib/features/client/offer_actions.dart` (copy ~L462-466 y ~L479)

**Interfaces:**
- Consumes: `canAcceptMore`, `isClosedToOffers`, `clientSlotsMessage` (Task 1).

- [ ] **Step 1: Importar el helper en ambos archivos**

Añadir en cada archivo:
```dart
import '../../domain/finalist_slots.dart';
```
(ajusta la profundidad relativa: desde `features/client/` son dos niveles → `../../domain/finalist_slots.dart`).

- [ ] **Step 2: Calcular `acceptedCount` en `request_status_screen.dart`**

Localiza (con Read) la línea ~245 que calcula `hasAccepted`:
```dart
    final hasAccepted = list.any(
      (o) => o['status'] == 'accepted' || o['status'] == 'completed',
    );
```
Reemplázala por un conteo:
```dart
    final acceptedCount = list
        .where((o) => o['status'] == 'accepted' || o['status'] == 'completed')
        .length;
```
Luego, donde se pasa `hasAccepted:` al widget hijo (~L287) y donde se declara ese campo (`final bool hasAccepted;` ~L314) y se recibe (`required this.hasAccepted` ~L305), cámbialo a `acceptedCount` (`final int acceptedCount;`, `required this.acceptedCount`, y `acceptedCount: acceptedCount,`).

- [ ] **Step 3: Cambiar el gating de la hoja de oferta**

En la llamada a `showOfferSheet` (~L331-335), el argumento actual:
```dart
      hasAcceptedElsewhere: widget.hasAccepted && o['status'] == 'pending',
```
pásalo a "ya no hay cupo" (3 finalistas):
```dart
      hasAcceptedElsewhere:
          isClosedToOffers(widget.acceptedCount) && o['status'] == 'pending',
```

- [ ] **Step 4: Mostrar "Puedes aceptar N más" en el panel del cliente**

En el `_AmberPanel` / cuerpo del detalle, donde se muestra `_phaseCopy[phase]!` (busca `_phaseCopy[phase]` en el archivo), añade debajo — visible cuando hay ofertas y aún no está completada:
```dart
                  if (offers.isNotEmpty && phase != RequestPhase.completed) ...[
                    const SizedBox(height: 6),
                    Text(
                      clientSlotsMessage(acceptedCount),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
```
> Ese widget necesita `acceptedCount` en scope. Si el `_AmberPanel` no lo recibe todavía, pásalo como parámetro (igual que `phase`). Usa el mismo `acceptedCount` del Step 2.

- [ ] **Step 5: Copy del modelo de 3 en `offer_actions.dart`**

Localiza (~L462-466) el helper:
```dart
          Text(
              'Solo puedes aceptar UNA oferta por solicitud. Es gratis, pero '
              'definitiva: el proveedor podrá desbloquear tu contacto.',
```
Reemplázalo por:
```dart
          Text(
              'Puedes aceptar hasta 3 ofertas por solicitud. Es gratis; cada '
              'proveedor que elijas podrá desbloquear tu contacto.',
```
Y (~L479) el mensaje de "sin cupo":
```dart
          const Text('Ya aceptaste otra oferta para esta solicitud.',
```
por:
```dart
          const Text('Ya tienes 3 finalistas. Descarta una para elegir otra.',
```

- [ ] **Step 6: Gates**

Run (desde `app/`): `flutter analyze` (0) y `flutter test` (verde). Si algún test de `request_status_screen` afirmaba el copy viejo o `hasAccepted`, actualízalo al nuevo modelo.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/client/request_status_screen.dart app/lib/features/client/offer_actions.dart
git commit -m "feat(app): cliente acepta hasta 3 finalistas + mensaje de cupos"
```

---

### Task 4: Proveedor — escalera de FOMO + gate de ofertar

**Files:**
- Modify: `app/lib/data/repos.dart` (`requestById` select, ~L459)
- Modify: `app/lib/features/provider/request_detail_screen.dart` (render de la escalera + gate del submit)

**Interfaces:**
- Consumes: `providerSlotSignal`, `isClosedToOffers` (Task 1); columnas `accepted_offers_count` / `offers_count` del request.

- [ ] **Step 1: Traer los contadores en `requestById`**

En `app/lib/data/repos.dart`, en el `.select(...)` de `requestById` (~L459), añade al final del string de columnas: `,offers_count,accepted_offers_count`.

- [ ] **Step 2: Importar el helper y leer el conteo en el detalle**

En `app/lib/features/provider/request_detail_screen.dart` añade:
```dart
import '../../domain/finalist_slots.dart';
```
El detalle ya guarda la fila en `_req` (`_req = r`). El conteo de finalistas es `(_req?['accepted_offers_count'] as num?)?.toInt() ?? 0`; el de ofertas ya está en `_offerCount` (de `offerCountsForRequests`) — puedes seguir usándolo, o usar `(_req?['offers_count'] as num?)?.toInt() ?? _offerCount`.

- [ ] **Step 3: Renderizar la escalera de color + recencia**

El detalle ya calcula recencia con `_req?['created_at']`. Añade, arriba del formulario de oferta (busca dónde se construye el form / el bloque `_offerChecked`), un widget que use la señal:
```dart
Widget _slotLadder(BuildContext context) {
  final accepted = (_req?['accepted_offers_count'] as num?)?.toInt() ?? 0;
  final offers = (_req?['offers_count'] as num?)?.toInt() ?? _offerCount;
  final signal = providerSlotSignal(accepted, offers);
  final cs = Theme.of(context).colorScheme;
  final (bg, fg) = switch (signal.tone) {
    SlotTone.green => (const Color(0x1A22C55E), const Color(0xFF15803D)),
    SlotTone.yellow => (const Color(0x1AF59E0B), const Color(0xFFB45309)),
    SlotTone.orange => (const Color(0x1AF97316), const Color(0xFFC2410C)),
    SlotTone.red => (const Color(0x1AF43F5E), const Color(0xFFBE123C)),
  };
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: fg.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(signal.text,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
        const SizedBox(height: 2),
        Text('$offers oferta${offers == 1 ? '' : 's'} recibida${offers == 1 ? '' : 's'}',
            style: TextStyle(
                fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    ),
  );
}
```
Inserta `_slotLadder(context)` justo antes del formulario de oferta. (Ajusta los colores a la paleta del proyecto si `brand.dart` expone tokens equivalentes; los tonos oscuros/claros pueden derivarse con `Theme.of(context).brightness` como en `offer_actions.dart`.)

- [ ] **Step 4: Gate del submit cuando está llena**

Donde se dispara el envío de la oferta (el botón de ofertar / `submitOffer`), antes de llamar a `submitOffer` añade:
```dart
    if (isClosedToOffers(
        (_req?['accepted_offers_count'] as num?)?.toInt() ?? 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta solicitud ya completó su selección (3 de 3).')));
      return;
    }
```
y deshabilita el botón de ofertar cuando `isClosedToOffers(accepted)` (añade la condición a su `onPressed`/`enabled`). Esto complementa el gate de BD `block_offer_when_full` (que lanzaría una PostgrestException no-23505 en el `insert`).

- [ ] **Step 5: Gates**

Run (desde `app/`): `flutter analyze` (0) y `flutter test` (verde).

- [ ] **Step 6: Commit**

```bash
git add app/lib/data/repos.dart app/lib/features/provider/request_detail_screen.dart
git commit -m "feat(app): FOMO de cupos + gate de ofertar para el proveedor"
```

---

## Nota: lo que YA existe en la app (no rehacer)

- **Bandeja del proveedor** (`inbox_screen.dart`): ya muestra la cantidad de ofertas por solicitud (`_offerCounts` vía RPC `offer_counts_for_requests`, render en la tarjeta). El requisito "cantidad de ofertas en la lista" del proveedor **ya está cubierto** — no se toca.
- `phaseForRequest` (`domain/phase.dart`) ya replica la derivación de fase de la web; se mantiene. La "N de 3" del cliente se comunica con `clientSlotsMessage`, no cambiando el enum de fase.
- Ninguna migración de BD: `accept_offer`, `block_offer_when_full`, los contadores y el trigger de exclusividad relajado ya están en prod.

## Self-Review (cobertura vs. paridad web)

- Cliente acepta hasta 3 + "Puedes aceptar N más" → Task 3.
- Tope 3 atómico consumido vía RPC → Task 2.
- Escalera FOMO 🟢🟡🟠🔴 + recencia + gate de ofertar (proveedor) → Task 4.
- Conteo de ofertas en la lista del proveedor → ya existente (no-op).
- Copy exacto (cliente y proveedor) → Tasks 1/3/4, tests en Task 1.
- Follow-ups (heredados del web, NO en v1): chip de estado por-proveedor, aviso "cupo liberado", auto-timeout de cupo muerto.

## Verificación final (device)

Tras las 4 tasks: `flutter analyze` 0, `flutter test` verde, y smoke en device con cuenta de cliente (aceptar hasta 3, ver "Puedes aceptar N más", el 4º intento bloqueado, descartar → reabre) y de proveedor (escalera de color según finalistas, gate a 3/3). El PO empuja la rama.
