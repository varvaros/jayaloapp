# Jayalo v1 "El corazón en Flutter" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** App Android 100% nativa (Flutter) que cubre el ciclo completo del corazón de Jayalo
(crear solicitud con IA → ofertar → aceptar → desbloquear → WhatsApp) para cliente y proveedor,
con push FCM en cada transición, contra el backend existente sin tocar la web ni el Worker.

**Architecture:** Shell Flutter Material 3 + `supabase_flutter` (hereda RLS/RPCs) contra el
proyecto `mfaiklvobnvgusbcssbx`. La IA de crear-solicitud habla con el endpoint existente
`POST https://jayalo.com/api/ai/chat-stream` (que pese al nombre NO es streaming: cada turno es
un POST que devuelve UN objeto JSON). Push = tabla nueva `device_tokens` + trigger sobre
`notifications` + Edge Function `send-push` (FCM HTTP v1). PayPal/recarga → navegador externo.

**Tech Stack:** Flutter estable (Dart 3), `supabase_flutter`, `google_sign_in` ^6,
`firebase_messaging`+`firebase_core`, `go_router`, `webview_flutter` (SOLO plomería invisible de
Turnstile), `url_launcher`, `http`. Backend: SQL (Postgres/Supabase) + Edge Function Deno.

**Spec:** `docs/superpowers/specs/2026-07-16-v1-corazon-flutter-design.md` (rev. 2).

## Global Constraints

- Repo: `C:\Users\ac\Downloads\jayalo-app` (git propio). `jayalo-main` NO se toca salvo Task 0.
- Package Android: **`com.jayalo.app`** (obligatorio: el OAuth client Android está atado a este
  package + SHA-1 debug `C0:02:66:E7:F6:0A:88:9B:02:4A:C3:14:C4:9F:04:8E:B6:89:45:2E`).
- Supabase: URL `https://mfaiklvobnvgusbcssbx.supabase.co`; publishable key (pública, horneable):
  `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mYWlrbHZvYm52Z3VzYmNzc2J4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2NDQ1OTgsImV4cCI6MjA5ODIyMDU5OH0.UT_8eeSffp_K8HjykO1V9DVy81gO49-kNw1lfhQ4VcE`
- Google Web Client ID (para `signInWithIdToken`):
  `606236193258-80p6roa1ohq3dd63n3uodnrvqncpt44k.apps.googleusercontent.com`
- Turnstile sitekey (pública): `0x4AAAAAAD2eR3eQ3TC10fVF`. El widget invisible se carga con
  `baseUrl: 'https://jayalo.com'` (el hostname debe estar permitido — gotcha 110200).
- Endpoint IA: `POST https://jayalo.com/api/ai/chat-stream` con header
  `Origin: https://jayalo.com` (falla cerrado sin él). Primer turno (`messages.length == 1`)
  exige `turnstileToken`. Rate limit 10/min por IP.
- Copy: español dominicano, montos `RD$`. La web se hereda como VOZ y semántica de fases, no
  como layout (spec §2). NO FlutterFlow. Sin WebViews de UI (solo el Turnstile invisible).
- Reglas de dinero: el costo REAL lo calcula `try_unlock_offer` server-side; `pointsForOffer`
  en Dart es SOLO para mostrar. Ofertar es gratis; se paga al desbloquear.
- Cambios de BD (Task 13): solo ADITIVOS (tabla nueva + 2 triggers + 1 función). Se aplican vía
  MCP de Supabase **con confirmación nombrada del PO por migración** (regla del proyecto).
  ⚠️ El MCP de Supabase requiere autorización OAuth en la sesión que ejecute; si no está
  disponible, el PO aplica el SQL por dashboard.
- Commits: mensaje `feat:`/`fix:`/`docs:` + `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Gate de cada task de app: `flutter analyze` en 0 errores + `flutter test` verde antes del commit.

## Prerrequisitos [PO] — una sola vez, guiados

1. **SDK de Flutter en Windows**: descargar el zip estable de https://docs.flutter.dev/get-started/install/windows,
   extraer en `C:\dev\flutter` (ruta sin espacios), agregar `C:\dev\flutter\bin` al PATH del
   usuario. Verificar: `flutter doctor` (Android toolchain ya está: Android Studio + SDK 36 ✔).
   Aceptar licencias: `flutter doctor --android-licenses`.
2. **Proyecto Firebase**: en https://console.firebase.google.com → "Agregar proyecto" →
   **usar el proyecto Google Cloud existente `jayalo-501005`** (opción "agregar Firebase a un
   proyecto de Google Cloud" — evita un proyecto nuevo). Dentro: Agregar app → Android →
   package `com.jayalo.app` → descargar **`google-services.json`** (se usa en Task 14). En
   Configuración del proyecto → Cuentas de servicio → **Generar nueva clave privada** (JSON) —
   es el secreto del emisor FCM (Task 13). NO commitear ninguno de los dos JSON.
3. **Teléfono Android por USB** con depuración activada (`flutter devices` debe listarlo).

---

## Estructura de archivos (app)

```
jayalo-app/
  app/                          # proyecto Flutter (flutter create aquí)
    lib/
      main.dart                 # bootstrap: Supabase.initialize + runApp
      app.dart                  # MaterialApp.router + tema M3
      core/config.dart          # constantes (URLs, keys públicas)
      core/turnstile.dart       # token Turnstile vía WebView invisible
      core/ai_client.dart       # cliente del endpoint IA (POST + Origin)
      core/router.dart          # go_router + deep links
      domain/pricing.dart       # tiers + pointsForOffer (port de la web)
      domain/phase.dart         # RequestPhase + derivación
      domain/ai_turns.dart      # sealed classes de turnos IA + fromJson
      data/repos.dart           # queries Supabase (requests/offers/wallet/tokens)
      features/auth/login_screen.dart
      features/shell/home_shell.dart
      features/client/create_request_screen.dart
      features/client/my_requests_screen.dart
      features/client/request_status_screen.dart
      features/provider/inbox_screen.dart
      features/provider/request_detail_screen.dart
      features/provider/my_offers_screen.dart
      features/settings/settings_screen.dart
      push/push_service.dart    # FCM + registro de token + deep link
    test/
      pricing_test.dart
      phase_test.dart
      ai_turns_test.dart
  supabase/
    migrations/20260716120000_device_tokens_and_push.sql
    functions/send-push/index.ts
  docs/superpowers/{specs,plans}/
```

---

### Task 0: Revertir `cb675fc` en jayalo-main

**Files:**
- Modify: `C:\Users\ac\Downloads\jayalo-main\jayalo-main` (repo git; revert de un commit)

**Interfaces:** ninguna (limpieza previa; decisión PO spec §11). El commit era el helper
`signInWithGoogle` de Capacitor, **sin desplegar**.

- [ ] **Step 1: Verificar que el commit existe y qué toca**

Run: `cd C:\Users\ac\Downloads\jayalo-main\jayalo-main && git log --oneline -3 cb675fc && git show --stat cb675fc`
Expected: commit `cb675fc` con `src/lib/googleAuth.ts` + ~4 call sites.

- [ ] **Step 2: Revert (sin push todavía)**

```bash
git revert --no-edit cb675fc
```
Si hay conflictos (commits posteriores tocaron esos archivos), resolver conservando la versión
SIN el helper (la rama nativa `window.Capacitor` muere entera; los call sites vuelven a
`supabase.auth.signInWithOAuth` directo).

- [ ] **Step 3: Gates**

Run: `npx tsc --noEmit && npm run lint && npx vitest run`
Expected: 0 errores / 0 errores / suite verde (baseline ~225 tests).

- [ ] **Step 4: Push (el CI NO despliega si falta el secreto; si despliega, es el revert — inocuo)**

```bash
git push origin master
```

---

### Task 1: Scaffold Flutter `app/` con package `com.jayalo.app` + tema M3

**Files:**
- Create: `app/` (flutter create), `app/lib/app.dart`, `app/lib/core/config.dart`
- Modify: `app/android/app/build.gradle.kts` (applicationId), `app/lib/main.dart`

**Interfaces:**
- Produces: `AppConfig` (constantes estáticas: `supabaseUrl`, `supabasePublishableKey`,
  `googleWebClientId`, `turnstileSiteKey`, `siteUrl = 'https://jayalo.com'`,
  `aiEndpoint = 'https://jayalo.com/api/ai/chat-stream'`,
  `walletUrl = 'https://jayalo.com/provider/wallet'`); `JayaloApp` (root widget con tema M3).

- [ ] **Step 1: Crear el proyecto**

```bash
cd C:\Users\ac\Downloads\jayalo-app
flutter create --org com.jayalo --project-name jayalo_app --platforms android app
```

- [ ] **Step 2: Fijar el applicationId a `com.jayalo.app`**

En `app/android/app/build.gradle.kts`: `namespace = "com.jayalo.app"` y
`applicationId = "com.jayalo.app"` (flutter create genera `com.jayalo.jayalo_app` — corregir
ambos). Mover `MainActivity.kt` de `android/app/src/main/kotlin/com/jayalo/jayalo_app/` a
`.../com/jayalo/app/` y actualizar su `package com.jayalo.app`.

- [ ] **Step 3: Dependencias**

```bash
cd app
flutter pub add supabase_flutter google_sign_in:^6.2.2 go_router url_launcher http webview_flutter
```
(`firebase_*` se agregan en Task 14 para no bloquear el arranque con config de Firebase.)

- [ ] **Step 4: `core/config.dart`**

```dart
abstract final class AppConfig {
  static const supabaseUrl = 'https://mfaiklvobnvgusbcssbx.supabase.co';
  static const supabasePublishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mYWlrbHZvYm52Z3VzYmNzc2J4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2NDQ1OTgsImV4cCI6MjA5ODIyMDU5OH0.UT_8eeSffp_K8HjykO1V9DVy81gO49-kNw1lfhQ4VcE';
  static const googleWebClientId =
      '606236193258-80p6roa1ohq3dd63n3uodnrvqncpt44k.apps.googleusercontent.com';
  static const turnstileSiteKey = '0x4AAAAAAD2eR3eQ3TC10fVF';
  static const siteUrl = 'https://jayalo.com';
  static const aiEndpoint = '$siteUrl/api/ai/chat-stream';
  static const walletUrl = '$siteUrl/provider/wallet';
}
```

- [ ] **Step 5: Tema M3 en `app.dart` + `main.dart` mínimo**

```dart
// app.dart
import 'package:flutter/material.dart';

const _seed = Color(0xFF7C3AED); // violeta de marca Jayalo

ThemeData jayaloTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      visualDensity: VisualDensity.standard,
    );

class JayaloApp extends StatelessWidget {
  const JayaloApp({super.key, required this.home});
  final Widget home;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jayalo',
        theme: jayaloTheme(Brightness.light),
        darkTheme: jayaloTheme(Brightness.dark),
        home: home,
      );
}
```
```dart
// main.dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() => runApp(const JayaloApp(
    home: Scaffold(body: Center(child: Text('Jayalo v1')))));
```
(En Task 7 `MaterialApp` pasa a `MaterialApp.router`; este `home` es temporal.)

- [ ] **Step 6: Correr en el device**

Run: `flutter run` (device USB conectado)
Expected: app "Jayalo v1" abre en el teléfono. `flutter analyze` → 0 issues.

- [ ] **Step 7: Commit**

```bash
git add app/ && git commit -m "feat: scaffold Flutter com.jayalo.app + tema M3"
```

---

### Task 2: Dominio puro — pricing y fases (TDD)

**Files:**
- Create: `app/lib/domain/pricing.dart`, `app/lib/domain/phase.dart`
- Test: `app/test/pricing_test.dart`, `app/test/phase_test.dart`

**Interfaces:**
- Produces: `PricingTier{minRD, maxRD, points}` · `PricingTier tierForPrice(double priceRD)` ·
  `int pointsForOffer({double? price, double? priceMin, double? priceMax, String? pricingMode,
  double? hourlyRate, double? estimatedHours})` · `enum RequestPhase {waiting, withOffers,
  accepted, unlocked, completed}` · `class OfferLite{String status; DateTime? unlockedAt}` ·
  `RequestPhase phaseForRequest({required String requestStatus, required List<OfferLite> offers})`.

- [ ] **Step 1: Tests de pricing (portan la semántica EXACTA de la web, incl. el caso 3000.5)**

```dart
// test/pricing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/pricing.dart';

void main() {
  test('tiers por límite superior (cascada, sin huecos)', () {
    expect(tierForPrice(0).points, 1);
    expect(tierForPrice(3000).points, 1);
    expect(tierForPrice(3000.5).points, 2); // caso fraccionario: NO salta al fallback
    expect(tierForPrice(3001).points, 2);
    expect(tierForPrice(5000).points, 2);
    expect(tierForPrice(8000).points, 3);
    expect(tierForPrice(12000).points, 4);
    expect(tierForPrice(18000).points, 5);
    expect(tierForPrice(25000).points, 6);
    expect(tierForPrice(32000).points, 7);
    expect(tierForPrice(40000).points, 8);
    expect(tierForPrice(50000).points, 9);
    expect(tierForPrice(50001).points, 10);
    expect(tierForPrice(999999).points, 10);
  });

  test('pointsForOffer: precio fijo > rango > por hora; 0 si nada', () {
    expect(pointsForOffer(price: 4000), 2);
    expect(pointsForOffer(priceMin: 3000, priceMax: 3001), 2); // avg 3000.5
    expect(pointsForOffer(pricingMode: 'hourly', hourlyRate: 2000, estimatedHours: 3), 3); // 6000
    expect(pointsForOffer(pricingMode: 'hourly', hourlyRate: 2500), 1); // 1h default
    expect(pointsForOffer(), 0);
    expect(pointsForOffer(price: 0), 0);
  });
}
```

- [ ] **Step 2: Correr y ver fallar**

Run: `cd app && flutter test test/pricing_test.dart`
Expected: FAIL (símbolos no definidos).

- [ ] **Step 3: Implementar `pricing.dart`**

```dart
class PricingTier {
  const PricingTier(this.minRD, this.maxRD, this.points);
  final double minRD;
  final double? maxRD; // null = sin tope
  final int points;
}

/// Idéntica a `PRICING_TIERS` de la web (src/mocks/pricing-tiers.ts) y a la SQL
/// autoritativa `points_for_price_rd`. Cascada por límite SUPERIOR.
const pricingTiers = <PricingTier>[
  PricingTier(0, 3000, 1),
  PricingTier(3001, 5000, 2),
  PricingTier(5001, 8000, 3),
  PricingTier(8001, 12000, 4),
  PricingTier(12001, 18000, 5),
  PricingTier(18001, 25000, 6),
  PricingTier(25001, 32000, 7),
  PricingTier(32001, 40000, 8),
  PricingTier(40001, 50000, 9),
  PricingTier(50001, null, 10),
];

PricingTier tierForPrice(double priceRD) => pricingTiers
    .firstWhere((t) => t.maxRD == null || priceRD <= t.maxRD!, orElse: () => pricingTiers.last);

int _pointsForPrice(double? priceRD) =>
    (priceRD == null || priceRD <= 0) ? 0 : tierForPrice(priceRD).points;

/// SOLO para mostrar el costo en la UI. El cobro real lo calcula la RPC
/// `try_unlock_offer` server-side (regla de seguridad del proyecto).
int pointsForOffer({
  double? price,
  double? priceMin,
  double? priceMax,
  String? pricingMode,
  double? hourlyRate,
  double? estimatedHours,
}) {
  if (price != null && price > 0) return _pointsForPrice(price);
  if (priceMin != null && priceMax != null && priceMax >= priceMin) {
    return _pointsForPrice((priceMin + priceMax) / 2);
  }
  if (pricingMode == 'hourly' && hourlyRate != null && hourlyRate > 0) {
    final hours = (estimatedHours != null && estimatedHours > 0) ? estimatedHours : 1.0;
    return _pointsForPrice(hourlyRate * hours);
  }
  return 0;
}
```

- [ ] **Step 4: Tests de fase**

```dart
// test/phase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';

OfferLite o(String s, {DateTime? u}) => OfferLite(status: s, unlockedAt: u);

void main() {
  test('derivación de fases (misma semántica que la web)', () {
    expect(phaseForRequest(requestStatus: 'open', offers: []), RequestPhase.waiting);
    expect(phaseForRequest(requestStatus: 'open', offers: [o('pending')]),
        RequestPhase.withOffers);
    expect(phaseForRequest(requestStatus: 'open', offers: [o('accepted'), o('pending')]),
        RequestPhase.accepted);
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('accepted', u: DateTime(2026)), o('rejected')]),
        RequestPhase.unlocked);
    expect(phaseForRequest(requestStatus: 'completed', offers: [o('accepted')]),
        RequestPhase.completed);
    expect(phaseForRequest(requestStatus: 'open', offers: [o('completed')]),
        RequestPhase.completed);
    // rejected no cuenta como "con ofertas" activas… sí cuenta: la web cuenta ofertas
    // recibidas totales para with_offers.
    expect(phaseForRequest(requestStatus: 'open', offers: [o('rejected')]),
        RequestPhase.withOffers);
  });
}
```

- [ ] **Step 5: Implementar `phase.dart`**

```dart
enum RequestPhase { waiting, withOffers, accepted, unlocked, completed }

class OfferLite {
  const OfferLite({required this.status, this.unlockedAt});
  final String status; // pending | accepted | completed | rejected
  final DateTime? unlockedAt;
}

/// Réplica de la derivación de la web (src/routes/requests/$requestId.tsx ~L989-1010):
/// completed si la solicitud está completed/closed o la oferta aceptada está completed;
/// unlocked si la aceptada tiene unlocked_at; accepted si hay aceptada; si no, por conteo.
RequestPhase phaseForRequest({
  required String requestStatus,
  required List<OfferLite> offers,
}) {
  final accepted = offers.where((o) => o.status == 'accepted' || o.status == 'completed');
  final acceptedOffer = accepted.isEmpty ? null : accepted.first;
  final requestClosed = requestStatus == 'completed' || requestStatus == 'closed';
  final offerDone = acceptedOffer?.status == 'completed';
  if (requestClosed || offerDone) return RequestPhase.completed;
  if (acceptedOffer != null && acceptedOffer.unlockedAt != null) return RequestPhase.unlocked;
  if (acceptedOffer != null) return RequestPhase.accepted;
  return offers.isEmpty ? RequestPhase.waiting : RequestPhase.withOffers;
}
```

- [ ] **Step 6: Verde + commit**

Run: `flutter test` → Expected: PASS (todos).
```bash
git add app/lib/domain app/test && git commit -m "feat: dominio puro — pricing tiers y fases del pedido (TDD)"
```

---

### Task 3: Modelo de turnos IA (TDD)

**Files:**
- Create: `app/lib/domain/ai_turns.dart`
- Test: `app/test/ai_turns_test.dart`

**Interfaces:**
- Produces: `sealed class AiTurn` con subclases `AiQuestion{question, options, allowOther}`,
  `AiImageRequest{message, hint}`, `AiRouting{message, categories, rubros}`,
  `AiReady{title, bullets, wholesale}`, `AiKindSwitch{message, suggestedKind, options}` y
  `AiTurn parseAiTurn(Map<String, dynamic> json)` (lanza `FormatException` si `type` es desconocido).

Contrato verificado en `jayalo-main/src/lib/ai/prompts.ts` L30-82 y `chat-stream.ts` L438-500.
`routing.rubros` lo añade el servidor (UUIDs de rubros); `ready.wholesale` es opcional.

- [ ] **Step 1: Tests con JSON reales del contrato**

```dart
// test/ai_turns_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_turns.dart';

void main() {
  test('question', () {
    final t = parseAiTurn(jsonDecode(
        '{"type":"question","question":"¿Qué medida?","options":["1/2\\"","3/4\\""],"allowOther":true}'));
    final q = t as AiQuestion;
    expect(q.question, '¿Qué medida?');
    expect(q.options, ['1/2"', '3/4"']);
    expect(q.allowOther, isTrue);
  });
  test('routing con rubros del servidor', () {
    final t = parseAiTurn(jsonDecode(
        '{"type":"routing","message":"Voy a enviar tu solicitud a:","categories":["plomeria"],"rubros":["a1b2","c3d4"]}'));
    final r = t as AiRouting;
    expect(r.categories, ['plomeria']);
    expect(r.rubros, ['a1b2', 'c3d4']);
  });
  test('ready con y sin wholesale', () {
    final r1 = parseAiTurn(jsonDecode(
        '{"type":"ready","title":"Llave de paso 1/2\\"","bullets":["Marca: cualquiera"]}')) as AiReady;
    expect(r1.wholesale, isFalse);
    final r2 = parseAiTurn(jsonDecode(
        '{"type":"ready","title":"Compra al por mayor: 500 camisetas","bullets":["Cantidad: 500"],"wholesale":true}')) as AiReady;
    expect(r2.wholesale, isTrue);
  });
  test('kind_switch e image_request', () {
    expect(parseAiTurn(jsonDecode(
        '{"type":"kind_switch","message":"Parece servicio","suggested_kind":"servicio","options":["Sí, cambiar a servicio","No"]}')),
        isA<AiKindSwitch>());
    expect(parseAiTurn(jsonDecode(
        '{"type":"image_request","message":"Necesito ver mejor","hint":"Foto del sifón"}')),
        isA<AiImageRequest>());
  });
  test('type desconocido lanza', () {
    expect(() => parseAiTurn({'type': 'sorpresa'}), throwsFormatException);
  });
}
```

- [ ] **Step 2: Ver fallar** — `flutter test test/ai_turns_test.dart` → FAIL.

- [ ] **Step 3: Implementar `ai_turns.dart`**

```dart
sealed class AiTurn {
  const AiTurn();
}

class AiQuestion extends AiTurn {
  const AiQuestion({required this.question, required this.options, required this.allowOther});
  final String question;
  final List<String> options;
  final bool allowOther;
}

class AiImageRequest extends AiTurn {
  const AiImageRequest({required this.message, required this.hint});
  final String message;
  final String hint;
}

class AiRouting extends AiTurn {
  const AiRouting({required this.message, required this.categories, required this.rubros});
  final String message;
  final List<String> categories;
  final List<String> rubros; // UUIDs — los añade el servidor al post-procesar
}

class AiReady extends AiTurn {
  const AiReady({required this.title, required this.bullets, required this.wholesale});
  final String title;
  final List<String> bullets;
  final bool wholesale;
}

class AiKindSwitch extends AiTurn {
  const AiKindSwitch(
      {required this.message, required this.suggestedKind, required this.options});
  final String message;
  final String suggestedKind;
  final List<String> options;
}

List<String> _strs(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const [];

AiTurn parseAiTurn(Map<String, dynamic> json) => switch (json['type']) {
      'question' => AiQuestion(
          question: json['question'] as String? ?? '',
          options: _strs(json['options']),
          allowOther: json['allowOther'] as bool? ?? true),
      'image_request' => AiImageRequest(
          message: json['message'] as String? ?? '', hint: json['hint'] as String? ?? ''),
      'routing' => AiRouting(
          message: json['message'] as String? ?? '',
          categories: _strs(json['categories']),
          rubros: _strs(json['rubros'])),
      'ready' => AiReady(
          title: json['title'] as String? ?? '',
          bullets: _strs(json['bullets']),
          wholesale: json['wholesale'] == true),
      'kind_switch' => AiKindSwitch(
          message: json['message'] as String? ?? '',
          suggestedKind: json['suggested_kind'] as String? ?? 'servicio',
          options: _strs(json['options'])),
      _ => throw FormatException('Turno IA desconocido: ${json['type']}'),
    };
```

- [ ] **Step 4: Verde + commit**

Run: `flutter test` → PASS.
```bash
git add app/lib/domain/ai_turns.dart app/test/ai_turns_test.dart && git commit -m "feat: parser de turnos del endpoint IA (TDD)"
```

---

### Task 4: Servicio Turnstile (WebView invisible solo-token)

**Files:**
- Create: `app/lib/core/turnstile.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml` (INTERNET permission si falta)

**Interfaces:**
- Produces: `Future<String> getTurnstileToken(BuildContext context)` — inserta un OverlayEntry
  invisible con el widget Turnstile cargado bajo hostname `jayalo.com`, resuelve con el token o
  lanza `TurnstileException` (timeout 25s / error del widget).
- Consumes: `AppConfig.turnstileSiteKey`, `AppConfig.siteUrl`.

Es la ÚNICA pieza WebView permitida (plomería, spec §7 opción a). Riesgo conocido: si Cloudflare
rechaza el hostname (código 110200), el PO agrega el hostname faltante en el dashboard del widget
Turnstile — no es un cambio de código.

- [ ] **Step 1: Implementar `turnstile.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'config.dart';

class TurnstileException implements Exception {
  TurnstileException(this.message);
  final String message;
  @override
  String toString() => 'TurnstileException: $message';
}

String _html() => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width">
<!-- Sin SRI a propósito: api.js de Turnstile es un script rotativo que Cloudflare
     actualiza sin aviso; un hash integrity pineado rompería el widget. Mismo modo
     de carga que usa la web de Jayalo (TurnstileWidget.tsx). -->
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTsLoad" async defer></script>
</head><body><div id="ts"></div><script>
function onTsLoad(){
  turnstile.render('#ts',{
    sitekey:'${AppConfig.turnstileSiteKey}',
    callback:function(t){TokenChannel.postMessage(t);},
    'error-callback':function(c){TokenChannel.postMessage('ERROR:'+c);}
  });
}
</script></body></html>''';

/// Obtiene un token Turnstile sin mostrar nada al usuario (~1s). El HTML se
/// carga con baseUrl jayalo.com para que el hostname pase la validación del
/// widget (gotcha 110200).
Future<String> getTurnstileToken(BuildContext context) {
  final completer = Completer<String>();
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;

  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('TokenChannel', onMessageReceived: (msg) {
      if (completer.isCompleted) return;
      final v = msg.message;
      if (v.startsWith('ERROR:')) {
        completer.completeError(TurnstileException('widget ${v.substring(6)}'));
      } else {
        completer.complete(v);
      }
    })
    ..loadHtmlString(_html(), baseUrl: AppConfig.siteUrl);

  entry = OverlayEntry(
    builder: (_) => Offstage(
      offstage: true,
      child: SizedBox(width: 1, height: 1, child: WebViewWidget(controller: controller)),
    ),
  );
  overlay.insert(entry);

  return completer.future
      .timeout(const Duration(seconds: 25),
          onTimeout: () => throw TurnstileException('timeout'))
      .whenComplete(entry.remove);
}
```

- [ ] **Step 2: Verificación manual en device (pantalla temporal)**

En `main.dart`, botón temporal que llama `getTurnstileToken(context)` y muestra los primeros 20
chars del token en un SnackBar.

Run: `flutter run` → tocar el botón.
Expected: SnackBar con un token (empieza tipo `0.`). Si sale `TurnstileException: widget 110200`
→ [PO] agregar hostname en Cloudflare → Turnstile → widget → Domains. Quitar el botón temporal
después.

- [ ] **Step 3: `flutter analyze` en 0 + commit**

```bash
git add app/lib/core/turnstile.dart app/lib/main.dart && git commit -m "feat: token Turnstile via WebView invisible (plomeria, sin UI)"
```

---

### Task 5: Supabase init + login nativo con Google (SPIKE de riesgo 1)

**Files:**
- Create: `app/lib/features/auth/login_screen.dart`
- Modify: `app/lib/main.dart` (Supabase.initialize + gate de sesión)

**Interfaces:**
- Produces: `LoginScreen({required VoidCallback onSignedIn})`; helper
  `Future<void> signInWithGoogleNative(BuildContext context)` (lanza en fallo);
  `SessionGate` en main: con sesión → home (placeholder por ahora), sin sesión → LoginScreen.
- Consumes: `getTurnstileToken` (Task 4), `AppConfig`.

- [ ] **Step 1: Inicializar Supabase en `main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: AppConfig.supabaseUrl, anonKey: AppConfig.supabasePublishableKey);
  runApp(const JayaloApp(home: SessionGate()));
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const Scaffold(body: Center(child: Text('Sesión activa ✔'))); // Task 7 la reemplaza
      },
    );
  }
}
```

- [ ] **Step 2: `login_screen.dart` (Google nativo + retry con captchaToken)**

```dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config.dart';
import '../../core/turnstile.dart';

Future<void> signInWithGoogleNative(BuildContext context) async {
  final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
  final account = await google.signIn();
  if (account == null) throw Exception('Inicio de sesión cancelado');
  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) throw Exception('Google no devolvió idToken');

  final supa = Supabase.instance.client.auth;
  try {
    await supa.signInWithIdToken(
        provider: OAuthProvider.google, idToken: idToken, accessToken: auth.accessToken);
  } on AuthException catch (e) {
    // CAPTCHA global de Supabase (ADR-0028): reintento con token Turnstile.
    if (!e.message.toLowerCase().contains('captcha')) rethrow;
    if (!context.mounted) rethrow;
    final captcha = await getTurnstileToken(context);
    await supa.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
        captchaToken: captcha);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await signInWithGoogleNative(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo iniciar sesión: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Jayalo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Pide lo que buscas. Los proveedores te ofertan.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _busy ? null : _go,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Continuar con Google'),
              ),
              const SizedBox(height: 12),
              Text('¿Cuenta nueva? Regístrate en jayalo.com',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verificar en device (cuenta existente del PO)**

Run: `flutter run` → "Continuar con Google" → hoja de cuentas → elegir cuenta.
Expected: "Sesión activa ✔". Gotchas: `[28444]`/DEVELOPER_ERROR = propagación del OAuth client o
SHA-1/package mal (revisar Step 2 de Task 1); `captcha_failed` sin retry = revisar Task 4.
Matar la app y reabrir → sigue "Sesión activa ✔" (persistencia).

- [ ] **Step 4: Commit**

```bash
git add app/lib && git commit -m "feat: login nativo Google + Supabase (signInWithIdToken + captcha retry)"
```

---

### Task 6: Cliente IA (SPIKE de riesgo 2)

**Files:**
- Create: `app/lib/core/ai_client.dart`

**Interfaces:**
- Produces: `class AiClient` con
  `Future<AiTurn> sendTurn({required List<AiMessage> messages, String? kind, bool wholesale = false, String? turnstileToken})`
  y `class AiMessage{String role; String content}`. Errores: `AiHttpException(status, message)`.
- Consumes: `parseAiTurn` (Task 3), `AppConfig.aiEndpoint`.

- [ ] **Step 1: Implementar `ai_client.dart`**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_turns.dart';
import 'config.dart';

class AiMessage {
  const AiMessage(this.role, this.content); // role: 'user' | 'assistant'
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AiHttpException implements Exception {
  AiHttpException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'AiHttpException($status): $message';
}

class AiClient {
  AiClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  /// Un turno = un POST. El primer turno (messages.length == 1) DEBE llevar
  /// turnstileToken. El header Origin es obligatorio (el endpoint falla cerrado).
  Future<AiTurn> sendTurn({
    required List<AiMessage> messages,
    String? kind, // 'producto' | 'servicio'
    bool wholesale = false,
    String? turnstileToken,
  }) async {
    final res = await _http.post(
      Uri.parse(AppConfig.aiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Origin': AppConfig.siteUrl, // cliente propio de confianza; sin esto → 403
      },
      body: jsonEncode({
        'messages': messages.map((m) => m.toJson()).toList(),
        if (kind != null) 'kind': kind,
        if (wholesale) 'wholesale': true,
        if (turnstileToken != null) 'turnstileToken': turnstileToken,
      }),
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw AiHttpException(res.statusCode, body['error']?.toString() ?? 'Error');
    }
    return parseAiTurn(body);
  }
}
```

- [ ] **Step 2: Spike E2E en device (pantalla temporal)**

Botón temporal (en el placeholder "Sesión activa ✔") que ejecute:

```dart
final token = await getTurnstileToken(context);
final turn = await AiClient().sendTurn(
  messages: const [AiMessage('user', 'Busco una llave de paso de 1/2 pulgada')],
  kind: 'producto',
  turnstileToken: token,
);
debugPrint('TURN OK: $turn');
```
Expected: en logcat `TURN OK: Instance of 'AiQuestion'` (o kind_switch). Errores esperables:
403 "Forbidden" = header Origin no llegó; 403 "Verificación de seguridad requerida." = token
Turnstile inválido (¿hostname?); 429 = rate limit (esperar 1 min). Quitar el botón temporal.

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/ai_client.dart && git commit -m "feat: cliente del endpoint IA (Origin + Turnstile primer turno)"
```
**⛔ CHECKPOINT DE RIESGO: si Steps 2 de Tasks 5 y 6 pasan en el device, los dos únicos riesgos
técnicos de la v1 quedan retirados. Si el Turnstile invisible NO funciona tras el fix de
hostname, PARAR y consultar al PO el plan (b) del spec §7 (excepción autenticada en el Worker).**

---

### Task 7: Router + shell por rol + ajustes

**Files:**
- Create: `app/lib/core/router.dart`, `app/lib/features/shell/home_shell.dart`,
  `app/lib/features/settings/settings_screen.dart`, `app/lib/data/repos.dart` (arranque)
- Modify: `app/lib/app.dart` (MaterialApp.router), `app/lib/main.dart`

**Interfaces:**
- Produces: rutas `('/login', '/client', '/client/create', '/client/request/:id', '/provider',
  '/provider/request/:id', '/provider/offers', '/settings')`; `GoRouter buildRouter()` con
  redirect por sesión; `Future<bool> isProviderAccount()` en repos.dart
  (lee `profiles.account_type == 'provider'`); `HomeShell` con `NavigationBar` M3 por rol
  (cliente: Mis solicitudes · Crear · Ajustes — proveedor: Solicitudes · Mis ofertas · Ajustes).
- Consumes: pantallas de Tasks 8-12 (hasta que existan, placeholders `Scaffold` vacíos por ruta
  que cada task siguiente reemplaza).

- [ ] **Step 1: `repos.dart` (arranque con el helper de rol)**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

final supa = Supabase.instance.client;

Future<bool> isProviderAccount() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supa
      .from('profiles')
      .select('account_type')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['account_type'] == 'provider';
}
```

- [ ] **Step 2: `router.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/home_shell.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/client',
      refreshListenable: _AuthNotifier(),
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        final onLogin = state.matchedLocation == '/login';
        if (!loggedIn) return onLogin ? null : '/login';
        if (onLogin) return '/client';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        ShellRoute(
          builder: (_, __, child) => HomeShell(child: child),
          routes: [
            GoRoute(path: '/client', builder: (_, __) => const _Todo('Mis solicitudes')),
            GoRoute(path: '/client/create', builder: (_, __) => const _Todo('Crear solicitud')),
            GoRoute(
                path: '/client/request/:id',
                builder: (_, s) => _Todo('Pedido ${s.pathParameters['id']}')),
            GoRoute(path: '/provider', builder: (_, __) => const _Todo('Solicitudes')),
            GoRoute(
                path: '/provider/request/:id',
                builder: (_, s) => _Todo('Solicitud ${s.pathParameters['id']}')),
            GoRoute(path: '/provider/offers', builder: (_, __) => const _Todo('Mis ofertas')),
            GoRoute(path: '/settings', builder: (_, __) => const _Todo('Ajustes')),
          ],
        ),
      ],
    );

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

class _Todo extends StatelessWidget {
  const _Todo(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(label)), body: Center(child: Text(label)));
}
```
(Cada `_Todo` se sustituye por la pantalla real en Tasks 8-12; el import de la pantalla real
reemplaza al placeholder en su task.)

- [ ] **Step 3: `home_shell.dart` (tabs por rol)**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool? _provider;

  @override
  void initState() {
    super.initState();
    isProviderAccount().then((p) {
      if (mounted) {
        setState(() => _provider = p);
        // Aterriza en el home correcto según el rol.
        final loc = GoRouterState.of(context).matchedLocation;
        if (p && loc == '/client') context.go('/provider');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final provider = _provider!;
    final loc = GoRouterState.of(context).matchedLocation;
    final tabs = provider
        ? const [('/provider', Icons.inbox_outlined, 'Solicitudes'),
                 ('/provider/offers', Icons.local_offer_outlined, 'Mis ofertas'),
                 ('/settings', Icons.settings_outlined, 'Ajustes')]
        : const [('/client', Icons.receipt_long_outlined, 'Mis solicitudes'),
                 ('/client/create', Icons.add_circle_outline, 'Crear'),
                 ('/settings', Icons.settings_outlined, 'Ajustes')];
    var idx = tabs.indexWhere((t) => loc.startsWith(t.$1));
    if (idx < 0) idx = 0;
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(tabs[i].$1),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `settings_screen.dart` + enganchar router**

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: Text(email)),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Términos y privacidad'),
          onTap: () => launchUrl(Uri.parse('https://jayalo.com/terminos'),
              mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: () => Supabase.instance.client.auth.signOut(),
        ),
      ]),
    );
  }
}
```
En `app.dart`: `MaterialApp.router(routerConfig: buildRouter(), theme: ..., darkTheme: ...)`;
`main.dart` deja de pasar `home` y el `SessionGate` muere (lo cubre el redirect del router).
Sustituir el placeholder `_Todo('Ajustes')` por `SettingsScreen`.

- [ ] **Step 5: Verificar en device**

Run: `flutter run`. Expected: al abrir con sesión → tabs del rol correcto (probar con la cuenta
consumer del PO y con la de proveedor QA); logout → vuelve al login.

- [ ] **Step 6: Commit**

```bash
git add app/lib && git commit -m "feat: router + shell por rol + ajustes minimos"
```

---

### Task 8: Cliente — crear solicitud con IA (nativa)

**Files:**
- Create: `app/lib/features/client/create_request_screen.dart`
- Modify: `app/lib/core/router.dart` (sustituir placeholder), `app/lib/data/repos.dart`

**Interfaces:**
- Produces: `CreateRequestScreen`; en repos: `Future<void> submitRequest({required String title,
  required List<String> bullets, required String kind, required bool wholesale,
  required List<String> categories, required List<String> rubros})`.
- Consumes: `AiClient.sendTurn`, `getTurnstileToken`, `parseAiTurn` types.

Alcance v1: **sin fotos** (la IA soporta el camino sin foto — prompts.ts regla 7 "Si no hay
foto, salta confirmación"; `image_request` se responde "No puedo enviar foto ahora" y la IA
continúa). Fotos = fase posterior.

- [ ] **Step 1: `submitRequest` en repos.dart (campos EXACTOS de la web, new.tsx L541-570)**

```dart
Future<void> submitRequest({
  required String title,
  required List<String> bullets,
  required String kind, // 'producto' | 'servicio'
  required bool wholesale,
  required List<String> categories, // del turno routing (ya canónicas)
  required List<String> rubros, // del turno routing (UUIDs)
}) async {
  final uid = supa.auth.currentUser!.id;
  final isService = kind == 'servicio';
  await supa.from('customer_requests').insert({
    'user_id': uid,
    'kind': kind,
    'title': title,
    'description': bullets.join(' • '),
    'bullets': bullets,
    'image_url': '',
    'image_urls': <String>[],
    'image_thumb_url': null,
    'with_shipping': false,
    'with_installation': false,
    'requires_evaluation': false,
    'condition': '',
    'urgency': 'normal',
    'status': 'open',
    'target_categories': categories,
    'target_rubros': rubros,
    'service_modality': '',
    'service_event_date': null,
    'urgency_level': '',
    'budget_min': null,
    'budget_max': null,
    'is_recurring': false,
    'recurrence_note': '',
    'is_wholesale': !isService && wholesale,
    'target_business_id': null,
  });
}
```

- [ ] **Step 2: `create_request_screen.dart` — chat conversacional M3**

Comportamiento (máquina de estados de la conversación):
1. Estado inicial: selector `SegmentedButton` Producto/Servicio + chip "Al por mayor" (solo
   producto) + campo de texto "¿Qué estás buscando?".
2. Primer envío: `getTurnstileToken` → `sendTurn(messages:[user], kind, wholesale,
   turnstileToken)`. Turnos siguientes: sin token.
3. Render por tipo de turno: `AiQuestion` → burbuja + `FilterChip`s con las opciones (+ campo
   libre si `allowOther`); tocar chip = enviar esa respuesta. `AiKindSwitch` → burbuja + 2
   botones (aceptar cambia `kind` local y continúa). `AiImageRequest` → responder
   automáticamente `'No puedo enviar foto ahora, sigamos sin foto.'` (v1 sin fotos).
   `AiRouting` → guardar `categories`/`rubros`, burbuja informativa, y continuar
   automáticamente con `AiMessage('user','ok')` para provocar el `ready`. `AiReady` → tarjeta
   de resumen (título + bullets + badge "Al por mayor" si aplica) con botones "Enviar solicitud"
   / "Corregir algo".
4. "Enviar solicitud" → `submitRequest(...)` → animación de éxito sobria → `context.go('/client')`.
5. El historial `messages` acumula TODOS los turnos (`assistant` = el JSON crudo re-serializado
   `jsonEncode(turnJson)` — el endpoint espera su propio formato de vuelta como texto).
6. Errores: SnackBar con el `message` de `AiHttpException`; en 429 deshabilitar el envío 60s.

Código completo:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/ai_client.dart';
import '../../core/turnstile.dart';
import '../../data/repos.dart';
import '../../domain/ai_turns.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _Bubble {
  _Bubble.user(this.text) : isUser = true, turn = null;
  _Bubble.ai(this.turn, this.text) : isUser = false;
  final bool isUser;
  final String text;
  final AiTurn? turn;
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _ai = AiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  final List<_Bubble> _bubbles = [];
  String _kind = 'producto';
  bool _wholesale = false;
  bool _busy = false;
  List<String> _categories = [];
  List<String> _rubros = [];
  AiReady? _ready;

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _bubbles.add(_Bubble.user(text));
      _messages.add(AiMessage('user', text));
      _input.clear();
    });
    try {
      String? token;
      if (_messages.length == 1) token = await getTurnstileToken(context);
      final turn = await _ai.sendTurn(
          messages: _messages, kind: _kind, wholesale: _wholesale, turnstileToken: token);
      _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(turn))));
      await _handleTurn(turn);
    } on AiHttpException catch (e) {
      _toast(e.status == 429 ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.' : e.message);
      setState(() {
        _messages.removeLast();
        _bubbles.removeLast();
      });
    } catch (e) {
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        _bubbles.removeLast();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  Future<void> _handleTurn(AiTurn turn) async {
    switch (turn) {
      case AiQuestion q:
        setState(() => _bubbles.add(_Bubble.ai(q, q.question)));
      case AiKindSwitch k:
        setState(() => _bubbles.add(_Bubble.ai(k, k.message)));
      case AiImageRequest _:
        // v1 sin fotos: responder y seguir.
        await _send('No puedo enviar foto ahora, sigamos sin foto.');
      case AiRouting r:
        setState(() {
          _categories = r.categories;
          _rubros = r.rubros;
          _bubbles.add(_Bubble.ai(r, '${r.message} ${r.categories.join(", ")}'));
        });
        await _send('ok');
      case AiReady rd:
        setState(() {
          _ready = rd;
          _bubbles.add(_Bubble.ai(rd, '¡Listo! Revisa tu solicitud:'));
        });
    }
  }

  Map<String, dynamic> _turnToJson(AiTurn t) => switch (t) {
        AiQuestion q => {'type': 'question', 'question': q.question, 'options': q.options,
            'allowOther': q.allowOther},
        AiImageRequest i => {'type': 'image_request', 'message': i.message, 'hint': i.hint},
        AiRouting r => {'type': 'routing', 'message': r.message, 'categories': r.categories,
            'rubros': r.rubros},
        AiReady r => {'type': 'ready', 'title': r.title, 'bullets': r.bullets,
            if (r.wholesale) 'wholesale': true},
        AiKindSwitch k => {'type': 'kind_switch', 'message': k.message,
            'suggested_kind': k.suggestedKind, 'options': k.options},
      };

  Future<void> _submit() async {
    final r = _ready!;
    if (_rubros.isEmpty) {
      _toast('La solicitud no tiene rubros; escribe "corrige la categoría" para reintentar.');
      return;
    }
    setState(() => _busy = true);
    try {
      await submitRequest(
          title: r.title, bullets: r.bullets, kind: _kind,
          wholesale: r.wholesale || _wholesale, categories: _categories, rubros: _rubros);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('¡Solicitud enviada! 🎉')));
      context.go('/client');
    } catch (_) {
      _toast('No se pudo enviar la solicitud.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final started = _messages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Crear solicitud')),
      body: Column(children: [
        if (!started)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'producto', label: Text('Producto')),
                  ButtonSegment(value: 'servicio', label: Text('Servicio')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  if (_kind == 'servicio') _wholesale = false;
                }),
              ),
              const SizedBox(width: 8),
              if (_kind == 'producto')
                FilterChip(
                    label: const Text('Al por mayor'),
                    selected: _wholesale,
                    onSelected: (v) => setState(() => _wholesale = v)),
            ]),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _bubbles.length,
            itemBuilder: (_, i) {
              final b = _bubbles[i];
              final isLast = i == _bubbles.length - 1;
              return Column(
                crossAxisAlignment:
                    b.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: b.isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(b.text),
                  ),
                  if (!b.isUser && isLast && !_busy) _turnActions(b.turn),
                ],
              );
            },
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_ready == null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _input,
                enabled: !_busy,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: started ? 'Escribe tu respuesta…' : '¿Qué estás buscando?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.send), onPressed: () => _send(_input.text)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _turnActions(AiTurn? t) => switch (t) {
        AiQuestion q => Wrap(spacing: 8, children: [
            for (final op in q.options)
              ActionChip(label: Text(op), onPressed: () => _send(op)),
          ]),
        AiKindSwitch k => Wrap(spacing: 8, children: [
            for (final op in k.options)
              ActionChip(
                  label: Text(op),
                  onPressed: () {
                    if (op.toLowerCase().startsWith('sí') || op.toLowerCase().startsWith('si')) {
                      setState(() => _kind = k.suggestedKind);
                    }
                    _send(op);
                  }),
          ]),
        AiReady r => Card(
            margin: const EdgeInsets.only(top: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final b in r.bullets) Text('• $b'),
                if (r.wholesale || _wholesale)
                  const Padding(
                      padding: EdgeInsets.only(top: 6), child: Chip(label: Text('Al por mayor'))),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton(onPressed: _busy ? null : _submit,
                      child: const Text('Enviar solicitud')),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => setState(() => _ready = null),
                      child: const Text('Corregir algo')),
                ]),
              ]),
            ),
          ),
        _ => const SizedBox.shrink(),
      };
}
```
Sustituir el placeholder de `/client/create` en `router.dart` por `CreateRequestScreen`.

- [ ] **Step 3: Verificar en device (E2E real, cuenta consumer)**

Flujo: "Busco una llave de paso de 1/2 pulgada" → responder chips → routing → ready → Enviar.
Expected: fila nueva en `customer_requests` visible en jayalo.com (o en "Mis solicitudes" de la
web). Borrar la solicitud de prueba desde la web al terminar.

- [ ] **Step 4: `flutter analyze` 0 + commit**

```bash
git add app/lib && git commit -m "feat: crear solicitud con IA nativa (chat M3, chips, ready->insert)"
```

---

### Task 9: Cliente — mis solicitudes + estado del pedido (pantalla insignia)

**Files:**
- Create: `app/lib/features/client/my_requests_screen.dart`,
  `app/lib/features/client/request_status_screen.dart`
- Modify: `app/lib/data/repos.dart`, `app/lib/core/router.dart` (placeholders)

**Interfaces:**
- Produces (repos): `Future<List<Map<String, dynamic>>> myRequests()` — select
  `id,title,kind,status,is_wholesale,created_at` de `customer_requests` del usuario, desc;
  `Future<List<Map<String, dynamic>>> offersForRequest(String requestId)` — select
  `id,business_id,user_id,price,price_min,price_max,pricing_mode,hourly_rate,estimated_hours,message,status,unlocked_at,created_at,image_urls,offers_shipping,offers_installation`
  de `provider_offers` por request; `Stream<List<Map<String, dynamic>>> offersStream(String requestId)`
  — `supa.from('provider_offers').stream(primaryKey: ['id']).eq('request_id', requestId)`.
- Produces (UI): `MyRequestsScreen`, `RequestStatusScreen(requestId)` con timeline de 5 fases
  (usa `phaseForRequest`) + lista de ofertas; navega a aceptar (Task 10).
- Consumes: `RequestPhase`, `phaseForRequest`, `OfferLite`.

- [ ] **Step 1: repos**

```dart
Future<List<Map<String, dynamic>>> myRequests() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('customer_requests')
      .select('id,title,kind,status,is_wholesale,created_at')
      .eq('user_id', uid)
      .order('created_at', ascending: false));
}

const offerCols =
    'id,request_id,business_id,user_id,price,price_min,price_max,pricing_mode,hourly_rate,'
    'estimated_hours,message,status,unlocked_at,created_at';

Future<List<Map<String, dynamic>>> offersForRequest(String requestId) async =>
    List<Map<String, dynamic>>.from(await supa
        .from('provider_offers')
        .select(offerCols)
        .eq('request_id', requestId)
        .order('created_at', ascending: false));

Stream<List<Map<String, dynamic>>> offersStream(String requestId) => supa
    .from('provider_offers')
    .stream(primaryKey: ['id'])
    .eq('request_id', requestId);

OfferLite offerLite(Map<String, dynamic> o) => OfferLite(
    status: o['status'] as String,
    unlockedAt: o['unlocked_at'] == null ? null : DateTime.parse(o['unlocked_at'] as String));
```
(agregar `import '../domain/phase.dart';` a repos.dart)

- [ ] **Step 2: `my_requests_screen.dart`**

Lista `ListView` con `Card` por solicitud: título, `RelativeTime` simple (`hace 2h` — helper
local `String timeAgo(DateTime)`), badge de fase con color (waiting=neutral,
withOffers=primary, accepted=ámbar, unlocked=verde, completed=gris — misma semántica de color
que la web). La fase se calcula cargando en paralelo las ofertas de todas mis solicitudes con
UNA query (`.inFilter('request_id', ids)`) y agrupando en memoria. Tap → `/client/request/:id`.
Estado vacío con guía: "Aún no has pedido nada. Toca Crear y dinos qué buscas." Pull-to-refresh
(`RefreshIndicator`).

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

(Color, String) phaseBadge(BuildContext c, RequestPhase p) {
  final cs = Theme.of(c).colorScheme;
  return switch (p) {
    RequestPhase.waiting => (cs.outline, 'Esperando ofertas'),
    RequestPhase.withOffers => (cs.primary, 'Con ofertas'),
    RequestPhase.accepted => (Colors.amber.shade800, 'Oferta aceptada'),
    RequestPhase.unlocked => (Colors.green.shade700, 'Contacto desbloqueado'),
    RequestPhase.completed => (cs.outline, 'Completada'),
  };
}

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<(Map<String, dynamic>, RequestPhase)>> _load = _fetch();

  Future<List<(Map<String, dynamic>, RequestPhase)>> _fetch() async {
    final reqs = await myRequests();
    if (reqs.isEmpty) return [];
    final ids = reqs.map((r) => r['id'] as String).toList();
    final offers = List<Map<String, dynamic>>.from(await supa
        .from('provider_offers')
        .select('request_id,status,unlocked_at')
        .inFilter('request_id', ids));
    final byReq = <String, List<OfferLite>>{};
    for (final o in offers) {
      byReq.putIfAbsent(o['request_id'] as String, () => []).add(offerLite(o));
    }
    return [
      for (final r in reqs)
        (r, phaseForRequest(requestStatus: r['status'] as String,
            offers: byReq[r['id']] ?? const []))
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis solicitudes')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _load = _fetch()),
        child: FutureBuilder(
          future: _load,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final items = snap.data!;
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.receipt_long_outlined, size: 56),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aún no has pedido nada.\nToca "Crear" y dinos qué buscas.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final (r, phase) = items[i];
                final (color, label) = phaseBadge(context, phase);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    title: Text(r['title'] as String,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(timeAgo(DateTime.parse(r['created_at'] as String))),
                    trailing: Chip(
                        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
                        side: BorderSide(color: color.withValues(alpha: .4))),
                    onTap: () => context.go('/client/request/${r['id']}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: `request_status_screen.dart` — la insignia**

Estructura: `StreamBuilder(offersStream)` → deriva fase en vivo → cabecera con la fase
prominente + `AnimatedSwitcher` al cambiar + stepper horizontal de 5 pasos (fase actual
resaltada) + copy heredado de la web por fase ("El proveedor te contactará pronto." /
"Ya puedes hablar con el proveedor." / "Califica al proveedor…") + lista de ofertas (precio con
`RD$` formateado, mensaje, estado). Tap en oferta pending y sin aceptada → sheet de aceptar
(Task 10). Código:

```dart
import 'package:flutter/material.dart';
import '../../data/repos.dart';
import '../../domain/phase.dart';
import 'my_requests_screen.dart' show phaseBadge;
import 'offer_actions.dart'; // Task 10: showOfferSheet

String fmtRD(num? v) => v == null ? '' : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

String offerPriceLabel(Map<String, dynamic> o) {
  if (o['price'] != null) return fmtRD(o['price'] as num);
  if (o['price_min'] != null && o['price_max'] != null) {
    return '${fmtRD(o['price_min'] as num)} – ${fmtRD(o['price_max'] as num)}';
  }
  if (o['pricing_mode'] == 'hourly' && o['hourly_rate'] != null) {
    return '${fmtRD(o['hourly_rate'] as num)}/hora';
  }
  return 'A evaluar';
}

const _phaseCopy = {
  RequestPhase.waiting: 'Tu solicitud está publicada. Los proveedores la están viendo.',
  RequestPhase.withOffers: 'Revisa las ofertas y acepta la que más te convenga.',
  RequestPhase.accepted: 'El proveedor te contactará pronto.',
  RequestPhase.unlocked: 'Ya puedes hablar con el proveedor.',
  RequestPhase.completed: 'Califica al proveedor para ayudar a la comunidad.',
};

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    supa
        .from('customer_requests')
        .select('id,title,status,kind,bullets,user_id,created_at')
        .eq('id', widget.requestId)
        .single()
        .then((r) => mounted ? setState(() => _request = r) : null);
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    if (req == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(req['title'] as String, maxLines: 1)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: offersStream(widget.requestId),
        builder: (context, snap) {
          final offers = snap.data ?? const <Map<String, dynamic>>[];
          final phase = phaseForRequest(
              requestStatus: req['status'] as String,
              offers: offers.map(offerLite).toList());
          final (color, label) = phaseBadge(context, phase);
          final hasAccepted = offers.any(
              (o) => o['status'] == 'accepted' || o['status'] == 'completed');
          return ListView(padding: const EdgeInsets.all(16), children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Card(
                key: ValueKey(phase),
                color: color.withValues(alpha: .08),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(_phaseCopy[phase]!),
                    const SizedBox(height: 16),
                    _PhaseStepper(phase: phase, color: color),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Ofertas (${offers.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (offers.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Todavía no hay ofertas. Te avisaremos con una notificación.')),
            for (final o in offers)
              Card(
                child: ListTile(
                  title: Text(offerPriceLabel(o),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(o['message'] as String? ?? '',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: _offerStatusChip(context, o, hasAccepted),
                  onTap: () => showOfferSheet(context, req, o,
                      hasAcceptedElsewhere:
                          hasAccepted && o['status'] == 'pending'),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _offerStatusChip(BuildContext context, Map<String, dynamic> o, bool hasAccepted) {
    final st = o['status'] as String;
    final txt = switch (st) {
      'accepted' => o['unlocked_at'] != null ? 'Desbloqueada' : 'Aceptada',
      'completed' => 'Completada',
      'rejected' => 'Rechazada',
      _ => hasAccepted ? 'Otra aceptada' : 'Pendiente',
    };
    return Chip(label: Text(txt, style: const TextStyle(fontSize: 11)));
  }
}

class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.phase, required this.color});
  final RequestPhase phase;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final idx = RequestPhase.values.indexOf(phase);
    return Row(children: [
      for (var i = 0; i < RequestPhase.values.length; i++) ...[
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: 14, height: 14,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= idx ? color : Theme.of(context).colorScheme.surfaceContainerHighest),
        ),
        if (i < RequestPhase.values.length - 1)
          Expanded(
              child: Container(
                  height: 3,
                  color: i < idx
                      ? color
                      : Theme.of(context).colorScheme.surfaceContainerHighest)),
      ],
    ]);
  }
}
```
Sustituir los placeholders `/client` y `/client/request/:id` en `router.dart`.

- [ ] **Step 4: Verificar en device** (con la solicitud creada en Task 8 + una oferta insertada
desde la cuenta proveedor QA en la web): lista muestra fase; detalle muestra oferta y el stream
actualiza en vivo al ofertar desde la web. Expected: fase cambia sin refrescar.

- [ ] **Step 5: Commit**

```bash
git add app/lib && git commit -m "feat: mis solicitudes + estado del pedido (timeline animado, realtime)"
```

---

### Task 10: Cliente — aceptar/rechazar oferta, contacto y calificar

**Files:**
- Create: `app/lib/features/client/offer_actions.dart`
- Modify: `app/lib/data/repos.dart`

**Interfaces:**
- Produces (repos): `Future<bool> acceptOffer({required String offerId})` — `UPDATE
  provider_offers SET status='accepted', customer_id=<uid> WHERE id=<offerId> AND
  status='pending'` con `.select('id')`, retorna false si 0 filas (ya aceptada/carrera);
  `Future<void> rejectOffer({required String offerId, required String reason})`;
  `Future<void> submitReview({required String businessId, required int rating, String comment})`
  — insert en `business_reviews {business_id, reviewer_id, rating, comment}` (rating 1-10).
- Produces (UI): `void showOfferSheet(BuildContext, Map request, Map offer,
  {required bool hasAcceptedElsewhere})` — bottom sheet M3 con detalle + acciones según estado.
- Consumes: `offerPriceLabel`, `fmtRD` (Task 9).

- [ ] **Step 1: repos**

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

Future<void> rejectOffer({required String offerId, required String reason}) async {
  await supa
      .from('provider_offers')
      .update({'status': 'rejected', 'rejection_reason': reason})
      .eq('id', offerId);
}

Future<void> submitReview(
    {required String businessId, required int rating, String comment = ''}) async {
  await supa.from('business_reviews').insert({
    'business_id': businessId,
    'reviewer_id': supa.auth.currentUser!.id,
    'rating': rating,
    'comment': comment,
  });
}
```

- [ ] **Step 2: `offer_actions.dart` (bottom sheet)**

Contenido del sheet según estado de la oferta:
- `pending` y NO hay otra aceptada → detalle (precio grande, mensaje completo) + FilledButton
  "Aceptar esta oferta" (con diálogo de confirmación "Solo puedes aceptar UNA oferta por
  solicitud") + TextButton "Rechazar" (pide razón corta en un TextField).
- `pending` y HAY otra aceptada → detalle en gris + nota "Ya aceptaste otra oferta".
- `accepted` sin `unlocked_at` → "Oferta aceptada — el proveedor te contactará pronto." (sin
  acciones; el desbloqueo es del proveedor).
- `accepted` con `unlocked_at` → "Contacto desbloqueado" + botón "Calificar al vendedor"
  (slider/estrellas 1-10 → `submitReview(businessId)`).

```dart
import 'package:flutter/material.dart';
import '../../data/repos.dart';
import 'request_status_screen.dart' show offerPriceLabel;

void showOfferSheet(BuildContext context, Map<String, dynamic> request,
    Map<String, dynamic> offer, {required bool hasAcceptedElsewhere}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: _OfferSheetBody(offer: offer, hasAcceptedElsewhere: hasAcceptedElsewhere),
    ),
  );
}

class _OfferSheetBody extends StatefulWidget {
  const _OfferSheetBody({required this.offer, required this.hasAcceptedElsewhere});
  final Map<String, dynamic> offer;
  final bool hasAcceptedElsewhere;
  @override
  State<_OfferSheetBody> createState() => _OfferSheetBodyState();
}

class _OfferSheetBodyState extends State<_OfferSheetBody> {
  bool _busy = false;
  int _rating = 8;

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(offerPriceLabel(o),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(o['message'] as String? ?? ''),
      const SizedBox(height: 20),
      if (st == 'pending' && !widget.hasAcceptedElsewhere) ...[
        FilledButton(
          onPressed: _busy ? null : () => _accept(context),
          child: const Text('Aceptar esta oferta'),
        ),
        TextButton(
            onPressed: _busy ? null : () => _reject(context),
            child: const Text('Rechazar')),
      ] else if (st == 'pending')
        const Text('Ya aceptaste otra oferta para esta solicitud.',
            textAlign: TextAlign.center)
      else if (st == 'accepted' && !unlocked)
        const Text('Oferta aceptada. El proveedor te contactará pronto.',
            textAlign: TextAlign.center)
      else if (unlocked) ...[
        const Text('Contacto desbloqueado. Ya pueden hablar.'),
        const SizedBox(height: 12),
        Text('Califica al vendedor: $_rating/10'),
        Slider(value: _rating.toDouble(), min: 1, max: 10, divisions: 9,
            label: '$_rating',
            onChanged: (v) => setState(() => _rating = v.round())),
        FilledButton(
          onPressed: _busy ? null : () => _review(context),
          child: const Text('Enviar calificación'),
        ),
      ],
    ]);
  }

  Future<void> _accept(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('¿Aceptar esta oferta?'),
              content: const Text('Solo puedes aceptar UNA oferta por solicitud.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(d, true),
                    child: const Text('Sí, aceptar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final accepted = await acceptOffer(offerId: widget.offer['id'] as String);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accepted
            ? '¡Oferta aceptada! El proveedor será notificado. 🏆'
            : 'Esta oferta ya no está disponible.')));
  }

  Future<void> _reject(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Rechazar oferta'),
              content: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: '¿Por qué? (opcional)')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false),
                    child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(d, true),
                    child: const Text('Rechazar')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await rejectOffer(offerId: widget.offer['id'] as String, reason: ctrl.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _review(BuildContext context) async {
    setState(() => _busy = true);
    try {
      await submitReview(
          businessId: widget.offer['business_id'] as String, rating: _rating);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Gracias por calificar al vendedor!')));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }
}
```

- [ ] **Step 3: Verificar en device**: aceptar la oferta de prueba → en la web (cuenta
proveedor QA) la oferta aparece aceptada; el guard: intentar aceptar otra → sheet "Ya aceptaste
otra". Expected: coherente con la web.

- [ ] **Step 4: Commit**

```bash
git add app/lib && git commit -m "feat: aceptar/rechazar oferta + calificar (guard anti-doble-aceptacion)"
```

---

### Task 11: Proveedor — bandeja + detalle + hacer oferta

**Files:**
- Create: `app/lib/features/provider/inbox_screen.dart`,
  `app/lib/features/provider/request_detail_screen.dart`
- Modify: `app/lib/data/repos.dart`, `app/lib/core/router.dart`

**Interfaces:**
- Produces (repos): `Future<List<Map<String, dynamic>>> providerInbox({String? kind})` — RPC
  `get_provider_inbox_unified(p_limit: 100, p_offset: 0, p_kind: kind)` (filtrar en memoria
  `source == 'marketplace'`); `Future<Map<String, dynamic>?> requestById(String id)`;
  `Future<String?> myBusinessId()` — primer `provider_businesses.id` del usuario;
  `Future<void> makeOffer({required Map request, required String businessId, double? price,
  double? priceMin, double? priceMax, required String message})`.
- Produces (UI): `ProviderInboxScreen`, `ProviderRequestDetailScreen(requestId)` con formulario
  de oferta (precio fijo o rango + mensaje + costo de desbloqueo estimado ANTES de ofertar).
- Consumes: `pointsForOffer` (Task 2).

- [ ] **Step 1: repos**

```dart
Future<List<Map<String, dynamic>>> providerInbox({String? kind}) async {
  final rows = List<Map<String, dynamic>>.from(await supa.rpc('get_provider_inbox_unified',
      params: {'p_limit': 100, 'p_offset': 0, 'p_kind': kind}));
  return rows.where((r) => r['source'] == 'marketplace').toList();
}

Future<Map<String, dynamic>?> requestById(String id) async => await supa
    .from('customer_requests')
    .select('id,user_id,title,description,bullets,kind,status,urgency,zone,is_wholesale,created_at')
    .eq('id', id)
    .maybeSingle();

Future<String?> myBusinessId() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('provider_businesses')
      .select('id')
      .eq('user_id', uid)
      .limit(1)
      .maybeSingle();
  return row?['id'] as String?;
}

/// Ofertar es GRATIS. Campos idénticos al insert de la web
/// (RequestRespondSection.tsx L940-954, camino producto/precio).
Future<void> makeOffer({
  required Map<String, dynamic> request,
  required String businessId,
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_offers').insert({
    'user_id': uid,
    'business_id': businessId,
    'request_id': request['id'],
    'request_title': request['title'],
    'price': price,
    'price_min': priceMin,
    'price_max': priceMax,
    'message': message,
    'status': 'pending',
    'image_urls': <String>[],
    'offers_shipping': false,
    'offers_installation': false,
    'requires_evaluation': false,
    'pricing_mode': price != null ? 'fixed' : 'range',
    'hourly_rate': null,
  });
}
```

- [ ] **Step 2: `inbox_screen.dart`**

`SegmentedButton` Todo/Producto/Servicio (param `p_kind: null|'producto'|'servicio'`), lista de
cards (título, descripción 2 líneas, urgencia, zona, `timeAgo`; borde primario + chip si
`is_wholesale` — la RPC no lo devuelve: mostrarlo en el detalle). Estado vacío: "Aquí verás las
solicitudes que coinciden con tu negocio." Pull-to-refresh. Tap → `/provider/request/:id`.

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repos.dart';
import '../client/my_requests_screen.dart' show timeAgo;

class ProviderInboxScreen extends StatefulWidget {
  const ProviderInboxScreen({super.key});
  @override
  State<ProviderInboxScreen> createState() => _ProviderInboxScreenState();
}

class _ProviderInboxScreenState extends State<ProviderInboxScreen> {
  String? _kind;
  late Future<List<Map<String, dynamic>>> _load = providerInbox();

  void _refetch() => setState(() => _load = providerInbox(kind: _kind));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitudes para ti')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('Todo')),
              ButtonSegment(value: 'producto', label: Text('Productos')),
              ButtonSegment(value: 'servicio', label: Text('Servicios')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              _kind = s.first;
              _refetch();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refetch(),
            child: FutureBuilder(
              future: _load,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final items = snap.data!;
                if (items.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 120),
                    Icon(Icons.inbox_outlined, size: 56),
                    Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Aquí verás las solicitudes que coinciden con tu negocio.',
                            textAlign: TextAlign.center)),
                  ]);
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text(r['title'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${r['description'] ?? ''}\n${timeAgo(DateTime.parse(r['created_at'] as String))}',
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        onTap: () => context.go('/provider/request/${r['id']}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 3: `request_detail_screen.dart` (detalle + formulario de oferta)**

Carga `requestById`; muestra título, bullets, chip "Al por mayor" si aplica, urgencia/zona.
Formulario: toggle Precio fijo/Rango, campos numéricos, mensaje, y una línea VIVA de
transparencia: "Si te aceptan, desbloquear este contacto te costará ~N créditos"
(`pointsForOffer` sobre lo tecleado, actualizado con `onChanged`). Botón "Enviar oferta
(gratis)" → `makeOffer` → snackbar + pop. Si `myBusinessId()` es null → mensaje "Completa tu
negocio en jayalo.com" (Custom Tab).

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../client/request_status_screen.dart' show fmtRD;

class ProviderRequestDetailScreen extends StatefulWidget {
  const ProviderRequestDetailScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<ProviderRequestDetailScreen> createState() => _ProviderRequestDetailScreenState();
}

class _ProviderRequestDetailScreenState extends State<ProviderRequestDetailScreen> {
  Map<String, dynamic>? _req;
  String? _businessId;
  bool _fixed = true;
  bool _busy = false;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _msg = TextEditingController();

  @override
  void initState() {
    super.initState();
    requestById(widget.requestId).then((r) => mounted ? setState(() => _req = r) : null);
    myBusinessId().then((b) => mounted ? setState(() => _businessId = b) : null);
  }

  int get _estimatedCost => pointsForOffer(
        price: _fixed ? double.tryParse(_price.text) : null,
        priceMin: _fixed ? null : double.tryParse(_min.text),
        priceMax: _fixed ? null : double.tryParse(_max.text),
      );

  Future<void> _submit() async {
    final req = _req!;
    final p = double.tryParse(_price.text);
    final mn = double.tryParse(_min.text);
    final mx = double.tryParse(_max.text);
    if (_fixed && (p == null || p <= 0)) return _toast('Pon el precio en RD\$.');
    if (!_fixed && (mn == null || mx == null || mx < mn)) {
      return _toast('Revisa el rango de precio.');
    }
    if (_msg.text.trim().isEmpty) return _toast('Escribe un mensaje corto al cliente.');
    setState(() => _busy = true);
    try {
      await makeOffer(
          request: req, businessId: _businessId!,
          price: _fixed ? p : null,
          priceMin: _fixed ? null : mn, priceMax: _fixed ? null : mx,
          message: _msg.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Oferta enviada! Te avisamos si te aceptan. 🚀')));
      context.go('/provider');
    } catch (_) {
      _toast('No se pudo enviar la oferta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final req = _req;
    if (req == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final bullets = List<String>.from(req['bullets'] as List? ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de solicitud')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(req['title'] as String, style: Theme.of(context).textTheme.titleLarge),
        if (req['is_wholesale'] == true)
          const Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Al por mayor'))),
        const SizedBox(height: 8),
        for (final b in bullets) Text('• $b'),
        const Divider(height: 32),
        if (_businessId == null)
          FilledButton(
            onPressed: () => launchUrl(Uri.parse('${AppConfig.siteUrl}/provider'),
                mode: LaunchMode.externalApplication),
            child: const Text('Completa tu negocio en jayalo.com para ofertar'),
          )
        else ...[
          Text('Tu oferta', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Precio fijo')),
              ButtonSegment(value: false, label: Text('Rango')),
            ],
            selected: {_fixed},
            onSelectionChanged: (s) => setState(() => _fixed = s.first),
          ),
          const SizedBox(height: 12),
          if (_fixed)
            TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Precio (RD\$)', border: OutlineInputBorder()))
          else
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Desde (RD\$)', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Hasta (RD\$)', border: OutlineInputBorder()))),
            ]),
          const SizedBox(height: 12),
          TextField(
              controller: _msg,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Mensaje al cliente', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          if (_estimatedCost > 0)
            Text(
                'Ofertar es GRATIS. Si te aceptan, desbloquear el contacto te costará '
                '~$_estimatedCost crédito${_estimatedCost == 1 ? '' : 's'}.',
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Enviar oferta (gratis)')),
        ],
      ]),
    );
  }
}
```
Sustituir placeholders `/provider` y `/provider/request/:id` en router.

- [ ] **Step 4: Verificar en device** (cuenta proveedor QA): bandeja lista la solicitud de la
Task 8 (si matchea categorías del negocio QA); ofertar → la oferta aparece en la app del cliente
(Task 9, vía realtime) y en la web. Expected: costo estimado coincide con el que muestra la web.

- [ ] **Step 5: Commit**

```bash
git add app/lib && git commit -m "feat: bandeja proveedor + hacer oferta (costo estimado transparente)"
```

---

### Task 12: Proveedor — mis ofertas, desbloquear, WhatsApp y saldo

**Files:**
- Create: `app/lib/features/provider/my_offers_screen.dart`
- Modify: `app/lib/data/repos.dart`, `app/lib/core/router.dart`

**Interfaces:**
- Produces (repos): `Future<List<Map<String, dynamic>>> myOffers()` — mis `provider_offers`
  (cols de Task 9 + `request_title,points_charged,purchase_completed`);
  `Future<int?> walletBalance()`;
  `Future<({bool ok, bool already, int charged, int? newBalance})> unlockOffer(String offerId)`
  — RPC `try_unlock_offer(_offer_id, _cost)` (el `_cost` se envía con el estimado pero el
  server lo IGNORA y calcula el real);
  `Future<({String? firstName, String? phone})> unlockedContact(String offerId)` — RPC
  `get_unlocked_offer_contact`; `Future<void> markPurchaseCompleted(String offerId)` — update
  `{purchase_completed: true, purchase_completed_at: now, status: 'completed'}`.
- Produces (UI): `MyOffersScreen` con secciones (Aceptadas — ¡desbloquea! / Pendientes /
  Historial), sheet de desbloqueo con costo+saldo y botón de confirmación deliberada
  (LongPress), reveal de contacto + botón WhatsApp, card de saldo con "Recargar" (Custom Tab).
- Consumes: `pointsForOffer`, `fmtRD`, `offerPriceLabel`, `AppConfig.walletUrl`.

- [ ] **Step 1: repos**

```dart
Future<List<Map<String, dynamic>>> myOffers() async {
  final uid = supa.auth.currentUser!.id;
  return List<Map<String, dynamic>>.from(await supa
      .from('provider_offers')
      .select('$offerCols,request_title,points_charged,purchase_completed')
      .eq('user_id', uid)
      .order('created_at', ascending: false));
}

Future<int?> walletBalance() async {
  final uid = supa.auth.currentUser!.id;
  final row =
      await supa.from('provider_wallets').select('balance').eq('user_id', uid).maybeSingle();
  return row?['balance'] as int?;
}

Future<({bool ok, bool already, int charged, int? newBalance})> unlockOffer(
    String offerId, int estimatedCost) async {
  final res = await supa.rpc('try_unlock_offer',
      params: {'_offer_id': offerId, '_cost': estimatedCost}) as Map<String, dynamic>;
  return (
    ok: res['ok'] == true,
    already: res['already_unlocked'] == true,
    charged: (res['charged'] as num?)?.toInt() ?? 0,
    newBalance: (res['new_balance'] as num?)?.toInt(),
  );
}

Future<({String? firstName, String? phone})> unlockedContact(String offerId) async {
  final rows = List<Map<String, dynamic>>.from(
      await supa.rpc('get_unlocked_offer_contact', params: {'_offer_id': offerId}));
  final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
  return (firstName: r['first_name'] as String?, phone: r['phone'] as String?);
}

Future<void> markPurchaseCompleted(String offerId) async {
  await supa.from('provider_offers').update({
    'purchase_completed': true,
    'purchase_completed_at': DateTime.now().toIso8601String(),
    'status': 'completed',
  }).eq('id', offerId);
}
```

- [ ] **Step 2: `my_offers_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../client/request_status_screen.dart' show offerPriceLabel;

int estimatedUnlockCost(Map<String, dynamic> o) {
  final c = pointsForOffer(
    price: (o['price'] as num?)?.toDouble(),
    priceMin: (o['price_min'] as num?)?.toDouble(),
    priceMax: (o['price_max'] as num?)?.toDouble(),
    pricingMode: o['pricing_mode'] as String?,
    hourlyRate: (o['hourly_rate'] as num?)?.toDouble(),
    estimatedHours: (o['estimated_hours'] as num?)?.toDouble(),
  );
  return c < 1 ? 1 : c;
}

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});
  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _offers = [];
  int? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver del navegador (recarga PayPal), refrescar el saldo (spec §6).
    if (state == AppLifecycleState.resumed) _refetch();
  }

  Future<void> _refetch() async {
    final results = await Future.wait([myOffers(), walletBalance()]);
    if (!mounted) return;
    setState(() {
      _offers = results[0] as List<Map<String, dynamic>>;
      _balance = results[1] as int?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final toUnlock = _offers
        .where((o) => o['status'] == 'accepted' && o['unlocked_at'] == null)
        .toList();
    final pending = _offers.where((o) => o['status'] == 'pending').toList();
    final rest = _offers
        .where((o) =>
            o['status'] == 'rejected' ||
            o['status'] == 'completed' ||
            (o['status'] == 'accepted' && o['unlocked_at'] != null))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Mis ofertas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refetch,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text('${_balance ?? '—'} créditos',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: FilledButton.tonal(
                      onPressed: () => launchUrl(Uri.parse(AppConfig.walletUrl),
                          mode: LaunchMode.externalApplication),
                      child: const Text('Recargar'),
                    ),
                  ),
                ),
                if (toUnlock.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('🏆 ¡Te aceptaron! Desbloquea el contacto',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final o in toUnlock) _offerCard(o, highlight: true),
                ],
                const SizedBox(height: 16),
                Text('Pendientes (${pending.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final o in pending) _offerCard(o),
                const SizedBox(height: 16),
                Text('Historial', style: Theme.of(context).textTheme.titleMedium),
                for (final o in rest) _offerCard(o),
              ]),
            ),
    );
  }

  Widget _offerCard(Map<String, dynamic> o, {bool highlight = false}) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    final label = switch (st) {
      'accepted' => unlocked ? 'Desbloqueada' : 'ACEPTADA',
      'completed' => 'Completada',
      'rejected' => 'Rechazada',
      _ => 'Pendiente',
    };
    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade700, width: 2))
          : null,
      child: ListTile(
        title: Text(o['request_title'] as String? ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${offerPriceLabel(o)} · $label'),
        trailing: highlight ? const Icon(Icons.lock_open) : null,
        onTap: () => _openOffer(o),
      ),
    );
  }

  void _openOffer(Map<String, dynamic> o) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    if (st == 'accepted' && !unlocked) {
      _showUnlockSheet(o);
    } else if (unlocked) {
      _showContactSheet(o);
    }
  }

  void _showUnlockSheet(Map<String, dynamic> o) {
    final cost = estimatedUnlockCost(o);
    final enough = (_balance ?? 0) >= cost;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Desbloquear contacto',
              style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Costo: $cost crédito${cost == 1 ? '' : 's'} · Tu saldo: ${_balance ?? 0}'),
          const SizedBox(height: 16),
          if (!enough)
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(AppConfig.walletUrl),
                  mode: LaunchMode.externalApplication),
              child: const Text('Saldo insuficiente — Recargar'),
            )
          else
            GestureDetector(
              onLongPress: () async {
                Navigator.pop(ctx);
                final res = await unlockOffer(o['id'] as String, cost);
                if (!mounted) return;
                if (res.ok) {
                  await _refetch();
                  final refreshed =
                      _offers.firstWhere((x) => x['id'] == o['id'], orElse: () => o);
                  _showContactSheet(refreshed);
                }
              },
              child: FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Mantén presionado para confirmar'))),
                icon: const Icon(Icons.lock_open),
                label: const Text('Mantén presionado para desbloquear'),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _showContactSheet(Map<String, dynamic> o) async {
    ({String? firstName, String? phone}) contact;
    try {
      contact = await unlockedContact(o['id'] as String);
    } catch (_) {
      contact = (firstName: null, phone: null);
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('✅ Contacto desbloqueado', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(contact.phone != null
              ? '${contact.firstName ?? 'Cliente'} · ${contact.phone}'
              : 'El cliente no tiene WhatsApp verificado disponible; contáctalo por el chat de jayalo.com.'),
          const SizedBox(height: 16),
          if (contact.phone != null)
            FilledButton.icon(
              onPressed: () {
                final digits = contact.phone!.replaceAll(RegExp(r'\D'), '');
                launchUrl(Uri.parse('https://wa.me/$digits'),
                    mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.chat),
              label: const Text('Abrir WhatsApp'),
            ),
          const SizedBox(height: 8),
          if (o['purchase_completed'] != true)
            OutlinedButton(
              onPressed: () async {
                await markPurchaseCompleted(o['id'] as String);
                if (ctx.mounted) Navigator.pop(ctx);
                _refetch();
              },
              child: const Text('¿Se concretó la venta? Marcar completada'),
            ),
        ]),
      ),
    );
  }
}
```
Sustituir el placeholder `/provider/offers` en router.

- [ ] **Step 3: Verificar en device (dinero real de prueba — cuenta QA con créditos)**:
long-press desbloquear → saldo baja lo que dice la web (el server calcula; comparar `charged`
vs estimado), contacto revela nombre+teléfono, botón WhatsApp abre el chat. Repetir el unlock →
`already_unlocked` (idempotente, cobra 0). Expected: idéntico a la web.

- [ ] **Step 4: Commit**

```bash
git add app/lib && git commit -m "feat: mis ofertas + desbloqueo (RPC atomica) + WhatsApp + saldo con recarga externa"
```

---

### Task 13: Backend push — `device_tokens` + triggers + Edge Function `send-push`

**Files:**
- Create: `supabase/migrations/20260716120000_device_tokens_and_push.sql`
- Create: `supabase/functions/send-push/index.ts`

**Interfaces:**
- Produces: tabla `public.device_tokens(user_id, token, platform, updated_at)` con RLS de
  dueño; trigger `trg_notify_customer_on_unlock` (nueva notificación `offer_unlocked` — hoy NO
  existe evento para el cliente al desbloquear); trigger `trg_push_on_notification` sobre
  `notifications` (whitelist de 4 kinds) → `net.http_post` a la Edge Function; Edge Function
  `send-push` (verifica `x-webhook-secret`, envía FCM HTTP v1, borra tokens `UNREGISTERED`).
- Consumes (Task 14): la app hace upsert en `device_tokens` y recibe pushes con
  `data: {link, kind}`.

⚠️ TODO lo de esta task es ADITIVO (cero cambios a objetos existentes). Aplicar la migración
vía MCP de Supabase con **confirmación nombrada del PO** (o el PO por dashboard). La Edge
Function se despliega con MCP `deploy_edge_function` o `supabase functions deploy send-push
--no-verify-jwt` si hay CLI.

- [ ] **Step 1: Migración SQL**

```sql
-- 20260716120000_device_tokens_and_push.sql
-- Push nativo (app Flutter, spec jayalo-app 2026-07-16). Todo ADITIVO.

-- 1) Tokens de dispositivo (FCM). Sin datos sensibles: RLS de dueño + grants CRUD.
CREATE TABLE public.device_tokens (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'android',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY device_tokens_owner_all ON public.device_tokens
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
REVOKE ALL ON public.device_tokens FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;

-- 2) Notificación al CLIENTE cuando el proveedor desbloquea (hoy no existe este evento).
CREATE OR REPLACE FUNCTION public.notify_customer_on_unlock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications
      (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
    VALUES
      (NEW.customer_id, 'offer_unlocked', 'Contacto desbloqueado',
       COALESCE(NEW.request_title, 'El proveedor ya puede contactarte'),
       '/requests/' || NEW.request_id, NEW.user_id, 'offer', NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_notify_customer_on_unlock
  AFTER UPDATE OF unlocked_at ON public.provider_offers
  FOR EACH ROW
  WHEN (OLD.unlocked_at IS NULL AND NEW.unlocked_at IS NOT NULL)
  EXECUTE FUNCTION public.notify_customer_on_unlock();

-- 3) Fan-out a push: cada notification de un kind del corazón dispara la Edge Function.
--    Mismo patrón de secreto que enqueue_notification_email (app_settings.internal_webhook_secret).
--    NOTA: si pg_net vive en otro schema tras la relocación de 2026-07-14, usar el MISMO
--    cualificador que usa enqueue_notification_email en prod (verificar en pg_proc antes de aplicar).
CREATE OR REPLACE FUNCTION public.push_on_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_secret text;
BEGIN
  IF NEW.kind NOT IN
     ('request_new_in_category', 'offer_new', 'offer_accepted', 'offer_unlocked') THEN
    RETURN NEW;
  END IF;
  SELECT value #>> '{}' INTO v_secret
  FROM public.app_settings WHERE key = 'internal_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;
  PERFORM net.http_post(
    url := 'https://mfaiklvobnvgusbcssbx.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object(
      'user_id', NEW.user_id, 'kind', NEW.kind, 'title', NEW.title,
      'body', NEW.body, 'link', NEW.link)
  );
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_push_on_notification
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.push_on_notification();
```

- [ ] **Step 2: Edge Function `send-push/index.ts`**

```ts
// Supabase Edge Function: send-push
// Deploy: --no-verify-jwt (la auth es x-webhook-secret, patrón de los webhooks internos).
// Secretos requeridos (supabase secrets set):
//   INTERNAL_WEBHOOK_SECRET  = mismo valor que app_settings.internal_webhook_secret
//   FCM_SERVICE_ACCOUNT      = JSON completo de la cuenta de servicio de Firebase
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta la plataforma.
import { createClient } from "npm:@supabase/supabase-js@2";

const enc = new TextEncoder();

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", enc.encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- OAuth2 para FCM HTTP v1 (JWT RS256 con la service account) ---
let cachedToken: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? enc.encode(data) : data;
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function fcmAccessToken(sa: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----|\n/g, "");
  const keyData = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`)));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`OAuth FCM falló: ${JSON.stringify(json)}`);
  cachedToken = { token: json.access_token, exp: now + 3500 };
  return json.access_token;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("INTERNAL_WEBHOOK_SECRET") ?? "";
  const got = req.headers.get("x-webhook-secret") ?? "";
  if (!secret || (await sha256Hex(got)) !== (await sha256Hex(secret))) {
    return new Response("unauthorized", { status: 401 });
  }

  const { user_id, kind, title, body, link } = await req.json();
  if (!user_id || !title) return new Response("bad request", { status: 400 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: tokens } = await admin
    .from("device_tokens").select("token").eq("user_id", user_id);
  if (!tokens?.length) return new Response("no tokens", { status: 200 });

  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
  const access = await fcmAccessToken(sa);
  const results: string[] = [];

  for (const { token } of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body: body ?? "" },
            data: { link: link ?? "", kind: kind ?? "" },
            android: { priority: "HIGH" },
          },
        }),
      },
    );
    if (res.status === 404 || res.status === 400) {
      // Token muerto (UNREGISTERED/INVALID) → limpiar.
      await admin.from("device_tokens").delete().eq("token", token);
      results.push(`dead:${res.status}`);
    } else {
      results.push(`sent:${res.status}`);
    }
  }
  return new Response(JSON.stringify({ ok: true, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
```

- [ ] **Step 3: Desplegar y configurar [PO + MCP]**

1. `supabase secrets set` (o dashboard → Edge Functions → Secrets): `INTERNAL_WEBHOOK_SECRET`
   (mismo valor que `app_settings.internal_webhook_secret` — el PO lo tiene) y
   `FCM_SERVICE_ACCOUNT` (el JSON del prerrequisito 2, pegado completo).
2. Deploy de la función (MCP `deploy_edge_function` o CLI `--no-verify-jwt`).
3. Aplicar la migración (MCP `apply_migration`, confirmación nombrada del PO). ANTES de
   aplicar: verificar en `pg_proc` el cualificador real de `http_post` que usa
   `enqueue_notification_email` (por la relocación de pg_net) y ajustar el `net.` si difiere.

- [ ] **Step 4: Probar la función sola (sin app)**

```bash
curl -s -X POST https://mfaiklvobnvgusbcssbx.supabase.co/functions/v1/send-push \
  -H "Content-Type: application/json" -H "x-webhook-secret: <el secreto>" \
  -d '{"user_id":"00000000-0000-0000-0000-000000000000","kind":"offer_new","title":"test","body":"","link":""}'
```
Expected: `{"ok":true,...}` con `"no tokens"` o resultados; con secreto malo → 401.
Verificar también el trigger: `INSERT` manual en `notifications` con un kind whitelisted en una
transacción de prueba → la función registra la llamada (logs de la Edge Function).

- [ ] **Step 5: Commit**

```bash
git add supabase/ && git commit -m "feat: backend push — device_tokens + triggers + edge function send-push (FCM v1)"
```

---

### Task 14: App — integración FCM + deep links

**Files:**
- Create: `app/lib/push/push_service.dart`
- Modify: `app/lib/main.dart`, `app/lib/core/router.dart`, `app/lib/data/repos.dart`,
  `app/android/app/build.gradle.kts` + `app/android/settings.gradle.kts` (plugin
  google-services), `app/android/app/google-services.json` (del prerrequisito 2 — NO commitear:
  agregarlo a `.gitignore`)

**Interfaces:**
- Produces: `Future<void> initPush(GoRouter router)` — pide permiso de notificaciones
  (Android 13+), registra/refresca token (`upsert` a `device_tokens`), maneja tap en push
  (background/terminated) navegando según `data.link`; `String mapLinkToRoute(String link)`.
- Consumes: rutas de Task 7; tabla de Task 13.

- [ ] **Step 1: Config Firebase en Android**

```bash
cd app
flutter pub add firebase_core firebase_messaging
```
Copiar `google-services.json` a `app/android/app/`. En `app/android/settings.gradle.kts`
agregar el plugin `id("com.google.gms.google-services") version "4.4.2" apply false` y en
`app/android/app/build.gradle.kts` aplicarlo (`id("com.google.gms.google-services")`).
Agregar `android/app/google-services.json` al `.gitignore` del repo.

- [ ] **Step 2: `push_service.dart`**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// '/requests/<id>' (links de la web en notifications.link) → ruta nativa.
String mapLinkToRoute(String link) {
  final reqMatch = RegExp(r'^/requests/([0-9a-f-]+)').firstMatch(link);
  if (reqMatch != null) return '/client/request/${reqMatch.group(1)}';
  final provMatch = RegExp(r'^/provider/requests/([0-9a-f-]+)').firstMatch(link);
  if (provMatch != null) return '/provider/offers';
  if (link.startsWith('/provider')) return '/provider';
  return '/client';
}

Future<void> _saveToken(String token) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  await Supabase.instance.client.from('device_tokens').upsert(
      {'user_id': uid, 'token': token, 'platform': 'android',
       'updated_at': DateTime.now().toIso8601String()},
      onConflict: 'user_id,token');
}

Future<void> initPush(GoRouter router) async {
  await Firebase.initializeApp();
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(); // Android 13+: diálogo del sistema

  // Registrar token ahora (si hay sesión) y en cada login/refresh.
  final token = await fcm.getToken();
  if (token != null) await _saveToken(token);
  fcm.onTokenRefresh.listen(_saveToken);
  Supabase.instance.client.auth.onAuthStateChange.listen((e) async {
    if (e.event == AuthChangeEvent.signedIn) {
      final t = await fcm.getToken();
      if (t != null) await _saveToken(t);
    }
  });

  void goFrom(RemoteMessage m) {
    final link = m.data['link'] as String? ?? '';
    router.go(mapLinkToRoute(link));
  }

  // App abierta desde terminated por un push:
  final initial = await fcm.getInitialMessage();
  if (initial != null) goFrom(initial);
  // App en background → tap:
  FirebaseMessaging.onMessageOpenedApp.listen(goFrom);
}
```

- [ ] **Step 3: Enganchar en `main.dart`**

```dart
final router = buildRouter();
// tras Supabase.initialize:
await initPush(router);
runApp(JayaloApp(router: router));
```
(`JayaloApp` pasa a recibir el router por parámetro en vez de construirlo.)
Logout (settings): antes de `signOut()`, borrar el token del device:
`final t = await FirebaseMessaging.instance.getToken(); if (t != null) { await supa.from('device_tokens').delete().eq('token', t); }`.

- [ ] **Step 4: Verificar las 4 transiciones en device (2 cuentas: consumer en la app,
proveedor QA en la web — y luego al revés)**

| # | Acción | Push esperado en |
|---|---|---|
| 1 | Cliente crea solicitud (app) que matchea el negocio QA | teléfono con sesión proveedor: "Nueva solicitud en tu rubro" |
| 2 | Proveedor oferta (web o app) | teléfono cliente: "Nueva oferta recibida" |
| 3 | Cliente acepta (app) | teléfono proveedor: "Cliente interesado en hablar contigo" |
| 4 | Proveedor desbloquea (app) | teléfono cliente: "Contacto desbloqueado" |

Probar cada push con la app en foreground, background y CERRADA; el tap debe abrir la pantalla
de estado correcta. Expected: 4/4 con deep link correcto.

- [ ] **Step 5: Commit**

```bash
git add app/ && git commit -m "feat: push FCM + registro de device token + deep links"
```

---

### Task 15: Cierre — runbook E2E + criterios del spec

**Files:**
- Create: `docs/qa/2026-07-XX-runbook-e2e-v1.md` (fecha del día que se ejecute)

**Interfaces:** ninguna (verificación final contra spec §13).

- [ ] **Step 1: Ejecutar el ciclo completo con el PO en su teléfono**

Checklist (cada ítem con evidencia — screenshot o anotación):
1. Login Google nativo < 10s, sin captcha visible.
2. Crear solicitud por IA (streaming de turnos fluido, chips, ready correcto).
3. La solicitud aparece en jayalo.com intacta (título, bullets, categorías, rubros).
4. Proveedor (QA) la ve en su bandeja de la app; oferta desde la app.
5. Push #2 llega al cliente; tap abre el estado del pedido; fase = "Con ofertas" en vivo.
6. Aceptar → push #3 al proveedor → "Mis ofertas" resalta la aceptada.
7. Desbloquear (long-press) → débito correcto (comparar con la web) → contacto → WhatsApp abre.
8. Push #4 al cliente; fase "Contacto desbloqueado".
9. Marcar completada + calificar → fase "Completada"; review visible en la web.
10. Recargar → navegador externo abre `/provider/wallet`; al volver el saldo refresca.
11. Sensación de rendimiento en el device de gama media: veredicto del PO (el criterio #1 del spec).
12. `jayalo-main` sin cambios (salvo Task 0); `db-security-check.sql` #1-#10 sigue en 0 filas.

- [ ] **Step 2: Documentar resultados + pendientes en el runbook y commitear**

```bash
git add docs/qa/ && git commit -m "docs: runbook E2E v1 — resultados"
```

- [ ] **Step 3: Actualizar el spec** — marcar estado "implementado" + desviaciones reales.

---

## Self-review (hecho al escribir el plan)

- **Cobertura del spec:** §3.1 ciclo completo → Tasks 8-12; IA nativa → Tasks 3/6/8; login →
  Task 5; push → Tasks 13-14; navegador externo → Tasks 7 (términos), 11 (negocio), 12
  (recarga); filosofía M3 → tema (Task 1), sheets/steppers/motion (Tasks 9-12); criterios §13 →
  Task 15. Revert `cb675fc` (§11) → Task 0. Chat interno y onboarding: fuera (decisión PO).
- **Corrección al spec descubierta investigando:** el endpoint IA NO es SSE/streaming — un POST
  por turno que devuelve UN JSON (`chat-stream.ts` L498). El spec §7/§10 mencionaba SSE; el
  spec se corrige junto con este plan.
- **Tipos consistentes entre tasks:** `OfferLite/offerLite`, `offerCols`, `fmtRD`,
  `offerPriceLabel`, `timeAgo`, `phaseBadge` se definen una vez y se importan donde se usan.
- **Sin placeholders:** todos los pasos llevan código o comando concreto. Los dos puntos
  marcados "verificar antes de aplicar" (cualificador de pg_net; hostname Turnstile) son
  verificaciones operativas contra prod, no huecos de diseño.
