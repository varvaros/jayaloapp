# Play Billing v1 (solo paquetes) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el proveedor compre créditos DENTRO de la app con Google Play Billing, verificado y acreditado server-side, y que desaparezca el link-out al wallet web que la política de pagos de Play prohíbe.

**Architecture:** La app lanza la compra con el plugin `in_app_purchase`; el `purchaseToken` viaja a `POST /api/app/play-verify` (worker de Cloudflare), que lo valida contra la Play Developer API con una service account, resuelve los créditos desde `credit_packages` (nunca desde el cliente) y acredita en UNA transacción con una RPC nueva `credit_play_purchase`. La idempotencia es un `INSERT ... ON CONFLICT (play_purchase_token) DO NOTHING` sobre `payment_orders` — no el `UPDATE` de PayPal, que en Play se tragaría la primera compra de cada usuario.

**Tech Stack:** Flutter + `in_app_purchase` · TanStack Start sobre Cloudflare Workers (WebCrypto, sin librerías de Node) · Supabase/Postgres (RPC `SECURITY DEFINER`) · vitest (web) · flutter_test (app).

**Spec:** `docs/superpowers/specs/2026-08-07-play-billing-paquetes-design.md` (repo app, commit `1cd7eb5`).

## Global Constraints

- **Nada de link-out al pago externo.** Ni enlace, ni precio de la web, ni mención de que fuera es más barato (anti-steering). Aplica a copy, tooltips y mensajes de error.
- **El costo/beneficio se resuelve SIEMPRE en el servidor.** Un `productId` del cliente solo sirve para *buscar* en `credit_packages`; jamás para decidir cuántos créditos acreditar. Regla ya vigente en todas las RPCs de cobro del proyecto.
- **Toda RPC nueva lleva `REVOKE ALL ... FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE ... TO service_role`.** Supabase Cloud auto-otorga EXECUTE a `authenticated` en cada función nueva vía `ALTER DEFAULT PRIVILEGES`; sin el REVOKE, cualquier usuario se autoacredita por PostgREST.
- **`payment_orders` sigue siendo server-only para escritura** (`SELECT` para `authenticated`). Es lo que sostiene que `points` sea de fiar.
- **Ids de producto de Play (permanentes, irreutilizables):** `creditos_10usd`, `creditos_50usd`, `creditos_100usd`, `creditos_180usd`.
- **`applicationId` = `com.jayalo.app`** (permanente, atado a los OAuth clients).
- **Gates que deben quedar verdes al terminar cada tarea:** web `npx tsc --noEmit` (baseline **0** errores), `npm run lint` (0 errores), `npx vitest run`; app `flutter analyze`, `flutter test`.
- **Commits:** en cada tarea, con `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` al final.
- **Migraciones:** el fichero en `supabase/migrations/` NO es la verdad; hay que aplicarlas a prod (`mfaiklvobnvgusbcssbx`) vía MCP **con autorización explícita del PO por cada migración**, y verificarlas después con `list_migrations`.

---

## Trabajo previo del PO (no es código; bloquea la PRUEBA, no la implementación)

Ninguna de estas cuatro cosas la puede hacer Claude. Se pueden ir haciendo en paralelo a las tareas 1-11; **la 3 y la 4 bloquean el smoke real**.

1. **Confirmar si la cuenta de Play Console es persona física u organización.** Persona física ⇒ prueba cerrada de 12 testers × 14 días continuos antes de producción. No cambia el código; fija el calendario.
2. **Confirmar la comisión aplicable** (15 % reducida vs 30 %). No cambia el código; cambia si el PO quiere revisar precios.
3. **Alta de los 4 productos in-app** en la consola (gestionados, consumibles), con los ids exactos de arriba y los precios USD 10 / 50 / 100 / 180. Más el alta de los **license testers** (correos que compran sin cobro).
4. **Service account con acceso a la Play Developer API**: crearla en `jayalo-501005`, concederle permiso en Play Console (Usuarios y permisos → "Ver información financiera" + "Gestionar pedidos"), descargar la clave JSON y cargarla como secreto del worker:
   ```bash
   npx wrangler secret put PLAY_SERVICE_ACCOUNT_JSON --name varvaros-jayalo-afd966bf
   ```
   (el `--name` es obligatorio; pegar el JSON completo de una línea).
5. **Tercer OAuth client** en `jayalo-501005` con el SHA-1 de **Play App Signing** (Play re-firma el AAB con SU llave). Sin esto el login con Google falla **solo** para quien instale desde la tienda —incluida la prueba interna— y no se reproduce en local. Ya pasó una vez (`ApiException: 10`).

⚠️ **No existe estado intermedio publicable.** Un binario con link-out no puede subir a Play ni a prueba interna, y Play Billing no se puede probar sin haber subido antes. La retirada del link-out y el billing viajan en el MISMO binario: el primer AAB que Google vea ya es compatible.

## Ramas y orden

- **Web** (`C:\Users\ac\Downloads\jayalo-main\jayalo-main`): rama `feat/play-billing` desde `master`. Tareas 1-5.
- **App** (`C:\Users\ac\Downloads\jayalo-app\app`): rama `feat/play-billing` desde `feat/tanda-ui-08-05` (donde vive el spec). Tareas 6-11.
- **El servidor va primero.** La app no se puede probar de punta a punta contra un endpoint que no existe.

⚠️ **Dependencia conocida:** `src/lib/creditShop.ts` (el algoritmo de ahorro/beneficio que la tarea 7 porta a Dart) vive en la rama **sin mergear** `feat/tienda-creditos-wallet` (worktree `wallet-tienda`). El plan incluye su contenido literal en la tarea 7, así que no bloquea; pero si esa rama cambia el algoritmo antes de mergearse, hay que re-sincronizar el port de Dart.

## File Structure

**Web (`jayalo-main`)**

| Fichero | Responsabilidad |
|---|---|
| `supabase/migrations/20260808120000_play_billing.sql` (crear) | Columnas de Play en `payment_orders` + `credit_packages.play_product_id` + RPC `credit_play_purchase` + grants |
| `scripts/db-security-check.sql` (modificar) | Check #14: la RPC nueva no tiene EXECUTE para anon/authenticated |
| `src/lib/playPurchase.ts` (crear) | Lógica **pura**: interpreta la respuesta de la Developer API (estado, entorno, si hay que reconocer). Sin I/O |
| `src/lib/playPurchase.test.ts` (crear) | Tests de lo anterior |
| `src/lib/playApi.server.ts` (crear) | Cliente HTTP de la Play Developer API: token OAuth desde la service account (WebCrypto RS256), `get` y `acknowledge` |
| `src/lib/playApi.server.test.ts` (crear) | Tests con `fetch` mockeado |
| `src/routes/api/app/play-verify.ts` (crear) | El endpoint: Origin fail-closed + JWT + rate limit + orquestación |
| `src/integrations/supabase/types.ts` (modificar) | Declarar la RPC nueva |

**App (`jayalo-app/app`)**

| Fichero | Responsabilidad |
|---|---|
| `pubspec.yaml` (modificar) | Dependencia `in_app_purchase` |
| `lib/domain/credit_shop.dart` (crear) | Port Dart puro de `creditShop.ts` (ahorro, $/crédito, mejor precio) |
| `test/credit_shop_test.dart` (crear) | Tests espejo de `creditShop.test.ts` |
| `lib/core/play_verify_client.dart` (crear) | Cliente HTTP de `/api/app/play-verify` (calca `account_deletion_client.dart`) |
| `test/play_verify_client_test.dart` (crear) | Tests con `http` mockeado |
| `lib/core/play_billing_service.dart` (crear) | Envoltura de `in_app_purchase`: catálogo, compra, stream, completar |
| `test/play_billing_service_test.dart` (crear) | Tests con un `InAppPurchase` falso |
| `lib/features/provider/credit_shop_screen.dart` (crear) | La tienda: banda violeta, carrusel de tarjetas, CTA |
| `test/credit_shop_screen_test.dart` (crear) | Tests de widget |
| `lib/core/config.dart` (modificar) | `playVerifyEndpoint`; se retira `walletUrl` |
| `lib/core/router.dart` (modificar) | Ruta `/tienda-creditos` |
| `lib/features/provider/unlock_flow.dart` (modificar) | `openProviderWallet` → `openCreditShop` |
| `lib/features/provider/product_interest_detail_screen.dart` (modificar) | link-out → tienda |
| `lib/features/shared/profile_avatar_button.dart` (modificar) | link-out → tienda |
| `lib/data/repos.dart` (modificar) | Retirar `createWalletLoginLink`; añadir `activeCreditPackages()` |

---

## Task 1: Migración de BD — columnas de Play, RPC atómica y grants

**Files:**
- Create: `supabase/migrations/20260808120000_play_billing.sql`
- Modify: `scripts/db-security-check.sql` (añadir check #14 al final)
- Modify: `src/integrations/supabase/types.ts` (declarar `credit_play_purchase` bajo `Functions`)

**Interfaces:**
- Produces: RPC `credit_play_purchase(_play_purchase_token text, _product_id text, _user_id uuid, _environment text, _raw jsonb)` → `TABLE(balance integer, points integer, credited boolean)`. La consume la tarea 4.
- Produces: `credit_packages.play_product_id text UNIQUE NULL`. La consumen las tareas 4 y 11.

- [ ] **Step 1: Escribir la migración**

Crear `supabase/migrations/20260808120000_play_billing.sql`:

```sql
-- Play Billing v1 — solo paquetes.
--
-- Por qué el claim NO es el UPDATE de PayPal: en PayPal la orden se CREA antes
-- de pagar, así que existe una fila 'created' que capturar y el
-- `UPDATE ... WHERE status='created' RETURNING` es la carrera que solo uno gana.
-- En Play la compra ocurre entera dentro de Google y nos llega YA pagada: no hay
-- fila previa. Un UPDATE no encontraría nada, caería en el IF NOT FOUND (que
-- significa "ya se acreditó, devuelve el balance") y se tragaría la PRIMERA
-- compra de cada usuario -- pagó y no recibe nada, y la idempotencia bloquea el
-- reintento. El claim correcto para un pago que nace cobrado es el INSERT.

-- 1) credit_packages: qué producto de Play vende este paquete.
-- Nullable a propósito: la web sigue vendiendo paquetes sin producto de Play.
ALTER TABLE public.credit_packages
  ADD COLUMN IF NOT EXISTS play_product_id text;

CREATE UNIQUE INDEX IF NOT EXISTS credit_packages_play_product_id_key
  ON public.credit_packages (play_product_id)
  WHERE play_product_id IS NOT NULL;

-- 2) payment_orders: admitir una fila que no viene de PayPal.
ALTER TABLE public.payment_orders
  ALTER COLUMN paypal_order_id DROP NOT NULL;

ALTER TABLE public.payment_orders
  ADD COLUMN IF NOT EXISTS play_purchase_token text;

-- Índice único PARCIAL. Ojo: para usarlo como target de ON CONFLICT hay que
-- repetir su predicado en la sentencia (ver la RPC de abajo), o Postgres
-- responde "no unique or exclusion constraint matching the ON CONFLICT
-- specification".
CREATE UNIQUE INDEX IF NOT EXISTS payment_orders_play_token_key
  ON public.payment_orders (play_purchase_token)
  WHERE play_purchase_token IS NOT NULL;

-- Quitar el NOT NULL sin más dejaría entrar filas sin NINGUNA referencia de
-- pago. El CHECK cruzado es lo que lo impide.
ALTER TABLE public.payment_orders
  ADD CONSTRAINT payment_orders_provider_ref_chk CHECK (
    (provider = 'paypal' AND paypal_order_id IS NOT NULL)
    OR (provider = 'play' AND play_purchase_token IS NOT NULL)
  );

ALTER TABLE public.payment_orders
  ADD CONSTRAINT payment_orders_provider_chk
  CHECK (provider IN ('paypal', 'play'));

COMMENT ON COLUMN public.payment_orders.amount_usd IS
  'PayPal: el importe realmente capturado. Play: el precio USD NOMINAL del '
  'paquete en credit_packages -- la Play Developer API no devuelve el precio, y '
  'Play localiza y a veces recauda el impuesto. En filas de Play este campo NO '
  'es conciliable con el cobro real.';

-- 3) La RPC. Espeja credit_captured_payment (misma forma: claim + crédito en
-- UNA transacción, rollback total si el crédito lanza) con la primitiva
-- correcta para Play.
CREATE OR REPLACE FUNCTION public.credit_play_purchase(
  _play_purchase_token text,
  _product_id text,
  _user_id uuid,
  _environment text,
  _raw jsonb
) RETURNS TABLE(balance integer, points integer, credited boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pkg_id    uuid;
  v_pkg_pts   integer;
  v_pkg_price numeric(10,2);
  v_user      uuid;
  v_points    integer;
BEGIN
  -- Los créditos son AUTORITATIVOS del servidor: se resuelven por el id de
  -- producto contra la tabla, nunca se aceptan del cliente.
  SELECT p.id, p.points, p.price_usd
    INTO v_pkg_id, v_pkg_pts, v_pkg_price
    FROM public.credit_packages p
   WHERE p.play_product_id = _product_id
     AND p.is_active
   LIMIT 1;

  IF v_pkg_id IS NULL THEN
    RAISE EXCEPTION 'unknown_play_product:%', _product_id;
  END IF;

  -- Claim atómico. El predicado del índice parcial va en el ON CONFLICT.
  INSERT INTO public.payment_orders (
    user_id, provider, environment, play_purchase_token, package_id,
    points, amount_usd, currency, status, raw_response, captured_at
  ) VALUES (
    _user_id, 'play', _environment, _play_purchase_token, v_pkg_id,
    v_pkg_pts, v_pkg_price, 'USD', 'captured', _raw, now()
  )
  ON CONFLICT (play_purchase_token) WHERE play_purchase_token IS NOT NULL
  DO NOTHING
  RETURNING payment_orders.user_id, payment_orders.points INTO v_user, v_points;

  IF NOT FOUND THEN
    -- Token ya visto (reintento del cliente o dos peticiones a la vez).
    SELECT w.balance INTO balance
      FROM public.provider_wallets w
      JOIN public.payment_orders o ON o.user_id = w.user_id
     WHERE o.play_purchase_token = _play_purchase_token;
    balance  := COALESCE(balance, 0);
    points   := 0;
    credited := false;
    RETURN NEXT;
    RETURN;
  END IF;

  balance  := public._adjust_wallet(
                v_user, v_points, 'recharge',
                'Recarga Google Play — ' || v_points || ' créditos (' || _product_id || ')');
  points   := v_points;
  credited := true;
  RETURN NEXT;
END;
$$;

-- OBLIGATORIO: Supabase Cloud auto-otorga EXECUTE a anon+authenticated en cada
-- función nueva. Sin este REVOKE, un usuario llama la RPC por PostgREST con un
-- token inventado y se autoacredita sin pagar.
REVOKE ALL ON FUNCTION public.credit_play_purchase(text, text, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.credit_play_purchase(text, text, uuid, text, jsonb)
  TO service_role;
```

- [ ] **Step 2: Probar la migración contra prod SIN persistir**

Vía MCP de Supabase `execute_sql` sobre `mfaiklvobnvgusbcssbx`, envolviendo TODO en una transacción que se deshace. Verifica tres cosas de golpe: que el DDL aplica sobre el schema real, que el claim acredita la primera vez y que no acredita la segunda.

```sql
BEGIN;
-- (pegar aquí el contenido completo de la migración)

-- Semilla: atar un paquete real a un producto de Play.
UPDATE public.credit_packages SET play_product_id = 'creditos_10usd'
 WHERE price_usd = 10.00 AND is_active;

-- Un usuario real con wallet.
CREATE TEMP TABLE t AS
  SELECT user_id, balance FROM public.provider_wallets ORDER BY user_id LIMIT 1;

SELECT 'antes' AS fase, balance FROM t;
SELECT 'primera' AS fase, * FROM public.credit_play_purchase(
  'tok_prueba_1', 'creditos_10usd', (SELECT user_id FROM t), 'sandbox', '{}'::jsonb);
SELECT 'segunda' AS fase, * FROM public.credit_play_purchase(
  'tok_prueba_1', 'creditos_10usd', (SELECT user_id FROM t), 'sandbox', '{}'::jsonb);
ROLLBACK;
```

Esperado: `primera` → `credited=true`, `points=10`, balance subido 10; `segunda` → `credited=false`, `points=0`, mismo balance. **Si `primera` devuelve `credited=false`, el claim está mal y la tarea no está hecha** — es exactamente el fallo que este diseño existe para evitar.

- [ ] **Step 3: Probar los CHECK cruzados**

```sql
BEGIN;
-- (migración otra vez)
-- Debe FALLAR: provider 'play' sin token.
INSERT INTO public.payment_orders (user_id, provider, environment, package_id,
  points, amount_usd, status)
VALUES ((SELECT user_id FROM public.provider_wallets LIMIT 1), 'play', 'live',
        (SELECT id FROM public.credit_packages WHERE is_active LIMIT 1), 10, 10, 'captured');
ROLLBACK;
```

Esperado: error `payment_orders_provider_ref_chk`. Si el INSERT pasa, el CHECK está mal escrito.

- [ ] **Step 4: Añadir el check #14 a `scripts/db-security-check.sql`**

Al final del fichero, siguiendo el formato de los checks #1-#13 (cada uno debe devolver **0 filas**):

```sql
-- #14: credit_play_purchase NUNCA debe tener EXECUTE para anon/authenticated.
-- Supabase Cloud los auto-otorga al recrear la función; con ese grant, un
-- usuario se autoacredita por PostgREST inventando un purchaseToken.
SELECT 'check14_play_rpc_grant' AS check, r.rolname
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL (VALUES ('anon'), ('authenticated')) AS r(rolname)
 WHERE n.nspname = 'public'
   AND p.proname = 'credit_play_purchase'
   AND has_function_privilege(r.rolname, p.oid, 'EXECUTE');
```

- [ ] **Step 5: Declarar la RPC en `types.ts`**

En `src/integrations/supabase/types.ts`, dentro de `Functions`, en orden alfabético (junto a `credit_captured_payment`):

```ts
      credit_play_purchase: {
        Args: {
          _play_purchase_token: string
          _product_id: string
          _user_id: string
          _environment: string
          _raw: Json
        }
        Returns: {
          balance: number
          points: number
          credited: boolean
        }[]
      }
```

- [ ] **Step 6: Verificar que los gates siguen verdes**

Run: `npx tsc --noEmit`
Expected: 0 errores (baseline).

- [ ] **Step 7: Aplicar a producción**

**Pedir autorización nominal al PO para esta migración concreta** (el clasificador no acepta una autorización general por adelantado). Luego, vía MCP `apply_migration` sobre `mfaiklvobnvgusbcssbx`, y verificar con `list_migrations` que aparece `20260808120000_play_billing` y con el check #14 que devuelve 0 filas.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260808120000_play_billing.sql scripts/db-security-check.sql src/integrations/supabase/types.ts
git commit -m "feat(db): Play Billing — claim por INSERT, columnas de Play y RPC credit_play_purchase"
```

---

## Task 2: Lógica pura de interpretación de la compra

**Files:**
- Create: `src/lib/playPurchase.ts`
- Test: `src/lib/playPurchase.test.ts`

**Interfaces:**
- Produces: `type PlayPurchase`, `type PurchaseVerdict`, `judgePurchase(p: PlayPurchase): PurchaseVerdict`. Las consume la tarea 4.

Se separa de la llamada HTTP por la misma razón que `paypal-validate.ts`: se puede testear sin mockear nada.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `src/lib/playPurchase.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { judgePurchase } from "./playPurchase";

describe("judgePurchase", () => {
  it("acepta una compra pagada y sin reconocer", () => {
    const v = judgePurchase({ purchaseState: 0, acknowledgementState: 0 });
    expect(v.ok).toBe(true);
    expect(v.needsAcknowledge).toBe(true);
    expect(v.environment).toBe("live");
  });

  it("acepta una compra pagada YA reconocida (reintento) sin re-reconocer", () => {
    const v = judgePurchase({ purchaseState: 0, acknowledgementState: 1 });
    expect(v.ok).toBe(true);
    expect(v.needsAcknowledge).toBe(false);
  });

  it("marca sandbox la compra de un license tester", () => {
    // purchaseType 0 = Test. El campo solo viene en compras de prueba/promo.
    const v = judgePurchase({ purchaseState: 0, acknowledgementState: 0, purchaseType: 0 });
    expect(v.environment).toBe("sandbox");
  });

  it("rechaza una compra pendiente", () => {
    const v = judgePurchase({ purchaseState: 2, acknowledgementState: 0 });
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("not_purchased");
  });

  it("rechaza una compra cancelada", () => {
    const v = judgePurchase({ purchaseState: 1, acknowledgementState: 0 });
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("not_purchased");
  });

  it("rechaza una respuesta sin purchaseState (payload roto o error disfrazado)", () => {
    const v = judgePurchase({} as never);
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("not_purchased");
  });
});
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `npx vitest run src/lib/playPurchase.test.ts`
Expected: FAIL — "Failed to resolve import ./playPurchase".

- [ ] **Step 3: Implementar**

Crear `src/lib/playPurchase.ts`:

```ts
/**
 * Lógica pura sobre la respuesta de `purchases.products.get` de la Play
 * Developer API. Sin I/O — separada del cliente HTTP por la misma razón que
 * `paypal-validate.ts`: es la parte que decide si se acredita dinero, y tiene
 * que ser testeable sin red.
 *
 * @see https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products
 */

export type PlayPurchase = {
  /** 0 = comprada, 1 = cancelada, 2 = pendiente. */
  purchaseState?: number;
  /** 0 = sin reconocer, 1 = reconocida. */
  acknowledgementState?: number;
  /** Solo viene en compras que NO son reales: 0 = Test, 1 = Promo, 2 = Rewarded. */
  purchaseType?: number;
  orderId?: string;
};

export type PurchaseVerdict =
  | { ok: true; needsAcknowledge: boolean; environment: "sandbox" | "live" }
  | { ok: false; reason: "not_purchased" };

/** Compra pagada. Cualquier otro estado no acredita nada. */
const PURCHASED = 0;
/** `purchaseType` 0 = compra de un license tester: no hay dinero de verdad. */
const TEST_PURCHASE = 0;

export function judgePurchase(p: PlayPurchase): PurchaseVerdict {
  if (p?.purchaseState !== PURCHASED) return { ok: false, reason: "not_purchased" };
  return {
    ok: true,
    needsAcknowledge: p.acknowledgementState !== 1,
    environment: p.purchaseType === TEST_PURCHASE ? "sandbox" : "live",
  };
}
```

- [ ] **Step 4: Correr los tests**

Run: `npx vitest run src/lib/playPurchase.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/lib/playPurchase.ts src/lib/playPurchase.test.ts
git commit -m "feat(web): lógica pura del veredicto de una compra de Play"
```

---

## Task 3: Cliente de la Play Developer API (service account + WebCrypto)

**Files:**
- Create: `src/lib/playApi.server.ts`
- Test: `src/lib/playApi.server.test.ts`

**Interfaces:**
- Consumes: `PlayPurchase` de `src/lib/playPurchase.ts` (tarea 2).
- Produces: `getPlayPurchase(productId: string, token: string): Promise<PlayPurchase>` y `acknowledgePlayPurchase(productId: string, token: string): Promise<void>`. Las consume la tarea 4.

**Por qué a mano y no con `googleapis`:** el runtime es Cloudflare Workers, no Node. No hay `crypto` de Node ni `fs`. El JWT de la service account se firma con **WebCrypto** (`crypto.subtle`), que sí existe en Workers.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `src/lib/playApi.server.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { getPlayPurchase, acknowledgePlayPurchase, __resetTokenCacheForTests } from "./playApi.server";

// Clave RSA de PRUEBA generada para este test (no sirve para nada real).
// Se genera en el propio test para no meter material criptográfico en el repo.
async function fakeServiceAccountJson() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const b64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64.match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  return JSON.stringify({ client_email: "bot@jayalo.iam.gserviceaccount.com", private_key: pem });
}

describe("playApi.server", () => {
  beforeEach(async () => {
    process.env.PLAY_SERVICE_ACCOUNT_JSON = await fakeServiceAccountJson();
    __resetTokenCacheForTests();
  });
  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.PLAY_SERVICE_ACCOUNT_JSON;
  });

  it("pide un access token y consulta la compra en la URL correcta", async () => {
    const calls: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string) => {
      calls.push(String(url));
      if (String(url).includes("oauth2.googleapis.com")) {
        return new Response(JSON.stringify({ access_token: "tk", expires_in: 3600 }), { status: 200 });
      }
      return new Response(JSON.stringify({ purchaseState: 0, acknowledgementState: 0 }), { status: 200 });
    }));

    const p = await getPlayPurchase("creditos_10usd", "TOKEN123");

    expect(p.purchaseState).toBe(0);
    expect(calls[0]).toContain("oauth2.googleapis.com/token");
    expect(calls[1]).toBe(
      "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
      "com.jayalo.app/purchases/products/creditos_10usd/tokens/TOKEN123",
    );
  });

  it("reutiliza el access token entre llamadas (no re-firma en cada request)", async () => {
    const fetchMock = vi.fn(async (url: string) =>
      String(url).includes("oauth2")
        ? new Response(JSON.stringify({ access_token: "tk", expires_in: 3600 }), { status: 200 })
        : new Response(JSON.stringify({ purchaseState: 0, acknowledgementState: 1 }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await getPlayPurchase("creditos_10usd", "A");
    await getPlayPurchase("creditos_10usd", "B");

    const tokenCalls = fetchMock.mock.calls.filter((c) => String(c[0]).includes("oauth2"));
    expect(tokenCalls).toHaveLength(1);
  });

  it("lanza si Google responde 404 (token inexistente)", async () => {
    vi.stubGlobal("fetch", vi.fn(async (url: string) =>
      String(url).includes("oauth2")
        ? new Response(JSON.stringify({ access_token: "tk", expires_in: 3600 }), { status: 200 })
        : new Response("not found", { status: 404 })));

    await expect(getPlayPurchase("creditos_10usd", "NOPE")).rejects.toThrow(/404/);
  });

  it("acknowledge llama al :acknowledge y NO lanza si ya estaba reconocida", async () => {
    const urls: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string) => {
      urls.push(String(url));
      if (String(url).includes("oauth2")) {
        return new Response(JSON.stringify({ access_token: "tk", expires_in: 3600 }), { status: 200 });
      }
      return new Response(JSON.stringify({ error: { message: "already acknowledged" } }), { status: 400 });
    }));

    await expect(acknowledgePlayPurchase("creditos_10usd", "T")).resolves.toBeUndefined();
    expect(urls[1]).toMatch(/tokens\/T:acknowledge$/);
  });

  it("lanza si falta el secreto de la service account", async () => {
    delete process.env.PLAY_SERVICE_ACCOUNT_JSON;
    __resetTokenCacheForTests();
    await expect(getPlayPurchase("x", "y")).rejects.toThrow(/PLAY_SERVICE_ACCOUNT_JSON/);
  });
});
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `npx vitest run src/lib/playApi.server.test.ts`
Expected: FAIL — no existe `./playApi.server`.

- [ ] **Step 3: Implementar**

Crear `src/lib/playApi.server.ts`:

```ts
/**
 * Cliente de la Google Play Developer API (androidpublisher v3).
 *
 * Escrito a mano en vez de con `googleapis` porque el runtime es Cloudflare
 * Workers: no hay `crypto` de Node ni `fs`. El JWT de la service account se
 * firma con WebCrypto (RS256), que sí existe en Workers.
 *
 * @see https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/get
 */
import type { PlayPurchase } from "./playPurchase";

const PACKAGE_NAME = "com.jayalo.app";
const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";

type ServiceAccount = { client_email: string; private_key: string };

/**
 * El token vive ~1h y el isolate de Workers se reutiliza entre requests:
 * cachearlo evita firmar un JWT y hacer un round-trip a Google en cada compra.
 */
let cachedToken: { value: string; expiresAt: number } | null = null;

/** Solo para tests: limpia el cache entre casos. */
export function __resetTokenCacheForTests() {
  cachedToken = null;
}

function loadServiceAccount(): ServiceAccount {
  const raw = process.env.PLAY_SERVICE_ACCOUNT_JSON;
  if (!raw) throw new Error("Falta PLAY_SERVICE_ACCOUNT_JSON");
  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.client_email || !sa.private_key) throw new Error("PLAY_SERVICE_ACCOUNT_JSON incompleto");
  return sa;
}

const b64url = (bytes: ArrayBuffer | Uint8Array) => {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (const b of arr) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  // El JSON de la service account trae el PEM con \n reales o escapados.
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // 60 s de margen: un token que caduca a mitad de la request no sirve.
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const sa = loadServiceAccount();
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: SCOPE,
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }).toString(),
  });
  if (!res.ok) throw new Error(`Play OAuth ${res.status}: ${await res.text()}`);

  const json = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: json.access_token, expiresAt: now + json.expires_in };
  return json.access_token;
}

/** Lee el estado real de una compra. Fuente de verdad, no el cliente. */
export async function getPlayPurchase(productId: string, token: string): Promise<PlayPurchase> {
  const at = await getAccessToken();
  const url = `${API}/${PACKAGE_NAME}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${at}` } });
  if (!res.ok) throw new Error(`Play API ${res.status}: ${await res.text()}`);
  return (await res.json()) as PlayPurchase;
}

/**
 * Reconoce la compra. Si no se reconoce en 3 días, Google la reembolsa y la
 * revoca automáticamente — y el usuario se quedaría con los créditos Y con el
 * reembolso. Por eso lo hace el SERVIDOR, dentro del mismo flujo que acredita.
 *
 * No lanza ante un fallo de Google: llegados aquí el crédito YA está dado, y
 * tumbar la respuesta haría que el cliente reintentara sin ganar nada. Se
 * registra para poder verlo en los logs del worker.
 */
export async function acknowledgePlayPurchase(productId: string, token: string): Promise<void> {
  const at = await getAccessToken();
  const url = `${API}/${PACKAGE_NAME}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:acknowledge`;
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
    body: "{}",
  });
  if (!res.ok) {
    console.error(`[play-verify] acknowledge ${res.status}:`, await res.text());
  }
}
```

**Cierra la pregunta abierta del spec §5** ("¿la Developer API expone consumo server-side?"):
sí, existe `purchases.products.consume`. **Aun así el consumo se queda en el cliente.** Consumir
desde el servidor no libera la compra de la cola local del plugin: el cliente tendría que llamar
`completePurchase` igualmente, así que el servidor se cargaría un segundo punto de fallo sin
quitarle ninguna responsabilidad al cliente. Lo que sí importa —el reloj de 3 días— lo cierra el
`acknowledge`, y ese sí lo hace el servidor. El consumo solo decide si el SKU se puede recomprar,
y si nunca ocurre, la compra se re-entrega al abrir la app y la idempotencia impide el doble
crédito.

- [ ] **Step 4: Correr los tests**

Run: `npx vitest run src/lib/playApi.server.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Verificar tipos y lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: 0 errores en ambos.

- [ ] **Step 6: Commit**

```bash
git add src/lib/playApi.server.ts src/lib/playApi.server.test.ts
git commit -m "feat(web): cliente de la Play Developer API con service account sobre WebCrypto"
```

---

## Task 4: El endpoint `/api/app/play-verify`

**Files:**
- Create: `src/routes/api/app/play-verify.ts`
- Test: `src/lib/playVerifyBody.test.ts` (validación del cuerpo, ver más abajo)

**Interfaces:**
- Consumes: `judgePurchase` (tarea 2), `getPlayPurchase` / `acknowledgePlayPurchase` (tarea 3), RPC `credit_play_purchase` (tarea 1).
- Produces: `POST /api/app/play-verify` → `200 { balance: number, credited: boolean, points: number }`. La consume la tarea 8.

El patrón de auth se calca de `src/routes/api/app/delete-account.ts` (léelo antes de escribir): Origin fail-closed → rate limit → bearer → `getClaims` envuelto en try/catch.

⚠️ **Diferencia con `delete-account`:** allí la RPC se invoca con el JWT del usuario porque decide por `auth.uid()`. Aquí la RPC es `service_role` (acredita dinero, no puede estar al alcance del cliente), así que el `user_id` se toma del JWT ya validado y se le pasa por parámetro a la RPC.

- [ ] **Step 1: Escribir el test de la validación del cuerpo**

Crear `src/lib/playVerifyBody.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { parsePlayVerifyBody } from "./playVerifyBody";

describe("parsePlayVerifyBody", () => {
  it("acepta un cuerpo válido", () => {
    expect(parsePlayVerifyBody({ purchaseToken: "abc", productId: "creditos_10usd" }))
      .toEqual({ purchaseToken: "abc", productId: "creditos_10usd" });
  });

  it("rechaza un productId que no es de los nuestros", () => {
    expect(parsePlayVerifyBody({ purchaseToken: "abc", productId: "creditos_9999usd" })).toBeNull();
  });

  it("rechaza un token vacío", () => {
    expect(parsePlayVerifyBody({ purchaseToken: "", productId: "creditos_10usd" })).toBeNull();
  });

  it("rechaza campos que no son strings", () => {
    expect(parsePlayVerifyBody({ purchaseToken: 42, productId: "creditos_10usd" })).toBeNull();
  });

  it("rechaza null y undefined", () => {
    expect(parsePlayVerifyBody(null)).toBeNull();
    expect(parsePlayVerifyBody(undefined)).toBeNull();
  });
});
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `npx vitest run src/lib/playVerifyBody.test.ts`
Expected: FAIL — no existe `./playVerifyBody`.

- [ ] **Step 3: Implementar la validación**

Crear `src/lib/playVerifyBody.ts`:

```ts
/**
 * Validación del cuerpo de /api/app/play-verify.
 *
 * La allowlist de productos es una primera criba barata: aunque el id acabe
 * resolviéndose contra `credit_packages` dentro de la RPC (que es la
 * autoridad real), no queremos mandar a la Play API cualquier cadena que
 * llegue por la red.
 */

export const PLAY_PRODUCT_IDS = [
  "creditos_10usd",
  "creditos_50usd",
  "creditos_100usd",
  "creditos_180usd",
] as const;

export type PlayVerifyBody = { purchaseToken: string; productId: string };

export function parsePlayVerifyBody(body: unknown): PlayVerifyBody | null {
  if (!body || typeof body !== "object") return null;
  const { purchaseToken, productId } = body as Record<string, unknown>;
  if (typeof purchaseToken !== "string" || purchaseToken.length === 0) return null;
  if (typeof productId !== "string") return null;
  if (!(PLAY_PRODUCT_IDS as readonly string[]).includes(productId)) return null;
  return { purchaseToken, productId };
}
```

- [ ] **Step 4: Correr el test**

Run: `npx vitest run src/lib/playVerifyBody.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Escribir el endpoint**

Crear `src/routes/api/app/play-verify.ts`:

```ts
// createFileRoute viene de @tanstack/react-router (NO @tanstack/react-start) —
// así lo importan el resto de rutas API de /api/app/*.
import { createFileRoute } from "@tanstack/react-router";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/database";
import {
  getSupabaseUrl,
  getSupabasePublishableKey,
  getSupabaseServiceRoleKey,
} from "@/integrations/supabase/env.server";
import { extractBearerToken } from "@/lib/aiSession.server";
import { checkRateLimit } from "@/lib/rateLimit.server";
import { parsePlayVerifyBody } from "@/lib/playVerifyBody";
import { judgePurchase } from "@/lib/playPurchase";
import { getPlayPurchase, acknowledgePlayPurchase } from "@/lib/playApi.server";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/**
 * Verificación y acreditación de una compra de Google Play (Play Billing v1).
 *
 * Patrón de auth calcado de /api/app/delete-account: Origin fail-closed +
 * rate limit + JWT de sesión validado server-side.
 *
 * ⚠️ A diferencia de delete-account, la RPC va con SERVICE_ROLE: acreditar
 * dinero no puede estar al alcance del cliente (credit_play_purchase no tiene
 * EXECUTE para authenticated, a propósito). El user_id sale del JWT ya
 * validado, NUNCA del cuerpo.
 */
export const Route = createFileRoute("/api/app/play-verify")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const origin = request.headers.get("origin") ?? "";
        const allowedOrigins = [
          process.env.SITE_URL ?? "",
          "https://jayalo.com",
          "https://jallalo.com",
          "https://jayalo.net",
          "https://jallalo.net",
        ].filter(Boolean);
        if (!origin || !allowedOrigins.includes(origin)) {
          return json({ error: "Forbidden" }, 403);
        }

        const allowed = await checkRateLimit(request, {
          name: "app-play-verify",
          maxPerMinute: 20,
        });
        if (!allowed) {
          return json({ error: "Demasiadas solicitudes. Intenta de nuevo en un minuto." }, 429);
        }

        const token = extractBearerToken(request.headers.get("authorization"));
        if (!token) return json({ error: "No autenticado" }, 401);

        const url = getSupabaseUrl();
        const pubKey = getSupabasePublishableKey();
        const svcKey = getSupabaseServiceRoleKey();
        if (!url || !pubKey || !svcKey) return json({ error: "Backend mal configurado" }, 500);

        // getClaims() LANZA con un JWT expirado (no devuelve {error}) — sin el
        // try/catch una sesión vencida recibiría un 500 en vez de un 401.
        const userClient = createClient<Database>(url, pubKey, {
          global: { headers: { Authorization: `Bearer ${token}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
        let userId: string | undefined;
        try {
          const { data: claims, error: claimsErr } = await userClient.auth.getClaims(token);
          userId = claims?.claims?.sub;
          if (claimsErr || !userId) return json({ error: "No autenticado" }, 401);
        } catch {
          return json({ error: "No autenticado" }, 401);
        }

        const parsed = parsePlayVerifyBody(await request.json().catch(() => null));
        if (!parsed) return json({ error: "Petición inválida" }, 400);

        let purchase;
        try {
          purchase = await getPlayPurchase(parsed.productId, parsed.purchaseToken);
        } catch (e) {
          // Google caído o token que no existe: la compra queda pendiente en el
          // cliente y se reintenta al abrir la app. NUNCA decir "falló el pago".
          console.error("[play-verify] Play API:", e);
          return json({ error: "No se pudo confirmar el pago todavía" }, 502);
        }

        const verdict = judgePurchase(purchase);
        if (!verdict.ok) return json({ error: "purchase_not_completed" }, 409);

        const admin = createClient<Database>(url, svcKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        });
        const { data, error } = await admin.rpc("credit_play_purchase", {
          _play_purchase_token: parsed.purchaseToken,
          _product_id: parsed.productId,
          _user_id: userId,
          _environment: verdict.environment,
          _raw: purchase as unknown as never,
        });
        if (error) {
          console.error("[play-verify] credit_play_purchase:", error);
          return json({ error: "No se pudo acreditar" }, 500);
        }

        // El acknowledge va DESPUÉS del crédito y a propósito no rompe la
        // respuesta: el reloj de 3 días de Google importa, pero el usuario ya
        // tiene sus créditos.
        if (verdict.needsAcknowledge) {
          await acknowledgePlayPurchase(parsed.productId, parsed.purchaseToken);
        }

        const row = (data ?? [])[0];
        return json(
          {
            balance: row?.balance ?? 0,
            points: row?.points ?? 0,
            credited: row?.credited === true,
          },
          200,
        );
      },
    },
  },
});
```

- [ ] **Step 6: Regenerar el routeTree y verificar**

Run: `npm run build`
Expected: build verde. (`routeTree.gen.ts` lleva `@ts-nocheck`: una ruta nueva NO la detecta `tsc`, solo el build.)

- [ ] **Step 7: Correr todos los gates**

Run: `npx tsc --noEmit && npm run lint && npx vitest run`
Expected: 0 errores, 0 errores, todos los tests en verde.

- [ ] **Step 8: Commit**

```bash
git add src/routes/api/app/play-verify.ts src/lib/playVerifyBody.ts src/lib/playVerifyBody.test.ts src/routeTree.gen.ts
git commit -m "feat(web): endpoint /api/app/play-verify que verifica y acredita compras de Play"
```

---

## Task 5: Desplegar y verificar el endpoint en vivo

**Files:** ninguno (operación).

- [ ] **Step 1: Mergear a master y desplegar**

El push a `master` dispara el job `deploy` del CI (build → verificación del ref de Supabase horneado → `wrangler deploy` → smoke).

```bash
git checkout master && git merge --no-ff feat/play-billing && git push origin master
```

- [ ] **Step 2: Verificar que la ruta existe y falla cerrada**

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://jayalo.com/api/app/play-verify
```
Expected: `403` — sin header `Origin` la ruta rechaza. Un `404` significa que la ruta no se desplegó (routeTree sin regenerar).

- [ ] **Step 3: Verificar que exige sesión**

```bash
curl -s -X POST https://jayalo.com/api/app/play-verify -H "Origin: https://jayalo.com"
```
Expected: `{"error":"No autenticado"}` (401).

- [ ] **Step 4: Verificar que el secreto está cargado**

Con una sesión válida y un token inventado, la respuesta debe ser `502` ("No se pudo confirmar el pago todavía") por el 404 de Google — **no** un 500 de "Backend mal configurado" ni un error de `PLAY_SERVICE_ACCOUNT_JSON`. Si sale lo segundo, falta el paso 4 del trabajo del PO.

---

## Task 6: Dependencia `in_app_purchase` en la app

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts` (solo si el build lo pide)

- [ ] **Step 1: Añadir la dependencia**

Run: `flutter pub add in_app_purchase`

(No fijamos la versión a mano: que resuelva la actual compatible con el SDK del proyecto. Anotar en el commit qué versión quedó.)

- [ ] **Step 2: Verificar que compila el APK de debug**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL. El plugin añade solo el permiso `com.android.vending.BILLING` al manifest fusionado; no hay que declararlo a mano.

- [ ] **Step 3: Verificar que la suite sigue verde**

Run: `flutter analyze && flutter test`
Expected: 0 issues; todos los tests pasando (baseline 550+).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(app): dependencia in_app_purchase para Play Billing"
```

---

## Task 7: Port a Dart de la lógica de la tienda

**Files:**
- Create: `lib/domain/credit_shop.dart`
- Test: `test/credit_shop_test.dart`

**Interfaces:**
- Produces: `class ShopPackage`, `class ShopTier`, `List<ShopTier> buildShopTiers(List<ShopPackage>)`, `String? tierName(String?)`. Las consume la tarea 10.

Espejo de `src/lib/creditShop.ts` de la web (rama `feat/tienda-creditos-wallet`). Mismo algoritmo, mismos casos de prueba: si divergen, la app y la web anunciarían ahorros distintos para el mismo paquete.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/credit_shop_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/credit_shop.dart';

void main() {
  // Los 4 paquetes reales de producción.
  final packages = [
    const ShopPackage(id: 'a', points: 10, priceUSD: 10, label: 'Inicial — 10 puntos'),
    const ShopPackage(id: 'b', points: 55, priceUSD: 50, label: 'Popular — 55 puntos'),
    const ShopPackage(id: 'c', points: 110, priceUSD: 100, label: 'Pro — 110 puntos'),
    const ShopPackage(id: 'd', points: 200, priceUSD: 180, label: 'Max — 200 puntos'),
  ];

  group('buildShopTiers', () {
    test('ordena por créditos ascendente', () {
      final tiers = buildShopTiers(packages.reversed.toList());
      expect(tiers.map((t) => t.points), [10, 55, 110, 200]);
    });

    test('el ahorro se mide contra el PEOR \$/crédito y nunca es negativo', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.first.savingsPct, 0); // el de entrada ES el peor
      expect(tiers.last.savingsPct, 10); // 0.90 vs 1.00 => 10%
      expect(tiers.every((t) => t.savingsPct >= 0), isTrue);
    });

    test('a igualdad de \$/crédito, "mejor precio" es el paquete MÁS GRANDE', () {
      // Pro (110/\$100) y Popular (55/\$50) empatan a \$0.909; gana Max.
      final tiers = buildShopTiers(packages);
      expect(tiers.firstWhere((t) => t.isBestValue).points, 200);
      expect(tiers.where((t) => t.isBestValue).length, 1);
    });

    test('"Más popular" NO se inventa: solo si el label del admin lo dice', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.where((t) => t.isPopular).map((t) => t.points), [55]);
    });

    test('el estimado de contactos es créditos/3, mínimo 1', () {
      final tiers = buildShopTiers(packages);
      expect(tiers.first.contactsEstimate, 3); // 10/3 = 3.33 -> 3
      expect(
        buildShopTiers([const ShopPackage(id: 'x', points: 1, priceUSD: 2)]).first.contactsEstimate,
        1,
      );
    });

    test('descarta paquetes con puntos o precio no positivos', () {
      final tiers = buildShopTiers([
        const ShopPackage(id: 'ok', points: 10, priceUSD: 10),
        const ShopPackage(id: 'sin-puntos', points: 0, priceUSD: 10),
        const ShopPackage(id: 'gratis', points: 10, priceUSD: 0),
      ]);
      expect(tiers.map((t) => t.id), ['ok']);
    });

    test('lista vacía devuelve lista vacía (no lanza)', () {
      expect(buildShopTiers([]), isEmpty);
    });
  });

  group('tierName', () {
    test('recorta el sufijo cuando repite el número', () {
      expect(tierName('Inicial — 10 puntos'), 'Inicial');
      expect(tierName('Pro — 110 puntos'), 'Pro');
    });

    test('NO mutila un label sin dígitos en el sufijo', () {
      expect(tierName('Ahorro — el más pedido'), 'Ahorro — el más pedido');
    });

    test('devuelve null si no hay label', () {
      expect(tierName(null), isNull);
      expect(tierName('   '), isNull);
    });
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `flutter test test/credit_shop_test.dart`
Expected: FAIL — no existe `lib/domain/credit_shop.dart`.

- [ ] **Step 3: Implementar**

Crear `lib/domain/credit_shop.dart`:

```dart
/// Lógica pura de la tienda de créditos — port de `src/lib/creditShop.ts`
/// (web). Los dos tienen que decir lo MISMO: si divergen, el mismo paquete
/// anuncia un ahorro distinto según dónde se mire.
///
/// Todo se deriva de los paquetes reales de `credit_packages`, nada
/// hardcodeado. El PRECIO que se pinta, en cambio, viene de Play
/// (`ProductDetails.price`, localizado y con impuestos), no de aquí.

/// Créditos promedio por desbloqueo, usados para el estimado de contactos.
/// Punto medio de la escala 1-10 créditos de `pricing-tiers.ts`.
const int avgCreditsPerUnlock = 3;

class ShopPackage {
  const ShopPackage({
    required this.id,
    required this.points,
    required this.priceUSD,
    this.label,
    this.playProductId,
  });

  final String id;
  final int points;
  final double priceUSD;
  final String? label;
  final String? playProductId;
}

class ShopTier {
  const ShopTier({
    required this.id,
    required this.points,
    required this.priceUSD,
    required this.label,
    required this.playProductId,
    required this.perCredit,
    required this.savingsPct,
    required this.contactsEstimate,
    required this.isBestValue,
    required this.isPopular,
  });

  final String id;
  final int points;
  final double priceUSD;
  final String? label;
  final String? playProductId;
  final double perCredit;

  /// % de ahorro contra el peor $/crédito activo. Redondeado, nunca negativo.
  final int savingsPct;

  /// ~contactos desbloqueables (créditos/3, mínimo 1).
  final int contactsEstimate;
  final bool isBestValue;
  final bool isPopular;
}

/// Nombre corto para el chip de tier a partir del label del admin.
///
/// Los labels de producción son "Inicial — 10 puntos": el sufijo repite el
/// número que la tarjeta ya muestra en grande y dice "puntos" (término viejo;
/// la UI dice créditos). Solo se recorta cuando el sufijo trae dígitos, para
/// no mutilar un label legítimo como "Ahorro — el más pedido".
String? tierName(String? label) {
  final raw = (label ?? '').trim();
  if (raw.isEmpty) return null;
  final m = RegExp(r'^(.*?)\s*[—–-]\s*(.*)$').firstMatch(raw);
  final head = m?.group(1);
  final tail = m?.group(2) ?? '';
  final name = (head != null && head.isNotEmpty && RegExp(r'\d').hasMatch(tail))
      ? head.trim()
      : raw;
  return name.isEmpty ? null : name;
}

List<ShopTier> buildShopTiers(List<ShopPackage> packages) {
  final valid = packages.where((p) => p.points > 0 && p.priceUSD > 0).toList();
  if (valid.isEmpty) return const [];

  double perCredit(ShopPackage p) => p.priceUSD / p.points;
  final basePerCredit =
      valid.map(perCredit).reduce((a, b) => a > b ? a : b);

  // Mejor precio: menor $/crédito; a igualdad gana el paquete más grande.
  final best = valid.reduce((a, b) {
    if (perCredit(b) < perCredit(a)) return b;
    if (perCredit(b) == perCredit(a) && b.points > a.points) return b;
    return a;
  });

  final sorted = [...valid]..sort((a, b) => a.points.compareTo(b.points));
  return sorted.map((p) {
    final pc = perCredit(p);
    final savings = ((1 - pc / basePerCredit) * 100).round();
    return ShopTier(
      id: p.id,
      points: p.points,
      priceUSD: p.priceUSD,
      label: p.label,
      playProductId: p.playProductId,
      perCredit: pc,
      savingsPct: savings < 0 ? 0 : savings,
      contactsEstimate: (p.points / avgCreditsPerUnlock).round() < 1
          ? 1
          : (p.points / avgCreditsPerUnlock).round(),
      isBestValue: p.id == best.id,
      isPopular: RegExp('popular', caseSensitive: false).hasMatch(p.label ?? ''),
    );
  }).toList();
}
```

- [ ] **Step 4: Correr los tests**

Run: `flutter test test/credit_shop_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/credit_shop.dart test/credit_shop_test.dart
git commit -m "feat(app): port a Dart de la logica de la tienda de creditos"
```

---

## Task 8: Cliente HTTP de `/api/app/play-verify`

**Files:**
- Modify: `lib/core/config.dart`
- Create: `lib/core/play_verify_client.dart`
- Test: `test/play_verify_client_test.dart`

**Interfaces:**
- Produces: `class PlayVerifyClient` con `Future<PlayVerifyResult> verify({required String accessToken, required String purchaseToken, required String productId})`, y `class PlayVerifyException`. Los consume la tarea 9.

Calca `lib/core/account_deletion_client.dart` (léelo antes): mismo `http.Client` inyectable, mismos headers, mismo manejo de cuerpo no-JSON.

- [ ] **Step 1: Añadir el endpoint a la config**

En `lib/core/config.dart`, junto a los otros tres:

```dart
  static const playVerifyEndpoint = '$siteUrl/api/app/play-verify';
```

- [ ] **Step 2: Escribir los tests que fallan**

Crear `test/play_verify_client_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo_app/core/config.dart';
import 'package:jayalo_app/core/play_verify_client.dart';

void main() {
  test('manda Origin y Bearer, y devuelve el balance', () async {
    late http.Request seen;
    final client = PlayVerifyClient(inner: MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({'balance': 65, 'points': 55, 'credited': true}), 200);
    }));

    final res = await client.verify(
      accessToken: 'JWT', purchaseToken: 'TOK', productId: 'creditos_50usd');

    expect(res.balance, 65);
    expect(res.points, 55);
    expect(res.credited, isTrue);
    expect(seen.headers['Authorization'], 'Bearer JWT');
    expect(seen.headers['Origin'], AppConfig.siteUrl);
    expect(jsonDecode(seen.body), {'purchaseToken': 'TOK', 'productId': 'creditos_50usd'});
  });

  test('credited=false (reintento del mismo token) NO es un error', () async {
    final client = PlayVerifyClient(inner: MockClient((_) async =>
      http.Response(jsonEncode({'balance': 65, 'points': 0, 'credited': false}), 200)));

    final res = await client.verify(
      accessToken: 'JWT', purchaseToken: 'TOK', productId: 'creditos_50usd');

    expect(res.credited, isFalse);
    expect(res.balance, 65);
  });

  test('un 502 se traduce en excepción reintentable', () async {
    final client = PlayVerifyClient(inner: MockClient((_) async =>
      http.Response(jsonEncode({'error': 'No se pudo confirmar el pago todavía'}), 502)));

    await expectLater(
      client.verify(accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
        .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  test('un 409 (compra no completada) NO es reintentable', () async {
    final client = PlayVerifyClient(inner: MockClient((_) async =>
      http.Response(jsonEncode({'error': 'purchase_not_completed'}), 409)));

    await expectLater(
      client.verify(accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()
        .having((e) => e.retryable, 'retryable', isFalse)),
    );
  });

  test('una respuesta que no es JSON no revienta con FormatException', () async {
    final client = PlayVerifyClient(inner: MockClient((_) async =>
      http.Response('<html>502 Bad Gateway</html>', 502)));

    await expectLater(
      client.verify(accessToken: 'J', purchaseToken: 'T', productId: 'creditos_10usd'),
      throwsA(isA<PlayVerifyException>()),
    );
  });
}
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

Run: `flutter test test/play_verify_client_test.dart`
Expected: FAIL — no existe `play_verify_client.dart`.

- [ ] **Step 4: Implementar**

Crear `lib/core/play_verify_client.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Fallo al verificar una compra de Play.
///
/// [retryable] separa "vuelve a intentarlo luego" (red, Google caído) de "esta
/// compra no va a acreditar nunca" (no está pagada). Importa para el copy: al
/// usuario que ya pagó JAMÁS se le dice que el pago falló.
class PlayVerifyException implements Exception {
  PlayVerifyException(this.status, this.message);
  final int status;
  final String message;

  bool get retryable => status >= 500 || status == 429 || status == 0;

  @override
  String toString() => 'PlayVerifyException($status): $message';
}

class PlayVerifyResult {
  const PlayVerifyResult({
    required this.balance,
    required this.points,
    required this.credited,
  });

  final int balance;
  final int points;

  /// false = el servidor ya había acreditado este token (reintento). No es un
  /// error: el saldo devuelto sigue siendo el bueno.
  final bool credited;
}

/// Manda el `purchaseToken` al servidor, que es quien decide si acredita.
/// Mismo patrón que `AccountDeletionClient`: Origin + Bearer del JWT.
class PlayVerifyClient {
  PlayVerifyClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async {
    final http.Response res;
    try {
      res = await _http.post(
        Uri.parse(AppConfig.playVerifyEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Origin': AppConfig.siteUrl,
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'purchaseToken': purchaseToken, 'productId': productId}),
      );
    } catch (e) {
      // Sin red: reintentable por definición.
      throw PlayVerifyException(0, e.toString());
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw PlayVerifyException(res.statusCode, 'Respuesta inválida');
    }

    if (res.statusCode != 200) {
      throw PlayVerifyException(
          res.statusCode, body['error']?.toString() ?? 'Error');
    }

    return PlayVerifyResult(
      balance: (body['balance'] as num?)?.toInt() ?? 0,
      points: (body['points'] as num?)?.toInt() ?? 0,
      credited: body['credited'] == true,
    );
  }
}
```

- [ ] **Step 5: Correr los tests**

Run: `flutter test test/play_verify_client_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/config.dart lib/core/play_verify_client.dart test/play_verify_client_test.dart
git commit -m "feat(app): cliente de /api/app/play-verify"
```

---

## Task 9: Servicio de Play Billing

**Files:**
- Create: `lib/core/play_billing_service.dart`
- Test: `test/play_billing_service_test.dart`

**Interfaces:**
- Consumes: `PlayVerifyClient` (tarea 8).
- Produces: `class PlayBillingService` con `Future<List<ProductDetails>> loadProducts(Set<String> ids)`, `Future<void> buy(ProductDetails p)`, `Stream<CreditPurchaseEvent> get events`, `Future<void> start()`, `void dispose()`. Los consume la tarea 10.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/play_billing_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jayalo_app/core/play_billing_service.dart';
import 'package:jayalo_app/core/play_verify_client.dart';

/// Doble de `PlayVerifyClient` que registra lo que recibió.
class _FakeVerify implements PlayVerifyClient {
  _FakeVerify(this._result, {this.error});
  final PlayVerifyResult _result;
  final Object? error;
  final List<String> seenTokens = [];

  // `implements` basta: el único miembro PÚBLICO de PlayVerifyClient es
  // `verify` (el campo `_http` es privado de su librería, así que no forma
  // parte de la interfaz). No hace falta noSuchMethod.
  @override
  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async {
    seenTokens.add(purchaseToken);
    if (error != null) throw error!;
    return _result;
  }
}

PurchaseDetails _purchase(String token, PurchaseStatus status) => PurchaseDetails(
      productID: 'creditos_50usd',
      purchaseID: 'p1',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    );

void main() {
  test('una compra purchased se verifica en el servidor y emite éxito', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);

    expect(verify.seenTokens, ['TOK']);
    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(events.single.balance, 65);
    // Completar SOLO después de que el servidor confirmó: si se completa antes
    // y la verificación falla, Google da la compra por consumida y el crédito
    // se pierde.
    expect(completed, hasLength(1));
  });

  test('si la verificación es reintentable NO se completa la compra', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: PlayVerifyException(502, 'caído'));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);

    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(completed, isEmpty, reason: 'la compra debe seguir viva para reintentar');
  });

  test('una compra cancelada por el usuario no llama al servidor', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (_) async {},
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.canceled)]);

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.canceled);
  });

  test('credited=false (ya acreditada antes) se trata como éxito y se completa', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 65, points: 0, credited: false));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);

    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(completed, hasLength(1));
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `flutter test test/play_billing_service_test.dart`
Expected: FAIL — no existe `play_billing_service.dart`.

- [ ] **Step 3: Implementar**

Crear `lib/core/play_billing_service.dart`:

```dart
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'play_verify_client.dart';

enum CreditPurchaseKind {
  /// El servidor confirmó: el saldo de [CreditPurchaseEvent.balance] es el bueno.
  credited,

  /// Pagó, pero no pudimos confirmarlo todavía. Se reintenta al abrir la app.
  /// ⚠️ El copy NUNCA puede decir que el pago falló.
  pending,

  /// El usuario cerró la hoja de Google. Sin ruido.
  canceled,

  /// Play devolvió error antes de cobrar.
  failed,
}

class CreditPurchaseEvent {
  const CreditPurchaseEvent(this.kind, {this.balance, this.points});
  final CreditPurchaseKind kind;
  final int? balance;
  final int? points;
}

/// Envuelve `in_app_purchase` y le pone encima la regla del proyecto: **el
/// cliente no acredita nada**. Solo transporta el `purchaseToken` al servidor
/// y actúa según lo que el servidor conteste.
///
/// `completePurchase` y `accessToken` se inyectan para poder testear todo el
/// flujo sin el canal de plataforma de Play.
class PlayBillingService {
  PlayBillingService({
    required PlayVerifyClient verifyClient,
    required Future<String?> Function() accessToken,
    required Future<void> Function(PurchaseDetails) completePurchase,
    InAppPurchase? iap,
  })  : _verify = verifyClient,
        _accessToken = accessToken,
        _complete = completePurchase,
        _iapOrNull = iap;

  final PlayVerifyClient _verify;
  final Future<String?> Function() _accessToken;
  final Future<void> Function(PurchaseDetails) _complete;

  // PEREZOSO a propósito: `InAppPurchase.instance` toca el canal de
  // plataforma, que en `flutter test` no existe. Si se resolviera en el
  // constructor, los tests de esta clase reventarían sin haber ejercitado
  // nada. `handlePurchases` no lo necesita.
  InAppPurchase? _iapOrNull;
  InAppPurchase get _iap => _iapOrNull ??= InAppPurchase.instance;

  final _events = StreamController<CreditPurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Stream<CreditPurchaseEvent> get events => _events.stream;

  /// Engancha el stream de Play. Debe llamarse ANTES de comprar: las compras
  /// que quedaron a medias en un arranque anterior se re-entregan aquí.
  Future<void> start() async {
    _sub ??= _iap.purchaseStream.listen(handlePurchases);
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> loadProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  Future<void> buy(ProductDetails product) =>
      _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));

  /// Pública a propósito: es lo que se testea.
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
          break;

        case PurchaseStatus.canceled:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.canceled));
          if (p.pendingCompletePurchase) await _complete(p);
          break;

        case PurchaseStatus.error:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.failed));
          if (p.pendingCompletePurchase) await _complete(p);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndCredit(p);
          break;
      }
    }
  }

  Future<void> _verifyAndCredit(PurchaseDetails p) async {
    final jwt = await _accessToken();
    if (jwt == null) {
      // Sin sesión no se puede acreditar a nadie. La compra queda VIVA (no se
      // completa) y se reintenta cuando el usuario vuelva a entrar.
      _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      return;
    }

    try {
      final res = await _verify.verify(
        accessToken: jwt,
        // En Android `serverVerificationData` ES el purchaseToken.
        purchaseToken: p.verificationData.serverVerificationData,
        productId: p.productID,
      );
      // credited=false significa "este token ya se había acreditado", que
      // también es un final feliz: el balance devuelto es el correcto.
      _events.add(CreditPurchaseEvent(
        CreditPurchaseKind.credited,
        balance: res.balance,
        points: res.points,
      ));
      // Completar SOLO ahora. Antes de la confirmación del servidor,
      // completar consume la compra en Google y el crédito se perdería.
      if (p.pendingCompletePurchase) await _complete(p);
    } on PlayVerifyException catch (e) {
      if (e.retryable) {
        // No se completa: la compra sigue en la cola de Play y se vuelve a
        // entregar al abrir la app.
        _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      } else {
        _events.add(const CreditPurchaseEvent(CreditPurchaseKind.failed));
        if (p.pendingCompletePurchase) await _complete(p);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
```

- [ ] **Step 4: Correr los tests**

Run: `flutter test test/play_billing_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/play_billing_service.dart test/play_billing_service_test.dart
git commit -m "feat(app): servicio de Play Billing con verificacion server-side"
```

---

## Task 10: Pantalla de la tienda de créditos

**Files:**
- Modify: `lib/data/repos.dart` (añadir `activeCreditPackages()`)
- Create: `lib/features/provider/credit_shop_screen.dart`
- Modify: `lib/core/router.dart` (ruta `/tienda-creditos`)
- Test: `test/credit_shop_screen_test.dart`

**Interfaces:**
- Consumes: `buildShopTiers`/`tierName`/`ShopPackage` (tarea 7), `PlayBillingService` (tarea 9).
- Produces: `class CreditShopScreen`, `Future<void> openCreditShop(BuildContext)`. Los consume la tarea 11.

**Diseño** (ya aprobado, sección "Versión app (Flutter)" de `2026-08-07-tienda-creditos-wallet-design.md`): banda violeta `Brand.primary → 0xFF5B2EE0` con la mascota asomando detrás del panel; carrusel horizontal con snap; por tarjeta el chip de tier, los créditos en grande, el beneficio ("~N contactos"), el ahorro y el precio **de Play**; sello "Pago seguro con Google Play".

⚠️ **El precio que se pinta es el de `ProductDetails.price`**, nunca `priceUSD` de la BD: Play redondea a sus escalones por país y en muchos países recauda el impuesto. `priceUSD` solo alimenta el cálculo de ahorro.

⚠️ Si un producto no aparece en `notFoundIDs` de Play, **su tarjeta no se pinta** y se reporta al tracker de errores. La tienda nunca muestra un paquete que no se puede comprar.

- [ ] **Step 1: Añadir la lectura de paquetes en `repos.dart`**

`credit_packages` tiene `GRANT SELECT` para `authenticated` y política `USING (true)`, así que se lee directo:

```dart
/// Paquetes activos con producto de Play. Los créditos SIEMPRE vienen de aquí
/// (la consola de Play solo aporta el precio localizado).
Future<List<ShopPackage>> activeCreditPackages() async {
  final rows = await supa
      .from('credit_packages')
      .select('id, points, price_usd, label, play_product_id')
      .eq('is_active', true)
      .not('play_product_id', 'is', null)
      .order('sort_order');
  return (rows as List)
      .map((r) => ShopPackage(
            id: r['id'] as String,
            points: (r['points'] as num).toInt(),
            priceUSD: (r['price_usd'] as num).toDouble(),
            label: r['label'] as String?,
            playProductId: r['play_product_id'] as String?,
          ))
      .toList();
}
```

- [ ] **Step 2: Escribir los tests de widget que fallan**

Crear `test/credit_shop_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/credit_shop.dart';
import 'package:jayalo_app/features/provider/credit_shop_screen.dart';

void main() {
  final tiers = buildShopTiers(const [
    ShopPackage(id: 'a', points: 10, priceUSD: 10, label: 'Inicial — 10 puntos',
        playProductId: 'creditos_10usd'),
    ShopPackage(id: 'b', points: 55, priceUSD: 50, label: 'Popular — 55 puntos',
        playProductId: 'creditos_50usd'),
  ]);

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('pinta el precio de PLAY, no el USD de la base de datos', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      // Precio tal como lo devuelve Play: localizado y con impuesto.
      playPrices: const {'creditos_10usd': 'RD\$650.00', 'creditos_50usd': 'RD\$3,200.00'},
      onBuy: (_) {},
    )));

    expect(find.text('RD\$650.00'), findsOneWidget);
    expect(find.textContaining('\$10.00'), findsNothing);
  });

  testWidgets('no pinta la tarjeta de un producto que Play no conoce', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (_) {},
    )));

    expect(find.text('Inicial'), findsOneWidget);
    expect(find.text('Popular'), findsNothing);
  });

  testWidgets('marca "Más popular" solo donde el label del admin lo dice', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00', 'creditos_50usd': 'RD\$3,200.00'},
      onBuy: (_) {},
    )));

    expect(find.text('Más popular'), findsOneWidget);
  });

  testWidgets('el sello dice Google Play y no menciona la web ni PayPal', (t) async {
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (_) {},
    )));

    expect(find.textContaining('Google Play'), findsWidgets);
    // Anti-steering: ni PayPal ni jayalo.com pueden aparecer en esta pantalla.
    expect(find.textContaining('PayPal'), findsNothing);
    expect(find.textContaining('jayalo.com'), findsNothing);
  });

  testWidgets('el CTA entrega el id de producto de Play', (t) async {
    String? bought;
    await t.pumpWidget(host(CreditShopBody(
      tiers: tiers,
      playPrices: const {'creditos_10usd': 'RD\$650.00'},
      onBuy: (id) => bought = id,
    )));

    await t.tap(find.byKey(const ValueKey('buy_creditos_10usd')));
    expect(bought, 'creditos_10usd');
  });

  testWidgets('sin productos disponibles muestra un vacío, no una lista rota', (t) async {
    await t.pumpWidget(host(const CreditShopBody(
      tiers: [], playPrices: {}, onBuy: _noop)));

    expect(find.textContaining('No hay paquetes disponibles'), findsOneWidget);
  });
}

void _noop(String _) {}
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

Run: `flutter test test/credit_shop_screen_test.dart`
Expected: FAIL — no existe `credit_shop_screen.dart`.

- [ ] **Step 4: Implementar la pantalla**

Crear `lib/features/provider/credit_shop_screen.dart` con dos piezas separadas a propósito:

- `CreditShopBody` — **puro**: recibe `tiers`, `playPrices` (mapa `playProductId → precio ya formateado por Play`) y `onBuy`. Es lo que testean los widget tests, sin plugin ni red.
- `CreditShopScreen` — el `StatefulWidget` que carga (`activeCreditPackages()` + `loadProducts`), arranca el `PlayBillingService`, escucha `events` y pinta `CreditShopBody`.

El esqueleto de `CreditShopBody` — es el contrato que fijan los tests, hay que respetarlo literal:

```dart
/// Parte PURA de la tienda: sin plugin, sin red, sin Supabase. Todo lo que
/// pinta llega por parámetro, que es lo que la hace testeable.
class CreditShopBody extends StatelessWidget {
  const CreditShopBody({
    super.key,
    required this.tiers,
    required this.playPrices,
    required this.onBuy,
  });

  final List<ShopTier> tiers;

  /// playProductId -> precio YA formateado por Play (localizado, con impuesto
  /// donde Google lo recauda). Es el único precio que se muestra.
  final Map<String, String> playPrices;

  /// Recibe el id de producto de Play del paquete elegido.
  final void Function(String playProductId) onBuy;

  @override
  Widget build(BuildContext context) {
    // Una tarjeta sin precio de Play NO se pinta: significa que el id no está
    // dado de alta en la consola y el botón llevaría a un callejón sin salida.
    final visibles = tiers
        .where((t) => t.playProductId != null && playPrices.containsKey(t.playProductId))
        .toList();

    if (visibles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay paquetes disponibles ahora mismo.'),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const PageScrollPhysics(),
            itemCount: visibles.length,
            itemBuilder: (context, i) {
              final t = visibles[i];
              return _TierCard(
                tier: t,
                playPrice: playPrices[t.playProductId]!,
                onBuy: () => onBuy(t.playProductId!),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Pago seguro con Google Play'),
        ),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.playPrice, required this.onBuy});
  final ShopTier tier;
  final String playPrice;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final name = tierName(tier.label);
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null) Chip(label: Text(name)),
          if (tier.isPopular) const Text('Más popular'),
          if (tier.isBestValue) const Text('Mejor precio'),
          Text('${tier.points}', style: Theme.of(context).textTheme.displaySmall),
          const Text('créditos'),
          Text('~${tier.contactsEstimate} contactos'),
          if (tier.savingsPct > 0) Text('Ahorras ${tier.savingsPct}%'),
          Text(playPrice), // <- de Play, NUNCA tier.priceUSD
          FilledButton(
            key: ValueKey('buy_${tier.playProductId}'),
            onPressed: onBuy,
            child: const Text('Comprar'),
          ),
        ],
      ),
    );
  }
}
```

`CreditShopScreen` (el `StatefulWidget`) hace el resto: en `initState` arranca el
`PlayBillingService`, carga en paralelo `activeCreditPackages()` y
`loadProducts({...playProductIds})`, y escucha `events`. Copy de cada evento — **el de `pending`
es el delicado**:

| Evento | Mensaje |
|---|---|
| `credited` | «Listo. Tienes N créditos.» |
| `pending` | «Estamos confirmando tu pago. Te avisamos en un momento.» |
| `canceled` | sin ruido: se cierra la hoja |
| `failed` | «No se pudo completar la compra.» |

**Nunca** decir que el pago falló en el caso `pending`: el usuario ya pagó, y el dinero está en
Google. Los productos que Play devuelva en `notFoundIDs` se reportan al tracker de errores
(`report-error`, mismo camino que el resto de la app).

Estética (spec ya aprobado): banda superior con `LinearGradient(Brand.primary, Color(0xFF5B2EE0))`,
mascota en `Positioned(top: -N)` detrás del panel, tarjetas `Brand.card` (`Brand.dCard` en
oscuro), chip de tier con `Brand.accent/accentFg`, ahorro en `Brand.success`.

- [ ] **Step 5: Correr los tests**

Run: `flutter test test/credit_shop_screen_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Registrar la ruta**

En `lib/core/router.dart`, junto a las demás rutas del proveedor:

```dart
            GoRoute(
              path: '/tienda-creditos',
              builder: (_, _) => const CreditShopScreen(),
            ),
```

Y el helper que usarán los tres call sites de la tarea 11:

```dart
/// Sustituye a `openProviderWallet` (ADR-0031). El pago ocurre DENTRO de la
/// app: Play prohíbe llevar al usuario a otro método de pago.
Future<void> openCreditShop(BuildContext context) =>
    context.push('/tienda-creditos');
```

- [ ] **Step 7: Verificar la suite completa**

Run: `flutter analyze && flutter test`
Expected: 0 issues; toda la suite en verde.

- [ ] **Step 8: Commit**

```bash
git add lib/features/provider/credit_shop_screen.dart lib/core/router.dart lib/data/repos.dart test/credit_shop_screen_test.dart
git commit -m "feat(app): tienda de creditos in-app con precios de Google Play"
```

---

## Task 11: Retirada del link-out (los 3 sitios + anti-steering)

**Files:**
- Modify: `lib/features/provider/unlock_flow.dart` (`openProviderWallet`, ~línea 58-70)
- Modify: `lib/features/provider/product_interest_detail_screen.dart` (~línea 175)
- Modify: `lib/features/shared/profile_avatar_button.dart` (~líneas 21 y 292)
- Modify: `lib/core/config.dart` (retirar `walletUrl`)
- Modify: `lib/data/repos.dart` (retirar `createWalletLoginLink`, ~línea 1516)
- Test: `test/no_link_out_test.dart` (crear)

**Interfaces:**
- Consumes: `openCreditShop` (tarea 10).

⚠️ **Esta es la tarea que hace el binario publicable.** Mientras quede un solo link-out, el AAB no puede subir ni a prueba interna.

- [ ] **Step 1: Escribir el test de regresión que falla**

Crear `test/no_link_out_test.dart`. Es un test sobre el CÓDIGO FUENTE a propósito: lo que hay que garantizar es que nadie reintroduzca el enlace, y eso no se ve ejercitando widgets.

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Play prohíbe llevar al usuario a un método de pago que no sea el suyo
/// (link-out) y también insinuárselo (anti-steering). Un solo call site
/// reintroducido hace el binario NO publicable, así que se vigila desde los
/// tests en vez de confiar en la revisión.
void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('ningún fichero abre el wallet web ni acuña magic links', () {
    final ofensores = <String>[];
    for (final f in dart) {
      final src = f.readAsStringSync();
      if (src.contains('walletUrl') ||
          src.contains('createWalletLoginLink') ||
          src.contains('create-wallet-login-link') ||
          src.contains('/provider/wallet')) {
        ofensores.add(f.path);
      }
    }
    expect(ofensores, isEmpty,
        reason: 'link-out a Play prohibido reintroducido en: $ofensores');
  });

  test('ninguna pantalla sugiere pagar fuera de la app', () {
    final ofensores = <String>[];
    final prohibido = RegExp(
        r'(recargar en la web|desde la web|en jayalo\.com|más barato en)',
        caseSensitive: false);
    for (final f in dart) {
      if (prohibido.hasMatch(f.readAsStringSync())) ofensores.add(f.path);
    }
    expect(ofensores, isEmpty, reason: 'copy anti-steering en: $ofensores');
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `flutter test test/no_link_out_test.dart`
Expected: FAIL — lista los 3 ficheros con `walletUrl`/`createWalletLoginLink` más `config.dart` y `repos.dart`.

- [ ] **Step 3: Sustituir el primer call site**

En `lib/features/provider/unlock_flow.dart`, `openProviderWallet` se borra entera (con su comentario de ADR-0031 y el `launchAuthenticatedUrl`) y todos sus usos pasan a `openCreditShop(context)` de `lib/core/router.dart`. Si algún import de `secure_web_launch.dart` o `createWalletLoginLink` queda huérfano, se retira.

- [ ] **Step 4: Sustituir los otros dos**

- `lib/features/provider/product_interest_detail_screen.dart:175` — el bloque `target = Uri.parse(await createWalletLoginLink())` + `launchAuthenticatedUrl` pasa a `await openCreditShop(context)`.
- `lib/features/shared/profile_avatar_button.dart` — igual; además quitar `createWalletLoginLink` de la lista de imports de la línea 21.

- [ ] **Step 5: Retirar las piezas muertas**

- `lib/core/config.dart`: borrar `static const walletUrl = '$siteUrl/provider/wallet';`
- `lib/data/repos.dart`: borrar `Future<String> createWalletLoginLink()` (~línea 1516).

⚠️ La **edge function** `create-wallet-login-link` se queda desplegada por ahora: alguien con la versión vieja instalada todavía la llama. Su retirada es una tarea aparte, posterior al despliegue (anotada en "Fuera de alcance" del spec).

- [ ] **Step 6: Correr el test de regresión**

Run: `flutter test test/no_link_out_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Correr la suite completa y compilar**

Run: `flutter analyze && flutter test && flutter build apk --debug`
Expected: 0 issues, toda la suite verde, BUILD SUCCESSFUL.

- [ ] **Step 8: Commit**

```bash
git add lib/ test/no_link_out_test.dart
git commit -m "feat(app): retirada del link-out al wallet web — la recarga ocurre dentro de la app"
```

---

## Cierre: smoke real en prueba interna

No es una tarea de código; es lo que convierte "compila" en "funciona". Requiere los pasos 3 y 4 del trabajo del PO hechos.

- [ ] Construir el AAB: `./scripts/build-release-apk.ps1 -Bundle` (verificar la firma con `jarsigner -verify`).
- [ ] Subirlo al track de **prueba interna** y añadir el correo del tester a **license testers**.
- [ ] Instalar DESDE PLAY (no el APK local: los productos solo son visibles para una app instalada desde un track y firmada con la llave de Play).
- [ ] **Login con Google** — es lo primero que hay que probar: si falta el tercer OAuth client, falla justo aquí y solo aquí.
- [ ] Abrir la tienda: se pintan 4 tarjetas con precios en la moneda local.
- [ ] Comprar el paquete de USD 10 (sin cobro real, por license tester) → el saldo sube en los créditos correctos.
- [ ] Comprobar en `payment_orders` que la fila quedó con `provider='play'`, `environment='sandbox'` (compra de tester) y el `play_purchase_token`.
- [ ] **Repetir la compra del mismo paquete** → debe poder comprarse de nuevo (se consumió) y crear una fila NUEVA.
- [ ] Matar la app justo tras pagar y volver a abrirla → la compra pendiente se re-entrega, el servidor responde `credited=false` y el saldo **no** se duplica.
- [ ] Recorrer los 3 antiguos link-outs (desbloqueo de oferta sin saldo, interés en producto, menú del avatar) → los tres llevan a la tienda in-app.
