# «Ver WhatsApp del cliente» en el ⋮ del chat — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el proveedor pida el WhatsApp del cliente desde el ⋮ del chat, con el gate de siempre, sin perder el derecho a la devolución de créditos por abrir un menú o una hoja.

**Architecture:** El ítem aparece siempre para proveedor + chat abierto, y sale GRIS con el motivo cuando el servidor dice que no se puede. El estado se consulta una vez al cargar el chat (RPC sin efectos secundarios); el teléfono se pide **después** del «mantén presionado», nunca antes. `WhatsappReveal` pasa de recibir un `String phone` a recibir un `Future<String?> Function() loadPhone`, y ese cambio de firma es lo que hace estructuralmente imposible volver a adelantar la carga.

**Tech Stack:** Flutter (Dart 3, `switch` expressions y patrones), `supabase_flutter`, `url_launcher`, `go_router`. Tests con `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-04-whatsapp-en-menu-chat-design.md`

## Global Constraints

- **CERO cambios de servidor.** Ninguna migración, ninguna RPC nueva, ningún cambio de RLS ni de grants. Si una tarea parece pedirlo, se para y se consulta.
- **Repo y rama:** worktree `C:\Users\ac\Downloads\jayalo-app-wa-menu`, rama `feat/whatsapp-en-menu-chat` sobre `feat/fecha-pautada-app` (`cb32f10`). El proyecto Flutter está en `app/`.
- **Nunca editar ficheros con acentos desde PowerShell 5.1** (`Get-Content`+`Set-Content` doble-codifica un UTF-8 sin BOM). Usar las herramientas de edición o `sed -i` desde Bash.
- **Rótulo exacto del ítem:** `Ver WhatsApp del cliente`. No «Desbloquear»: dentro de un chat el contacto ya está pagado.
- **Motivos exactos** (copy cerrado con el PO):
  - `El cliente prefiere solo el chat de Jayalo`
  - `El cliente no dejó un teléfono`
  - `No pudimos comprobarlo`
- **Mensaje de fallo exacto:** `No pudimos abrir WhatsApp. Intenta de nuevo.`
- **Los 8 tests de `test/chat_menu_roles_test.dart` se conservan intactos.** Solo se añaden.
- Cada commit termina con:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- Comandos desde `C:\Users\ac\Downloads\jayalo-app-wa-menu\app`.

## Estructura de ficheros

| fichero | qué le pasa |
| --- | --- |
| `app/lib/features/provider/unlock_flow.dart` | `WhatsappReveal` cambia de firma (T1); nace `showWhatsappRevealSheet` (T1); `showOfferContactSheet` deja de marcar el revelado (T2) |
| `app/lib/features/provider/product_interest_detail_screen.dart` | adapta su llamada a `WhatsappReveal` (T1) |
| `app/lib/data/repos.dart` | `customer_id` en `offerCols` (T2); `customerWhatsappRevealEnabled` (T3) |
| `app/lib/features/chat/chat_screen.dart` | `WhatsappRevealGate` + `whatsappMenuReason` (T3); ítem del ⋮, carga del gate, apertura de la hoja, clave de guía a `.v2` (T4) |
| `app/lib/features/shared/onboarding_copy.dart` | `chat.menu.provider.v1` → `.v2` (T4) |
| `app/test/whatsapp_reveal_test.dart` | **nuevo** (T1) |
| `app/test/offer_cols_test.dart` | **nuevo** (T2) |
| `app/test/whatsapp_menu_reason_test.dart` | **nuevo** (T3) |
| `app/test/chat_menu_roles_test.dart` | se le añaden 3 tests (T4) |

---

### Task 1: `WhatsappReveal` pide el teléfono TARDE

Es la tarea que arregla la raíz: mientras el widget reciba un `String phone` ya resuelto, alguien lo habrá traído antes de tiempo. Al recibir un cargador, la llamada solo puede pasar tras el hold.

**Files:**
- Modify: `app/lib/features/provider/unlock_flow.dart:519-585` (la clase `WhatsappReveal`)
- Modify: `app/lib/features/provider/unlock_flow.dart:282-380` (llamada dentro de `showOfferContactSheet`, adaptación MECÁNICA — el arreglo de verdad es la Task 2)
- Modify: `app/lib/features/provider/product_interest_detail_screen.dart:428-433`
- Create: `app/lib/features/provider/unlock_flow.dart` — función nueva `showWhatsappRevealSheet` (al final del fichero, junto a `WhatsappReveal`)
- Test: `app/test/whatsapp_reveal_test.dart` (nuevo)

**Interfaces:**
- Produces:
  - `WhatsappReveal({Key? key, required Future<String?> Function() loadPhone, required String? firstName, bool refundApplies = false})`
  - `Future<void> showWhatsappRevealSheet(BuildContext context, {required Future<String?> Function() loadPhone, required bool refundApplies, String? peerName})`
- Consumes: `HoldToConfirmButton` y `HoldToConfirmTone` de `features/shared/brand_kit.dart`; `_snack(BuildContext, String)` y `_TallSheet`, ambos ya privados en `unlock_flow.dart`; `JayaloMotion.sheetRise` de `core/motion.dart`.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/whatsapp_reveal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/unlock_flow.dart';
// `HoldToConfirmButton` vive aquí: el segundo test lo busca para hacer el hold.
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// El teléfono NO se pide al pintar. En las ofertas, la RPC que lo devuelve
/// (`get_unlocked_offer_contact`) MARCA `whatsapp_revealed_at` y con eso el
/// proveedor pierde el derecho a la devolución de créditos: pedirlo antes del
/// hold se lo quitaba sin que hubiera visto nada (bug 2026-09-04).
Widget _host(Future<String?> Function() loadPhone) => MaterialApp(
      home: Scaffold(
        body: WhatsappReveal(
          loadPhone: loadPhone,
          firstName: 'Ana',
          refundApplies: true,
        ),
      ),
    );

void main() {
  testWidgets('no pide el teléfono al pintar', (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(_host(() async {
      llamadas++;
      return '8095551234';
    }));
    expect(llamadas, 0,
        reason: 'pedir el teléfono al pintar quema la devolución');
  });

  testWidgets('sin teléfono avisa y no cierra el aviso', (tester) async {
    await tester.pumpWidget(_host(() async => null));

    final boton = find.byType(HoldToConfirmButton);
    final gesto = await tester.startGesture(tester.getCenter(boton));
    // El hold dura JayaloMotion.holdConfirm (2,5 s); se pasa de largo.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await gesto.up();
    await tester.pumpAndSettle();

    expect(find.text('No pudimos abrir WhatsApp. Intenta de nuevo.'),
        findsOneWidget);
    expect(find.byType(WhatsappReveal), findsOneWidget,
        reason: 'el aviso sigue en pantalla para reintentar');
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/whatsapp_reveal_test.dart
```

Esperado: FALLA al compilar — `The named parameter 'loadPhone' isn't defined` (hoy el parámetro es `phone`).

- [ ] **Step 3: Cambiar la firma de `WhatsappReveal`**

En `app/lib/features/provider/unlock_flow.dart`, sustituir el constructor y los campos de la clase `WhatsappReveal`:

```dart
  const WhatsappReveal(
      {super.key,
      required this.loadPhone,
      required this.firstName,
      this.refundApplies = false});

  /// Trae el teléfono. Se llama SOLO tras el hold, nunca al pintar: en las
  /// ofertas la RPC que lo devuelve (`get_unlocked_offer_contact`) MARCA
  /// `whatsapp_revealed_at`, y con esa marca el proveedor pierde el derecho a
  /// pedir la devolución de créditos. Recibirlo ya resuelto obligaba a
  /// traerlo antes de tiempo, así que la firma es parte del arreglo.
  final Future<String?> Function() loadPhone;
  final String? firstName;
```

y sustituir el `onConfirmed` del `HoldToConfirmButton`:

```dart
          onConfirmed: () async {
            String? phone;
            try {
              phone = await loadPhone();
            } catch (_) {
              // Cae al aviso de abajo: nunca un wa.me con el número vacío.
            }
            if (phone == null || phone.trim().isEmpty) {
              if (context.mounted) {
                _snack(context, 'No pudimos abrir WhatsApp. Intenta de nuevo.');
              }
              return;
            }
            final digits = phone.replaceAll(RegExp(r'\D'), '');
            await launchUrl(Uri.parse('https://wa.me/$digits'),
                mode: LaunchMode.externalApplication);
          },
```

- [ ] **Step 4: Adaptar los dos llamadores para que compile**

En `product_interest_detail_screen.dart` (bloque `if (widget.contactPhone != null) ...[`):

```dart
                      WhatsappReveal(
                          // Su RPC (`get_unlocked_product_interest_contact`)
                          // es STABLE y no marca nada, así que el teléfono ya
                          // está en mano: el cargador solo lo entrega.
                          loadPhone: () async => widget.contactPhone,
                          firstName: widget.contactName),
```

En `showOfferContactSheet` (dentro de `unlock_flow.dart`), adaptación **mecánica y temporal** — la Task 2 la reemplaza:

```dart
              WhatsappReveal(
                  loadPhone: () async => contact.phone,
                  firstName: contact.firstName,
                  refundApplies: true),
```

- [ ] **Step 5: Añadir `showWhatsappRevealSheet`**

Al final de `unlock_flow.dart`, después de la clase `WhatsappReveal`:

```dart
/// Hoja que enseña SOLO el gate de WhatsApp: el aviso + el hold, nada más.
///
/// Existe para que el ⋮ del chat no tenga que reconstruir el gate: una sola
/// definición del aviso y del hold, imposible que las dos superficies
/// diverjan en copy o en duración del hold.
Future<void> showWhatsappRevealSheet(
  BuildContext context, {
  required Future<String?> Function() loadPhone,
  required bool refundApplies,
  String? peerName,
}) =>
    showModalBottomSheet<void>(
      sheetAnimationStyle: JayaloMotion.sheetRise,
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => _TallSheet(
        heightFactor: .5,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('WhatsApp de ${peerName ?? 'tu cliente'}',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              WhatsappReveal(
                  loadPhone: loadPhone,
                  firstName: peerName,
                  refundApplies: refundApplies),
            ]),
      ),
    );
```

- [ ] **Step 6: Correr el test y el análisis**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/whatsapp_reveal_test.dart && flutter analyze lib/features/provider
```

Esperado: los 2 tests PASAN; `flutter analyze` sin issues nuevos.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git add app/lib/features/provider/unlock_flow.dart app/lib/features/provider/product_interest_detail_screen.dart app/test/whatsapp_reveal_test.dart && git commit -m "fix(app): WhatsappReveal pide el telefono TRAS el hold, no al pintar

get_unlocked_offer_contact MARCA whatsapp_revealed_at: traerlo al pintar le
quitaba al proveedor el derecho a la devolucion sin que hubiera visto nada.
La firma pasa a un cargador para que no se pueda volver a adelantar.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: La hoja de contacto deja de quemar la devolución

**Files:**
- Modify: `app/lib/data/repos.dart:283-306` (constante `offerCols`)
- Modify: `app/lib/features/provider/unlock_flow.dart:282-380` (`showOfferContactSheet`)
- Test: `app/test/offer_cols_test.dart` (nuevo)

**Interfaces:**
- Consumes: `WhatsappReveal({required loadPhone, ...})` de la Task 1; `canRevealOffer(String offerId) → Future<bool>` (`repos.dart:1646`); `unlockedContact(String offerId) → Future<({String? firstName, String? phone})>` (`repos.dart:1147`); `customerPublicProfile(String customerId, {String? requestId, String? offerId, String? interestId}) → Future<({bool unlocked, String? firstName, String? lastName, String? avatarUrl})>` (`repos.dart:2809`).
- Produces: `offerCols` incluye `customer_id`.

**Nota de honestidad sobre las pruebas:** `showOfferContactSheet` es una hoja modal atada a Supabase; no hay forma de probarla sin red, y montar un doble solo para esto sería más superficie que valor. Su garantía estructural es el test de la Task 1 (`loadPhone` no se llama al pintar), que es lo que impide que la carga vuelva a adelantarse. Lo único con test propio aquí es la dependencia nueva: `customer_id` en `offerCols`.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/offer_cols_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// `showOfferContactSheet` resuelve el NOMBRE del cliente con
/// `customerPublicProfile`, que no marca nada, en vez de con
/// `get_unlocked_offer_contact`, que MARCA `whatsapp_revealed_at`. Para eso
/// necesita el `customer_id` de la oferta, y la fila que recibe sale de
/// `offerCols`. Sin esta columna la hoja perdería el nombre en silencio.
void main() {
  test('offerCols trae customer_id', () {
    expect(offerCols.split(',').map((c) => c.trim()), contains('customer_id'));
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/offer_cols_test.dart
```

Esperado: FALLA — `Expected: contains 'customer_id'`.

- [ ] **Step 3: Añadir la columna**

En `app/lib/data/repos.dart`, en la primera línea de `offerCols`, añadir `customer_id` detrás de `user_id`:

```dart
const offerCols =
    'id,request_id,business_id,user_id,customer_id,price,price_min,price_max,'
    'pricing_mode,'
    'hourly_rate,estimated_hours,message,status,unlocked_at,created_at,'
```

Justo encima de la constante, añadir el porqué:

```dart
// `customer_id` tiene SELECT concedido a `authenticated` (comprobado en
// information_schema.column_privileges el 2026-09-04) y lo necesita
// `showOfferContactSheet` para resolver el nombre del cliente con
// `customerPublicProfile` — la vía que NO marca `whatsapp_revealed_at`.
// No hay fuga hacia el cliente: quien lee estas ofertas ES el customer_id.
```

- [ ] **Step 4: Correr el test**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/offer_cols_test.dart
```

Esperado: PASA.

- [ ] **Step 5: Reescribir la carga de `showOfferContactSheet`**

En `unlock_flow.dart`, sustituir el bloque que hoy va desde `var canWhatsapp = false;` hasta `if (!context.mounted) return;` por:

```dart
  var canWhatsapp = false;
  try {
    canWhatsapp = await canRevealOffer(offer['id'] as String);
  } catch (_) {}
  // El NOMBRE sale del perfil público, que NO marca nada. Antes salía de
  // `get_unlocked_offer_contact`, que hace `UPDATE … SET whatsapp_revealed_at
  // = now()`: abrir esta hoja le quitaba al proveedor el derecho a la
  // devolución de créditos aunque nunca llegara a ver el WhatsApp
  // (bug 2026-09-04). El teléfono ya no se pide aquí: lo pide el cargador de
  // `WhatsappReveal`, tras el hold.
  String? firstName;
  final customerId = offer['customer_id'] as String?;
  if (customerId != null) {
    try {
      final p = await customerPublicProfile(customerId,
          offerId: offer['id'] as String);
      firstName = p.firstName;
    } catch (_) {
      // best-effort: la hoja cae a «Cliente»/«tu cliente», como ya hacía
      // cuando `first_name` venía null.
    }
  }
  if (!context.mounted) return;
```

- [ ] **Step 6: Adaptar el cuerpo de la hoja a `firstName`**

Tres sustituciones dentro del mismo `showOfferContactSheet`:

```dart
            Text(canWhatsapp
                ? (firstName ?? 'Cliente')
                : 'Escríbele a ${firstName ?? 'tu cliente'} por el '
                    'chat de Jayalo.'),
```

```dart
                context.push('/messages/$convId',
                    extra: {'peer_name': firstName});
```

```dart
            if (canWhatsapp) ...[
              const SizedBox(height: 12),
              // Hoja de contacto de una OFERTA: aquí la devolución sí existe.
              // El teléfono se pide DENTRO del cargador, ya pasado el hold.
              WhatsappReveal(
                  loadPhone: () async =>
                      (await unlockedContact(offer['id'] as String)).phone,
                  firstName: firstName,
                  refundApplies: true),
            ],
```

- [ ] **Step 7: Comprobar que nada más llama al revelado temprano**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && grep -rn "unlockedContact" lib/
```

Esperado: exactamente **dos** apariciones — su definición en `lib/data/repos.dart` y la de dentro del `loadPhone` en `lib/features/provider/unlock_flow.dart`. Cualquier otra es una carga adelantada y hay que convertirla en cargador.

- [ ] **Step 8: Analizar y correr la batería de la zona**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter analyze lib/ && flutter test test/offer_cols_test.dart test/whatsapp_reveal_test.dart
```

Esperado: sin issues; 3 tests PASAN.

- [ ] **Step 9: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git add app/lib/data/repos.dart app/lib/features/provider/unlock_flow.dart app/test/offer_cols_test.dart && git commit -m "fix(app): abrir la hoja de contacto ya no quema la devolucion de creditos

El nombre pasa a salir de customerPublicProfile (no marca) en vez de
get_unlocked_offer_contact (marca whatsapp_revealed_at). Para eso, customer_id
entra en offerCols: SELECT ya concedido a authenticated, sin permisos nuevos.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: El gate — función pura + lectura del interruptor del cliente

**Files:**
- Modify: `app/lib/data/repos.dart` (añadir `customerWhatsappRevealEnabled` justo detrás de `setWhatsappRevealEnabled`, sobre la línea 1295)
- Modify: `app/lib/features/chat/chat_screen.dart:47` (detrás de `chatMenuValues`, junto a las otras funciones puras del fichero)
- Test: `app/test/whatsapp_menu_reason_test.dart` (nuevo)

**Interfaces:**
- Produces:
  - `enum WhatsappRevealGate { canReveal, optedOut, noPhone, unknown }` (en `chat_screen.dart`)
  - `String? whatsappMenuReason(WhatsappRevealGate gate)` — `null` = habilitado
  - `Future<bool> customerWhatsappRevealEnabled(String customerId)` (en `repos.dart`)
- Consumes: nada de tareas anteriores.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/whatsapp_menu_reason_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/chat_screen.dart';

/// El ⋮ enseña el ítem SIEMPRE (proveedor + chat abierto) y lo pinta gris con
/// el motivo cuando no se puede — decisión PO 2026-09-04: ni oculto ni activo.
/// `null` es el único valor que lo habilita.
void main() {
  test('solo canReveal habilita', () {
    expect(whatsappMenuReason(WhatsappRevealGate.canReveal), isNull);
    for (final g in [
      WhatsappRevealGate.optedOut,
      WhatsappRevealGate.noPhone,
      WhatsappRevealGate.unknown,
    ]) {
      expect(whatsappMenuReason(g), isNotNull, reason: '$g debe salir gris');
    }
  });

  test('los motivos son el copy cerrado con el PO', () {
    expect(whatsappMenuReason(WhatsappRevealGate.optedOut),
        'El cliente prefiere solo el chat de Jayalo');
    expect(whatsappMenuReason(WhatsappRevealGate.noPhone),
        'El cliente no dejó un teléfono');
    expect(whatsappMenuReason(WhatsappRevealGate.unknown),
        'No pudimos comprobarlo');
  });
}
```

- [ ] **Step 2: Correrlo y ver que falla**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/whatsapp_menu_reason_test.dart
```

Esperado: FALLA al compilar — `Undefined name 'WhatsappRevealGate'`.

- [ ] **Step 3: Escribir el enum y la función pura**

En `app/lib/features/chat/chat_screen.dart`, justo debajo de `chatMenuValues` (línea 47 aprox., antes de `canResolveReviewBusiness`):

```dart
/// Por qué el ⋮ puede (o no) enseñar el WhatsApp del cliente.
///
/// `unknown` es el estado de ARRANQUE y el de "la consulta falló": por
/// defecto el ítem sale gris, y solo el servidor puede habilitarlo.
enum WhatsappRevealGate { canReveal, optedOut, noPhone, unknown }

/// Motivo que va bajo «Ver WhatsApp del cliente» en el ⋮. `null` = el ítem va
/// habilitado. Pura y pública por el mismo motivo que [chatMenuValues]: se
/// fija en un test sin montar la pantalla (su initState toca Supabase).
String? whatsappMenuReason(WhatsappRevealGate gate) => switch (gate) {
      WhatsappRevealGate.canReveal => null,
      // El interruptor es del CLIENTE (`profiles.whatsapp_reveal_enabled`,
      // false por defecto): no es un fallo nuestro y el copy no debe sonar a
      // error. Es el caso de 9 de cada 10 ofertas reales.
      WhatsappRevealGate.optedOut => 'El cliente prefiere solo el chat de Jayalo',
      WhatsappRevealGate.noPhone => 'El cliente no dejó un teléfono',
      WhatsappRevealGate.unknown => 'No pudimos comprobarlo',
    };
```

- [ ] **Step 4: Correr el test**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/whatsapp_menu_reason_test.dart
```

Esperado: los 2 tests PASAN.

- [ ] **Step 5: Añadir la lectura del interruptor en `repos.dart`**

Detrás de `setWhatsappRevealEnabled` (sobre la línea 1295):

```dart
/// ¿El CLIENTE aceptó que lo contacten por WhatsApp?
///
/// Lee `profiles.whatsapp_reveal_enabled` de OTRO usuario. Lo permite la
/// política `Profiles: select`, que además del dueño y de los admin admite al
/// proveedor con un `product_interests` desbloqueado de ese cliente; la
/// columna tiene SELECT concedido a `authenticated` (ambas cosas comprobadas
/// contra prod el 2026-09-04). Fuera de ese caso la fila simplemente no llega
/// y se devuelve `false` — default seguro, igual que la columna.
///
/// ⚠️ Es una reja de UI, NO del servidor:
/// `get_unlocked_product_interest_contact` sigue devolviendo el teléfono sin
/// mirar esta bandera. Apretarla es un ticket con migración propia (ver §9 del
/// spec 2026-09-04); no se hace desde el cliente.
Future<bool> customerWhatsappRevealEnabled(String customerId) async {
  final row = await supa
      .from('profiles')
      .select('whatsapp_reveal_enabled')
      .eq('user_id', customerId)
      .maybeSingle();
  return row?['whatsapp_reveal_enabled'] as bool? ?? false;
}
```

- [ ] **Step 6: Analizar**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter analyze lib/data/repos.dart lib/features/chat/chat_screen.dart
```

Esperado: sin issues.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git add app/lib/data/repos.dart app/lib/features/chat/chat_screen.dart app/test/whatsapp_menu_reason_test.dart && git commit -m "feat(app): gate del WhatsApp del chat — enum, motivo puro y lectura del interruptor

whatsappMenuReason decide si el item va habilitado o gris con su motivo.
customerWhatsappRevealEnabled lee la bandera del cliente por la rama de
product_interests de la politica de profiles: sin migracion.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: El ítem en el ⋮ del chat

**Files:**
- Modify: `app/lib/features/chat/chat_screen.dart` — `chatMenuValues` (línea 50), campos de estado (línea ~121), `_load` (línea ~252), `_loadPeerBadges` vecindad (nueva `_loadWhatsappGate`), `onSelected` (línea ~1373), `itemBuilder` (línea ~1430), `_chatMenuGuideKey` (línea ~1450)
- Modify: `app/lib/features/shared/onboarding_copy.dart:75-78`
- Test: `app/test/chat_menu_roles_test.dart` (añadir 3 tests)

**Interfaces:**
- Consumes: `WhatsappRevealGate`, `whatsappMenuReason`, `customerWhatsappRevealEnabled` (Task 3); `showWhatsappRevealSheet` (Task 1); `canRevealOffer`, `unlockedContact`, `productInterestContact` de `repos.dart`.
- Produces: `chatMenuValues` incluye `'whatsapp'` cuando `isProvider && isOpen`. **Su firma NO cambia** — §5 del spec suponía un parámetro nuevo y no hace falta: la presencia del ítem depende solo del rol y de si el chat está abierto, y el estado lo decide `whatsappMenuReason`. Menos superficie y los 8 tests existentes siguen compilando sin tocarlos.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final del `main()` de `app/test/chat_menu_roles_test.dart`, **sin tocar los 8 que ya hay**:

```dart
  test('ver WhatsApp es solo del proveedor', () {
    // El item aparece SIEMPRE (proveedor + chat abierto) y sale gris con su
    // motivo cuando no se puede — decision PO 2026-09-04. El cliente no lo ve:
    // el WhatsApp del proveedor ya vive en su tienda publica.
    expect(chatMenuValues(isProvider: true, isOpen: true), contains('whatsapp'));
    expect(chatMenuValues(isProvider: false, isOpen: true),
        isNot(contains('whatsapp')));
  });

  test('ver WhatsApp desaparece con el chat cerrado', () {
    for (final isProvider in [true, false]) {
      expect(chatMenuValues(isProvider: isProvider, isOpen: false),
          isNot(contains('whatsapp')));
    }
  });

  test('ver WhatsApp va justo detrás del perfil del cliente', () {
    // Las dos son "cosas del cliente"; cerrar el trato queda debajo.
    expect(chatMenuValues(isProvider: true, isOpen: true),
        containsAllInOrder(['profile', 'whatsapp', 'complete']));
  });
```

- [ ] **Step 2: Correrlos y ver que fallan**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/chat_menu_roles_test.dart
```

Esperado: los 3 nuevos FALLAN (`Expected: contains 'whatsapp'`); los 8 viejos PASAN.

- [ ] **Step 3: Añadir el valor a `chatMenuValues`**

En `chat_screen.dart`, sustituir el cuerpo de la lista:

```dart
List<String> chatMenuValues({required bool isProvider, required bool isOpen}) =>
    [
      // Perfil del cliente (mockup aprobado 2026-08-11): solo el PROVEEDOR —
      // el perfil anónimo/revelado es de clientes; el cliente ya ve la tienda
      // del proveedor por su propia vía.
      if (isProvider) 'profile',
      // Ver el WhatsApp del cliente (PO 2026-09-04). Va justo detrás del
      // perfil: las dos son "cosas del cliente". SIEMPRE presente para el
      // proveedor con el chat abierto — cuando no se puede se pinta gris con
      // el motivo (ver `whatsappMenuReason`), no se esconde. Con el chat
      // cerrado desaparece, como el resto de acciones vivas.
      if (isProvider && isOpen) 'whatsapp',
      if (isProvider && isOpen) 'complete',
      if (isOpen) 'lost',
      if (isProvider) 'funnel',
      'report',
    ];
```

- [ ] **Step 4: Correr los tests del menú**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter test test/chat_menu_roles_test.dart
```

Esperado: **11 tests PASAN**.

- [ ] **Step 5: Commit del contrato del menú**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git add app/lib/features/chat/chat_screen.dart app/test/chat_menu_roles_test.dart && git commit -m "feat(app): el menu del chat ofrece «Ver WhatsApp del cliente»

Solo proveedor y solo con el chat abierto, justo detras del perfil.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Añadir el estado y su carga**

En `chat_screen.dart`, junto a `PeerBadges? _peerBadges;` (línea ~121):

```dart
  /// Motivo por el que el ⋮ NO puede enseñar el WhatsApp del cliente. `null`
  /// = habilitado. Arranca en «no pudimos comprobarlo» a propósito: por
  /// defecto el ítem va gris, y solo una respuesta del servidor lo enciende.
  String? _waReason = whatsappMenuReason(WhatsappRevealGate.unknown);

  /// Teléfono del cliente en un chat de INTERÉS de producto. Su RPC es STABLE
  /// (no marca nada), así que se resuelve al cargar; NO se pinta en ninguna
  /// parte hasta pasar el hold. En los chats de OFERTA queda null: allí el
  /// teléfono se pide dentro del cargador, porque pedirlo marca el revelado.
  String? _waPhone;
```

Añadir el método, justo debajo de `_loadPeerBadges`:

```dart
  /// ¿Puede este proveedor ver el WhatsApp del cliente? Best-effort, con el
  /// mismo patrón fire-and-forget que `_loadPeerBadges`: si algo falla, el
  /// ítem se queda gris con «No pudimos comprobarlo» y el chat se pinta igual.
  ///
  /// Las dos consultas que usa son de SOLO LECTURA (`can_reveal_offer_whatsapp`
  /// es STABLE; `get_unlocked_product_interest_contact` también). Ninguna marca
  /// `whatsapp_revealed_at`: eso solo puede pasar tras el hold.
  Future<void> _loadWhatsappGate(Map<String, dynamic> conv) async {
    if (conv['provider_user_id'] != _uid) return;
    final sourceId = conv['source_id'] as String?;
    if (sourceId == null) return;
    try {
      if (conv['kind'] == 'offer') {
        final can = await canRevealOffer(sourceId);
        if (!mounted) return;
        setState(() => _waReason = whatsappMenuReason(can
            ? WhatsappRevealGate.canReveal
            // El bool no distingue "interruptor apagado" de "sin WhatsApp
            // verificado" y separarlo costaría otra consulta para el caso
            // raro: contra prod, 9 de cada 10 clientes con oferta desbloqueada
            // SÍ están verificados, así que el motivo real es el interruptor.
            : WhatsappRevealGate.optedOut));
        return;
      }
      if (conv['kind'] != 'product_interest') return;
      final customerId = conv['customer_id'] as String?;
      if (customerId == null) return;
      // En paralelo: el teléfono y el interruptor del cliente. La RPC del
      // interés NO mira `whatsapp_reveal_enabled` (agujero conocido, ticket
      // §9 del spec), así que la reja la pone aquí la app.
      final contactF = productInterestContact(sourceId);
      final enabledF = customerWhatsappRevealEnabled(customerId);
      final contact = await contactF;
      final enabled = await enabledF;
      if (!mounted) return;
      final phone = contact.phone;
      setState(() {
        _waPhone = phone;
        _waReason = whatsappMenuReason(!enabled
            ? WhatsappRevealGate.optedOut
            : (phone == null || phone.trim().isEmpty)
                ? WhatsappRevealGate.noPhone
                : WhatsappRevealGate.canReveal);
      });
    } catch (_) {
      // best-effort: se queda en «No pudimos comprobarlo».
    }
  }
```

En `_load()`, justo detrás de `_loadPeerBadges(conv);`:

```dart
      // ¿Se puede enseñar el WhatsApp? Best-effort, igual que los sellos.
      _loadWhatsappGate(conv);
```

- [ ] **Step 7: Abrir la hoja desde el ⋮**

En `chat_screen.dart`, añadir el import (junto al resto de `features/`):

```dart
import '../provider/unlock_flow.dart' show showWhatsappRevealSheet;
```

En el `switch (v)` de `onSelected`, entre `case 'profile'` y `case 'complete'`:

```dart
              case 'whatsapp':
                // `enabled: false` impide que este case corra sin gate: un
                // PopupMenuItem deshabilitado no dispara `onSelected`.
                final src = _conv?['source_id'] as String?;
                if (src == null) return;
                final isOffer = _conv?['kind'] == 'offer';
                final phone = _waPhone;
                await showWhatsappRevealSheet(
                  context,
                  peerName: _peerName,
                  // La devolución de créditos solo existe en las ofertas
                  // (PO 2026-08-28); en el interés el aviso viejo es el que
                  // dice la verdad.
                  refundApplies: isOffer,
                  loadPhone: isOffer
                      // Esta RPC MARCA el revelado: por eso vive aquí dentro
                      // y no en la carga del chat.
                      ? () async => (await unlockedContact(src)).phone
                      : () async => phone,
                );
```

- [ ] **Step 8: Pintar el ítem, gris cuando toque**

Sustituir el `itemBuilder` completo:

```dart
          itemBuilder: (_) => [
            for (final v in chatMenuValues(
                isProvider: _isProvider, isOpen: _isOpen))
              PopupMenuItem(
                value: v,
                // Solo el de WhatsApp puede salir gris: es el único que
                // depende de una decisión del otro lado.
                enabled: v != 'whatsapp' || _waReason == null,
                child: _menuItemChild(
                  switch (v) {
                    'profile' => 'Ver perfil del cliente',
                    'whatsapp' => 'Ver WhatsApp del cliente',
                    'complete' => 'Marcar como completado',
                    'lost' => 'Marcar como no concretado',
                    'funnel' => 'Estado del cliente',
                    _ => 'Denunciar cuenta',
                  },
                  reason: v == 'whatsapp' ? _waReason : null,
                ),
              ),
          ],
```

Y añadir el helper, justo debajo de `_buildHeader`:

```dart
  /// Hijo de un `PopupMenuItem`. Sin [reason] devuelve el `Text` pelado, para
  /// que los cinco ítems de siempre se pinten exactamente igual que antes.
  Widget _menuItemChild(String label, {String? reason}) {
    if (reason == null) return Text(label);
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(reason,
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
      ],
    );
  }
```

- [ ] **Step 9: Subir la clave de la guía**

En `chat_screen.dart`:

```dart
  /// Guía del ⋮, por rol (ver `onboarding_copy.dart`).
  String get _chatMenuGuideKey =>
      _isProvider ? 'chat.menu.provider.v2' : 'chat.menu.client.v1';
```

En `app/lib/features/shared/onboarding_copy.dart`, sustituir la entrada del proveedor (la del cliente NO se toca: su menú es idéntico):

```dart
  // v2 (2026-09-04): el ⋮ del proveedor gana «Ver WhatsApp del cliente». La
  // clave sube porque quien ya vio la v1 la tiene marcada en el backend, y sin
  // subirla el texto nuevo sería invisible para todos los usuarios actuales.
  'chat.menu.provider.v2': [
    OnboardingStep(
        'Aquí cierras el trato —completado o no concretado—, ves el perfil del cliente, pides su WhatsApp y denuncias si algo no cuadra.'),
  ],
```

- [ ] **Step 10: Analizar y correr la batería completa**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter analyze lib/ && flutter test
```

Esperado: `No issues found!` y la batería entera en verde (los 1734 del carril base + los 5 nuevos). Si `flutter analyze` marca `unused_element` en `_menuItemChild`, es que el `itemBuilder` no se sustituyó: volver al Step 8.

- [ ] **Step 11: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git add app/lib/features/chat/chat_screen.dart app/lib/features/shared/onboarding_copy.dart && git commit -m "feat(app): «Ver WhatsApp del cliente» en el menu del chat, gris con su motivo

Se consulta al cargar el chat con RPC de solo lectura; el telefono se pide
dentro del cargador, tras el hold. En los chats de interes la app pone la reja
que la RPC no pone. Guia del menu del proveedor a v2.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Verificación y APK para el smoke del PO

**Files:** ninguno de código.

**Interfaces:** consume todo lo anterior.

- [ ] **Step 1: Batería completa y análisis, desde limpio**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter analyze && flutter test
```

Esperado: `No issues found!` y 0 tests fallando. **Pegar la cifra real de tests en el informe** — no decir «pasan» sin el número.

- [ ] **Step 2: Confirmar que no se coló nada de servidor**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git diff feat/fecha-pautada-app --stat -- supabase/
```

Esperado: **salida vacía**. Si aparece algo, se para: esta rama no lleva migraciones.

- [ ] **Step 3: Confirmar que el árbol está limpio antes de compilar**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu && git status --short
```

Esperado: vacío. Un worktree sucio mete el aviso de «sucio» en el sello del APK y, peor, puede dejar fuera del build cambios sin commitear.

- [ ] **Step 4: Compilar el APK**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && flutter build apk --release
```

Esperado: `Built build/app/outputs/flutter-apk/app-release.apk`. Si falla por firma, faltan `app/android/key.properties` o `app/android/app/google-services.json` — ya se copiaron al crear el worktree; volver a copiarlos desde `C:/Users/ac/Downloads/jayalo-app/app/android/`.

- [ ] **Step 5: Comprobar el sello del build**

```bash
cd /c/Users/ac/Downloads/jayalo-app-wa-menu/app && "$ANDROID_HOME/build-tools/34.0.0/aapt.exe" dump badging build/app/outputs/flutter-apk/app-release.apk | grep -i "meta-data\|versionCode"
```

Esperado: el `meta-data` del sello dice rama `feat/whatsapp-en-menu-chat` y el commit de la Task 4, sin marca de árbol sucio. (Si `aapt` no está en esa ruta, buscarlo con `ls $ANDROID_HOME/build-tools/`.)

- [ ] **Step 6: Preparar el smoke del PO**

Escribir en el informe, literalmente, que el ítem **saldrá gris en los 11 chats de oferta de hoy** y que para verlo habilitado hay que:

1. entrar con la cuenta de un CLIENTE que tenga una oferta desbloqueada,
2. Ajustes → activar «que me contacten por WhatsApp» (`profiles.whatsapp_reveal_enabled`),
3. volver al chat con la cuenta del PROVEEDOR y **recargar el chat** (el gate se lee al cargar, no en tiempo real).

Sin ese paso el smoke solo puede comprobar el estado gris y su motivo — que también hay que comprobar.

- [ ] **Step 7: Entregar**

Enviar el APK al PO y **no mergear** a `feat/fecha-pautada-app` hasta que dé el smoke. Antes del merge faltan además las dos revisiones de después (verificador + certificador) de la regla de los 4 agentes.

---

## Fuera de esta rama (tickets)

No se implementan aquí; quedan anotados para que nadie los dé por hechos:

1. **`get_unlocked_product_interest_contact` es permisiva:** devuelve `profiles.phone` sin mirar `whatsapp_reveal_enabled` (3 de 5 intereses desbloqueados reales). El fix real es una migración con `can_reveal_interest_whatsapp` + apretar esa RPC, con sondas y sus 4 revisiones.
2. **`product_interest_detail_screen`** sigue enseñando el gate sin la reja del interruptor que sí pone el ⋮. Alinearlo para que las dos superficies no digan cosas distintas.
