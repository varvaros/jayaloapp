# Tutorial coach-mark "mantén presionado" — Diseño

Fecha: 2026-07-26
Estado: aprobado, listo para plan de implementación
Repo: jayalo-app · rama base: feat/error-tracking

## Problema

El botón de confirmar por hold (`HoldToConfirmButton`) ya se rellena al
mantenerlo presionado y ya rotula "Mantén presionado para aceptar/desbloquear".
Aun así, usuarios nuevos **tocan** el botón (tap corto) esperando que actúe como
un botón normal, sueltan antes de completar el gesto y creen que "no funciona".

Queremos un **tutorial animado** que aparezca encima del botón y demuestre el
gesto en bucle, de modo que el usuario entienda que hay que **mantener**, no
tocar. Se apaga para siempre una vez que logra el gesto.

## Alcance

- Solo Flutter (`jayalo-app`). La web queda fuera.
- Dos flujos, ambos con hoja (bottom sheet) que contiene el `HoldToConfirmButton`:
  - Cliente: aceptar oferta — `lib/features/client/offer_actions.dart`
  - Proveedor: desbloquear — `lib/features/provider/unlock_flow.dart`
- Sin cambios de backend (BD/RPC/edge). Todo local y visual.
- Un solo commit, reversible.

### Fuera de alcance (YAGNI)

- Sin tope de repeticiones (se muestra hasta el primer éxito, sin cap).
- Sin sincronización entre dispositivos (pista local por dispositivo).
- Sin tutorial en la web.
- No toca el flujo alterno de WhatsApp (`HoldToConfirmTone.free` para "ver
  WhatsApp") — solo los dos gestos principales de aceptar y desbloquear.

## Decisiones de producto

| Tema | Decisión |
| --- | --- |
| Disparador | Se muestra hasta que el usuario complete **un** hold exitoso de ese gesto; después nunca más. |
| Alcance del "ya lo logré" | **Separado por gesto**: `accept` y `unlock` cuentan aparte. Un usuario que hace ambos roles ve cada tutorial una vez. |
| Forma visual | **Spotlight**: se atenúa el contenido de la hoja y el botón queda iluminado, con recuadro-guía encima y demo animada sobre el botón real. |
| Escape | **Tap fuera del botón** cierra el coach-mark y deja la hoja normal. No marca nada como logrado → reaparece la próxima vez hasta que haya un hold exitoso. |
| Persistencia | Local (`SharedPreferences`), mismo patrón que `OpenedConversationsStore`. |

## Arquitectura

Dos unidades nuevas, mínimas y con una sola responsabilidad cada una, más un
punto de integración en cada hoja.

### 1. `HoldTutorialStore` (persistencia)

Nuevo archivo `lib/features/shared/hold_tutorial_store.dart`. Copia directa del
patrón de `lib/features/chat/opened_conversations.dart`:

- `ChangeNotifier` con un `Set<String>` en memoria de gestos ya logrados.
- Llaves: `'accept'`, `'unlock'`.
- Clave de `SharedPreferences`: `hold_tutorial_done` (lista de strings).
- API:
  - `Future<void> ensureLoaded()` — carga perezosa una vez, best-effort (si
    falla, arranca vacío → el tutorial se muestra).
  - `bool isDone(String gesture)` — ¿ya logró ese gesto?
  - `void markDone(String gesture)` — idempotente; notifica y persiste en
    segundo plano.
- Instancia singleton exportada: `final holdTutorialStore = HoldTutorialStore();`

Racional: una pista local basta para "ya aprendió el gesto"; evita una tabla/RPC
nueva y el costo de red. Best-effort: en el peor caso el tutorial se muestra de
más, nunca de menos (falla hacia enseñar).

### 2. `HoldCoachMark` (overlay visual)

Nuevo widget en `lib/features/shared/brand_kit.dart`, junto a
`HoldToConfirmButton` (viven en el mismo archivo, comparten tokens de marca).

Un overlay `Stack` que se pinta **sobre** el contenido de la hoja:

- **Velo spotlight:** capa semitransparente oscura sobre el contenido de la hoja
  (precio, mascota), con un "hueco" iluminado (recorte/realce) alrededor del
  botón. El botón queda visualmente destacado.
- **Recuadro flotante** encima del botón:
  - Texto: `Mantén presionado para aceptar` o `Mantén presionado para
    desbloquear` (según el gesto).
  - Mini-barra que se llena sola en bucle (demo).
  - Puntero/tail apuntando hacia abajo al botón.
- **Demo sobre el botón real:** el botón se rellena solo en bucle usando el mismo
  relleno claro que ya usa el hold real, con un "dedito" (círculo translúcido)
  pulsante encima. Esto muestra el gesto sobre el control de verdad, no en una
  maqueta aparte.
- **Toque pasa al botón:** la zona del botón NO queda bloqueada por el velo; el
  usuario puede empezar a mantener presionado. Un tap en la zona oscurecida (fuera
  del botón) invoca `onDismiss`.

Parámetros del widget (propuesta, a afinar en el plan):

- `required String label` — copy del gesto.
- `required VoidCallback onDismiss` — tap fuera del botón.
- `required ValueListenable<double> progress` — el mismo `ValueNotifier<double>`
  del `HoldToConfirmButton`; se usa para **pausar la demo** cuando el usuario está
  presionando de verdad (`progress > 0`).
- `required HoldToConfirmTone tone` — para que el color de la demo coincida con el
  del botón (violeta pagado).
- `child` — el botón (o el área que lo contiene), para poder recortarlo/realzarlo.

Animación: un `AnimationController` propio en bucle (`repeat`) para la demo;
`SingleTickerProviderStateMixin`. Se detiene/oculta la demo cuando `progress > 0`
para no competir con el relleno real.

### 3. Integración en las hojas

En cada hoja, envolver el área del botón de modo que:

```
if (!holdTutorialStore.isDone(gesture))
  mostrar HoldCoachMark(... child: HoldToConfirmButton(...))
else
  HoldToConfirmButton(...) tal cual
```

Detalles:

- Reusar el `ValueNotifier<double>` de progreso que **ya existe** en ambas hojas
  (`_acceptProgress` en `offer_actions.dart:157`; `holdProgress` en
  `unlock_flow.dart:98`) — no crear un segundo timer ni doble conteo.
- Llamar `holdTutorialStore.ensureLoaded()` al construir/abrir la hoja.
- En el callback de éxito del hold (`onConfirmed` / `status == completed`), llamar
  `holdTutorialStore.markDone('accept'|'unlock')`.
- `onDismiss` oculta el coach-mark en esa apertura (estado local de la hoja), sin
  marcar el store → reaparece en la próxima apertura.
- Escuchar el store con `AnimatedBuilder`/`ListenableBuilder` para que, si ya está
  logrado, no se muestre.

## Flujo de datos

1. Se abre la hoja → `ensureLoaded()` → `isDone(gesture)`.
2. Si `false`: se pinta `HoldCoachMark` sobre el botón; la demo corre en bucle.
3. El usuario:
   - **Mantiene presionado el botón** → `progress > 0` → demo se pausa → el hold
     real avanza → al completar, `onConfirmed` ejecuta la acción y
     `markDone(gesture)` → el store notifica → el coach-mark ya no se mostrará.
   - **Toca fuera del botón** → `onDismiss` → se oculta el coach-mark en esta
     apertura; el store no cambia → reaparece la próxima vez.
   - **Cierra la hoja** sin gesto → el store no cambia → reaparece la próxima vez.

## Manejo de errores / bordes

- `SharedPreferences` falla → `ensureLoaded` deja el set vacío → tutorial se
  muestra (falla hacia enseñar, nunca bloquea la acción).
- `markDone` persiste en segundo plano; si falla, el próximo arranque podría
  volver a mostrar el tutorial una vez más — aceptable.
- Si el usuario suelta a mitad (tap corto), `progress` vuelve a 0 → la demo se
  reanuda; el coach-mark sigue visible (aún no logró el gesto). Esto es
  exactamente el caso que el tutorial busca corregir.
- El velo no debe interceptar el gesto sobre el botón (probar que el hold real
  funciona con el overlay encima).

## Pruebas

- `flutter analyze` en 0.
- Suite en verde (baseline actual ~415–420 tests).
- Tests de `HoldTutorialStore`: `isDone` falso por defecto; `markDone` lo vuelve
  verdadero e idempotente; separación por gesto (`accept` no afecta `unlock`).
- Test de widget del coach-mark: se muestra cuando `!isDone`; `onDismiss` se
  dispara al tocar fuera del botón; la demo se pausa cuando `progress > 0`.
- Verificación visual en device (smoke) queda para el PO tras el build.

## Reversibilidad

Un solo commit. Revertirlo elimina el archivo del store, el widget nuevo del
`brand_kit.dart` y los envoltorios en las dos hojas, dejando los
`HoldToConfirmButton` tal como están hoy. Sin migraciones ni estado remoto que
deshacer.
