# Hallazgo — "Cerrada" en la lista, y el aviso de completado que dice "Nuevo mensaje"

Fecha: 2026-08-03
Reportado por: el PO, usando la app
Estado: **sin diseñar**. Punto de partida, no una solución aprobada.

Son dos cosas distintas que salieron juntas porque comparten concepto: qué pasa cuando un trato
**termina**. Se pueden hacer por separado y en cualquier orden.

---

## A) El aviso de completado se anuncia como "Nuevo mensaje"

### Qué pasa

Al marcar una conversación como completada, al otro lado le llega una notificación titulada
**"Nuevo mensaje"** con el cuerpo "marcado como completado". El título miente: no es un mensaje que
alguien haya escrito.

### Qué debería pasar (petición del PO)

Algo como **"Conversación marcada como completada por el proveedor"**. La redacción exacta está por
decidir; lo que importa es que el título diga lo que de verdad pasó.

### Dónde está, exactamente

**No está en la app.** `notifications_screen.dart` pinta `n.title` tal cual viene de la fila de la
base (`:526`). El único "Nuevo mensaje" del código Dart es el **respaldo** de
`push/push_service.dart:29,101`, que solo actúa si el push llega sin título — no es este caso.

La causa: marcar como completada **inserta un mensaje de sistema en el chat**
(`chat_screen.dart:1215` compone el texto), y ese INSERT dispara el trigger de "mensaje nuevo", que
escribe la notificación con su título genérico. El aviso viaja por el camino de los mensajes porque,
técnicamente, es un mensaje.

**El concepto ya existe:** `domain/notifications.dart:18` conoce el tipo `sale_completed_provider`.
Hay que ver si se puede reutilizar en vez de inventar uno.

### El nudo

El arreglo es **una migración sobre el trigger**, no un cambio de copy en Dart. Hay que decidir si el
mensaje de sistema deja de generar notificación de mensaje y pasa a generar una propia, o si el
trigger aprende a distinguir los mensajes de sistema. Lo segundo es más pequeño; lo primero, más
limpio.

**Requiere el conector de Supabase autorizado** (Ajustes → Conectores en claude.ai). Sin él se puede
escribir la migración, pero no aplicarla ni verificarla contra la base.

---

## B) Una solicitud cuya conversación se cerró sin completar

### Qué pasa

No se distingue de las demás. Hoy la lista de solicitudes solo conoce cinco fases
(`domain/phase.dart:1`): esperando, con ofertas, aceptada, desbloqueada y completada.

### Qué debería pasar (petición del PO)

Que salga **"Cerrada", en gris** — apagada como la completada, pero **sin el violeta**: el violeta es
para el trato que terminó bien, y este no terminó, se apagó.

### El dato clave, y por qué no es lo que parece

**Nada pone el estado de una solicitud en `'closed'`.** Se revisaron las migraciones: ese valor está
contemplado en `phase.dart:20` de forma defensiva, pero no ocurre nunca. Así que **no basta con
mapear un estado existente: hay que crear la fase.**

Lo que sí se cierra es la **conversación**, que es otro objeto. La tabla `conversations` tiene
`closed_at`, `status` (con valores como `perdido` — "No concretado") e `inactivity_warned_at`, y se
enlaza con la solicitud por `source_id`. La regla, entonces, es algo así:

> conversación con `closed_at` puesto que **no** acabó completada → la solicitud es "Cerrada".

Queda por confirmar qué valores toma `status` en la práctica y cuál marca el completado.

### El nudo

1. **Toca el enum de fases**, y `RequestPhase` lo consumen `phaseChip`, `blockedReasonForPhase`,
   `toneFor` y sus tests. Añadir un valor obliga a revisar cada `switch`.
2. **La lista de solicitudes no consulta conversaciones.** `my_requests_screen._fetch` trae
   solicitudes y `provider_offers` (`:314-345`); haría falta una consulta más. Ojo con el
   rendimiento: esa pantalla ya pasó por una auditoría.
3. El autocierre por inactividad de conversaciones estaba **specificado pero sin construir** — hay
   que comprobar si existe hoy o si "se autocierra" es todavía una intención.

## Qué comprobar antes de dar por bueno el arreglo

- Una solicitud completada sigue en gris con su banda violeta "Completado" (no se toca).
- Una cuya conversación se cerró sin completar sale en gris con "Cerrada" y **sin violeta**.
- Las fases vivas (esperando / con ofertas / aceptada / desbloqueada) no cambian.
- La lista no se vuelve más lenta al abrir.

## Alcance

La parte A es **base de datos** (repo web, migración). La parte B es **solo la app**.
