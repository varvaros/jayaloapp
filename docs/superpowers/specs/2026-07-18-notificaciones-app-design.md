# Centro de notificaciones in-app — diseño

**Fecha:** 2026-07-18 · **Estado:** aprobado por el PO
**Objetivo:** darle a la app Flutter la UI de notificaciones que hoy solo existe en la web
(campana + badge + pantalla de lista), con una dirección visual propia ("tarjetas que
respiran"), y arreglar de paso el ruteo de taps de push que hoy manda a pantallas
equivocadas.

## Decisiones del PO

1. **Entrada = campana compartida en el header**, NO 5ª pestaña. Widget `NotificationBell`
   en `actions:` del AppBar de las 4 pantallas principales de ambos roles.
2. **Badge sin castigar batería** (misma doctrina del chat): conteo por `COUNT head:true`
   al montar pantalla principal y al resume de background. SIN socket persistente para el
   badge. Realtime en vivo SOLO dentro de la pantalla de notificaciones abierta.
3. **Dirección visual: "B · Tarjetas que respiran" + encabezados por día.** Elegida sobre
   la alternativa "línea de tiempo" en mockups. Detalle abajo.
4. **Referidos diferidos**: `referral_invite` / `referral_reward` se muestran como ítems
   informativos simples (sin botón compartir ni modal de recompensa). YAGNI v1.
5. **Estética**: app delicada, colores de marca respetados, animaciones fluidas. Se
   aprueba agregar el paquete `flutter_animate`.

## 1. Datos (sin cambios de backend)

Tabla `notifications` existente: `id, user_id, kind, title, body, link, read_at,
created_at, entity_type, entity_id`. RLS ya en producción (la web la usa).

- **Lista**: `select` de las columnas necesarias, `eq user_id` implícito por RLS,
  `order created_at desc`, paginado por `range` en páginas de **30** con botón
  "Cargar más" (como la web; no scroll infinito).
- **Conteo no-leídas**: `count: exact, head: true` con `read_at is null`.
- **Marcar leída** = `update read_at = now()`. **NUNCA DELETE** (convención del proyecto).
- **Marcar todas** = mismo update con `read_at is null`.
- **Body**: puede traer `__VALUE__:N`; se limpia con la misma regex de la web.
- **Realtime**: canal Postgres Changes sobre `notifications` filtrado por `user_id`,
  suscrito SOLO mientras la pantalla `/notifications` está visible y la app en foreground
  (patrón del chat). INSERT → tarjeta nueva animada + conteo +1.

## 2. Campana y badge (`NotificationBell`)

- Ícono campana en el AppBar de: my_requests, create_request (cliente), inbox, my_offers
  (proveedor) — y las pantallas principales equivalentes de cada shell.
- Badge circular rojo con el conteo, tope **"9+"**.
- Ciclo de vida del conteo: fetch al montar la pantalla que la contiene + al
  `AppLifecycleState.resumed`. Tras marcar leídas: baja optimista + revalida.
- Tap → `push('/notifications')`.
- Animaciones: badge aparece con pop elástico (scale 0→1 con rebote); pulso suave cuando
  el conteo sube.
- El estado del conteo se comparte entre pantallas (un solo store/notifier), no un fetch
  por campana duplicado.

## 3. Pantalla `/notifications` — "Tarjetas que respiran"

**Estructura**: AppBar con back + "Notificaciones" + píldora "N nuevas" (se encoge hasta
desaparecer al llegar a cero) + acción "marcar todas" (ícono checks, visible solo si hay
no-leídas). Cuerpo: tarjetas agrupadas bajo encabezados de día — "Hoy", "Ayer", fecha
corta ("mar 15") para lo anterior.

**Tarjeta**: muy redondeada (radius ~16), ícono en contenedor redondeado a la izquierda,
título + body (1–2 líneas, ellipsis) + hora relativa en español corto ("hace 5 min",
"ayer"). Sin leer: fondo teñido del color de su familia + textos en tonos oscuros de la
misma familia. Leída: fondo neutro (surface variant), textos apagados, ícono gris.

**Familias de color por kind** (sin leer):

| Familia | Kinds | Color |
|---|---|---|
| Mensajes | `message_new` | verde-azulado (teal) |
| Ofertas/ventas | `offer_*`, `job_response_new`, `sale_completed_provider`, `request_cancelled_provider`, `offer_cancelled_customer` | violeta de marca (#7C3AED) |
| Wallet | `wallet_*` | ámbar |
| Reseñas | `review_*` | rosa |
| Sistema | `welcome_*`, `referral_*`, desconocidos | neutro |

Cada familia define tinte de fondo, color de ícono y de textos (derivados del seed
Material 3 donde aplique; los tonos exactos se ajustan en implementación cuidando
contraste en light y dark). Ícono por kind mapeado como la web (~20 kinds, con fallback
de familia para kinds nuevos).

**Gestos**:

- **Swipe horizontal** sobre una tarjeta sin leer = marcar leída. La tarjeta NO se
  elimina: vuelve a su sitio con micro-rebote y el color se desvanece a gris (~300ms).
  Swipe sobre una leída: no-op (resiste con rebote corto).
- **Tap** = marcar leída (optimista; si el update falla igual navega) + navegar según
  `mapLinkToRoute(link)`.
- **Marcar todas**: las tarjetas teñidas se apagan en cascada suave; badge y píldora a 0.

**Animaciones** (`flutter_animate`):

- Entrada de la lista: cascada (fade + slide 12px hacia arriba, ~40ms de stagger).
- Llegada realtime: la tarjeta nueva se inserta deslizándose desde arriba con un
  destello breve de su color de familia.
- Transiciones de pantalla: las nativas de Material 3 ya usadas por la app.

**Estados**:

- Cargando: skeletons con forma de tarjeta.
- Vacío: "Aún no tienes notificaciones" + guía corta de qué llegará aquí.
- Error: mensaje amable + botón **Reintentar** (patrón existente de la app).
- Paginación: "Cargar más" al final mientras la última página venga llena.

## 4. Ruteo del tap — `mapLinkToRoute` extendido

Compartido por push (FCM) y por la lista. Links reales que escribe el backend
(verificados en migraciones de jayalo-main):

| Link | Ruta nativa |
|---|---|
| `/messages?c=<id>` y `/messages/<id>` | `/messages/<id>` |
| `/messages` | `/messages` |
| `/requests/<id>` | `/client/request/<id>` |
| `/provider/requests/<id>` | `/provider/request/<id>` |
| `/provider/offers`, `/provider?view=offers` | `/provider/offers` |
| `/provider?panel=wallet`, `/provider/wallet`, resto `/provider/*` | `/provider` |
| desconocido (`/empleos/…`, vacío, etc.) | fallback **por rol activo** |

Arregla 2 bugs vivos del push: (a) `/provider/requests/<id>` hoy cae en
`/provider/offers` aunque existe `/provider/request/:id`; (b) fallback fijo `/client`
que manda al proveedor a la pantalla equivocada. La firma pasa a recibir el rol activo
(o un resolver) para el fallback.

## 5. Capas y pruebas (TDD, patrón del chat)

- `lib/domain/notifications.dart` — puro, testeable: modelo `AppNotification`,
  `familyFor(kind)`, `iconFor(kind)`, `cleanBody` (regex `__VALUE__`), fecha relativa,
  agrupación por día, `mapLinkToRoute` (movido/extendido desde push_service con el rol).
- `lib/data/notifications_repository.dart` — lista paginada, conteo head, marcar
  una/todas, suscripción realtime.
- `lib/ui/notification_bell.dart` — campana + badge + store de conteo compartido.
- `lib/ui/notifications_screen.dart` — pantalla, gestos, estados.
- Ruta `/notifications` en el router (dentro del shell del rol activo o fuera, según el
  patrón existente de `/messages`).
- Cada task cierra con `flutter test` (baseline 108) + `flutter analyze` 0 + commit.
- `push_service.dart` pasa a delegar en el `mapLinkToRoute` de domain (una sola verdad).

## Fuera de alcance (v1)

- Acciones ricas de referidos (compartir link, modal de recompensa).
- Depuración de push/FCM (token viejo tras reinstalar es tema aparte, pre-existente).
- Preferencias de notificación (activar/desactivar tipos).
- Cambios de backend: cero migraciones, cero Edge Functions.
