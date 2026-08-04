# Bandeja limpia — las notificaciones leídas desaparecen, y retención de 30 días

Fecha: 2026-08-03
Estado: **decidido por el PO**, sin implementar. Tanda aparte del plan de "Cerrada".

> "Vamos a ponerle una política de 30 días, pero las que se leen desaparecen de las
> notificaciones. 0 notificaciones es una bandeja limpia." — PO

## Las dos reglas

1. **Al leerse, una notificación desaparece de la bandeja.** No se borra la fila: se deja de
   pintar. Cero notificaciones = bandeja limpia.
2. **Las leídas se borran a los 30 días.** Las SIN LEER no se tocan: son la bandeja visible del
   usuario, y borrarlas sería quitarle de delante un aviso que nunca vio.

Como las leídas ya son invisibles, esos 30 días no son una ventana de lectura: son ventana de
**soporte** (poder responder a un "a mí nunca me avisaron").

## Ocultar ≠ borrar — la trampa

`NotificationsBell.tsx:248` lleva un comentario que avisa exactamente de esto:

> Marcar leídas = poner `read_at` (NUNCA borrar: se pierde el historial y se descuadran los
> contadores de chat que cuentan `message_new` sin leer).

Sigue vigente. Los contadores que dependen de filas SIN LEER no se ven afectados por ocultar las
leídas, pero sí se romperían si borráramos al leer:

- badge de la campana (`read_at is null`)
- no leídos por conversación en la lista de chats
- `_fetchUnseenRequests` en `my_requests_screen`: solicitudes con `offer_new` sin leer
- `useUnreadMessageCount` en la web

**Propiedad bonita que sale gratis:** con las leídas ocultas, el badge y la longitud de la lista
pasan a ser el mismo número. Hoy pueden divergir.

## Alcance

**App** (`features/notifications/notifications_screen.dart`)
- La consulta filtra por `read_at is null`.
- Abrir la pantalla NO marca nada (verificado): solo el tap en una tarjeta (`_open` →
  `_markReadOptimistic`) y el botón de marcar todas. Así que la bandeja no se vacía sola al abrirla.
- El marcar-leída optimista hoy atenúa la tarjeta en sitio; pasa a **retirarla** con animación.
- El botón "marcar todas como leídas" se renombra a **"Vaciar"** — sigue haciendo lo mismo, pero
  ahora el efecto visible es que desaparece todo y el nombre viejo lo describiría mal. Sin diálogo
  de confirmación (decisión del PO: la bandeja limpia es el objetivo, no añadir fricción).

**Web** (`components/marketplace/NotificationsBell.tsx`)
- Mismo filtro, **server-side** (`.is("read_at", null)`): la consulta trae las 20 más recientes y
  filtrar en cliente gastaría el cupo en filas invisibles.
- `markAllRead` conserva su lógica; cambia su etiqueta.
- Ojo con `referral_reward`: el modal busca una `referral_reward` sin leer dentro de `items`. Sigue
  funcionando con el filtro puesto, pero hay que comprobarlo.

**Base de datos** (migración en el repo web)
- Función de purga + `cron.schedule`, siguiendo el molde de `purge_old_page_events` /
  `purge_old_error_events`, que ya existen.
- Borra `notifications` con `read_at IS NOT NULL AND read_at < now() - interval '30 days'`.
- Se corta por `read_at`, no por `created_at`: lo que arranca el reloj es haberla leído.

## Qué se pierde, dicho en voz alta

El usuario deja de poder repasar lo que ya vio. Si toca una notificación sin querer, desaparece de
la vista y no hay forma de recuperarla desde la UI. Es el precio de la bandeja limpia y el PO lo
acepta a propósito.

## Qué comprobar

- Tocar una notificación la retira de la lista y baja el badge en 1; los dos números siguen
  coincidiendo.
- Abrir la pantalla NO vacía nada.
- "Vaciar" deja la bandeja a cero y el badge a cero.
- Abrir un chat sigue marcando sus `message_new` y bajando el contador de esa conversación.
- La pestaña de solicitudes sigue marcando "ofertas sin ver" correctamente.
- El modal de `referral_reward` sigue apareciendo.
- La purga borra solo leídas de más de 30 días — verificado en `BEGIN`/`ROLLBACK` con filas
  sembradas de ambos lados de la frontera.
