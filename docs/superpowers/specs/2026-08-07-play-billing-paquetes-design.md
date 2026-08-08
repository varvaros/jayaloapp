# Play Billing en la app — v1: solo paquetes de créditos

**Fecha:** 2026-08-07 · **Revisado:** 2026-08-08 · **Estado:** listo para escribir el plan
**Reemplaza:** ADR-0031 (la app abre el wallet web en el navegador) → requiere **ADR-0033**
**Alcance web:** endpoint de verificación + BD (repo `jayalo-main`)
**Alcance app:** cliente de compra + pantalla de tienda (repo `jayalo-app`)

## Por qué

`ADR-0031` decidió que la app nunca procesa pagos: el botón "Recargar" abre
`jayalo.com/provider/wallet` en el navegador del sistema. Eso es exactamente el *link out* que
la política de pagos de Play prohíbe. Los créditos desbloquean funcionalidad dentro de la app ⇒
son contenido digital ⇒ **Play Billing es obligatorio**. La web con PayPal sigue igual: queda
fuera del alcance de Play.

## Restricción que ordena todo el trabajo

**Ningún binario con el link-out puede subir a Play, ni siquiera a prueba interna.** Y
**Play Billing no se puede probar sin haber subido antes** (los productos solo son visibles para
una app instalada desde un track, firmada con la llave de Play, con el comprador dado de alta
como *license tester*).

De esas dos juntas se deduce que **no existe un estado intermedio publicable**: la retirada del
link-out y la implementación del billing viajan en el mismo binario. El primer AAB que Google
vea es ya compatible y con billing dentro.

## Alcance de la v1 (decisión del PO, 2026-08-07)

**Solo paquetes de créditos.** El "desbloqueo directo" (comprar el desbloqueo suelto, +50 %)
queda para una fase 2 con datos reales de uso: no es requisito de Play, cuadruplicaría el alta en
consola (14 productos en vez de 4) y arrastra una pregunta de producto sin cerrar (si ofrecerlo
en los 10 niveles o solo hasta el 5-6).

## Diseño

### 1. Retirada del link-out (3 sitios + anti-steering)

- `lib/features/provider/unlock_flow.dart:62`
- `lib/features/provider/product_interest_detail_screen.dart:175`
- `lib/features/shared/profile_avatar_button.dart:292`

Los tres abren `AppConfig.walletUrl`. Pasan a abrir la **tienda in-app**. `walletUrl` se retira
de `lib/core/config.dart`.

⚠️ **Los tres pasan primero por `createWalletLoginLink()`** (`lib/data/repos.dart:1516` → edge
function `create-wallet-login-link`), que emite un magic link para entrar al wallet web ya
autenticado; `walletUrl` es solo el fallback. Esa función deja de llamarse desde la app: el
helper de Dart se retira con los tres call sites. **La web NO la llama** (verificado: cero
referencias en `src/`), así que al retirar la app queda sin ningún consumidor. Como acuña magic
links, dejarla desplegada y huérfana es superficie de ataque gratis: se retira en una tarea
aparte, **después** de que el binario nuevo esté en producción y nadie con la versión vieja
instalada dependa de ella.

⚠️ **No basta con quitar el enlace.** La política *anti-steering* también prohíbe dirigir al
usuario al pago externo: hay que eliminar todo texto que mencione la web, insinúe precios de
fuera o sugiera que allá es más barato. Fuera de la app (correo, redes, la propia web) no aplica.

`lib/domain/recharge.dart` (`shouldOfferRecharge`) se conserva: la decisión "¿hay saldo?" no
cambia, solo cambia a dónde lleva.

### 2. Productos en la consola

**Decisión del PO (2026-08-07): la escalera de la v1 son los 4 paquetes ACTUALES tal cual** —
`Inicial 10/USD 10`, `Popular 55/USD 50`, `Pro 110/USD 100`, `Max 200/USD 180`. Cero trabajo de
datos. (La escalera nueva de 6 niveles queda descartada por ahora. Anotado para cuando se
retome: `Pro — 110/$100` da exactamente el MISMO $/crédito que dos `Popular`, así que hoy no
aporta nada al que compara.)

4 productos **gestionados, consumibles** (`INAPP`), uno por paquete activo.

⚠️ **Los ids de producto de Play son permanentes e irreutilizables**: una vez creado, un id no se
puede borrar ni reciclar para otra cosa. Por eso NO se atan al número de créditos (que el admin
puede cambiar mañana) sino al **precio**, que es lo que de verdad define el producto en la
consola:

| Paquete | Id de Play | Precio | Créditos hoy |
|---|---|---|---|
| Inicial | `creditos_10usd` | USD 10 | 10 |
| Popular | `creditos_50usd` | USD 50 | 55 |
| Pro | `creditos_100usd` | USD 100 | 110 |
| Max | `creditos_180usd` | USD 180 | 200 |

Cambiar cuántos créditos da un paquete = editar `credit_packages` en el admin, sin tocar la
consola ni publicar binario. Cambiar el PRECIO sí obliga a un producto nuevo (id nuevo) y a
desactivar el viejo.

**Los créditos que otorga cada producto NO viven en la consola ni en el cliente**: viven en la
BD. Se añade `play_product_id` (texto, único, nullable) a `credit_packages`. El admin sigue
siendo el único sitio donde se define "este paquete da N créditos". La consola solo aporta el
**precio localizado con impuestos**.

Consecuencia de diseño: **la app nunca muestra el precio en USD de nuestra BD**, muestra el de
`ProductDetails` (Play redondea a sus escalones por país y en muchos países recauda el impuesto).
El % de ahorro y el "$X por crédito" se calculan en el cliente con el precio de Play y los
créditos del servidor — es el mismo algoritmo de `src/lib/creditShop.ts`, portado a Dart con
tests espejo.

### 3. Flujo de compra

```
app: queryProductDetails(ids)  ─┐
app: GET paquetes (créditos)   ─┴→ pinta la tienda (precio de Play + créditos de la BD)
usuario compra
  → purchaseStream entrega PurchaseDetails(purchaseToken, productId)
  → POST /api/app/play-verify  { purchaseToken, productId }
      servidor:
        1. valida el token contra la Play Developer API (purchases.products.get)
        2. exige purchaseState = purchased
        3. resuelve los créditos por play_product_id  ← autoritativo, nunca del cliente
        4. acredita ATÓMICAMENTE con idempotencia
        5. acknowledge en Play
      → devuelve { balance }
  → app: completePurchase() (consume, para que el SKU se pueda recomprar)
```

**El costo/beneficio se resuelve siempre en el servidor.** Es la misma regla que ya rige las RPCs
de cobro: un `productId` del cliente solo sirve para *buscar*, nunca para *decidir* cuánto
acreditar.

**Dónde vive el endpoint: `/api/app/play-verify`** (no `/api/play/verify`). La app ya consume
tres rutas bajo `/api/app/*` declaradas en `lib/core/config.dart` —`business-editor-link`,
`reverse-geocode`, `delete-account`—, todas con el mismo guard: check de `Origin` **fail-closed**
más JWT bearer de la sesión. Colgar el verificador de pago de otro prefijo obligaría a inventar
un cuarto patrón de auth para la ruta que mueve dinero. El `user_id` se toma **del JWT**, nunca
del cuerpo.

⚠️ Al añadir la ruta, añadir también su entrada en `config.dart`: el fallback de `siteUrl` es lo
que hace que una app de debug apunte al sitio correcto.

### 4. Idempotencia y atomicidad

Se hereda la *forma* del patrón de PayPal (`credit_captured_payment`): claim atómico + crédito en
UNA transacción, y si el crédito lanza, todo hace rollback.

⚠️ **Pero el claim NO puede ser el mismo `UPDATE`.** El de PayPal funciona porque la orden se
**crea antes** de pagar: la fila `status='created'` ya existe cuando llega la captura, y el
`UPDATE ... WHERE status='created' RETURNING` es la carrera que solo uno gana. En Play no hay
fila previa — la compra ocurre entera dentro de Google y nos enteramos cuando ya está pagada. Un
`UPDATE` sin fila que actualizar caería en el `IF NOT FOUND`, que significa *"ya se acreditó,
devuelve el balance"* → **la primera compra legítima de cada usuario se tragaría el crédito en
silencio**. El usuario paga y no recibe nada, y la idempotencia bloquea el reintento.

El claim para Play es el **INSERT**:

```sql
INSERT INTO public.payment_orders (user_id, provider, environment, play_purchase_token,
                                   package_id, points, amount_usd, status, ...)
VALUES (...)
ON CONFLICT (play_purchase_token) DO NOTHING
RETURNING user_id, points;
-- 0 filas ⇒ token ya visto ⇒ devolver balance actual, NO acreditar
```

Es el mismo invariante (una sola vía gana, el resto lee) con la primitiva correcta para un pago
que nace ya cobrado. Va en una RPC hermana, `credit_play_purchase`, `SECURITY DEFINER`, con el
mismo `REVOKE ALL ... FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE TO service_role` que
`credit_captured_payment` — Supabase Cloud auto-otorga EXECUTE a `authenticated` en cada función
nueva, y sin el REVOKE cualquier usuario se autoacredita por PostgREST inventando un token.
Añadir el check correspondiente a `scripts/db-security-check.sql`.

### 4.1 Migración de `payment_orders`

La tabla está modelada para PayPal y **no admite una fila de Play tal como está** (verificado
contra `20260624192907`):

| Columna hoy | Problema con Play | Cambio |
|---|---|---|
| `paypal_order_id text NOT NULL UNIQUE` | Play no tiene order id de PayPal | **quitar el `NOT NULL`** (el `UNIQUE` se queda: sigue siendo único cuando hay valor) |
| — | falta la clave de idempotencia de Play | `play_purchase_token text` + **índice único parcial** `WHERE play_purchase_token IS NOT NULL` |
| `provider text NOT NULL DEFAULT 'paypal'` | ya existe, sin CHECK | `CHECK (provider IN ('paypal','play'))` + **CHECK cruzado**: `paypal` exige `paypal_order_id`, `play` exige `play_purchase_token` |
| `environment CHECK IN ('sandbox','live')` | una compra de license tester es "real" mecánicamente | se mapea desde la API: `purchaseType = 0` (Test) ⇒ `'sandbox'`, ausente ⇒ `'live'` |
| `amount_usd numeric NOT NULL` | la Developer API **no devuelve el precio** | se guarda el precio USD del paquete en `credit_packages` — es el importe **nominal**, no lo que Google cobró (Play localiza y a veces incluye impuesto). Documentarlo en la migración: este campo deja de ser conciliable con el cobro real en las filas de Play |

El CHECK cruzado es lo que impide que quitar el `NOT NULL` abra la puerta a filas sin ninguna
referencia de pago. `credit_packages` gana `play_product_id text UNIQUE` (nullable: la web sigue
vendiendo paquetes sin producto de Play).

Los grants no cambian: `payment_orders` sigue siendo **server-only** para escritura (`SELECT`
para authenticated) — es justo lo que sostiene que `points` sea de fiar.

### 5. El plazo de 3 días

Si una compra no se reconoce en 3 días, Google la reembolsa y revoca automáticamente. El agujero
real: si el servidor acredita y el cliente muere antes de consumir, el usuario se queda con los
créditos **y** con el reembolso.

Por eso **el `acknowledge` lo hace el servidor**, dentro del mismo flujo que acredita, no el
cliente. El consumo (para poder recomprar el SKU) sí lo hace el cliente; si nunca ocurre, la
compra pendiente se vuelve a entregar al abrir la app y la idempotencia impide el doble crédito.

⚠️ A confirmar contra la documentación al implementar: si la Developer API expone consumo
server-side además de `acknowledge`, hacerlo también ahí y dejar al cliente sin responsabilidad
sobre el dinero.

### 6. Pantalla de tienda

**El diseño ya está aprobado y especificado**: la tienda de créditos de
`docs/superpowers/specs/2026-08-07-tienda-creditos-wallet-design.md` (repo web), sección
"Versión app (Flutter)". Banda violeta, mascota asomando, carrusel horizontal con snap, tier /
beneficio / ahorro por tarjeta. Cambia el sello: "Pago seguro con Google Play" en vez de PayPal.

### 7. Errores

- Compra cancelada por el usuario → sin ruido, se cierra la hoja.
- Fallo de red al verificar → la compra queda pendiente; se reintenta al abrir la app. El mensaje
  dice que el pago se está confirmando, **nunca** que falló.
- Producto no encontrado en Play (id mal dado de alta) → la tarjeta no se pinta; se reporta al
  tracker de errores. La tienda nunca muestra un paquete que no se puede comprar.

### 8. Pruebas

- Dart: el helper de ahorro/beneficio portado, con los mismos casos que `creditShop.test.ts`
  (incluido "a igualdad de $/crédito gana el paquete grande" y "el ahorro nunca es negativo").
- Servidor: verificación con respuestas de la Developer API fijadas — token válido, token de otro
  paquete, `purchaseState` no comprado, reintento con el mismo token (no acredita dos veces).
  **Caso obligatorio, el que rompía el diseño anterior: token nunca visto ⇒ SÍ acredita.** Un
  claim mal elegido hace que el primer pago de cada usuario se pierda en silencio, y un test que
  solo compruebe "no acredita dos veces" lo daría por bueno.
- Manual, en prueba interna con license testers: compra real de mecánica sin cobro.

## Trabajo previo que NO es código

- **Tercer OAuth client** en `jayalo-501005` con el SHA-1 de **Play App Signing**: Google re-firma
  el AAB con su llave, así que quien instale desde la tienda —incluida la prueba interna— tiene un
  certificado distinto al del keystore de subida. Sin esto el login con Google falla solo para
  ellos y no se reproduce en local (ya pasó una vez, `ApiException: 10`).
- **Service account** con acceso a la Play Developer API + su clave como secreto del worker.
- Alta de los 4 productos (`creditos_10usd`, `creditos_50usd`, `creditos_100usd`,
  `creditos_180usd`) y de los license testers.

## Preguntas abiertas (no bloquean escribir el plan)

1. ¿La cuenta de Play Console es **persona física u organización**? Decide si aplica la prueba
   cerrada de 12 testers × 14 días continuos antes de producción. No afecta al diseño, solo al
   calendario.
2. ¿Se subió ya algún AAB a esa cuenta? Si se subió el build actual, tiene link-out y conviene
   retirarlo antes de que nadie lo revise.
3. Confirmar la comisión aplicable (15 % reducida vs 30 %). No cambia el código; cambia si el PO
   quiere revisar la escalera de precios.

## Fuera de alcance (a propósito)

- Desbloqueo directo (+50 %) — fase 2.
- Suscripciones.
- iOS.
- Cambiar la escalera de precios. La v1 usa los 4 paquetes activos de `credit_packages`. Si más
  adelante el PO aprueba la escalera nueva (15/30/80/120/165/270), es una tarea de datos + alta
  en consola, no de código. (El paquete `test` de 2 pts / USD 0.01 ya está **inactivo**
  —verificado el 2026-08-06—, así que no entra en el alta de la consola.)
- Retirar la edge function `create-wallet-login-link` (tarea aparte, posterior al despliegue).
