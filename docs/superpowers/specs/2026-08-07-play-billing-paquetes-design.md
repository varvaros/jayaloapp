# Play Billing en la app — v1: solo paquetes de créditos

**Fecha:** 2026-08-07 · **Estado:** propuesta, pendiente de revisión del PO
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
queda para una fase 2 con datos reales de uso: no es requisito de Play, duplicaría el alta en
consola (16 productos en vez de 6) y arrastra una pregunta de producto sin cerrar (si ofrecerlo
en los 10 niveles o solo hasta el 5-6).

## Diseño

### 1. Retirada del link-out (3 sitios + anti-steering)

- `lib/features/provider/unlock_flow.dart:62`
- `lib/features/provider/product_interest_detail_screen.dart:175`
- `lib/features/shared/profile_avatar_button.dart:292`

Los tres abren `AppConfig.walletUrl`. Pasan a abrir la **tienda in-app**. `walletUrl` se retira
de `lib/core/config.dart`.

⚠️ **No basta con quitar el enlace.** La política *anti-steering* también prohíbe dirigir al
usuario al pago externo: hay que eliminar todo texto que mencione la web, insinúe precios de
fuera o sugiera que allá es más barato. Fuera de la app (correo, redes, la propia web) no aplica.

`lib/domain/recharge.dart` (`shouldOfferRecharge`) se conserva: la decisión "¿hay saldo?" no
cambia, solo cambia a dónde lleva.

### 2. Productos en la consola

6 productos **gestionados, consumibles** (`INAPP`), uno por paquete activo. Ids estables y
legibles: `creditos_15`, `creditos_30`, `creditos_80`, `creditos_120`, `creditos_165`,
`creditos_270`.

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
  → POST /api/play/verify  { purchaseToken, productId }
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

### 4. Idempotencia y atomicidad

Se reutiliza el patrón ya probado de PayPal (`credit_captured_payment`): el `UPDATE ... WHERE
status='created' RETURNING` es el claim atómico, y si el crédito lanza, todo hace rollback.

`payment_orders` gana `provider` (`'paypal' | 'play'`) y `play_purchase_token` con **índice
único parcial**. Un reintento con el mismo token no acredita dos veces; devuelve el balance
actual. Los grants siguen igual (server-only, `SELECT` para authenticated).

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
- Manual, en prueba interna con license testers: compra real de mecánica sin cobro.

## Trabajo previo que NO es código

- **Tercer OAuth client** en `jayalo-501005` con el SHA-1 de **Play App Signing**: Google re-firma
  el AAB con su llave, así que quien instale desde la tienda —incluida la prueba interna— tiene un
  certificado distinto al del keystore de subida. Sin esto el login con Google falla solo para
  ellos y no se reproduce en local (ya pasó una vez, `ApiException: 10`).
- **Service account** con acceso a la Play Developer API + su clave como secreto del worker.
- Alta de los 6 productos y de los license testers.

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
- Cambiar la escalera de precios. La v1 usa los paquetes activos de `credit_packages`; si el PO
  aprueba la escalera nueva (15/30/80/120/165/270), se da de alta en el admin y en la consola,
  pero es una tarea de datos, no de código.
