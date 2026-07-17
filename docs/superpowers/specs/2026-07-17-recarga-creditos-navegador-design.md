# Recarga de créditos desde la app — diseño (2026-07-17)

**Decisión marco:** ADR-0031 (repo jayalo-main). Los créditos son el cobro por
acceder a leads de servicios del mundo real (no moneda virtual, no contenido
digital, no features premium). **La app nunca procesa pagos**: recargar abre el
wallet web en el navegador del sistema.

## Alcance

Dar salida al proveedor sin saldo: hoy "Mis ofertas" muestra el balance y el
desbloqueo calcula `enough = balance >= cost`, pero cuando no alcanza no hay
ningún camino para recargar dentro de la app.

Fuera de alcance (YAGNI, decisión PO): deep link de retorno, polling de
balance, paquetes/precios dentro de la app, WebView, Play Billing.

## Diseño

### 1. Dominio puro (`app/lib/domain/recharge.dart`) — con tests

- `const walletUrl = 'https://jayalo.com/provider/wallet';`
- `bool shouldOfferRecharge({required int? balance, required int cost})` —
  `true` cuando `balance == null || balance < cost`. Es la única decisión de
  negocio; el resto es UI.

### 2. Apertura del navegador

- Dependencia nueva: `url_launcher` (modo `LaunchMode.externalApplication` —
  navegador del sistema, nunca WebView in-app, por ADR-0031).
- Helper `openWallet()` en la capa de UI que lanza `walletUrl` y muestra un
  SnackBar de error si el device no puede abrirlo (caso raro: sin navegador).

### 3. Puntos de entrada (ambos en `my_offers_screen.dart`)

- **Tarjeta de saldo**: `trailing` con `TextButton` "Recargar" → `openWallet()`.
  Visible siempre (recargar no requiere estar corto de saldo).
- **Flujo de desbloqueo**: donde hoy `enough == false` deshabilita/frustra el
  desbloqueo, el CTA pasa a "Recargar créditos" → `openWallet()`. El copy
  existente "Costo: X · Tu saldo: Y" se conserva.

### 4. Refresco al volver

`_MyOffersScreenState` pasa a `WidgetsBindingObserver`:
`didChangeAppLifecycleState(resumed)` → re-fetch de `myOffers()` +
`walletBalance()` (el mismo `_load` actual). Así el saldo comprado en el
navegador aparece solo al volver, sin pull-to-refresh manual.

### 5. Copy (es-DO)

- Botón: "Recargar" / CTA sin saldo: "Recargar créditos".
- Nunca describir créditos como dinero/moneda. Si hace falta explicar:
  "Los créditos se usan para contactar clientes".

## Errores

- `launchUrl` devuelve `false` o lanza → SnackBar "No se pudo abrir el
  navegador. Visita jayalo.com para recargar." (la URL queda dicha).
- El re-fetch al volver reutiliza el manejo de errores existente de la
  pantalla (FutureBuilder).

## Testing

- Unit (TDD, estilo del repo): `shouldOfferRecharge` (null, menor, igual,
  mayor) y `walletUrl` correcta.
- Device (manual, PO o adb): botón abre Chrome en el wallet; comprar con el
  paquete test de RD$0.01 (activo en prod) y verificar que el saldo se
  refresca al volver a la app.

## Riesgos aceptados

- La sesión web no se comparte: puede tocar loguearse en jayalo.com en el
  navegador (fricción aceptada, ADR-0031).
- El paquete "test" (2 pts / USD 0.01) sigue activo en prod — útil para este
  QA; desactivarlo sigue en launch-checklist (no lo resuelve este feature).
