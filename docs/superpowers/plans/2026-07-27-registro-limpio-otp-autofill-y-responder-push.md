# Registro limpio + OTP autofill + responder desde push — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Depurar el alta de consumidor (límites de nombre, WhatsApp con prefijo RD, dirección auto), hacer el OTP bloqueante con autocompletado del código, y permitir responder un chat desde la notificación push (Android).

**Architecture:** Tres tandas independientes. A (formularios app+web, sin BD). B (flujo de OTP bloqueante en la app + formato SMS Retriever en el edge function `send-otp` + autofill Flutter/iOS). C (data-message en `send-push` + `flutter_local_notifications` con acción de respuesta + envío en background isolate). La lógica pura (composición de teléfono, formato de dirección, cuerpo del SMS) se extrae a funciones testeables; la UI/nativo se verifica en device con pasos guiados.

**Tech Stack:** Flutter/Dart (`geocoding`, `smart_auth`, `flutter_local_notifications`, `firebase_messaging`, `supabase_flutter`), React/TanStack Start + Zod + shadcn (web), Supabase Edge Functions (Deno/TypeScript), Twilio SMS.

Spec: `docs/superpowers/specs/2026-07-27-registro-limpio-otp-autofill-y-responder-push-design.md`

## Global Constraints

- **Repos:** app = `C:\Users\ac\Downloads\jayalo-app` (Flutter en `app/`, edge functions en `supabase/functions/`, rama `feat/error-tracking`). Web = `C:\Users\ac\Downloads\jayalo-main\jayalo-main` (rama `master`).
- **Nombre/apellido:** máx **40** caracteres; charset permitido `[\p{L}\p{M} '\-]` (letras Unicode + marcas de acento + espacio + guion + apóstrofo). Bloquear dígitos y otros símbolos.
- **WhatsApp:** siempre `+1` + prefijo ∈ `{809, 829, 849}` (default `809`) + exactamente **7 dígitos** locales. Componer y pasar por `normalizePhone` existente antes de usar.
- **Canal OTP:** ya es `sms` (`app_settings.otp_channel`). El copy nunca debe prometer WhatsApp. El campo del código mantiene su estilo casi-gigante actual (`fontSize: 52, letterSpacing: 14` en `otp_sheet.dart`) — el autofill NO debe alterarlo.
- **OTP verify-before-write:** `verify-otp` solo escribe `account_verifications` (nunca `profiles`), por eso verificar antes de `completeConsumerProfile` es seguro.
- **Verde obligatorio:** app `flutter analyze` en 0; web `npx tsc --noEmit` y `npm run lint` en 0; tests nuevos pasando.
- **Commits:** uno por task, en el repo correspondiente. Terminar el mensaje con `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. **No hacer push** — el PO revisa y decide el push (convención de la app).
- **Migraciones/edge deploy:** Tanda C no toca esquema. Los cambios de edge function (`send-otp`, `send-push`) se editan en el repo; el **deploy a Supabase lo autoriza el PO** (no desplegar sin confirmación).

---

# TANDA A — Campos del registro (puntos 1, 2, 4)

### Task A1: Web — límite de nombre + WhatsApp con prefijo RD

**Files:**
- Modify: `src/lib/phone.ts` (nuevo helper `composeRdWhatsapp`)
- Create: `src/lib/phone.rd.test.ts`
- Modify: `src/components/consumer/ConsumerProfileForm.tsx`
- Modify: `src/components/provider/ProviderSignupWizard.tsx`

**Interfaces:**
- Produces: `composeRdWhatsapp(prefix: string, local: string): string` — devuelve E.164 (`+1809XXXXXXX`) o `""` si inválido. `RD_PREFIXES: readonly ["809","829","849"]`.

- [ ] **Step 1: Failing test para el helper de composición**

Create `src/lib/phone.rd.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { composeRdWhatsapp, RD_PREFIXES } from "./phone";

describe("composeRdWhatsapp", () => {
  it("arma E.164 con prefijo y 7 dígitos", () => {
    expect(composeRdWhatsapp("809", "5551234")).toBe("+18095551234");
  });
  it("acepta los tres prefijos válidos", () => {
    expect(RD_PREFIXES).toEqual(["809", "829", "849"]);
    for (const p of RD_PREFIXES) expect(composeRdWhatsapp(p, "1234567")).toBe(`+1${p}1234567`);
  });
  it("devuelve '' si los dígitos locales no son 7", () => {
    expect(composeRdWhatsapp("809", "12345")).toBe("");
    expect(composeRdWhatsapp("809", "12345678")).toBe("");
  });
  it("ignora no-dígitos en el campo local", () => {
    expect(composeRdWhatsapp("829", "555-12ab34")).toBe("+18295551234");
  });
});
```

- [ ] **Step 2: Correr y ver fallar**

Run: `cd /c/Users/ac/Downloads/jayalo-main/jayalo-main && npx vitest run src/lib/phone.rd.test.ts`
Expected: FAIL (`composeRdWhatsapp` no existe).

- [ ] **Step 3: Implementar el helper en `src/lib/phone.ts`** (al final del archivo)

```ts
export const RD_PREFIXES = ["809", "829", "849"] as const;

/**
 * Compone un WhatsApp RD desde un prefijo (809/829/849) y 7 dígitos locales.
 * Devuelve E.164 (`+1<prefijo><7 dígitos>`) o "" si el local no tiene 7 dígitos.
 */
export function composeRdWhatsapp(prefix: string, local: string): string {
  const p = RD_PREFIXES.includes(prefix as (typeof RD_PREFIXES)[number]) ? prefix : "809";
  const digits = local.replace(/\D/g, "").slice(0, 7);
  if (digits.length !== 7) return "";
  return normalizePhone(`${p}${digits}`);
}
```

- [ ] **Step 4: Correr y ver pasar**

Run: `npx vitest run src/lib/phone.rd.test.ts` — Expected: PASS (4 tests).

- [ ] **Step 5: `ConsumerProfileForm.tsx` — nombre con límite**

En el schema `signupSchema` (líneas ~39-44) cambiar `firstName`/`lastName`:
```ts
  firstName: z.string().trim().min(1, "Indica tu nombre.").max(40, "Máximo 40 caracteres.")
    .regex(/^[\p{L}\p{M} '\-]+$/u, "Solo letras."),
  lastName: z.string().trim().min(1, "Indica tu apellido.").max(40, "Máximo 40 caracteres.")
    .regex(/^[\p{L}\p{M} '\-]+$/u, "Solo letras."),
```
En los dos `<Input>` de nombre/apellido (líneas ~157, ~161) agregar `maxLength={40}`.

- [ ] **Step 6: `ConsumerProfileForm.tsx` — WhatsApp con Select + numérico**

Importar `Select*` de `@/components/ui/select` y `composeRdWhatsapp, RD_PREFIXES` de `@/lib/phone`. Reemplazar el estado `whatsapp` por `prefix`/`localPhone`:
```tsx
const [prefix, setPrefix] = useState<string>("809");
const [localPhone, setLocalPhone] = useState("");
```
Sustituir el bloque del `<Input>` de WhatsApp (líneas ~242-252) por:
```tsx
        <div>
          <label className="text-xs font-medium">WhatsApp *</label>
          <div className="mt-1 flex gap-2">
            <Select value={prefix} onValueChange={setPrefix}>
              <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
              <SelectContent>
                {RD_PREFIXES.map((p) => (
                  <SelectItem key={p} value={p}>{p}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              inputMode="numeric"
              maxLength={7}
              value={localPhone}
              onChange={(e) => setLocalPhone(e.target.value.replace(/\D/g, "").slice(0, 7))}
              placeholder="5551234"
            />
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            Te avisaremos por aquí cuando recibas ofertas.
          </p>
        </div>
```
En `handleSubmit`, reemplazar el uso de `whatsapp`: computar `const whatsapp = composeRdWhatsapp(prefix, localPhone);` y cambiar la validación `if (!isValidPhone(whatsapp))` por `if (!whatsapp) { toast.error("Escribe un WhatsApp de 7 dígitos."); return; }`. En el payload usar `whatsapp` (ya E.164 — no re-normalizar).

- [ ] **Step 7: `ProviderSignupWizard.tsx` — mismo tratamiento**

Nombre: en el `canProceed`/validación (líneas ~551-552) ya exige `.length > 0`; agregar `&& firstName.trim().length <= 40 && lastName.trim().length <= 40` y en los `<Input>` de nombre/apellido `maxLength={40}` + saneo `onChange` a charset `[\p{L}\p{M} '\-]` (`e.target.value.replace(/[^\p{L}\p{M} '\-]/gu, "").slice(0,40)`).
WhatsApp: sustituir el `<Input>` de teléfono por el mismo par Select(prefijo)+Input(7 díg.); reemplazar `normalizePhone(phone)` (línea ~591) por `composeRdWhatsapp(prefix, localPhone)` y bloquear el submit si devuelve `""`. Mantener el `is_whatsapp_taken` sobre el compuesto.

- [ ] **Step 8: Verificar verde**

Run: `npx tsc --noEmit && npm run lint && npx vitest run src/lib/phone.rd.test.ts`
Expected: 0 errores, tests PASS.

- [ ] **Step 9: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-main/jayalo-main
git add src/lib/phone.ts src/lib/phone.rd.test.ts src/components/consumer/ConsumerProfileForm.tsx src/components/provider/ProviderSignupWizard.tsx
git commit -m "feat(web): límite nombre 40 + WhatsApp con prefijo RD seleccionable"
```

---

### Task A2: App — límite de nombre + WhatsApp con prefijo RD

**Files:**
- Modify: `lib/domain/phone.dart` (helper `composeRdWhatsapp` + `kRdPrefixes`)
- Create: `test/domain/phone_test.dart`
- Modify: `lib/features/onboarding/consumer_onboarding_screen.dart`
- Modify: `lib/features/onboarding/provider_onboarding_screen.dart`

**Interfaces:**
- Produces: `String composeRdWhatsapp(String prefix, String local)` → E.164 o `''`. `const kRdPrefixes = ['809','829','849']`.

- [ ] **Step 1: Failing test**

Create `test/domain/phone_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/domain/phone.dart';

void main() {
  test('composeRdWhatsapp arma E.164', () {
    expect(composeRdWhatsapp('809', '5551234'), '+18095551234');
  });
  test('acepta los tres prefijos', () {
    expect(kRdPrefixes, ['809', '829', '849']);
  });
  test('vacío si no son 7 dígitos', () {
    expect(composeRdWhatsapp('809', '12345'), '');
    expect(composeRdWhatsapp('809', '12345678'), '');
  });
  test('ignora no-dígitos', () {
    expect(composeRdWhatsapp('829', '555-1234'), '+18295551234');
  });
}
```
(Ajustar el import `package:jayalo/...` al `name:` real de `pubspec.yaml` si difiere.)

- [ ] **Step 2: Ver fallar**

Run: `cd /c/Users/ac/Downloads/jayalo-app/app && flutter test test/domain/phone_test.dart`
Expected: FAIL (símbolo no definido).

- [ ] **Step 3: Implementar en `lib/domain/phone.dart`**

```dart
const kRdPrefixes = ['809', '829', '849'];

/// Compone un WhatsApp RD desde prefijo (809/829/849) + 7 dígitos locales.
/// Devuelve E.164 o '' si el local no tiene 7 dígitos.
String composeRdWhatsapp(String prefix, String local) {
  final p = kRdPrefixes.contains(prefix) ? prefix : '809';
  final digits = local.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 7) return '';
  return normalizePhone('$p$digits');
}
```

- [ ] **Step 4: Ver pasar**

Run: `flutter test test/domain/phone_test.dart` — Expected: PASS (4 tests).

- [ ] **Step 5: `consumer_onboarding_screen.dart` — nombre con formatters**

Importar `package:flutter/services.dart`. En los `TextField` `_first` y `_last` (líneas ~154, ~161) agregar:
```dart
            maxLength: 40,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            inputFormatters: [
              LengthLimitingTextInputFormatter(40),
              FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} '\-]", unicode: true)),
            ],
```

- [ ] **Step 6: `consumer_onboarding_screen.dart` — WhatsApp con Dropdown + numérico**

Reemplazar el controller `_phone` por estado `_prefix`/`_local`:
```dart
  String _prefix = '809';
  final _local = TextEditingController();
```
Sustituir el `TextField` de WhatsApp (líneas ~171-189) por:
```dart
          Row(children: [
            DropdownButton<String>(
              value: _prefix,
              items: [for (final p in kRdPrefixes) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() => _prefix = v ?? '809'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _local,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(7),
                ],
                decoration: InputDecoration(
                  labelText: 'Número de WhatsApp',
                  hintText: '5551234',
                  errorText: _phoneError,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() => _phoneError = null),
                onEditingComplete: () { FocusScope.of(context).nextFocus(); _checkPhone(); },
                onTapOutside: (_) { FocusScope.of(context).unfocus(); _checkPhone(); },
              ),
            ),
          ]),
```
Agregar un getter `String get _composedPhone => composeRdWhatsapp(_prefix, _local.text);`. En `_checkPhone`, `_valid` y `_submit` reemplazar los usos de `_phone.text`/`normalizePhone(_phone.text)` por `_composedPhone` (validez: `_composedPhone.isNotEmpty`). En `dispose` cambiar `_phone.dispose()` por `_local.dispose()`.

- [ ] **Step 7: `provider_onboarding_screen.dart` — mismo tratamiento**

Aplicar los mismos formatters de nombre (máx 40 + charset) y el mismo par Dropdown+numérico para WhatsApp; usar `composeRdWhatsapp` donde hoy normaliza el teléfono. (Leer el archivo para ubicar los controllers equivalentes.)

- [ ] **Step 8: Verde**

Run: `flutter analyze && flutter test test/domain/phone_test.dart`
Expected: `No issues found`, tests PASS.

- [ ] **Step 9: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/domain/phone.dart app/test/domain/phone_test.dart app/lib/features/onboarding/consumer_onboarding_screen.dart app/lib/features/onboarding/provider_onboarding_screen.dart
git commit -m "feat(app): límite nombre 40 + WhatsApp con prefijo RD seleccionable"
```

---

### Task A3: App — ubicación rellena la dirección (reverse geocoding nativo)

**Files:**
- Create: `lib/domain/geo.dart` (helper puro `formatPlacemarkAddress`)
- Create: `test/domain/geo_test.dart`
- Modify: `lib/features/onboarding/consumer_onboarding_screen.dart` (`_useLocation`)

**Interfaces:**
- Produces: `String formatPlacemarkAddress({String? street, String? subLocality, String? locality, String? administrativeArea})` — une los campos no vacíos, sin duplicados, con ", ".

- [ ] **Step 1: Failing test**

Create `test/domain/geo_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/domain/geo.dart';

void main() {
  test('une campos no vacíos', () {
    expect(
      formatPlacemarkAddress(street: 'Calle 1', subLocality: 'Los Prados', locality: 'Santo Domingo', administrativeArea: 'D.N.'),
      'Calle 1, Los Prados, Santo Domingo, D.N.',
    );
  });
  test('omite vacíos y nulos', () {
    expect(formatPlacemarkAddress(street: 'Calle 1', locality: 'SD'), 'Calle 1, SD');
  });
  test('deduplica repetidos', () {
    expect(formatPlacemarkAddress(locality: 'SD', administrativeArea: 'SD'), 'SD');
  });
  test('vacío si todo nulo', () {
    expect(formatPlacemarkAddress(), '');
  });
}
```

- [ ] **Step 2: Ver fallar** — Run: `flutter test test/domain/geo_test.dart` → FAIL.

- [ ] **Step 3: Implementar `lib/domain/geo.dart`**

```dart
/// Une los componentes de una dirección (de un Placemark) en una línea legible,
/// omitiendo vacíos y duplicados consecutivos/globales. Puro y testeable.
String formatPlacemarkAddress({
  String? street,
  String? subLocality,
  String? locality,
  String? administrativeArea,
}) {
  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [street, subLocality, locality, administrativeArea]) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty || seen.contains(v.toLowerCase())) continue;
    seen.add(v.toLowerCase());
    parts.add(v);
  }
  return parts.join(', ');
}
```

- [ ] **Step 4: Ver pasar** — Run: `flutter test test/domain/geo_test.dart` → PASS.

- [ ] **Step 5: Cablear en `_useLocation`**

Importar `package:geocoding/geocoding.dart` y `../../domain/geo.dart`. Tras fijar `_lat/_lng` (dentro del `setState`, después de asignarlos) agregar, aún en el try:
```dart
      // Reverse geocoding nativo (gratis). Solo rellena si el usuario no escribió.
      if (_address.text.trim().isEmpty) {
        try {
          final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (marks.isNotEmpty && mounted) {
            final m = marks.first;
            final addr = formatPlacemarkAddress(
              street: m.street,
              subLocality: m.subLocality,
              locality: m.locality,
              administrativeArea: m.administrativeArea,
            );
            if (addr.isNotEmpty) setState(() => _address.text = addr);
          }
        } catch (_) {
          // Best-effort: si el geocoder falla, se queda solo con lat/lng.
        }
      }
```

- [ ] **Step 6: Verde** — Run: `flutter analyze && flutter test test/domain/geo_test.dart` → 0 issues, PASS.

- [ ] **Step 7: Verificación manual (device/emulador)**

Abrir el alta de consumidor → "Usar mi ubicación" → conceder permiso. Esperado: el chip "Ubicación captada ✓" aparece Y el campo Dirección se rellena con una línea legible; si ya había texto escrito, NO se pisa; sigue editable.

- [ ] **Step 8: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/domain/geo.dart app/test/domain/geo_test.dart app/lib/features/onboarding/consumer_onboarding_screen.dart
git commit -m "feat(app): la ubicación rellena la dirección (reverse geocoding nativo)"
```

---

### Task A4: Web — ubicación rellena la dirección (Nominatim)

**Files:**
- Create: `src/lib/geo.ts` (helper puro `formatNominatimAddress`)
- Create: `src/lib/geo.test.ts`
- Create: `src/lib/geo.functions.ts` (server function `reverseGeocode`)
- Modify: `src/components/consumer/ConsumerProfileForm.tsx` (`captureLocation`)

**Interfaces:**
- Produces: `formatNominatimAddress(a: Record<string,string|undefined>): string`. Server fn `reverseGeocode({lat:number,lng:number}): Promise<{address:string}>`.

- [ ] **Step 1: Failing test**

Create `src/lib/geo.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { formatNominatimAddress } from "./geo";

describe("formatNominatimAddress", () => {
  it("arma línea desde el objeto address de Nominatim", () => {
    expect(formatNominatimAddress({ road: "Calle 1", suburb: "Los Prados", city: "Santo Domingo", state: "D.N." }))
      .toBe("Calle 1, Los Prados, Santo Domingo, D.N.");
  });
  it("omite vacíos y deduplica", () => {
    expect(formatNominatimAddress({ road: "Calle 1", city: "SD", state: "SD" })).toBe("Calle 1, SD");
  });
  it("vacío si no hay campos", () => {
    expect(formatNominatimAddress({})).toBe("");
  });
});
```

- [ ] **Step 2: Ver fallar** — Run: `npx vitest run src/lib/geo.test.ts` → FAIL.

- [ ] **Step 3: Implementar `src/lib/geo.ts`**

```ts
/** Une el objeto `address` de Nominatim en una línea legible (sin vacíos ni duplicados). */
export function formatNominatimAddress(a: Record<string, string | undefined>): string {
  const order = ["road", "house_number", "suburb", "neighbourhood", "city", "town", "village", "state"];
  const seen = new Set<string>();
  const parts: string[] = [];
  for (const key of order) {
    const v = (a[key] ?? "").trim();
    if (!v || seen.has(v.toLowerCase())) continue;
    seen.add(v.toLowerCase());
    parts.push(v);
  }
  return parts.join(", ");
}
```

- [ ] **Step 4: Ver pasar** — Run: `npx vitest run src/lib/geo.test.ts` → PASS.

- [ ] **Step 5: Server function `src/lib/geo.functions.ts`**

```ts
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { formatNominatimAddress } from "./geo";

const Input = z.object({ lat: z.number(), lng: z.number() });

export const reverseGeocode = createServerFn({ method: "POST" })
  .validator((d: unknown) => Input.parse(d))
  .handler(async ({ data }) => {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${data.lat}&lon=${data.lng}`;
    const res = await fetch(url, {
      headers: { "User-Agent": "jayalo.com (soporte@jayalo.com)", "Accept-Language": "es" },
    });
    if (!res.ok) return { address: "" };
    const j = (await res.json()) as { address?: Record<string, string> };
    return { address: formatNominatimAddress(j.address ?? {}) };
  });
```
(Ajustar el import de `createServerFn` al patrón real usado en otros `*.functions.ts` del repo.)

- [ ] **Step 6: Cablear en `captureLocation`**

Importar `useServerFn` y `reverseGeocode`. En el componente: `const revGeo = useServerFn(reverseGeocode);`. Dentro del callback de éxito de `getCurrentPosition`, tras `setLat/setLng`, agregar (best-effort, solo si el campo está vacío):
```ts
        if (!address.trim()) {
          revGeo({ data: { lat: pos.coords.latitude, lng: pos.coords.longitude } })
            .then((r) => { if (r.address) setAddress(r.address); })
            .catch(() => {});
        }
```

- [ ] **Step 7: Verde** — Run: `npx tsc --noEmit && npm run lint && npx vitest run src/lib/geo.test.ts` → 0, PASS.

- [ ] **Step 8: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-main/jayalo-main
git add src/lib/geo.ts src/lib/geo.test.ts src/lib/geo.functions.ts src/components/consumer/ConsumerProfileForm.tsx
git commit -m "feat(web): la ubicación rellena la dirección vía Nominatim"
```

---

# TANDA B — OTP obligatorio + autofill (solo app)

### Task B1: OTP bloqueante en el alta de consumidor

**Files:**
- Modify: `lib/features/onboarding/consumer_onboarding_screen.dart` (`_submit`)

**Interfaces:**
- Consumes: `showOtpSheet(context, {required String phone}) → Future<bool>` (ya existe en `lib/features/verification/otp_sheet.dart`), `_composedPhone` (Task A2).

- [ ] **Step 1: Reordenar `_submit` para verificar antes de escribir**

Importar `../verification/otp_sheet.dart`. Reemplazar el cuerpo de `_submit()` por:
```dart
  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      // 1) OTP BLOQUEANTE: sin verificar el WhatsApp no se crea la cuenta.
      final verified = await showOtpSheet(context, phone: _composedPhone);
      if (!verified) {
        if (mounted) _snack('Confirma tu WhatsApp para crear la cuenta.');
        return;
      }
      // 2) Recién ahora se persiste el perfil (número ya verificado).
      await completeConsumerProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        whatsapp: _composedPhone,
        address: _address.text.trim(),
        lat: _lat,
        lng: _lng,
        termsVersion: AppConfig.termsVersion,
      );
      await roleStore.refresh();
    } catch (e) {
      if (mounted) _snack(onboardingErrorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

- [ ] **Step 2: Verde** — Run: `cd /c/Users/ac/Downloads/jayalo-app/app && flutter analyze` → 0 issues.

- [ ] **Step 3: Verificación manual (device)**

Alta de consumidor con datos válidos → "Crear mi cuenta" → aparece la hoja de OTP y llega el SMS. (a) Cerrar la hoja sin verificar → NO se crea la cuenta, aviso "Confirma tu WhatsApp…", se queda en el form. (b) Verificar con el código → se crea la cuenta y entra a `/client`. Confirmar en `account_verifications` que el número quedó `whatsapp_verified_at` y en `profiles` que el `whatsapp` guardado == el verificado.

- [ ] **Step 4: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/features/onboarding/consumer_onboarding_screen.dart
git commit -m "feat(app): OTP de WhatsApp bloqueante en el alta de consumidor"
```

---

### Task B2: `send-otp` — cuerpo SMS con formato SMS Retriever

**Files:**
- Modify: `supabase/functions/_shared/otp.ts` (nuevo `buildOtpMessage`)
- Create: `supabase/functions/_shared/otp.test.ts`
- Modify: `supabase/functions/send-otp/index.ts`

**Interfaces:**
- Produces: `buildOtpMessage(code: string, channel: "sms" | "whatsapp", smsRetrieverHash: string | null): string`.
  - SMS con hash → formato SMS Retriever: empieza con `<#>`, contiene el código, termina con el hash en su propia línea, ≤140 bytes.
  - WhatsApp (o SMS sin hash) → copy normal con vencimiento.

- [ ] **Step 1: Failing test (Deno)**

Create `supabase/functions/_shared/otp.test.ts`:
```ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std/assert/mod.ts";
import { buildOtpMessage } from "./otp.ts";

Deno.test("SMS con hash cumple formato SMS Retriever", () => {
  const msg = buildOtpMessage("123456", "sms", "FA+9qCX9VSu");
  assert(msg.startsWith("<#>"), "debe iniciar con <#>");
  assertStringIncludes(msg, "123456");
  assert(msg.trimEnd().endsWith("FA+9qCX9VSu"), "el hash debe ir al final");
  assert(new TextEncoder().encode(msg).length <= 140, "≤140 bytes");
});

Deno.test("SMS sin hash usa copy normal", () => {
  const msg = buildOtpMessage("123456", "sms", null);
  assert(!msg.startsWith("<#>"));
  assertStringIncludes(msg, "123456");
});

Deno.test("WhatsApp usa copy normal aunque haya hash", () => {
  const msg = buildOtpMessage("123456", "whatsapp", "FA+9qCX9VSu");
  assert(!msg.startsWith("<#>"));
  assertStringIncludes(msg, "Jayalo");
});
```

- [ ] **Step 2: Ver fallar** — Run: `cd /c/Users/ac/Downloads/jayalo-app/supabase/functions && deno test _shared/otp.test.ts` → FAIL. (Si `deno` no está instalado, instalarlo o correr los tests en el entorno de edge functions del proyecto.)

- [ ] **Step 3: Implementar `buildOtpMessage` en `_shared/otp.ts`**

```ts
/**
 * Cuerpo del SMS/WhatsApp del OTP. Con canal SMS y hash presente, usa el formato
 * de Google SMS Retriever (autofill Android): `<#>` al inicio, el código en el
 * cuerpo, y el hash de 11 chars en la última línea; todo ≤140 bytes.
 */
export function buildOtpMessage(
  code: string,
  channel: "sms" | "whatsapp",
  smsRetrieverHash: string | null,
): string {
  if (channel === "sms" && smsRetrieverHash) {
    return `<#> Tu codigo Jayalo es ${code}. Vence en 10 min.\n${smsRetrieverHash}`;
  }
  return `Tu código de verificación Jayalo: ${code}\n\nVence en 10 minutos.`;
}
```

- [ ] **Step 4: Ver pasar** — Run: `deno test _shared/otp.test.ts` → PASS (3 tests).

- [ ] **Step 5: Usar el builder en `send-otp/index.ts`**

Importar `buildOtpMessage` y `getOtpChannel` (ya importado). Reemplazar el bloque `await sendOtpMessage(admin, phone, \`Tu código...\`)` (líneas ~90-94) por:
```ts
    const channel = await getOtpChannel(admin);
    const hash = Deno.env.get("SMS_RETRIEVER_HASH") ?? null;
    await sendOtpMessage(admin, phone, buildOtpMessage(code, channel, hash));
    return json({ ok: true, phone, channel });
```
(Elimina la segunda llamada a `getOtpChannel` del `return` original para no consultarlo dos veces.)

- [ ] **Step 6: Documentar el secreto**

Agregar al plan de deploy (no ejecutar): el edge function necesita el secreto `SMS_RETRIEVER_HASH` con el hash de 11 chars de la app. Se obtiene en la app con `smart_auth` (Task B3, `getAppSignature()`). ⚠️ Con Play App Signing el hash efectivo en producción es el de la clave de firma de Play, no la de upload — verificar con un AAB servido por Play. Para dev, usar el hash del keystore de debug.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add supabase/functions/_shared/otp.ts supabase/functions/_shared/otp.test.ts supabase/functions/send-otp/index.ts
git commit -m "feat(edge): send-otp arma SMS con formato SMS Retriever cuando hay hash"
```

---

### Task B3: Autofill del código en Flutter (Android SMS Retriever + iOS nativo)

**Files:**
- Modify: `app/pubspec.yaml` (dependencia `smart_auth`)
- Modify: `lib/features/verification/otp_sheet.dart`

**Interfaces:**
- Consumes: `smart_auth` (`SmartAuth`), el campo `_code` existente.

- [ ] **Step 1: Agregar dependencia**

En `app/pubspec.yaml` bajo `dependencies:` agregar `smart_auth: ^3.0.1` (verificar la última versión estable en pub.dev). Run: `cd /c/Users/ac/Downloads/jayalo-app/app && flutter pub get`.

- [ ] **Step 2: iOS — hint de autofill nativo**

En `otp_sheet.dart`, al `TextField _code` (línea ~134) agregar `autofillHints: const [AutofillHints.oneTimeCode],`. **No** tocar `style`/`decoration` (mantener el tamaño casi-gigante).

- [ ] **Step 3: Android — escuchar el SMS y autollenar**

En `_OtpSheetState`, tras iniciar (`initState`/`_send`), arrancar el listener de SMS Retriever:
```dart
  final _smartAuth = SmartAuth.instance;

  Future<void> _listenForCode() async {
    final res = await _smartAuth.getSmsCode(useUserConsentApi: false); // SMS Retriever
    if (!mounted) return;
    if (res.hasData && RegExp(r'^\d{6}$').hasMatch(res.data!.code ?? '')) {
      setState(() => _code.text = res.data!.code!);
      if (!_sending && !_verifying) _verify(); // auto-verifica
    }
  }
```
Llamar `_listenForCode()` al final de `_send()` (tras arrancar el countdown). En `dispose()` agregar `_smartAuth.removeSmsListener();`. (Ajustar los nombres de API a la versión instalada de `smart_auth` — su README es la fuente; el patrón es: iniciar listener, recibir `{code}`, poblar y verificar.)

- [ ] **Step 4: Obtener el hash de firma (para el secreto del edge)**

Añadir temporalmente, en `_send()` o un botón de debug, `debugPrint(await _smartAuth.getAppSignature());` para imprimir el hash de 11 chars del build actual. Anotarlo (debug y release). Quitar el `debugPrint` antes del commit. Este hash alimenta `SMS_RETRIEVER_HASH` (Task B2, deploy).

- [ ] **Step 5: Verde** — Run: `flutter analyze` → 0 issues.

- [ ] **Step 6: Verificación manual (device real, no emulador)**

Con `SMS_RETRIEVER_HASH` puesto en el edge (deploy autorizado por el PO) y un APK firmado con el keystore correspondiente: pedir OTP → al llegar el SMS, el código se autollena y se verifica solo. Probar también el camino manual (tipear) por si el hash no coincide: debe seguir funcionando. Confirmar que el campo mantiene el tamaño gigante.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/pubspec.yaml app/pubspec.lock app/lib/features/verification/otp_sheet.dart
git commit -m "feat(app): autocompletado del código OTP (SMS Retriever Android + iOS nativo)"
```

---

# TANDA C — Responder desde el push de chat (solo Android)

> Envía un mensaje normal a la conversación (no cita un mensaje). Sin cambios de esquema.
> El envío ocurre en un **background isolate** con la app cerrada — el riesgo clave es la
> disponibilidad de la sesión de Supabase ahí. Probar C3 en device temprano.

### Task C1: `send-push` — data-message con conversation_id y acción de responder

**Files:**
- Modify: `supabase/functions/send-push/index.ts`

- [ ] **Step 1: Leer el estado actual**

Leer `supabase/functions/send-push/index.ts` para ubicar dónde se arma el payload FCM de los push de tipo chat (`message_new`) y cómo se derivan `link`/`notification_count`.

- [ ] **Step 2: Añadir datos de respuesta al payload de chat**

Para los push de chat, incluir en `data` (que ya lleva `link`): `conversation_id` (extraído del link `/messages?c=<id>` o de la fila de notificación), y `kind: "chat"`. Enviar como **data-message** (mover `title`/`body` de `notification` a `data` para los de chat) para que la app controle el pintado en Android. Mantener el resto de tipos igual. Conservar `notification_count`/badge (send-push v15) — no regresarlo.

- [ ] **Step 3: Verificación**

`deno check supabase/functions/send-push/index.ts` (o el check del proyecto). Verificación funcional real ocurre en C2/C3 con el device. Deploy autorizado por el PO.

- [ ] **Step 4: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add supabase/functions/send-push/index.ts
git commit -m "feat(edge): send-push manda data-message de chat con conversation_id"
```

---

### Task C2: App — notificación local con acción "Responder"

**Files:**
- Modify: `app/pubspec.yaml` (`flutter_local_notifications`)
- Create: `lib/push/chat_notifications.dart`
- Modify: `lib/push/push_service.dart`

**Interfaces:**
- Produces: `showChatReplyNotification({required String conversationId, required String title, required String body})`, `const kChatChannelId`, `const kReplyActionId`, `const kReplyInputKey`.

- [ ] **Step 1: Dependencia**

`app/pubspec.yaml` → `flutter_local_notifications: ^19.0.0` (verificar última). `flutter pub get`.

- [ ] **Step 2: `lib/push/chat_notifications.dart` — plugin + canal + acción**

```dart
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const kChatChannelId = 'chat_replies';
const kReplyActionId = 'REPLY';
const kReplyInputKey = 'reply_text';

final flnp = FlutterLocalNotificationsPlugin();

Future<void> initChatNotifications(
  void Function(NotificationResponse) onResponse,
) async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flnp.initialize(
    const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
  );
}

Future<void> showChatReplyNotification({
  required String conversationId,
  required String title,
  required String body,
}) async {
  final details = AndroidNotificationDetails(
    kChatChannelId, 'Mensajes de chat',
    importance: Importance.high, priority: Priority.high,
    actions: <AndroidNotificationAction>[
      const AndroidNotificationAction(
        kReplyActionId, 'Responder',
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(label: 'Escribe tu respuesta'),
        ],
        allowGeneratedReplies: true,
        showsUserInterface: false,
      ),
    ],
  );
  await flnp.show(
    conversationId.hashCode & 0x7fffffff, // id estable por conversación
    title, body,
    NotificationDetails(android: details),
    payload: jsonEncode({'conversation_id': conversationId}),
  );
}
```

- [ ] **Step 3: Pintar la notificación al recibir push de chat**

En `push_service.dart`: en `FirebaseMessaging.onMessage.listen` y en el handler `onBackgroundMessage`, si `message.data['kind'] == 'chat'`, llamar `showChatReplyNotification(conversationId: message.data['conversation_id'], title: message.data['title'] ?? 'Nuevo mensaje', body: message.data['body'] ?? '')`. Registrar `FirebaseMessaging.onBackgroundMessage(_fcmBackground)` (handler top-level que llama `initChatNotifications`/`showChatReplyNotification`). Llamar `initChatNotifications(_onNotifResponse)` dentro de `initPush`.

- [ ] **Step 4: Verde** — `flutter analyze` → 0 issues.

- [ ] **Step 5: Verificación manual (device)**

Con el device en background, provocar un mensaje de chat. Esperado: la notificación aparece con el botón "Responder" y, al tocarlo, un campo de texto inline en la sombra. (El envío se implementa en C3 — aquí solo se valida el pintado y el input.)

- [ ] **Step 6: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/pubspec.yaml app/pubspec.lock app/lib/push/chat_notifications.dart app/lib/push/push_service.dart
git commit -m "feat(app): notificación de chat con acción de responder inline (Android)"
```

---

### Task C3: App — enviar la respuesta desde el background isolate

**Files:**
- Modify: `lib/push/chat_notifications.dart` (`notificationBackgroundHandler`)
- Modify: `lib/main.dart` (o donde se inicializa Supabase) para exponer init reusable

**Interfaces:**
- Consumes: `kReplyActionId`, `kReplyInputKey`, la config de Supabase (`AppConfig`/`supa`).

- [ ] **Step 1: Handler top-level de respuesta en background**

En `chat_notifications.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  if (r.actionId != kReplyActionId) return;
  final text = (r.input ?? '').trim();
  if (text.isEmpty) return;
  final payload = r.payload == null
      ? <String, dynamic>{}
      : jsonDecode(r.payload!) as Map<String, dynamic>;
  final conversationId = payload['conversation_id'] as String?;
  if (conversationId == null) return;

  // El isolate de background arranca en frío: hay que reinicializar Supabase.
  // supabase_flutter restaura la sesión persistida (SharedPreferences) al init.
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  final client = Supabase.instance.client;
  final session = client.auth.currentSession;
  if (session == null || session.isExpired) {
    await flnp.show(
      conversationId.hashCode & 0x7fffffff, 'No se pudo enviar', 'Abre la app para responder',
      const NotificationDetails(android: AndroidNotificationDetails(kChatChannelId, 'Mensajes de chat')),
    );
    return;
  }
  try {
    await client.from('conversation_messages').insert({
      'conversation_id': conversationId,
      'sender_id': client.auth.currentUser!.id,
      'body': text,
    });
    // Confirmación: reemplaza la notificación por "Enviado ✓".
    await flnp.show(
      conversationId.hashCode & 0x7fffffff, 'Respondiste', text,
      const NotificationDetails(android: AndroidNotificationDetails(kChatChannelId, 'Mensajes de chat')),
    );
  } catch (_) {
    await flnp.show(
      conversationId.hashCode & 0x7fffffff, 'No se pudo enviar', 'Abre la app para reintentar',
      const NotificationDetails(android: AndroidNotificationDetails(kChatChannelId, 'Mensajes de chat')),
    );
  }
}
```
⚠️ **Verificar el shape real del INSERT** contra `data/repos.dart` (líneas ~1270-1350, cómo el chat envía un mensaje hoy: nombres de columnas `sender_id`/`body`/etc. y si hay una RPC de envío en vez de INSERT directo). Usar el MISMO camino que el chat para no divergir (RLS/triggers).

- [ ] **Step 2: Verde** — `flutter analyze` → 0 issues.

- [ ] **Step 3: Verificación manual (device, app CERRADA)**

Cerrar la app por completo (swipe del recientes). Provocar un mensaje de chat → responder desde la notificación. Esperado: el texto se inserta en `conversation_messages` (verlo en la conversación al abrir), y la notificación cambia a "Respondiste ✓". Probar el caso sin sesión (logout) → "Abre la app para responder", sin perder el flujo.

- [ ] **Step 4: Commit**

```bash
cd /c/Users/ac/Downloads/jayalo-app
git add app/lib/push/chat_notifications.dart app/lib/main.dart
git commit -m "feat(app): responder el chat desde la notificación (background isolate)"
```

---

## Self-review (cobertura del spec)

- **A1 nombre 40 + charset:** Tasks A1 (web), A2 (app). ✅
- **A2 WhatsApp prefijo RD:** Tasks A1 (web), A2 (app). ✅
- **A3 ubicación→dirección:** Task A3 (app nativo), A4 (web Nominatim). ✅
- **B OTP bloqueante:** Task B1. ✅
- **B autofill (SMS Retriever + iOS):** Tasks B2 (edge body+hash), B3 (Flutter). ✅
- **C responder desde push (Android):** Tasks C1 (edge), C2 (pintado+acción), C3 (envío background). ✅
- **No-objetivos respetados:** sin columna `reply_to_message_id`; sin iOS/web para push reply; solo-RD por diseño. ✅

## Notas de ejecución

- **Orden:** A1→A2→A3→A4→B1→B2→B3→C1→C2→C3. A es independiente; B depende de A2 (`_composedPhone`); C es autónoma.
- **Deploys de edge (`send-otp`, `send-push`) y el secreto `SMS_RETRIEVER_HASH`:** los ejecuta/autoriza el PO — no desplegar sin confirmación.
- **Pruebas de device:** B3 y C2/C3 requieren APK firmado en device real (no emulador) por SMS Retriever y background isolate. Recordar el gotcha de la app: `flutter build apk --release` recompila; `flutter install` no.
- **Push:** commits por task, sin `git push` — el PO revisa y decide.
