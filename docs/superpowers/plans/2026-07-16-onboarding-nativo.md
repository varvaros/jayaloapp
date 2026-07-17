# Onboarding nativo (consumidor y proveedor) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Registro 100% nativo en jayalo-app (gate post-login, selector de rol, alta de
consumidor y de proveedor) + OTP diferido por SMS + los 3 fixes del bug de dinero, contra el
backend existente sin tocar la web ni el Worker.

**Architecture:** El alta de proveedor es UNA llamada a la RPC atómica
`complete_provider_onboarding` (ADR-0029, jayalo-main); el consumidor es un upsert único de
`profiles`. El OTP corre en dos Edge Functions nuevas (`send-otp`/`verify-otp`, ADR-0030) que
replican el hardening del Worker. La app solo recolecta datos y mapea errores por slug.

**Tech Stack:** Flutter estable (Dart 3), `supabase_flutter`, `geolocator` + `geocoding`,
`image_picker`, `go_router`. Backend: SQL (Postgres) + Edge Functions Deno.

**Spec:** `docs/superpowers/specs/2026-07-16-onboarding-nativo-design.md` (rev. 2, validado PO).

## Global Constraints

- Repos: app en `C:\Users\ac\Downloads\jayalo-app` (git local, SIN remote — no intentar push);
  la migración SQL y `database.ts` en `C:\Users\ac\Downloads\jayalo-main\jayalo-main` (push OK).
- Supabase proyecto único: `mfaiklvobnvgusbcssbx` (URL/publishable key ya en
  `app/lib/core/config.dart`).
- **La web y el Worker NO se tocan** (solo se AGREGA la migración y las Edge Functions).
- Migraciones: aplicar vía MCP de Supabase **con confirmación nombrada del PO por migración**;
  si el MCP no está autorizado en la sesión, el PO la aplica en el SQL editor del dashboard.
  `list_migrations` es la fuente de verdad de prod.
- RPCs nuevas: REVOKE explícito `FROM PUBLIC, anon` + GRANT a `authenticated` (Supabase Cloud
  auto-otorga EXECUTE al recrear — regla del proyecto).
- Secretos de Edge Functions: `npx supabase secrets set` **desde archivo/env-file por CLI**,
  nunca pegar JSON/valores en el dashboard (gotcha FCM_SERVICE_ACCOUNT).
- Copy: español dominicano. OTP: decir **SMS**, nunca prometer WhatsApp
  (`app_settings.otp_channel` = `'sms'` hoy).
- Regla de rol: **elegir rol NO escribe `account_type`** — solo el cierre de cada flujo escribe
  (lección `choose-role.tsx:67-72`).
- Gate de cada task de app: `flutter analyze` en 0 + `flutter test` verde antes del commit.
  (Ejecutar dentro de `app/`; Flutter en `C:\dev\flutter\bin`.)
- Commits: `feat:`/`fix:`/`docs:` + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Prerrequisitos [PO]

1. **Aplicar la migración de la Task 1** (confirmación nombrada; MCP o dashboard).
2. **Secretos Twilio para Edge Functions** (Task 2, paso guiado): los valores ya existen como
   secretos del Worker (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_SMS_FROM`); copiarlos
   a Supabase con `npx supabase secrets set --env-file <archivo temporal>` (CLI ya logueado).
3. Redmi por USB para las verificaciones en device (Tasks 6-10).

---

## Estructura de archivos (lo nuevo/modificado)

```
jayalo-main/ (repo web — solo aditivo)
  supabase/migrations/20260717000000_complete_provider_onboarding.sql   # Task 1
  scripts/db-security-check.sql                                        # Task 1 (check #11)
  src/integrations/supabase/database.ts                                # Task 1 (ManualFunctions)

jayalo-app/
  supabase/functions/_shared/otp.ts            # Task 2 (lógica compartida)
  supabase/functions/send-otp/index.ts         # Task 2
  supabase/functions/verify-otp/index.ts       # Task 2
  app/lib/domain/phone.dart                    # Task 3 (port de phone.ts)
  app/lib/domain/onboarding_errors.dart        # Task 3 (slugs → copy)
  app/lib/domain/catalog.dart                  # Task 3 (categorías, generado)
  app/lib/data/repos.dart                      # Task 4 (funciones nuevas)
  app/lib/core/session_state.dart              # Task 5 (RoleStore + redirectTarget)
  app/lib/core/router.dart                     # Task 5 (gate + rutas onboarding)
  app/lib/features/onboarding/gate_screen.dart          # Task 5
  app/lib/features/onboarding/choose_role_screen.dart   # Task 5
  app/lib/features/onboarding/consumer_onboarding_screen.dart  # Task 6
  app/lib/features/onboarding/provider_onboarding_screen.dart  # Task 7
  app/lib/features/verification/otp_sheet.dart           # Task 8
  app/lib/features/verification/verify_banner.dart       # Task 8
  app/lib/features/client/create_request_screen.dart     # Task 8 (banner)
  app/lib/features/settings/settings_screen.dart         # Task 8 (entradas)
  app/lib/features/provider/my_offers_screen.dart        # Task 9 (fixes dinero)
  app/lib/features/shell/home_shell.dart                  # Task 5 (tabs por rol)
  app/test/phone_test.dart                     # Task 3
  app/test/onboarding_errors_test.dart         # Task 3
  app/test/redirect_target_test.dart           # Task 5
  app/pubspec.yaml                             # Task 6/7 (geolocator, geocoding, image_picker)
```

---

### Task 1: RPC `complete_provider_onboarding` (jayalo-main)

**Files:**
- Create: `jayalo-main/supabase/migrations/20260717000000_complete_provider_onboarding.sql`
- Modify: `jayalo-main/scripts/db-security-check.sql` (check #11 al final)
- Modify: `jayalo-main/src/integrations/supabase/database.ts` (ManualFunctions)

**Interfaces:**
- Produces: RPC `complete_provider_onboarding(_first_name text, _last_name text, _phone text,
  _business jsonb, _terms_version text) → jsonb {ok:bool, already:bool, business_id:uuid}`.
  Excepciones con mensaje EXACTO en `{not_authenticated, invalid_business, whatsapp_taken,
  phone_taken, rnc_taken, duplicate}` — la Task 4 mapea esos slugs.
- `_business` = mismo shape que `pending_business` del trigger (`business_type, offers,
  category_id, category_ids[], rubros[], name, is_wholesale, rnc, description, whatsapp,
  country, city, sector, address, profession, experience_years, logo_url, owner_photo_url`).

- [ ] **Step 1: Escribir la migración**

```sql
-- Alta de proveedor atómica e idempotente para clientes nativos (ADR-0029).
-- Reemplaza (para la app; la web migra después) las 5 escrituras cliente del
-- flujo authed de ProviderSignupWizard. Errores con slug estable para que el
-- cliente mapee copy sin parsear mensajes de Postgres.

CREATE OR REPLACE FUNCTION public.complete_provider_onboarding(
  _first_name text,
  _last_name text,
  _phone text,
  _business jsonb,
  _terms_version text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_phone text;
  v_existing uuid;
  v_biz_id uuid;
  v_category text;
  v_cat_ids text[];
  v_cat text;
  v_pos int;
  v_rubro text;
  v_rubro_uuid uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF _business IS NULL OR jsonb_typeof(_business) <> 'object'
     OR COALESCE(_business ->> 'name', '') = '' THEN
    RAISE EXCEPTION 'invalid_business';
  END IF;

  -- Idempotencia: si ya hay un negocio real, reintentos (timeouts móviles) no duplican.
  SELECT id INTO v_existing
    FROM public.provider_businesses
   WHERE user_id = v_uid AND COALESCE(name, '') <> ''
   LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'already', true, 'business_id', v_existing);
  END IF;

  v_phone := NULLIF(regexp_replace(COALESCE(_phone, ''), '[^0-9+]', '', 'g'), '');

  -- Unicidad con mensaje específico ANTES de escribir nada.
  IF COALESCE(_business ->> 'whatsapp', '') <> '' AND public.is_whatsapp_taken(
       regexp_replace(_business ->> 'whatsapp', '\D', '', 'g'), v_uid) THEN
    RAISE EXCEPTION 'whatsapp_taken';
  END IF;
  IF COALESCE(_business ->> 'rnc', '') <> '' AND EXISTS (
       SELECT 1 FROM public.provider_businesses
        WHERE rnc = _business ->> 'rnc' AND user_id <> v_uid) THEN
    RAISE EXCEPTION 'rnc_taken';
  END IF;

  BEGIN
    INSERT INTO public.profiles (user_id, email, first_name, last_name, phone,
        account_type, business_name, terms_accepted_at, terms_version)
    VALUES (v_uid, (SELECT email FROM auth.users WHERE id = v_uid),
        NULLIF(_first_name, ''), NULLIF(_last_name, ''), v_phone,
        'provider', _business ->> 'name', now(), _terms_version)
    ON CONFLICT (user_id) DO UPDATE SET
      first_name = EXCLUDED.first_name,
      last_name = EXCLUDED.last_name,
      phone = EXCLUDED.phone,
      account_type = 'provider',
      business_name = EXCLUDED.business_name,
      terms_accepted_at = EXCLUDED.terms_accepted_at,
      terms_version = EXCLUDED.terms_version;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'phone_taken';
  END;

  -- Categorías: misma validación que handle_new_user (20260711150000).
  v_category := COALESCE(_business ->> 'category_id', '');
  IF v_category <> '' AND NOT public.is_valid_category_id(v_category) THEN
    v_category := '';
  END IF;
  v_cat_ids := ARRAY[]::text[];
  IF jsonb_typeof(_business -> 'category_ids') = 'array' THEN
    SELECT ARRAY(
      SELECT x FROM jsonb_array_elements_text(_business -> 'category_ids') t(x)
      WHERE public.is_valid_category_id(x)
      LIMIT 2
    ) INTO v_cat_ids;
  END IF;
  IF array_length(v_cat_ids, 1) IS NULL AND v_category <> '' THEN
    v_cat_ids := ARRAY[v_category];
  END IF;
  IF v_category = '' AND array_length(v_cat_ids, 1) >= 1 THEN
    v_category := v_cat_ids[1];
  END IF;

  -- Negocio: claim del placeholder vacío si existiera; si no, insert.
  SELECT id INTO v_biz_id
    FROM public.provider_businesses
   WHERE user_id = v_uid AND COALESCE(name, '') = ''
   LIMIT 1;

  BEGIN
    IF v_biz_id IS NOT NULL THEN
      UPDATE public.provider_businesses SET
        business_type = COALESCE(_business ->> 'business_type', 'informal'),
        offers = COALESCE(_business ->> 'offers', 'servicios'),
        category_id = v_category,
        name = _business ->> 'name',
        rnc = COALESCE(_business ->> 'rnc', ''),
        description = COALESCE(_business ->> 'description', ''),
        whatsapp = COALESCE(_business ->> 'whatsapp', ''),
        country = COALESCE(_business ->> 'country', ''),
        city = COALESCE(_business ->> 'city', ''),
        sector = COALESCE(_business ->> 'sector', ''),
        address = COALESCE(_business ->> 'address', ''),
        profession = COALESCE(_business ->> 'profession', ''),
        experience_years = NULLIF(_business ->> 'experience_years', '')::int,
        logo_url = COALESCE(_business ->> 'logo_url', ''),
        owner_photo_url = COALESCE(_business ->> 'owner_photo_url', ''),
        is_wholesale = COALESCE((_business ->> 'is_wholesale')::boolean, false)
      WHERE id = v_biz_id;
    ELSE
      INSERT INTO public.provider_businesses (
        user_id, business_type, offers, category_id,
        name, rnc, description, whatsapp,
        country, city, sector, address,
        profession, experience_years,
        logo_url, owner_photo_url, is_wholesale
      ) VALUES (
        v_uid,
        COALESCE(_business ->> 'business_type', 'informal'),
        COALESCE(_business ->> 'offers', 'servicios'),
        v_category,
        _business ->> 'name',
        COALESCE(_business ->> 'rnc', ''),
        COALESCE(_business ->> 'description', ''),
        COALESCE(_business ->> 'whatsapp', ''),
        COALESCE(_business ->> 'country', ''),
        COALESCE(_business ->> 'city', ''),
        COALESCE(_business ->> 'sector', ''),
        COALESCE(_business ->> 'address', ''),
        COALESCE(_business ->> 'profession', ''),
        NULLIF(_business ->> 'experience_years', '')::int,
        COALESCE(_business ->> 'logo_url', ''),
        COALESCE(_business ->> 'owner_photo_url', ''),
        COALESCE((_business ->> 'is_wholesale')::boolean, false)
      )
      RETURNING id INTO v_biz_id;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate';
  END;

  -- Categorías (máx 2): resync idempotente.
  DELETE FROM public.provider_business_categories WHERE business_id = v_biz_id;
  IF array_length(v_cat_ids, 1) >= 1 THEN
    v_pos := 0;
    FOREACH v_cat IN ARRAY v_cat_ids LOOP
      INSERT INTO public.provider_business_categories (business_id, category_id, is_primary, position)
      VALUES (v_biz_id, v_cat, v_pos = 0, v_pos)
      ON CONFLICT DO NOTHING;
      v_pos := v_pos + 1;
    END LOOP;
  END IF;

  -- Rubros: validados contra las categorías elegidas, igual que el trigger.
  DELETE FROM public.provider_business_rubros WHERE business_id = v_biz_id;
  IF jsonb_typeof(_business -> 'rubros') = 'array' THEN
    FOR v_rubro IN SELECT jsonb_array_elements_text(_business -> 'rubros') LOOP
      BEGIN
        v_rubro_uuid := v_rubro::uuid;
      EXCEPTION WHEN others THEN
        v_rubro_uuid := NULL;
      END;
      IF v_rubro_uuid IS NOT NULL THEN
        INSERT INTO public.provider_business_rubros (business_id, category_id, rubro_id)
        SELECT v_biz_id, r.category_id, r.id
          FROM public.rubros r
         WHERE r.id = v_rubro_uuid AND r.category_id = ANY(v_cat_ids)
        ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  -- Wallet en la MISMA transacción (el guard ADR-0010 permite: current_user = postgres).
  INSERT INTO public.provider_wallets (user_id, balance)
  VALUES (v_uid, 0)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'already', false, 'business_id', v_biz_id);
END;
$$;

-- Grants: gotcha del auto-EXECUTE de Supabase Cloud — REVOKE explícito obligatorio.
REVOKE ALL ON FUNCTION public.complete_provider_onboarding(text, text, text, jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_provider_onboarding(text, text, text, jsonb, text)
  TO authenticated;
```

- [ ] **Step 2: Check #11 en `scripts/db-security-check.sql`**

Añadir al final, siguiendo el formato de los checks existentes (query que debe devolver 0 filas):

```sql
-- #11: complete_provider_onboarding no debe ser ejecutable por anon
SELECT p.proname, r.rolname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS a
JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname = 'public'
  AND p.proname = 'complete_provider_onboarding'
  AND r.rolname = 'anon'
  AND a.privilege_type = 'EXECUTE';
```

- [ ] **Step 3: Declarar la RPC en `database.ts` (ManualFunctions)**

En `jayalo-main/src/integrations/supabase/database.ts`, dentro de `ManualFunctions`, añadir
(mismo estilo que las existentes):

```ts
complete_provider_onboarding: {
  Args: {
    _first_name: string;
    _last_name: string;
    _phone: string;
    _business: Json;
    _terms_version: string;
  };
  Returns: Json;
};
```

Run: `cd jayalo-main && npx tsc --noEmit` → 0 errores.

- [ ] **Step 4: Aplicar a prod [PO] y verificar**

Con confirmación nombrada del PO: aplicar vía MCP `apply_migration` (o SQL editor). Verificar
SIN residuo con transacción de prueba (patrón del proyecto), vía `execute_sql`:

```sql
BEGIN;
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"<uuid de la cuenta QA>","role":"authenticated"}';
SELECT public.complete_provider_onboarding(
  'QA','Onboarding','+18090000001',
  '{"name":"Negocio QA Onboarding","business_type":"informal","offers":"productos",
    "category_ids":["<categoria válida>"],"rubros":[],"whatsapp":"+18090000001",
    "city":"Santo Domingo","sector":"","country":"República Dominicana","address":"",
    "description":"","rnc":"","profession":"","experience_years":"","logo_url":"",
    "owner_photo_url":"","is_wholesale":false}'::jsonb,
  '2.0');
-- Segunda llamada: debe devolver already=true con el MISMO business_id
SELECT public.complete_provider_onboarding('QA','Onboarding','+18090000001',
  '{"name":"Negocio QA Onboarding"}'::jsonb, '2.0');
-- Comprobar wallet y categorías creadas
SELECT balance FROM provider_wallets WHERE user_id = '<uuid>';
ROLLBACK;
```

Expected: primera llamada `ok=true, already=false`; segunda `already=true` mismo id; wallet
`balance=0`; y tras `ROLLBACK`, cero filas nuevas (verificar conteos). Correr también el
check #11 (0 filas) y `get_advisors('security')` (sin hallazgos nuevos vs baseline).

- [ ] **Step 5: Commit + push (jayalo-main)**

```bash
git add supabase/migrations/20260717000000_complete_provider_onboarding.sql scripts/db-security-check.sql src/integrations/supabase/database.ts
git commit -m "feat(db): RPC atomica complete_provider_onboarding (ADR-0029) + check #11"
git push
```

---

### Task 2: Edge Functions `send-otp` / `verify-otp`

**Files:**
- Create: `jayalo-app/supabase/functions/_shared/otp.ts`
- Create: `jayalo-app/supabase/functions/send-otp/index.ts`
- Create: `jayalo-app/supabase/functions/verify-otp/index.ts`

**Interfaces:**
- Consumes: tabla `account_verifications` (existente), RPC `try_consume_rate_limit`,
  `app_settings.otp_channel` / `twilio_whatsapp_from`, API REST de Twilio.
- Produces (contrato para la Task 4):
  - `POST /functions/v1/send-otp` body `{ "phone": "+1809...", "business_id"?: "<uuid>" }`
    → 200 `{ ok: true, phone }` | 4xx `{ error: "<mensaje en español>" }`.
  - `POST /functions/v1/verify-otp` body `{ "code": "123456", "business_id"?: "<uuid>" }`
    → 200 `{ ok: true, phone, business_badge_verified: bool }` | 4xx `{ error }`.
  - Ambas requieren `Authorization: Bearer <access_token>` (verify_jwt del gateway + getUser).

⚠️ **No usar `owns_business` vía RPC aquí**: con el cliente service-role `auth.uid()` es NULL y
devolvería false siempre. La propiedad se valida con SELECT directo (service role bypassea RLS).

- [ ] **Step 1: `_shared/otp.ts`** — lógica portada de `whatsapp-otp.functions.ts` +
  `otpChannel.ts` + `phone.ts` de jayalo-main (misma semántica, mismos límites):

```ts
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const OTP_TTL_MS = 10 * 60 * 1000;
export const MAX_ATTEMPTS = 5;
export const RESEND_COOLDOWN_MS = 60 * 1000;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01/Accounts";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/** userId del Bearer token, o null. */
export async function requireUser(req: Request, admin: SupabaseClient): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const { data, error } = await admin.auth.getUser(auth.slice(7));
  if (error || !data?.user) return null;
  return data.user.id;
}

/** El negocio debe ser del usuario (anti-IDOR; SELECT directo, no owns_business). */
export async function ownsBusiness(
  admin: SupabaseClient, userId: string, businessId: string,
): Promise<boolean> {
  const { data } = await admin
    .from("provider_businesses").select("user_id").eq("id", businessId).maybeSingle();
  return data?.user_id === userId;
}

// ── ports 1:1 de jayalo-main (phone.ts / otpChannel.ts) ──
export function normalizePhone(raw: string): string {
  const t = raw.replace(/[^\d+]/g, "");
  if (!t) return "";
  if (t.startsWith("+")) return t;
  if (t.length === 10) return `+1${t}`;
  return t;
}
export function normalizePhoneStrict(raw: string): string {
  let v = normalizePhone(raw);
  if (!v) throw new Error("Teléfono inválido");
  if (!v.startsWith("+")) v = "+" + v;
  if (!/^\+\d{8,15}$/.test(v)) throw new Error("Teléfono inválido (formato E.164)");
  return v;
}
export function toWhatsappDigits(raw: string): string {
  return normalizePhone(raw).replace(/^\+/, "");
}
export function sameWhatsappNumber(a?: string | null, b?: string | null): boolean {
  if (!a || !b) return false;
  const da = toWhatsappDigits(a), db = toWhatsappDigits(b);
  return da.length > 0 && da === db;
}
export type OtpChannel = "sms" | "whatsapp";
export function parseOtpChannel(value: unknown): OtpChannel {
  let v: unknown = value;
  if (v && typeof v === "object" && "channel" in (v as object)) v = (v as { channel: unknown }).channel;
  return typeof v === "string" && v.trim().toLowerCase() === "sms" ? "sms" : "whatsapp";
}
export function buildOtpAddresses(channel: OtpChannel, fromRaw: string, toE164: string) {
  const bareFrom = fromRaw.replace(/^whatsapp:/i, "");
  const bareTo = toE164.replace(/^whatsapp:/i, "");
  return channel === "sms"
    ? { from: bareFrom, to: bareTo }
    : { from: `whatsapp:${bareFrom}`, to: `whatsapp:${bareTo}` };
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function getOtpChannel(admin: SupabaseClient): Promise<OtpChannel> {
  const { data } = await admin
    .from("app_settings").select("value").eq("key", "otp_channel").maybeSingle();
  return parseOtpChannel(data?.value ?? Deno.env.get("OTP_CHANNEL"));
}

export async function sendOtpMessage(admin: SupabaseClient, to: string, body: string) {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  if (!accountSid || !authToken) throw new Error("Twilio no está configurado");
  const channel = await getOtpChannel(admin);
  const { data } = await admin
    .from("app_settings").select("value").eq("key", "twilio_whatsapp_from").maybeSingle();
  const base = ((data?.value as Record<string, unknown> | null)?.from as string | undefined) ||
    Deno.env.get("TWILIO_WHATSAPP_FROM") || "+14155238886";
  const fromRaw = channel === "sms" ? (Deno.env.get("TWILIO_SMS_FROM") || base) : base;
  const { from, to: toAddr } = buildOtpAddresses(channel, fromRaw, to);
  const resp = await fetch(`${TWILIO_API_BASE}/${accountSid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ To: toAddr, From: from, Body: body }),
  });
  const j = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`Twilio error [${resp.status}] ${j?.message ?? j?.code ?? "desconocido"}`);
}
```

- [ ] **Step 2: `send-otp/index.ts`** — mismo orden de guards que el Worker
  (rate limit → cooldown → **persistir ANTES de enviar** → Twilio):

```ts
import {
  adminClient, json, requireUser, ownsBusiness, normalizePhoneStrict,
  sha256Hex, OTP_TTL_MS, RESEND_COOLDOWN_MS, sendOtpMessage,
} from "../_shared/otp.ts";

Deno.serve(async (req) => {
  try {
    const admin = adminClient();
    const userId = await requireUser(req, admin);
    if (!userId) return json({ error: "No autenticado" }, 401);

    const { phone: rawPhone, business_id: businessId } = await req.json().catch(() => ({}));
    if (typeof rawPhone !== "string" || rawPhone.trim().length < 7) {
      return json({ error: "Teléfono inválido" }, 400);
    }
    let phone: string;
    try { phone = normalizePhoneStrict(rawPhone); } catch (e) {
      return json({ error: (e as Error).message }, 400);
    }
    if (businessId && !(await ownsBusiness(admin, userId, businessId))) {
      return json({ error: "No autorizado para este negocio" }, 403);
    }

    // Tope por usuario (anti toll-fraud), fail-open si el limiter falla.
    const { data: allowed, error: rlErr } = await admin.rpc("try_consume_rate_limit", {
      _bucket: `wa_otp_send:${userId}`, _max: 5, _window_seconds: 900,
    });
    if (!rlErr && allowed === false) {
      return json({ error: "Enviaste demasiados códigos. Espera unos minutos e intenta de nuevo." }, 429);
    }

    let q = admin.from("account_verifications")
      .select("id, whatsapp_last_sent_at").eq("user_id", userId);
    q = businessId ? q.eq("business_id", businessId) : q.is("business_id", null);
    const { data: existing } = await q.maybeSingle();
    if (existing?.whatsapp_last_sent_at) {
      const last = new Date(existing.whatsapp_last_sent_at).getTime();
      if (Date.now() - last < RESEND_COOLDOWN_MS) {
        const wait = Math.ceil((RESEND_COOLDOWN_MS - (Date.now() - last)) / 1000);
        return json({ error: `Espera ${wait}s antes de reenviar el código` }, 429);
      }
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const { error: upErr } = await admin.from("account_verifications").upsert(
      {
        user_id: userId,
        business_id: businessId ?? null,
        whatsapp_e164: phone,
        whatsapp_otp_hash: await sha256Hex(code),
        whatsapp_otp_expires_at: new Date(Date.now() + OTP_TTL_MS).toISOString(),
        whatsapp_attempts: 0,
        whatsapp_last_sent_at: new Date().toISOString(),
      },
      { onConflict: businessId ? "user_id,business_id" : "user_id" },
    );
    if (upErr) return json({ error: upErr.message }, 500);

    await sendOtpMessage(admin, phone,
      `Tu código de verificación Jayalo: ${code}\n\nVence en 10 minutos.`);
    return json({ ok: true, phone });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Error inesperado" }, 500);
  }
});
```

- [ ] **Step 3: `verify-otp/index.ts`** — intentos, expiración, sello y espejo del badge:

```ts
import {
  adminClient, json, requireUser, ownsBusiness, sameWhatsappNumber,
  sha256Hex, MAX_ATTEMPTS,
} from "../_shared/otp.ts";

Deno.serve(async (req) => {
  try {
    const admin = adminClient();
    const userId = await requireUser(req, admin);
    if (!userId) return json({ error: "No autenticado" }, 401);

    const { code, business_id: businessId } = await req.json().catch(() => ({}));
    if (typeof code !== "string" || !/^\d{6}$/.test(code.trim())) {
      return json({ error: "Código inválido" }, 400);
    }
    if (businessId && !(await ownsBusiness(admin, userId, businessId))) {
      return json({ error: "No autorizado para este negocio" }, 403);
    }

    let q = admin.from("account_verifications")
      .select("id, whatsapp_otp_hash, whatsapp_otp_expires_at, whatsapp_attempts, whatsapp_e164")
      .eq("user_id", userId);
    q = businessId ? q.eq("business_id", businessId) : q.is("business_id", null);
    const { data: row } = await q.maybeSingle();

    if (!row?.whatsapp_otp_hash) return json({ error: "No hay código pendiente. Envía uno nuevo." }, 400);
    if (row.whatsapp_otp_expires_at && new Date(row.whatsapp_otp_expires_at).getTime() < Date.now()) {
      return json({ error: "El código expiró. Envía uno nuevo." }, 400);
    }
    if ((row.whatsapp_attempts ?? 0) >= MAX_ATTEMPTS) {
      return json({ error: "Demasiados intentos. Envía un código nuevo." }, 400);
    }
    if (await sha256Hex(code.trim()) !== row.whatsapp_otp_hash) {
      await admin.from("account_verifications")
        .update({ whatsapp_attempts: (row.whatsapp_attempts ?? 0) + 1 }).eq("id", row.id);
      return json({ error: "Código incorrecto" }, 400);
    }

    const verifiedAt = new Date().toISOString();
    await admin.from("account_verifications").update({
      whatsapp_verified_at: verifiedAt,
      whatsapp_otp_hash: null,
      whatsapp_otp_expires_at: null,
      whatsapp_attempts: 0,
    }).eq("id", row.id);

    // Espejo del badge SOLO si el número verificado es el público del negocio
    // (semántica exacta de la web, whatsapp-otp.functions.ts L255-268).
    let businessBadgeVerified = false;
    if (businessId) {
      const { data: biz } = await admin.from("provider_businesses")
        .select("whatsapp").eq("id", businessId).maybeSingle();
      businessBadgeVerified = sameWhatsappNumber(row.whatsapp_e164, biz?.whatsapp ?? null);
      await admin.from("provider_businesses")
        .update({ whatsapp_verified_at: businessBadgeVerified ? verifiedAt : null })
        .eq("id", businessId);
    }
    return json({ ok: true, phone: row.whatsapp_e164, business_badge_verified: businessBadgeVerified });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Error inesperado" }, 500);
  }
});
```

- [ ] **Step 4: Secretos [PO] + deploy**

```bash
# Archivo temporal FUERA del repo (borrar después) con:
#   TWILIO_ACCOUNT_SID=...  TWILIO_AUTH_TOKEN=...  TWILIO_SMS_FROM=...
npx supabase secrets set --env-file %TEMP%\twilio.env --project-ref mfaiklvobnvgusbcssbx
npx supabase functions deploy send-otp --project-ref mfaiklvobnvgusbcssbx
npx supabase functions deploy verify-otp --project-ref mfaiklvobnvgusbcssbx
```

- [ ] **Step 5: Verificar contra prod (sin device)**

Con un access token de la cuenta QA (obtenible con un mini-script Dart o desde la app ya
logueada): `curl` a `send-otp` con teléfono QA → 200 y SMS real llega; segundo envío inmediato
→ 429 "Espera Ns"; `verify-otp` con código malo → 400 "Código incorrecto"; con el bueno →
200 `ok:true`. Confirmar en la BD que `whatsapp_verified_at` quedó sellado (y limpiarlo si la
cuenta QA debe quedar como estaba).

- [ ] **Step 6: Commit (jayalo-app)**

```bash
git add supabase/functions
git commit -m "feat(otp): Edge Functions send-otp/verify-otp (ADR-0030)"
```

---

### Task 3: Dominio Dart puro — teléfono, slugs de error, catálogo

**Files:**
- Create: `app/lib/domain/phone.dart`, `app/lib/domain/onboarding_errors.dart`,
  `app/lib/domain/catalog.dart`
- Test: `app/test/phone_test.dart`, `app/test/onboarding_errors_test.dart`

**Interfaces (produces):**
- `normalizePhone(String) → String`, `isValidPhone(String) → bool` (port 1:1 de `phone.ts`).
- `onboardingErrorCopy(Object error) → String` — detecta los slugs de la Task 1 dentro del
  mensaje de `PostgrestException` y devuelve el copy; fallback genérico.
- `kCategories: List<({String id, String name})>` — port de `src/mocks/categories.ts`.

- [ ] **Step 1: Tests que fallan** (`phone_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phone.dart';

void main() {
  test('10 dígitos asume RD (+1)', () => expect(normalizePhone('8095551234'), '+18095551234'));
  test('respeta + existente', () => expect(normalizePhone('+34 600 111 222'), '+34600111222'));
  test('limpia caracteres', () => expect(normalizePhone('(809) 555-1234'), '+18095551234'));
  test('vacío', () => expect(normalizePhone('  '), ''));
  test('isValidPhone exige 8 dígitos', () {
    expect(isValidPhone('8095551'), false);
    expect(isValidPhone('80955512'), true);
  });
}
```

Y `onboarding_errors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/onboarding_errors.dart';

void main() {
  test('whatsapp_taken', () => expect(onboardingErrorCopy(Exception('whatsapp_taken')),
      contains('WhatsApp ya está registrado')));
  test('phone_taken', () => expect(onboardingErrorCopy(Exception('phone_taken')),
      contains('teléfono ya está registrado')));
  test('rnc_taken', () => expect(onboardingErrorCopy(Exception('rnc_taken')),
      contains('RNC')));
  test('fallback genérico', () => expect(onboardingErrorCopy(Exception('boom')),
      contains('No pudimos completar')));
}
```

Run: `flutter test test/phone_test.dart test/onboarding_errors_test.dart` → FAIL (no existen).

- [ ] **Step 2: Implementar**

`phone.dart`:

```dart
/// Port 1:1 de jayalo-main src/lib/phone.ts (misma semántica, RD +1).
String normalizePhone(String raw) {
  final t = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (t.isEmpty) return '';
  if (t.startsWith('+')) return t;
  if (t.length == 10) return '+1$t';
  return t;
}

bool isValidPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '').length >= 8;
```

`onboarding_errors.dart`:

```dart
/// Los slugs los lanza complete_provider_onboarding (ADR-0029). PostgREST los
/// entrega dentro del message de la excepción — basta buscar el slug.
const _slugCopy = {
  'whatsapp_taken':
      'Este WhatsApp ya está registrado en otro usuario. Usa otro número o inicia sesión con la cuenta que lo tiene.',
  'phone_taken':
      'Este teléfono ya está registrado en otra cuenta. Usa otro número o inicia sesión con la cuenta que lo tiene.',
  'rnc_taken': 'Este RNC ya está registrado.',
  'duplicate': 'Ese registro ya existe. Revisa tu WhatsApp o RNC.',
  'invalid_business': 'Falta el nombre del negocio.',
  'not_authenticated': 'Tu sesión expiró. Inicia sesión de nuevo.',
};

String onboardingErrorCopy(Object error) {
  final msg = error.toString();
  for (final e in _slugCopy.entries) {
    if (msg.contains(e.key)) return e.value;
  }
  return 'No pudimos completar tu registro. Revisa tu conexión e intenta de nuevo.';
}
```

`catalog.dart`: generar la lista desde la web con este script una vez (Node, desde
`jayalo-main/jayalo-main`):

```bash
node -e "const t=require('fs').readFileSync('src/mocks/categories.ts','utf8');const re=/id:\s*\"([^\"]+)\"[\s\S]*?name:\s*\"([^\"]+)\"/g;let m,out=[];while((m=re.exec(t)))out.push('  (id: \'' + m[1] + '\', name: \'' + m[2].replace(/'/g,\"\\\\'\") + '\'),');console.log(out.join('\n'))"
```

y volcar el resultado en:

```dart
/// Categorías del marketplace — port de jayalo-main src/mocks/categories.ts
/// (la tabla `categories` de prod está VACÍA; la web usa este mismo mock).
/// Regenerar con el script del plan si la web cambia la lista.
typedef Category = ({String id, String name});

const List<Category> kCategories = [
  // <<pegar aquí la salida del script>>
];
```

Ajustar la regex si el shape del mock difiere (verificar contra el archivo real al ejecutar).

- [ ] **Step 3: Tests verdes** — `flutter test` → PASS. **Step 4: Commit**

```bash
git add app/lib/domain app/test
git commit -m "feat(domain): phone + slugs de onboarding + catálogo de categorías"
```

---

### Task 4: Data layer (`repos.dart`)

**Files:**
- Modify: `app/lib/data/repos.dart`

**Interfaces (produces — las consumen Tasks 5-9):**

```dart
Future<Map<String, dynamic>?> myProfile();                 // account_type, nombres, phone
Future<bool> whatsappVerified();                           // fila personal sellada
Future<bool> isWhatsappTakenRemote(String digits);         // RPC is_whatsapp_taken
Future<void> completeConsumerProfile({...});               // upsert profiles (§6)
Future<String> completeProviderOnboarding({...});          // RPC ADR-0029 → business_id
Future<void> sendOtp({required String phone, String? businessId});
Future<({bool ok, bool businessBadgeVerified})> verifyOtp(
    {required String code, String? businessId});
Future<bool> canRevealOffer(String offerId);               // RPC can_reveal_offer_whatsapp
Future<List<Map<String, dynamic>>> rubrosForCategories(List<String> categoryIds);
Future<String?> uploadBusinessLogo(String filePath);       // bucket business-logos
```

- [ ] **Step 1: Implementar** (añadir al final de `repos.dart`, mismo estilo del archivo):

```dart
// ── Onboarding y verificación ───────────────────────────────────────────────

Future<Map<String, dynamic>?> myProfile() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  return await supa
      .from('profiles')
      .select('account_type,first_name,last_name,phone')
      .eq('user_id', uid)
      .maybeSingle();
}

Future<bool> whatsappVerified() async {
  final uid = supa.auth.currentUser!.id;
  final row = await supa
      .from('account_verifications')
      .select('whatsapp_verified_at')
      .eq('user_id', uid)
      .isFilter('business_id', null)
      .maybeSingle();
  return row?['whatsapp_verified_at'] != null;
}

Future<bool> isWhatsappTakenRemote(String digits) async =>
    await supa.rpc('is_whatsapp_taken', params: {
      '_whatsapp': digits,
      '_exclude_user': supa.auth.currentUser!.id,
    }) == true;

/// Alta de consumidor — payload idéntico a choose-role.tsx L88-104.
Future<void> completeConsumerProfile({
  required String firstName,
  required String lastName,
  required String whatsapp, // E.164
  required String address,
  double? lat,
  double? lng,
  required String termsVersion,
}) async {
  final u = supa.auth.currentUser!;
  await supa.from('profiles').upsert({
    'user_id': u.id,
    'email': u.email,
    'first_name': firstName.isEmpty ? null : firstName,
    'last_name': lastName.isEmpty ? null : lastName,
    'phone': whatsapp,
    'whatsapp': whatsapp,
    'address': address,
    'lat': lat,
    'lng': lng,
    'location_captured_at':
        (lat != null && lng != null) ? DateTime.now().toIso8601String() : null,
    'account_type': 'consumer',
    'terms_accepted_at': DateTime.now().toIso8601String(),
    'terms_version': termsVersion,
  }, onConflict: 'user_id');
}

/// Alta de proveedor — RPC atómica (ADR-0029). Lanza con slug estable.
Future<String> completeProviderOnboarding({
  required String firstName,
  required String lastName,
  required String phone, // E.164
  required Map<String, dynamic> business, // shape pending_business
  required String termsVersion,
}) async {
  final res = await supa.rpc('complete_provider_onboarding', params: {
    '_first_name': firstName,
    '_last_name': lastName,
    '_phone': phone,
    '_business': business,
    '_terms_version': termsVersion,
  }) as Map<String, dynamic>;
  return res['business_id'] as String;
}

Future<void> sendOtp({required String phone, String? businessId}) async {
  final res = await supa.functions.invoke('send-otp', body: {
    'phone': phone,
    if (businessId != null) 'business_id': businessId,
  });
  final data = res.data as Map<String, dynamic>?;
  if (data?['ok'] != true) {
    throw Exception(data?['error'] ?? 'No se pudo enviar el código');
  }
}

Future<({bool ok, bool businessBadgeVerified})> verifyOtp(
    {required String code, String? businessId}) async {
  final res = await supa.functions.invoke('verify-otp', body: {
    'code': code,
    if (businessId != null) 'business_id': businessId,
  });
  final data = res.data as Map<String, dynamic>?;
  if (data?['ok'] != true) {
    throw Exception(data?['error'] ?? 'No se pudo verificar el código');
  }
  return (ok: true, businessBadgeVerified: data?['business_badge_verified'] == true);
}

Future<bool> canRevealOffer(String offerId) async =>
    await supa.rpc('can_reveal_offer_whatsapp', params: {'_offer_id': offerId}) == true;

Future<List<Map<String, dynamic>>> rubrosForCategories(List<String> categoryIds) async =>
    List<Map<String, dynamic>>.from(await supa
        .from('rubros')
        .select('id,name,category_id')
        .inFilter('category_id', categoryIds)
        .order('name'));

Future<String?> uploadBusinessLogo(String filePath) async {
  final uid = supa.auth.currentUser!.id;
  final path = '$uid/logo-${DateTime.now().millisecondsSinceEpoch}.jpg';
  await supa.storage.from('business-logos').upload(path, File(filePath));
  return supa.storage.from('business-logos').getPublicUrl(path);
}
```

(Añadir `import 'dart:io';` arriba.) ⚠️ `supabase_flutter`: en errores 4xx `functions.invoke`
lanza `FunctionException` — envolver ambas llamadas en `try/on FunctionException catch (e)` y
re-lanzar `Exception((e.details as Map?)?['error'] ?? 'Error de conexión')` para que la UI
siempre reciba el mensaje en español del EF.

- [ ] **Step 2: Gate** — `flutter analyze` 0 errores. **Step 3: Commit**
  `feat(data): repos de onboarding, OTP y chequeo pre-desbloqueo`.

---

### Task 5: Gate post-login, RoleStore, selector de rol y home por rol

**Files:**
- Create: `app/lib/core/session_state.dart`, `app/lib/features/onboarding/gate_screen.dart`,
  `app/lib/features/onboarding/choose_role_screen.dart`
- Modify: `app/lib/core/router.dart`, `app/lib/features/shell/home_shell.dart`
- Test: `app/test/redirect_target_test.dart`

**Interfaces:**
- Produces: `RoleStore` (ChangeNotifier singleton `roleStore`) con
  `RoleState {unknown, needsOnboarding, consumer, provider}`, `Future<void> refresh()`
  (lee `myProfile()`; `account_type` NULL o sin fila → `needsOnboarding`) y
  `void invalidate()` (→ unknown + notify). Función pura
  `String? redirectTarget({required bool loggedIn, required RoleState role, required String location})`.
- Rutas nuevas: `/gate`, `/onboarding` (selector), `/onboarding/consumer`,
  `/onboarding/provider`. `initialLocation: '/gate'`.

- [ ] **Step 1: Test de la función pura** (`redirect_target_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';

void main() {
  test('sin sesión → /login', () => expect(
      redirectTarget(loggedIn: false, role: RoleState.unknown, location: '/client'), '/login'));
  test('login con sesión → /gate', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.consumer, location: '/login'), '/gate'));
  test('rol desconocido fuera de /gate → /gate', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.unknown, location: '/client'), '/gate'));
  test('needsOnboarding no alcanza el shell', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.needsOnboarding, location: '/provider'),
      '/onboarding'));
  test('needsOnboarding puede estar en onboarding', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.needsOnboarding, location: '/onboarding/consumer'),
      isNull));
  test('consumer no entra a onboarding', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.consumer, location: '/onboarding'), '/client'));
  test('provider en /client → /provider NO se fuerza (puede navegar)', () => expect(
      redirectTarget(loggedIn: true, role: RoleState.provider, location: '/client'), isNull));
}
```

Run → FAIL.

- [ ] **Step 2: `session_state.dart`**

```dart
import 'package:flutter/foundation.dart';
import '../data/repos.dart';

enum RoleState { unknown, needsOnboarding, consumer, provider }

/// El gate del spec §4: con account_type NULL no hay ruta del shell alcanzable.
String? redirectTarget({
  required bool loggedIn,
  required RoleState role,
  required String location,
}) {
  final inOnboarding = location.startsWith('/onboarding');
  final onLogin = location == '/login';
  final onGate = location == '/gate';
  if (!loggedIn) return onLogin ? null : '/login';
  if (onLogin) return '/gate';
  if (role == RoleState.unknown) return onGate ? null : '/gate';
  if (role == RoleState.needsOnboarding) {
    return (inOnboarding || onGate) ? null : '/onboarding';
  }
  // Rol resuelto: fuera de gate/onboarding se navega libre entre tabs.
  if (inOnboarding || onGate) {
    return role == RoleState.provider ? '/provider' : '/client';
  }
  return null;
}

class RoleStore extends ChangeNotifier {
  RoleState value = RoleState.unknown;

  Future<void> refresh() async {
    final p = await myProfile();
    value = switch (p?['account_type']) {
      'provider' => RoleState.provider,
      'consumer' => RoleState.consumer,
      _ => RoleState.needsOnboarding,
    };
    notifyListeners();
  }

  void invalidate() {
    value = RoleState.unknown;
    notifyListeners();
  }
}

final roleStore = RoleStore();
```

- [ ] **Step 3: `gate_screen.dart`** — splash que resuelve el rol:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/session_state.dart';

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await roleStore.refresh(); // el redirect del router hace el resto
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cargar tu cuenta.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Reintentar')),
                ]),
        ),
      );
}
```

- [ ] **Step 4: `choose_role_screen.dart`** — dos tarjetas M3, **sin escritura**:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card(IconData icon, String title, String body, String route) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(route), // NO escribe account_type (lección choose-role)
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 32, color: cs.primary),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(body),
              ]),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('¿Cómo quieres usar Jayalo?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Para terminar tu registro, elige cómo vas a usar la plataforma.'),
          const SizedBox(height: 24),
          card(Icons.shopping_bag_outlined, 'Quiero pedir',
              'Pido productos o servicios y recibo ofertas de proveedores cerca de mí.',
              '/onboarding/consumer'),
          const SizedBox(height: 16),
          card(Icons.storefront_outlined, 'Quiero ofrecer',
              'Tengo un negocio y quiero recibir solicitudes para ofertar.',
              '/onboarding/provider'),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: `router.dart`** — gate + rutas nuevas (las pantallas de Tasks 6-7 se registran
  aquí ya; hasta que existan, dejar `Placeholder()` compila pero NO commitear así — este task se
  commitea junto con stubs mínimos o después de crear los archivos vacíos de las Tasks 6-7 con
  `Scaffold` vacío):

```dart
GoRouter buildRouter() => GoRouter(
      initialLocation: '/gate',
      refreshListenable: Listenable.merge([_AuthNotifier(), roleStore]),
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        if (!loggedIn && roleStore.value != RoleState.unknown) roleStore.invalidate();
        return redirectTarget(
            loggedIn: loggedIn,
            role: roleStore.value,
            location: state.matchedLocation);
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/gate', builder: (_, _) => const GateScreen()),
        GoRoute(path: '/onboarding', builder: (_, _) => const ChooseRoleScreen()),
        GoRoute(path: '/onboarding/consumer',
            builder: (_, _) => const ConsumerOnboardingScreen()),
        GoRoute(path: '/onboarding/provider',
            builder: (_, _) => const ProviderOnboardingScreen()),
        ShellRoute( /* rutas del shell EXISTENTES sin cambios */ ),
      ],
    );
```

- [ ] **Step 6: `home_shell.dart`** — el tab inicial y los destinos visibles salen de
  `roleStore.value` (proveedor: Solicitudes/Mis ofertas/Ajustes; consumidor: Mis
  solicitudes/Crear/Ajustes). Mantener la navegación cruzada existente si ya la hay — solo
  cambia el default.

- [ ] **Step 7: Tests + gate** — `flutter test` PASS, `flutter analyze` 0.
- [ ] **Step 8: Commit** — `feat(onboarding): gate post-login, RoleStore y selector de rol`.

---

### Task 6: Onboarding de consumidor

**Files:**
- Create: `app/lib/features/onboarding/consumer_onboarding_screen.dart`
- Modify: `app/pubspec.yaml` (añadir `geolocator: ^13.0.0`), `android/app/src/main/AndroidManifest.xml`
  (`ACCESS_COARSE_LOCATION` + `ACCESS_FINE_LOCATION`)

**Interfaces:**
- Consumes: `completeConsumerProfile`, `isWhatsappTakenRemote`, `normalizePhone`,
  `roleStore.refresh()`.
- Constante `kTermsVersion = '2.0'` (crear en `core/config.dart`; DEBE coincidir con
  `TERMS_VERSION` de la web).

- [ ] **Step 1: Pantalla** — un `Stepper` M3 vertical (o PageView, a criterio visual §2 del
  spec) con 4 grupos: nombre (precargado de
  `supa.auth.currentUser!.userMetadata` claves `given_name`/`family_name`, fallback split de
  `full_name`), WhatsApp (validación `isValidPhone` + `isWhatsappTakenRemote` on-blur con
  mensaje "Este WhatsApp ya está registrado…"), ubicación (botón "Usar mi ubicación" →
  `Geolocator.requestPermission()` + `getCurrentPosition()` → guarda lat/lng y muestra chip
  "Ubicación captada ✓"; denegado/sin señal → solo dirección manual), dirección (obligatoria)
  y términos (CheckboxListTile + links con `launchUrl` a jayalo.com/terminos y /privacidad).
  Botón final deshabilitado hasta que todo valide.

Submit:

```dart
Future<void> _submit() async {
  setState(() => _busy = true);
  try {
    await completeConsumerProfile(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      whatsapp: normalizePhone(_phone.text),
      address: _address.text.trim(),
      lat: _lat, lng: _lng,
      termsVersion: kTermsVersion,
    );
    await roleStore.refresh(); // → redirect a /client
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(onboardingErrorCopy(e))));
    }
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

⚠️ El upsert de `profiles` puede chocar con `unique` de phone (23505): `onboardingErrorCopy`
ya cubre el fallback; añadir al mapa de la Task 3 la detección de `23505`+`phone` → copy de
`phone_taken` (test incluido).

- [ ] **Step 2: Verificar en device** — cuenta QA con `account_type` puesto a NULL por SQL
  (restaurar después): login → gate → selector → consumidor → GPS real → submit → aterriza en
  `/client`; reabrir la app → directo a `/client` (gate cachea bien). Camino negativo: WhatsApp
  de la otra cuenta QA → copy de duplicado, nada escrito.
- [ ] **Step 3: Gate + commit** — `feat(onboarding): flujo nativo de consumidor`.

---

### Task 7: Onboarding de proveedor

**Files:**
- Create: `app/lib/features/onboarding/provider_onboarding_screen.dart`
- Modify: `app/pubspec.yaml` (`geocoding: ^3.0.0`, `image_picker: ^1.1.0`),
  `AndroidManifest.xml` (cámara la declara image_picker solo)

**Interfaces:**
- Consumes: `completeProviderOnboarding`, `rubrosForCategories`, `uploadBusinessLogo`,
  `kCategories`, `normalizePhone`, `isWhatsappTakenRemote`, `onboardingErrorCopy`,
  `roleStore.refresh()`.
- El estado del flujo vive SOLO en memoria (spec §7: cero residuo al abandonar).

- [ ] **Step 1: Pantalla** — PageView de 6 pasos con indicador de progreso M3:

1. *Tu negocio*: nombre (obligatorio) · SegmentedButton informal/formal ("Informal: aún sin
   RNC — la mayoría empieza así") · si formal → campo RNC · SegmentedButton
   productos/servicios/ambos · si ofrece productos → SwitchListTile "Vendo al por mayor".
2. *Qué vendes*: `FilterChip`s de `kCategories` (máx 2 — al llegar a 2 deshabilitar el resto);
   al cambiar la selección, cargar `rubrosForCategories` y mostrar chips de rubros.
3. *Dónde trabajas*: botón "Usar mi ubicación" → `placemarkFromCoordinates` (geocoding) →
   prefill de `city` (locality) y `sector` (subLocality) en TextFields SIEMPRE editables;
   country fijo `'República Dominicana'`.
4. *Tu WhatsApp*: TextField precargado con `profiles.phone` si existe; `isValidPhone` +
   `isWhatsappTakenRemote` on-blur. Nota bajo el campo: "Después de crear tu negocio podrás
   confirmarlo por SMS para ganar el sello de verificado." (SIN OTP aquí — decisión PO §10.2).
5. *Foto (opcional)*: `image_picker` cámara/galería → preview → al elegir se sube con
   `uploadBusinessLogo` (spinner); TextButton "Después" salta el paso.
6. *Términos y confirmación*: resumen (nombre, categorías, ciudad, WhatsApp) + checkbox de
   términos + botón "Crear mi negocio".

Cierre (la ÚNICA escritura del flujo):

```dart
Future<void> _finish() async {
  setState(() => _busy = true);
  final phoneE164 = normalizePhone(_whatsapp.text);
  try {
    await completeProviderOnboarding(
      firstName: _first.text.trim(),   // precargados de claims Google, editables en paso 1
      lastName: _last.text.trim(),
      phone: phoneE164,
      business: {
        'business_type': _formal ? 'formal' : 'informal',
        'offers': _offers,             // 'productos' | 'servicios' | 'ambos'
        'category_id': _categories.isNotEmpty ? _categories.first : '',
        'category_ids': _categories,
        'rubros': _rubros,
        'name': _name.text.trim(),
        'is_wholesale': _wholesale,
        'rnc': _formal ? _rnc.text.trim() : '',
        'description': '',
        'whatsapp': phoneE164,
        'country': 'República Dominicana',
        'city': _city.text.trim(),
        'sector': _sector.text.trim(),
        'address': '',
        'profession': '',
        'experience_years': '',
        'logo_url': _logoUrl ?? '',
        'owner_photo_url': '',
      },
      termsVersion: kTermsVersion,
    );
    await roleStore.refresh(); // → redirect a /provider
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(onboardingErrorCopy(e)), duration: const Duration(seconds: 8)));
    }
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

(El nombre/apellido del paso 1 se muestran arriba del nombre del negocio, precargados de las
claims igual que en la Task 6.)

- [ ] **Step 2: Verificar en device** — segunda cuenta QA en NULL: flujo completo con GPS,
  foto por cámara y cierre → `/provider` con saldo 0 visible en "Mis ofertas". Camino negativo:
  WhatsApp duplicado → copy con salida, y verificar por SQL que NO quedó negocio ni wallet.
  Abandono: salir en el paso 3, matar la app, volver → selector de rol de nuevo, BD limpia.
- [ ] **Step 3: Gate + commit** — `feat(onboarding): flujo nativo de proveedor (RPC atómica)`.

---

### Task 8: Hoja de OTP + disparadores (banner y Ajustes)

**Files:**
- Create: `app/lib/features/verification/otp_sheet.dart`,
  `app/lib/features/verification/verify_banner.dart`
- Modify: `app/lib/features/client/create_request_screen.dart`,
  `app/lib/features/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `sendOtp`, `verifyOtp`, `whatsappVerified`, `myProfile`, `myBusinessId`.
- Produces: `Future<bool> showOtpSheet(BuildContext context, {required String phone,
  String? businessId})` → true si quedó verificado.

- [ ] **Step 1: `otp_sheet.dart`** — bottom sheet M3: al abrir llama `sendOtp` (spinner);
  luego campo de 6 dígitos (`TextField` con `maxLength: 6`, teclado numérico), copy **"Te
  enviamos un código por SMS al ####"**, countdown de 60 s para "Reenviar código", botón
  Verificar → `verifyOtp`; error → mensaje del EF bajo el campo (incorrecto/expirado/intentos);
  éxito → pop(true) con snackbar "✓ WhatsApp confirmado". Errores de `sendOtp` (cooldown/rate
  limit) se muestran dentro de la hoja con "Reintentar".

- [ ] **Step 2: `verify_banner.dart`** — el disparador del PO (§6.1), cerrable y no bloqueante:

```dart
import 'package:flutter/material.dart';
import '../../data/repos.dart';
import 'otp_sheet.dart';

/// Banner cerrable (decisión PO 2026-07-16): nudge de verificación al crear
/// solicitud. Cerrarlo solo lo oculta en esta pantalla; reaparece la próxima.
class VerifyWhatsappBanner extends StatefulWidget {
  const VerifyWhatsappBanner({super.key});
  @override
  State<VerifyWhatsappBanner> createState() => _VerifyWhatsappBannerState();
}

class _VerifyWhatsappBannerState extends State<VerifyWhatsappBanner> {
  bool _dismissed = false;
  bool? _verified;

  @override
  void initState() {
    super.initState();
    whatsappVerified().then((v) {
      if (mounted) setState(() => _verified = v);
    }).catchError((_) {
      if (mounted) setState(() => _verified = true); // en error, no molestar
    });
  }

  Future<void> _verify() async {
    final p = await myProfile();
    if (!mounted) return;
    final ok = await showOtpSheet(context, phone: (p?['phone'] as String?) ?? '');
    if (ok && mounted) setState(() => _verified = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _verified != false) return const SizedBox.shrink();
    return MaterialBanner(
      content: const Text(
          'Confirma tu WhatsApp: las solicitudes verificadas generan más confianza y reciben más ofertas.'),
      leading: const Icon(Icons.verified_outlined),
      actions: [
        TextButton(onPressed: _verify, child: const Text('Confirmar ahora')),
        TextButton(
            onPressed: () => setState(() => _dismissed = true),
            child: const Text('Ahora no')),
      ],
    );
  }
}
```

- [ ] **Step 3: Integrar el banner** en `create_request_screen.dart`: insertarlo como primer
  hijo del `Column` del body (encima de la lista de burbujas), sin tocar la lógica del chat.

- [ ] **Step 4: Entradas en Ajustes** (`settings_screen.dart`): tras la fila del email, añadir
  `FutureBuilder` con `whatsappVerified()`:
  - No verificado → `ListTile` "Confirmar mi cuenta" (subtítulo: "Verifica tu WhatsApp por
    SMS") → `showOtpSheet(phone: profiles.phone)`.
  - Verificado → `ListTile` con `Icons.verified` "WhatsApp confirmado ✓" (sin acción).
  - Y si `roleStore.value == RoleState.provider`: `ListTile` "Sello de WhatsApp del negocio"
    → `showOtpSheet(phone: <whatsapp del negocio>, businessId: await myBusinessId())`; al
    volver `businessBadgeVerified=true` → snackbar "Tu negocio ya muestra el sello ✓".

- [ ] **Step 5: Verificar en device** — cuenta consumidor QA sin verificar: crear solicitud →
  banner visible → "Ahora no" lo cierra y NO bloquea el envío → nueva solicitud → banner
  reaparece → "Confirmar ahora" → SMS real → verificado → banner no vuelve. Ajustes muestra
  "WhatsApp confirmado ✓".
- [ ] **Step 6: Gate + commit** — `feat(verification): hoja OTP por SMS + banner cerrable + Ajustes`.

---

### Task 9: Fixes del bug de dinero en "Mis ofertas"

**Files:**
- Modify: `app/lib/features/provider/my_offers_screen.dart`

**Interfaces:** Consumes `canRevealOffer` (Task 4).

- [ ] **Step 1: Chequeo pre-desbloqueo** — en `_showUnlockSheet` (L153), ANTES de mostrar la
  hoja:

```dart
void _openOffer(Map<String, dynamic> o) {
  final st = o['status'] as String;
  final unlocked = o['unlocked_at'] != null;
  if (st == 'accepted' && !unlocked) {
    _preUnlockCheck(o);
  } else if (unlocked || st == 'completed') {
    _showContactSheet(o);
  }
}

Future<void> _preUnlockCheck(Map<String, dynamic> o) async {
  bool revealable;
  try {
    revealable = await canRevealOffer(o['id'] as String);
  } catch (_) {
    _snack('No pudimos comprobar el contacto. Revisa tu conexión e intenta de nuevo.');
    return;
  }
  if (!mounted) return;
  if (!revealable) {
    // Paridad con la web (ProviderOffersSection.tsx:670): NUNCA cobrar si el
    // contacto no es revelable (cliente sin WhatsApp verificado u opt-out).
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Contacto aún no disponible', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              'Este cliente todavía no tiene su WhatsApp verificado, así que no se puede '
              'desbloquear su contacto (y no se te cobraría nada). Te avisaremos si lo confirma.'),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ]),
      ),
    );
    return;
  }
  _showUnlockSheet(o);
}

void _snack(String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
```

- [ ] **Step 2: Matar el catch silencioso** (L198-204) — el error de red/servidor deja de
  disfrazarse de "no tiene WhatsApp":

```dart
Future<void> _showContactSheet(Map<String, dynamic> o) async {
  ({String? firstName, String? phone}) contact;
  try {
    contact = await unlockedContact(o['id'] as String);
  } catch (_) {
    if (!mounted) return;
    // Derecho YA pagado: jamás presentar un fallo como "no hay contacto".
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('No pudimos cargar el contacto', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tu desbloqueo está guardado — no se te volverá a cobrar. '
              'Revisa tu conexión e intenta de nuevo.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showContactSheet(o);
            },
            child: const Text('Reintentar'),
          ),
        ]),
      ),
    );
    return;
  }
  if (!mounted) return;
  // ... (hoja de contacto existente sin cambios)
}
```

- [ ] **Step 3: Verificar en device** — con la cuenta QA proveedora y una oferta accepted de
  un cliente SIN verificar: tap → hoja "Contacto aún no disponible", saldo intacto (verificar
  por SQL). Con cliente verificado: flujo de pago normal. Modo avión tras desbloquear → hoja
  de error con Reintentar (no la hoja vacía).
- [ ] **Step 4: Gate + commit** — `fix(dinero): chequeo pre-desbloqueo + error visible en contacto (bug 2026-07-16)`.

---

### Task 10: E2E en device + runbook + cierre

**Files:**
- Create: `jayalo-app/docs/qa/2026-07-XX-e2e-onboarding.md` (resultados)

- [ ] **Step 1: Preparación [PO]** — dos cuentas Google NUEVAS (o borrar las QA de
  `auth.users` en prod con autorización) + Redmi por USB + APK debug fresco
  (`flutter run --release` no: el SHA-1 release no está registrado — usar debug).
- [ ] **Step 2: Corrida completa** (los criterios del spec §11, en orden): consumidor nuevo
  end-to-end (onboarding → solicitud → banner → OTP SMS real) · proveedor nuevo end-to-end
  (onboarding atómico → wallet 0 → oferta) · ciclo de dinero (aceptar → pre-check → desbloquear
  → contacto verificado) · caso sin verificar (pre-check bloquea, saldo intacto) · abandono
  limpio (salir a mitad, BD sin residuo) · sello del negocio desde Ajustes.
- [ ] **Step 3: Documentar resultados** en el runbook (qué pasó, bugs, SQL de verificación
  usado) y commitear. Si algo falla: `superpowers:systematic-debugging` antes de tocar código.
- [ ] **Step 4: Actualizar memoria/CLAUDE.md de la sesión** con el estado final.

---

## Self-Review (hecho al escribir el plan)

- **Cobertura del spec**: §4 gate → Task 5 · §5 selector → Task 5 · §6 consumidor → Task 6 ·
  §6.1/6.2 disparador+OTP → Tasks 2+8 · §7 proveedor → Tasks 1+7 · §8 fixes → Tasks 5 (home
  por rol) y 9 · §9 costuras → Tasks 1-2 · §11 criterios → Task 10.
- **Fuera del plan a propósito**: keystore release + SHA-1 (spec §3.2 — tarea hermana aparte);
  migración de la web a la RPC/EFs (deuda registrada en ADRs).
- **Riesgos señalados inline**: `owns_business` inútil bajo service role (Task 2) ·
  `FunctionException` en 4xx (Task 4) · regex del generador de catálogo a verificar contra el
  mock real (Task 3) · MCP sin autorizar → dashboard (Task 1).
