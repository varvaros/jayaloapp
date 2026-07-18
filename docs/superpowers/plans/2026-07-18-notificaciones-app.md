# Centro de notificaciones in-app — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Campana con badge en las 4 pantallas principales + pantalla `/notifications` con "tarjetas que respiran" (colores por familia, agrupación por día, swipe=leída, realtime foreground-only) + `mapLinkToRoute` extendido que arregla los 2 bugs de ruteo del push.

**Architecture:** Mismo patrón de 3 capas del chat: dominio puro testeable (`lib/domain/notifications.dart`), repositorio de funciones sueltas sobre `supa` (`lib/data/notifications_repository.dart`), y UI en `lib/features/notifications/`. Store de conteo compartido (`ChangeNotifier` global, como `roleStore`). Cero cambios de backend: la tabla `notifications`, su RLS y su publicación realtime ya están en producción (la web las usa).

**Tech Stack:** Flutter (Material 3, seed `#7C3AED`), supabase_flutter 2.x, go_router, `flutter_animate` (paquete NUEVO, aprobado por el PO en el spec).

**Spec:** `docs/superpowers/specs/2026-07-18-notificaciones-app-design.md`

## Global Constraints

- Directorio de trabajo del proyecto Flutter: `C:\Users\ac\Downloads\jayalo-app\app` (el repo es el padre). Flutter vive en `C:\dev\flutter` — si `flutter` no está en PATH usar `C:\dev\flutter\bin\flutter`.
- Cada task cierra con `flutter test` (baseline actual: **108 pasando**; solo puede crecer) + `flutter analyze` en **0 issues** + commit.
- **NUNCA DELETE** sobre `notifications` — marcar leída = `update read_at` (convención del proyecto).
- Paginado en páginas de **30** con botón **"Cargar más"** — NO scroll infinito.
- Badge con tope **"9+"**.
- **Sin socket persistente para el badge**: el conteo va por COUNT al montar + al resume. Realtime SOLO mientras `/notifications` está visible y la app en foreground (patrón del chat).
- Único paquete nuevo permitido: `flutter_animate`.
- Todo el copy visible en español (es-DO).
- Cero migraciones, cero Edge Functions, cero cambios en jayalo-main.
- Commits en español estilo del repo (`feat:`/`fix:`), terminando con `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Dominio puro — modelo, familias, iconos, limpieza y tiempos (TDD)

**Files:**
- Create: `app/lib/domain/notifications.dart`
- Test: `app/test/notifications_test.dart`

**Interfaces:**
- Consumes: `dayKey`, `formatDayLabel` de `app/lib/domain/chat_time.dart` (ya existen, reusar — DRY).
- Produces (los usan Tasks 4-6):
  - `enum NotifFamily { messages, offers, wallet, reviews, system }`
  - `NotifFamily familyFor(String kind)`
  - `IconData iconFor(String kind)`
  - `String cleanBody(String body)`
  - `String badgeLabel(int count)`
  - `String relativeTimeEs(DateTime d, {DateTime? now})`
  - `class AppNotification { String id, kind, title, body, link; DateTime createdAt; DateTime? readAt (mutable); bool get unread; factory fromMap(Map<String, dynamic>) }`
  - `List<({String label, List<AppNotification> items})> groupByDay(List<AppNotification> list, {DateTime? now})`

- [ ] **Step 1: Write the failing tests**

Crear `app/test/notifications_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/notifications.dart';

void main() {
  group('familyFor', () {
    test('message_new es familia mensajes', () {
      expect(familyFor('message_new'), NotifFamily.messages);
    });
    test('ofertas/ventas: offer_*, job_response_new, sale y cancelaciones', () {
      for (final k in [
        'offer_new', 'offer_accepted', 'offer_rejected', 'offer_sent_confirmation',
        'offer_cancelled_customer', 'job_response_new', 'sale_completed_provider',
        'request_cancelled_provider',
      ]) {
        expect(familyFor(k), NotifFamily.offers, reason: k);
      }
    });
    test('wallet_* es familia wallet', () {
      for (final k in ['wallet_low_balance', 'wallet_empty', 'wallet_recharged']) {
        expect(familyFor(k), NotifFamily.wallet, reason: k);
      }
    });
    test('review_* es familia reseñas', () {
      expect(familyFor('review_new'), NotifFamily.reviews);
      expect(familyFor('review_pending_reminder'), NotifFamily.reviews);
    });
    test('welcome, referidos y kinds desconocidos caen en sistema', () {
      for (final k in [
        'welcome_customer', 'welcome_provider', 'referral_invite',
        'referral_reward', 'kind_inventado_futuro',
      ]) {
        expect(familyFor(k), NotifFamily.system, reason: k);
      }
    });
  });

  group('iconFor', () {
    test('mapea los kinds conocidos como la web', () {
      expect(iconFor('offer_new'), Icons.inventory_2_outlined);
      expect(iconFor('job_response_new'), Icons.work_outline);
      expect(iconFor('review_new'), Icons.star_outline);
      expect(iconFor('referral_reward'), Icons.card_giftcard);
      expect(iconFor('wallet_empty'), Icons.account_balance_wallet_outlined);
      expect(iconFor('sale_completed_provider'), Icons.check_circle_outline);
      expect(iconFor('request_cancelled_provider'), Icons.cancel_outlined);
      expect(iconFor('welcome_provider'), Icons.auto_awesome);
      expect(iconFor('message_new'), Icons.chat_bubble_outline);
    });
    test('kind desconocido usa el fallback de su familia', () {
      expect(iconFor('wallet_algo_nuevo'), Icons.account_balance_wallet_outlined);
      expect(iconFor('cualquier_cosa'), Icons.notifications_none);
    });
  });

  group('cleanBody', () {
    test('quita el tag __VALUE__ con salto de línea (regex de la web)', () {
      expect(cleanBody('Recargaste créditos.\n__VALUE__:25'), 'Recargaste créditos.');
    });
    test('quita el tag sin salto de línea y con decimales', () {
      expect(cleanBody('Saldo bajo __VALUE__:2.5'), 'Saldo bajo');
    });
    test('cuerpo sin tag queda igual (trim aplicado)', () {
      expect(cleanBody('  Hola  '), 'Hola');
    });
  });

  group('badgeLabel', () {
    test('hasta 9 muestra el número, 10+ muestra 9+', () {
      expect(badgeLabel(1), '1');
      expect(badgeLabel(9), '9');
      expect(badgeLabel(10), '9+');
      expect(badgeLabel(99), '9+');
    });
  });

  group('relativeTimeEs', () {
    final now = DateTime(2026, 7, 18, 15, 0);
    test('menos de 1 min es "ahora"', () {
      expect(relativeTimeEs(now.subtract(const Duration(seconds: 30)), now: now), 'ahora');
    });
    test('minutos y horas del mismo día', () {
      expect(relativeTimeEs(now.subtract(const Duration(minutes: 5)), now: now), 'hace 5 min');
      expect(relativeTimeEs(DateTime(2026, 7, 18, 11, 0), now: now), 'hace 4 h');
    });
    test('ayer es "ayer" aunque hayan pasado pocas horas', () {
      expect(relativeTimeEs(DateTime(2026, 7, 17, 23, 30), now: now), 'ayer');
    });
    test('más viejo usa fecha corta', () {
      expect(relativeTimeEs(DateTime(2026, 7, 15, 10, 0), now: now), '15 jul');
    });
  });

  group('AppNotification.fromMap', () {
    test('parsea la fila y convierte created_at a hora local', () {
      final n = AppNotification.fromMap({
        'id': 'abc',
        'kind': 'offer_new',
        'title': 'Nueva oferta',
        'body': 'Te ofertaron\n__VALUE__:500',
        'link': '/requests/123',
        'read_at': null,
        'created_at': '2026-07-18T12:00:00+00:00',
      });
      expect(n.id, 'abc');
      expect(n.unread, isTrue);
      expect(n.createdAt.isUtc, isFalse);
    });
    test('read_at presente marca como leída; campos null no explotan', () {
      final n = AppNotification.fromMap({
        'id': 'x',
        'kind': null,
        'title': null,
        'body': null,
        'link': null,
        'read_at': '2026-07-18T13:00:00+00:00',
        'created_at': '2026-07-18T12:00:00+00:00',
      });
      expect(n.unread, isFalse);
      expect(n.title, '');
      expect(n.link, '');
    });
  });

  group('groupByDay', () {
    AppNotification mk(String id, DateTime d) => AppNotification.fromMap({
          'id': id, 'kind': 'message_new', 'title': 't', 'body': '', 'link': '',
          'read_at': null, 'created_at': d.toUtc().toIso8601String(),
        });
    test('agrupa preservando orden con etiquetas Hoy/Ayer/fecha', () {
      final now = DateTime(2026, 7, 18, 15, 0);
      final groups = groupByDay([
        mk('a', DateTime(2026, 7, 18, 14, 0)),
        mk('b', DateTime(2026, 7, 18, 9, 0)),
        mk('c', DateTime(2026, 7, 17, 20, 0)),
        mk('d', DateTime(2026, 7, 15, 8, 0)),
      ], now: now);
      expect(groups.map((g) => g.label).toList(), ['Hoy', 'Ayer', '15 jul']);
      expect(groups.first.items.map((n) => n.id).toList(), ['a', 'b']);
      expect(groups.last.items.single.id, 'd');
    });
    test('lista vacía produce cero grupos', () {
      expect(groupByDay([], now: DateTime(2026, 7, 18)), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (desde `app/`): `flutter test test/notifications_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jayalo_app/domain/notifications.dart'`.

- [ ] **Step 3: Write the implementation**

Crear `app/lib/domain/notifications.dart`:

```dart
/// Dominio del centro de notificaciones (spec 2026-07-18).
/// Puro y testeable: familias, iconos, limpieza de body, tiempos relativos y
/// agrupación por día. Los COLORES concretos por familia viven en la UI.
library;

import 'package:flutter/material.dart' show IconData, Icons;

import 'chat_time.dart';

enum NotifFamily { messages, offers, wallet, reviews, system }

/// Familia visual por kind (tabla del spec §3). Los prefijos cubren kinds
/// futuros de la misma familia sin tocar código.
NotifFamily familyFor(String kind) {
  if (kind == 'message_new') return NotifFamily.messages;
  if (kind.startsWith('offer_') ||
      kind == 'job_response_new' ||
      kind == 'sale_completed_provider' ||
      kind == 'request_cancelled_provider') {
    return NotifFamily.offers;
  }
  if (kind.startsWith('wallet_')) return NotifFamily.wallet;
  if (kind.startsWith('review_')) return NotifFamily.reviews;
  return NotifFamily.system;
}

/// Icono por kind — espejo del `iconFor` de la web (NotificationsBell.tsx),
/// con fallback por familia para kinds nuevos.
IconData iconFor(String kind) => switch (kind) {
      'offer_new' ||
      'offer_accepted' ||
      'offer_rejected' ||
      'offer_sent_confirmation' =>
        Icons.inventory_2_outlined,
      'job_response_new' => Icons.work_outline,
      'review_new' || 'review_pending_reminder' => Icons.star_outline,
      'referral_invite' || 'referral_reward' => Icons.card_giftcard,
      'wallet_low_balance' || 'wallet_empty' || 'wallet_recharged' =>
        Icons.account_balance_wallet_outlined,
      'sale_completed_provider' => Icons.check_circle_outline,
      'request_cancelled_provider' ||
      'offer_cancelled_customer' =>
        Icons.cancel_outlined,
      'welcome_customer' || 'welcome_provider' => Icons.auto_awesome,
      'message_new' => Icons.chat_bubble_outline,
      _ => _fallbackIcon(familyFor(kind)),
    };

IconData _fallbackIcon(NotifFamily f) => switch (f) {
      NotifFamily.messages => Icons.chat_bubble_outline,
      NotifFamily.offers => Icons.inventory_2_outlined,
      NotifFamily.wallet => Icons.account_balance_wallet_outlined,
      NotifFamily.reviews => Icons.star_outline,
      NotifFamily.system => Icons.notifications_none,
    };

/// El backend mete `__VALUE__:N` en el body de algunos correos/notifs
/// (misma regex de limpieza que la web: `/\n?__VALUE__:[\d.]+/g`).
final _valueTag = RegExp(r'\n?__VALUE__:[\d.]+');
String cleanBody(String body) => body.replaceAll(_valueTag, '').trim();

/// Texto del badge de la campana, tope "9+".
String badgeLabel(int count) => count > 9 ? '9+' : '$count';

/// Hora relativa corta en español: "ahora", "hace 5 min", "hace 3 h",
/// "ayer", "15 jul".
String relativeTimeEs(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (dayKey(d) == dayKey(n)) return 'hace ${diff.inHours} h';
  if (dayKey(d) == dayKey(n.subtract(const Duration(days: 1)))) return 'ayer';
  return formatDayLabel(d, now: n);
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        kind: m['kind'] as String? ?? '',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        link: m['link'] as String? ?? '',
        // La BD guarda UTC; agrupar por día y los tiempos relativos necesitan
        // la hora local del dispositivo.
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
      );

  final String id;
  final String kind;
  final String title;
  final String body;
  final String link;
  final DateTime createdAt;

  /// Mutable a propósito: el marcar-leída optimista lo escribe in situ y la
  /// tarjeta se apaga con AnimatedContainer sin reconstruir la lista.
  DateTime? readAt;

  bool get unread => readAt == null;
}

/// Agrupa una lista YA ordenada desc por fecha en secciones de día
/// ("Hoy", "Ayer", "15 jul") preservando el orden.
List<({String label, List<AppNotification> items})> groupByDay(
    List<AppNotification> list,
    {DateTime? now}) {
  final n = now ?? DateTime.now();
  final out = <({String label, List<AppNotification> items})>[];
  for (final item in list) {
    final label = formatDayLabel(item.createdAt, now: n);
    if (out.isEmpty || out.last.label != label) {
      out.add((label: label, items: [item]));
    } else {
      out.last.items.add(item);
    }
  }
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run (desde `app/`): `flutter test`
Expected: PASS, total ≥ 108 + ~17 nuevos.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/notifications.dart app/test/notifications_test.dart
git commit -m "feat: dominio de notificaciones (familias, iconos, tiempos, agrupacion)"
```

---

### Task 2: `mapLinkToRoute` extendido en dominio + `push_service` delega (TDD)

Arregla los 2 bugs vivos del push: (a) `/provider/requests/<id>` caía en `/provider/offers` aunque existe `/provider/request/:id`; (b) fallback fijo `/client` que mandaba al proveedor a la pantalla equivocada.

**Files:**
- Modify: `app/lib/domain/notifications.dart` (agregar `mapLinkToRoute` al final)
- Modify: `app/lib/push/push_service.dart` (borrar su `mapLinkToRoute` local y delegar)
- Test: `app/test/notifications_test.dart` (agregar grupo)

**Interfaces:**
- Consumes: `roleStore` / `RoleState` de `app/lib/core/session_state.dart` (solo en push_service; el dominio recibe un bool).
- Produces: `String mapLinkToRoute(String link, {required bool provider})` — la usan `push_service.dart` (Task 2) y la pantalla (Task 5). Una sola verdad de ruteo.

- [ ] **Step 1: Write the failing tests**

Agregar al final del `main()` de `app/test/notifications_test.dart`:

```dart
  group('mapLinkToRoute', () {
    test('mensajes: query ?c=, path directo y lista', () {
      expect(mapLinkToRoute('/messages?c=abc-123', provider: false), '/messages/abc-123');
      expect(mapLinkToRoute('/messages/abc-123', provider: true), '/messages/abc-123');
      expect(mapLinkToRoute('/messages', provider: false), '/messages');
    });
    test('solicitud del cliente', () {
      expect(mapLinkToRoute('/requests/deadbeef-1', provider: false), '/client/request/deadbeef-1');
    });
    test('BUG (a): detalle de solicitud del proveedor va al detalle nativo', () {
      expect(mapLinkToRoute('/provider/requests/deadbeef-2', provider: true),
          '/provider/request/deadbeef-2');
    });
    test('ofertas del proveedor en sus dos formatos', () {
      expect(mapLinkToRoute('/provider/offers', provider: true), '/provider/offers');
      expect(mapLinkToRoute('/provider?view=offers', provider: true), '/provider/offers');
    });
    test('wallet y resto de /provider caen en /provider', () {
      expect(mapLinkToRoute('/provider?panel=wallet', provider: true), '/provider');
      expect(mapLinkToRoute('/provider/wallet', provider: true), '/provider');
      expect(mapLinkToRoute('/provider', provider: true), '/provider');
    });
    test('BUG (b): desconocido/vacío cae por ROL activo, no fijo /client', () {
      expect(mapLinkToRoute('/empleos/xyz', provider: true), '/provider');
      expect(mapLinkToRoute('/empleos/xyz', provider: false), '/client');
      expect(mapLinkToRoute('', provider: true), '/provider');
      expect(mapLinkToRoute('', provider: false), '/client');
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/notifications_test.dart`
Expected: FAIL — `The function 'mapLinkToRoute' isn't defined`.

- [ ] **Step 3: Implement in domain and delegate in push_service**

Agregar al final de `app/lib/domain/notifications.dart`:

```dart
/// Ruteo del tap de una notificación (push Y lista in-app) — links reales que
/// escribe el backend, verificados en migraciones de jayalo-main (spec §4).
/// `provider` = rol activo, para el fallback de links desconocidos.
String mapLinkToRoute(String link, {required bool provider}) {
  final msgQuery = RegExp(r'^/messages\?c=([0-9a-f-]+)').firstMatch(link);
  if (msgQuery != null) return '/messages/${msgQuery.group(1)}';
  final msgPath = RegExp(r'^/messages/([0-9a-f-]+)').firstMatch(link);
  if (msgPath != null) return '/messages/${msgPath.group(1)}';
  if (link == '/messages') return '/messages';
  final req = RegExp(r'^/requests/([0-9a-f-]+)').firstMatch(link);
  if (req != null) return '/client/request/${req.group(1)}';
  final provReq = RegExp(r'^/provider/requests/([0-9a-f-]+)').firstMatch(link);
  if (provReq != null) return '/provider/request/${provReq.group(1)}';
  if (link == '/provider/offers' || link == '/provider?view=offers') {
    return '/provider/offers';
  }
  if (link.startsWith('/provider')) return '/provider';
  return provider ? '/provider' : '/client';
}
```

En `app/lib/push/push_service.dart`:

1. **Borrar** la función `mapLinkToRoute` local completa (líneas 7-16, incluido su doc comment).
2. Agregar imports:

```dart
import '../core/session_state.dart';
import '../domain/notifications.dart';
```

3. Reemplazar el cuerpo de `goFrom`:

```dart
  void goFrom(RemoteMessage m) {
    final link = m.data['link'] as String? ?? '';
    router.go(mapLinkToRoute(link,
        provider: roleStore.value == RoleState.provider));
  }
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test` → PASS (suite completa). `flutter analyze` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/notifications.dart app/lib/push/push_service.dart app/test/notifications_test.dart
git commit -m "fix: mapLinkToRoute extendido con rol (detalle proveedor y fallback correctos)"
```

---

### Task 3: Repositorio de datos (`notifications_repository.dart`)

Capa de red, sin tests unitarios (mismo trato que los repos del chat: la verificación es `analyze` + el E2E en device). NO tocar `repos.dart` salvo el import de `supa`.

**Files:**
- Create: `app/lib/data/notifications_repository.dart`

**Interfaces:**
- Consumes: `supa` (el singleton exportado por `app/lib/data/repos.dart`).
- Produces (los usan Tasks 4-6):
  - `const notifPageSize = 30`
  - `Future<List<Map<String, dynamic>>> notificationsPage(int page)`
  - `Future<int> unreadNotificationsCount()`
  - `Future<void> markNotificationRead(String id)`
  - `Future<void> markAllNotificationsRead()`
  - `RealtimeChannel subscribeNotifications(void Function(Map<String, dynamic> row) onInsert)`
  - `void unsubscribeNotifications(RealtimeChannel ch)`

- [ ] **Step 1: Write the repository**

Crear `app/lib/data/notifications_repository.dart`:

```dart
/// Datos del centro de notificaciones (spec 2026-07-18 §1).
/// Sin cambios de backend: tabla `notifications` + RLS + realtime ya en prod.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'repos.dart' show supa;

const notifCols = 'id,kind,title,body,link,read_at,created_at';
const notifPageSize = 30;

/// Página N (0-based) de 30, más recientes primero. La última página se
/// detecta porque vuelve con menos de [notifPageSize] filas.
Future<List<Map<String, dynamic>>> notificationsPage(int page) async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('notifications')
      .select(notifCols)
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .range(page * notifPageSize, page * notifPageSize + notifPageSize - 1));
}

/// Conteo de no-leídas para el badge. `count` respeta los filtros e IGNORA
/// limit/range, así que el `limit(1)` deja el payload en ~1 fila — el
/// equivalente práctico del `head: true` que usa la web.
Future<int> unreadNotificationsCount() async {
  final uid = supa.auth.currentUser!.id;
  final res = await supa
      .from('notifications')
      .select('id')
      .eq('user_id', uid)
      .isFilter('read_at', null)
      .limit(1)
      .count(CountOption.exact);
  return res.count;
}

/// Marcar leída = update de read_at. NUNCA DELETE (convención del proyecto).
Future<void> markNotificationRead(String id) async => supa
    .from('notifications')
    .update({'read_at': DateTime.now().toUtc().toIso8601String()})
    .eq('id', id)
    .isFilter('read_at', null);

Future<void> markAllNotificationsRead() async {
  final uid = supa.auth.currentUser!.id;
  await supa
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', uid)
      .isFilter('read_at', null);
}

/// Canal realtime de INSERTs del usuario. Suscribir SOLO con la pantalla de
/// notificaciones visible y la app en foreground (patrón del chat) — el
/// llamador es dueño del ciclo de vida.
RealtimeChannel subscribeNotifications(
    void Function(Map<String, dynamic> row) onInsert) {
  final uid = supa.auth.currentUser!.id;
  return supa
      .channel('notifs-$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();
}

void unsubscribeNotifications(RealtimeChannel ch) => supa.removeChannel(ch);
```

- [ ] **Step 2: Run tests + analyze**

Run: `flutter test` → PASS (mismo total que Task 2). `flutter analyze` → `No issues found!`
Nota: si el analyzer se queja de `res.count` (la forma exacta del retorno de `.count()` en la versión instalada de postgrest), ajustar a la firma que el analyzer indique — `select().…filtros….count(CountOption.exact)` devuelve `PostgrestResponse` con `.count` en postgrest 2.8.0 (verificado en el código fuente del paquete).

- [ ] **Step 3: Commit**

```bash
git add app/lib/data/notifications_repository.dart
git commit -m "feat: repositorio de notificaciones (paginado, conteo, leidas, realtime)"
```

---

### Task 4: `flutter_animate` + store de conteo + `NotificationBell` en las 4 pantallas

**Files:**
- Modify: `app/pubspec.yaml` (agregar `flutter_animate`)
- Create: `app/lib/features/notifications/notification_bell.dart`
- Modify: `app/lib/features/client/my_requests_screen.dart:60`
- Modify: `app/lib/features/client/create_request_screen.dart:262`
- Modify: `app/lib/features/provider/inbox_screen.dart:22`
- Modify: `app/lib/features/provider/my_offers_screen.dart:76`

**Interfaces:**
- Consumes: `unreadNotificationsCount()` (Task 3), `badgeLabel` (Task 1).
- Produces (los usan Tasks 5-6): `class NotifCountStore extends ChangeNotifier { int count; Future<void> refresh(); void add(int delta); void zero(); }` y el singleton `final notifCountStore = NotifCountStore()`, exportados desde `notification_bell.dart`. Widget `NotificationBell` (const, sin parámetros).

Nota de estructura: el spec §5 dice `lib/ui/…` pero el árbol real del proyecto usa `lib/features/<feature>/…` — se sigue la convención del código existente.

- [ ] **Step 1: Add flutter_animate**

En `app/pubspec.yaml`, dentro de `dependencies:`, después de `shared_preferences: ^2.5.2` agregar:

```yaml
  flutter_animate: ^4.5.0
```

Run (desde `app/`): `flutter pub get`
Expected: resuelve sin conflictos (flutter_animate no arrastra deps nativas).

- [ ] **Step 2: Write the bell + store**

Crear `app/lib/features/notifications/notification_bell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../data/notifications_repository.dart';
import '../../domain/notifications.dart';

/// Conteo de no-leídas COMPARTIDO entre las 4 campanas (un solo estado, no un
/// fetch por campana). Ciclo de vida (spec §2): refresh al montar la pantalla
/// que la contiene + al resume; optimista vía [add]/[zero] desde la pantalla
/// de notificaciones. SIN socket persistente.
class NotifCountStore extends ChangeNotifier {
  int count = 0;

  Future<void> refresh() async {
    try {
      final n = await unreadNotificationsCount();
      if (n != count) {
        count = n;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: el badge nunca rompe la pantalla que lo hospeda.
    }
  }

  void add(int delta) {
    final next = (count + delta).clamp(0, 999);
    if (next != count) {
      count = next;
      notifyListeners();
    }
  }

  void zero() => add(-count);
}

final notifCountStore = NotifCountStore();

/// Campana del AppBar (spec §2): badge rojo con tope 9+, pop elástico al
/// aparecer y pulso al cambiar el conteo. Tap → /notifications.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifCountStore.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) notifCountStore.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: notifCountStore,
      builder: (context, _) {
        final c = notifCountStore.count;
        return IconButton(
          tooltip: 'Notificaciones',
          onPressed: () => context.push('/notifications'),
          icon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.notifications_outlined),
            if (c > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  height: 16,
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel(c),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onError),
                  ),
                )
                    // La key por valor recrea el Animate en cada cambio de
                    // conteo: pop elástico al aparecer Y pulso al subir.
                    .animate(key: ValueKey(c))
                    .scale(
                        begin: const Offset(.4, .4),
                        end: const Offset(1, 1),
                        duration: 500.ms,
                        curve: Curves.elasticOut),
              ),
          ]),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Add the bell to the 4 AppBars (y SOLO esas 4)**

En `app/lib/features/client/my_requests_screen.dart` — import nuevo junto a los existentes:

```dart
import '../notifications/notification_bell.dart';
```

y el AppBar (línea ~60):

```dart
      appBar: AppBar(
          title: const Text('Mis solicitudes'),
          actions: const [NotificationBell()]),
```

En `app/lib/features/client/create_request_screen.dart` (línea ~262), mismo import y:

```dart
      appBar: AppBar(
          title: const Text('Crear solicitud'),
          actions: const [NotificationBell()]),
```

En `app/lib/features/provider/inbox_screen.dart` (línea ~22), mismo import y:

```dart
      appBar: AppBar(
          title: const Text('Solicitudes para ti'),
          actions: const [NotificationBell()]),
```

En `app/lib/features/provider/my_offers_screen.dart` (línea ~76), mismo import y:

```dart
      appBar: AppBar(
          title: const Text('Mis ofertas'),
          actions: const [NotificationBell()]),
```

Las demás pantallas (chat, ajustes, detalles) NO llevan campana.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test` → PASS. `flutter analyze` → `No issues found!`
(La ruta `/notifications` aún no existe — el `push` fallaría en runtime, se agrega en Task 5; analyze no lo detecta y no hay test de widget que lo ejercite, aceptable entre tasks.)

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/features/notifications/notification_bell.dart app/lib/features/client/my_requests_screen.dart app/lib/features/client/create_request_screen.dart app/lib/features/provider/inbox_screen.dart app/lib/features/provider/my_offers_screen.dart
git commit -m "feat: campana de notificaciones con badge animado en las 4 pantallas principales"
```

---

### Task 5: Ruta `/notifications` + pantalla base (lista, estados, paginación, tap, marcar todas)

Pantalla completa y funcional SIN gestos de swipe ni realtime ni cascada de entrada (Task 6). Sí incluye: colores por familia, encabezados de día, píldora "N nuevas", marcar todas (cascada simple por delays), tap = leída optimista + navegar.

**Files:**
- Create: `app/lib/features/notifications/notifications_screen.dart`
- Modify: `app/lib/core/router.dart` (ruta nueva en el ShellRoute)

**Interfaces:**
- Consumes: Task 1 (dominio), Task 3 (repositorio), `notifCountStore` (Task 4), `roleStore`/`RoleState` (`core/session_state.dart`), `BackGuard` (`features/shell/back_guard.dart` — SIEMPRE dentro de la ruta hija, gotcha PopScope/predictive-back).
- Produces: `NotificationsScreen` (const), función `familyColors(BuildContext, NotifFamily)` top-level del mismo archivo (Task 6 la reusa para el destello realtime).

- [ ] **Step 1: Add the route**

En `app/lib/core/router.dart`, agregar el import:

```dart
import '../features/notifications/notifications_screen.dart';
```

y dentro de `routes:` del `ShellRoute`, después de la ruta `/messages/:id`:

```dart
            GoRoute(
                path: '/notifications',
                builder: (_, _) =>
                    const BackGuard(child: NotificationsScreen())),
```

- [ ] **Step 2: Write the screen**

Crear `app/lib/features/notifications/notifications_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_state.dart';
import '../../data/notifications_repository.dart';
import '../../domain/notifications.dart';
import 'notification_bell.dart';

/// Colores por familia (spec §3): tinte de fondo + texto + icono, en light y
/// dark. Ofertas usa el contenedor primario del seed #7C3AED; el resto son
/// tonos fijos ajustados a contraste.
({Color bg, Color fg, Color icon}) familyColors(
    BuildContext context, NotifFamily f) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (f) {
    NotifFamily.messages => dark
        ? (bg: const Color(0xFF16302E), fg: const Color(0xFFB2DFDB), icon: const Color(0xFF4DB6AC))
        : (bg: const Color(0xFFE0F2F1), fg: const Color(0xFF00504A), icon: const Color(0xFF00796B)),
    NotifFamily.offers => (bg: cs.primaryContainer, fg: cs.onPrimaryContainer, icon: cs.primary),
    NotifFamily.wallet => dark
        ? (bg: const Color(0xFF3A2E12), fg: const Color(0xFFFFE082), icon: const Color(0xFFFFB300))
        : (bg: const Color(0xFFFFF8E1), fg: const Color(0xFF6D4C00), icon: const Color(0xFFB28704)),
    NotifFamily.reviews => dark
        ? (bg: const Color(0xFF3A1F2B), fg: const Color(0xFFF8BBD0), icon: const Color(0xFFF06292))
        : (bg: const Color(0xFFFCE4EC), fg: const Color(0xFF880E4F), icon: const Color(0xFFC2185B)),
    NotifFamily.system => (bg: cs.surfaceContainerHighest, fg: cs.onSurface, icon: cs.onSurfaceVariant),
  };
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _items = [];
  bool _loading = true;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 0;

  int get _unread => _items.where((n) => n.unread).length;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await notificationsPage(0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows.map(AppNotification.fromMap));
        _page = 0;
        _hasMore = rows.length == notifPageSize;
        _loading = false;
      });
      // Revalida el badge compartido con la verdad recién cargada.
      notifCountStore.refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await notificationsPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(rows.map(AppNotification.fromMap));
        _hasMore = rows.length == notifPageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _markReadOptimistic(AppNotification n) {
    if (!n.unread) return;
    setState(() => n.readAt = DateTime.now());
    notifCountStore.add(-1);
    markNotificationRead(n.id).catchError((_) {});
  }

  void _open(AppNotification n) {
    // Optimista: si el update falla igual se navega (spec §3).
    _markReadOptimistic(n);
    context.push(mapLinkToRoute(n.link,
        provider: roleStore.value == RoleState.provider));
  }

  void _markAll() {
    final unread = _items.where((n) => n.unread).toList();
    if (unread.isEmpty) return;
    markAllNotificationsRead().catchError((_) {});
    notifCountStore.zero();
    // Cascada suave: las tarjetas se apagan escalonadas (el AnimatedContainer
    // de cada tarjeta hace el fade de color al cambiar readAt).
    for (var i = 0; i < unread.length; i++) {
      Future.delayed(Duration(milliseconds: 60 * i), () {
        if (!mounted) return;
        setState(() => unread[i].readAt = DateTime.now());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          // Píldora "N nuevas": se encoge hasta desaparecer al llegar a 0.
          AnimatedScale(
            scale: _unread > 0 ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$_unread nueva${_unread == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer),
              ),
            ),
          ),
          if (_unread > 0)
            IconButton(
              tooltip: 'Marcar todas como leídas',
              icon: const Icon(Icons.done_all),
              onPressed: _markAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const _Skeletons();
    if (_error) return _ErrorRetry(onRetry: _loadFirst);
    if (_items.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final groups = groupByDay(_items);
    final children = <Widget>[];
    for (final g in groups) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          g.label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: cs.onSurfaceVariant),
        ),
      ));
      for (final n in g.items) {
        children.add(_buildCard(n));
      }
    }
    if (_hasMore) {
      children.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: _loadingMore
              ? const CircularProgressIndicator()
              : OutlinedButton(
                  onPressed: _loadMore, child: const Text('Cargar más')),
        ),
      ));
    }
    children.add(const SizedBox(height: 24));
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView(children: children),
    );
  }

  Widget _buildCard(AppNotification n) =>
      _NotifCard(key: ValueKey(n.id), n: n, onTap: () => _open(n));
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({super.key, required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fam = familyColors(context, familyFor(n.kind));
    final read = !n.unread;
    // Leída: fondo neutro, textos apagados, icono gris (spec §3). El
    // AnimatedContainer hace el desvanecido de color (~300ms) al marcar leída.
    final bg = read ? cs.surfaceContainerHighest.withValues(alpha: .55) : fam.bg;
    final fg = read ? cs.onSurfaceVariant : fam.fg;
    final ic = read ? cs.outline : fam.icon;
    final body = cleanBody(n.body);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ic.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconFor(n.kind), size: 20, color: ic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight:
                                read ? FontWeight.w500 : FontWeight.w700,
                            color: fg),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: fg.withValues(alpha: .8)),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        relativeTimeEs(n.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: fg.withValues(alpha: .65)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeletons extends StatelessWidget {
  const _Skeletons();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 84,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(children: const [
        SizedBox(height: 120),
        Icon(Icons.notifications_none, size: 56),
        Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no tienes notificaciones.\n'
            'Aquí verás tus ofertas, mensajes,\nreseñas y avisos de tu cuenta.',
            textAlign: TextAlign.center,
          ),
        ),
      ]);
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text('No se pudieron cargar las notificaciones'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}
```

- [ ] **Step 3: Run tests + analyze**

Run: `flutter test` → PASS. `flutter analyze` → `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/notifications/notifications_screen.dart app/lib/core/router.dart
git commit -m "feat: pantalla de notificaciones (tarjetas por familia, dias, paginado, marcar todas)"
```

---

### Task 6: Gestos, animaciones y realtime en la pantalla

Completa el spec §3: swipe=leída (la tarjeta NO se elimina), cascada de entrada, tarjeta realtime con destello, realtime foreground-only con re-sync al resume.

**Files:**
- Modify: `app/lib/features/notifications/notifications_screen.dart`

**Interfaces:**
- Consumes: `subscribeNotifications`/`unsubscribeNotifications` (Task 3), `familyColors` y todo lo de Task 5.
- Produces: nada nuevo hacia otras tasks (task final).

- [ ] **Step 1: Add realtime + lifecycle to the state**

En `notifications_screen.dart`, agregar imports:

```dart
import 'dart:math';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

Cambiar la declaración del estado a:

```dart
class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
```

Agregar campos al estado:

```dart
  RealtimeChannel? _channel;
  // Id de la tarjeta recién llegada por realtime (dispara su animación).
  String? _justArrivedId;
```

Reemplazar `initState` y agregar `dispose` + lifecycle + suscripción:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFirst();
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    super.dispose();
  }

  /// Realtime SOLO en foreground (spec §1, patrón del chat): al background se
  /// suelta el socket; al volver se re-carga la página 1 (cubre el gap) y se
  /// re-suscribe.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _unsubscribe();
    if (state == AppLifecycleState.resumed) {
      _loadFirst();
      _subscribe();
    }
  }

  void _subscribe() {
    _unsubscribe();
    _channel = subscribeNotifications((row) {
      if (!mounted) return;
      final n = AppNotification.fromMap(row);
      if (_items.any((x) => x.id == n.id)) return;
      setState(() {
        _items.insert(0, n);
        _justArrivedId = n.id;
      });
      notifCountStore.add(1);
    });
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) unsubscribeNotifications(ch);
  }
```

- [ ] **Step 2: Swipe = leída + cascada de entrada + destello realtime**

Reemplazar `_buildCard` y el loop de tarjetas de `_body` para llevar índice. En `_body`, sustituir el `for (final n in g.items)` por:

```dart
      for (final n in g.items) {
        children.add(_buildCard(n, cardIndex++));
      }
```

declarando `var cardIndex = 0;` justo antes del `for (final g in groups) {`.

Reemplazar `_buildCard` completo por:

```dart
  Widget _buildCard(AppNotification n, int index) {
    // Swipe horizontal = marcar leída; la tarjeta NUNCA se elimina:
    // confirmDismiss siempre devuelve false → Dismissible la regresa a su
    // sitio con rebote y el AnimatedContainer desvanece el color (~300ms).
    // Sobre una leída el mismo gesto es no-op y solo rebota (spec §3).
    Widget card = Dismissible(
      key: ValueKey('sw-${n.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: .35,
        DismissDirection.endToStart: .35,
      },
      movementDuration: const Duration(milliseconds: 250),
      confirmDismiss: (_) async {
        _markReadOptimistic(n);
        return false;
      },
      child: _NotifCard(key: ValueKey(n.id), n: n, onTap: () => _open(n)),
    );
    if (n.id == _justArrivedId) {
      // Llegada realtime: entra deslizándose desde arriba con un destello
      // breve del color de su familia (spec §3).
      final fam = familyColors(context, familyFor(n.kind));
      card = card
          .animate(key: ValueKey('new-${n.id}'))
          .slideY(begin: -.35, end: 0, duration: 300.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 250.ms)
          .then()
          .shimmer(duration: 700.ms, color: fam.icon.withValues(alpha: .35));
    } else {
      // Cascada de entrada: fade + slide 12px hacia arriba, ~40ms de stagger
      // (tope en los primeros ~14 items para no eternizar listas largas).
      card = card
          .animate(key: ValueKey('in-${n.id}'))
          .fadeIn(duration: 250.ms, delay: (40 * min(index, 14)).ms)
          .slideY(
              begin: .10,
              end: 0,
              duration: 250.ms,
              delay: (40 * min(index, 14)).ms,
              curve: Curves.easeOutCubic);
    }
    return card;
  }
```

- [ ] **Step 3: Run tests + analyze**

Run: `flutter test` → PASS. `flutter analyze` → `No issues found!`

- [ ] **Step 4: Manual smoke en device/emulador (si hay uno conectado)**

Run: `flutter run` en el Redmi si está conectado; si no, dejar el APK para el E2E del PO.
Verificar a ojo: campana con badge en las 4 pantallas, abrir `/notifications`, cascada de entrada, tap navega, swipe marca leída con rebote, marcar todas apaga en cascada, píldora se encoge a 0. (El realtime en vivo requiere generar una notificación desde otra cuenta — queda para el E2E con el PO, igual que el chat.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/notifications/notifications_screen.dart
git commit -m "feat: swipe=leida, cascada de entrada y realtime foreground en notificaciones"
```

---

## Cobertura del spec (self-review)

- §1 Datos: páginas de 30 + "Cargar más" (T3/T5), COUNT filtrado equivalente a head (T3), update read_at nunca DELETE (T3), regex `__VALUE__` (T1), realtime solo pantalla visible + foreground (T3/T6). ✅
- §2 Campana: 4 pantallas exactas (T4), badge 9+ (T1/T4), fetch al montar + resumed (T4), baja optimista + revalida (T5 `_markReadOptimistic`/`_loadFirst`), pop elástico + pulso (T4), store único compartido (T4). ✅
- §3 Pantalla: píldora que se encoge (T5), marcar todas visible solo con no-leídas (T5), encabezados Hoy/Ayer/fecha (T1/T5), tarjeta radius 16 + icono en contenedor + hora relativa (T5), familias de color light/dark (T5), swipe sin eliminar con rebote y desvanecido (T6), tap optimista + navega (T5), cascada de marcar todas (T5), cascada de entrada 40ms (T6), llegada realtime con destello (T6), skeletons/vacío/error+Reintentar/Cargar más (T5). ✅
- §4 Ruteo: tabla completa de links + 2 bugs arreglados + fallback por rol (T2). ✅
- §5 Capas: domain/data/features + ruta en shell como `/messages` + push_service delega (T2/T5). Tests y analyze en cada task. ✅
- Fuera de alcance respetado: referidos como ítems simples (sin botón compartir ni modal — caen en familia sistema), sin preferencias, sin backend. ✅
