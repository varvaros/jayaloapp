# Chat de la app móvil — diseño

**Fecha:** 2026-07-17 · **Estado:** aprobado por el PO
**Objetivo:** llevar el chat cliente↔proveedor de la web a la app Flutter con paridad
funcional, optimizado para no castigar el celular (batería, datos, querys).

## Decisiones del PO

1. **Alcance: core completo, IA diferida.** Todo el chat humano-a-humano. Se difieren SOLO
   la barra del Asistente IA de ventas (el panel de control — el bot responde igual porque
   vive server-side e inserta filas en `conversation_messages`), el portafolio ("mostrar
   trabajos pasados") y el selector de imágenes de la tienda.
2. **Lista por RPC agregado nuevo** (`get_my_conversations_list`), no el patrón de 4 queries
   de la web.
3. **Realtime solo en primer plano.** Socket abierto únicamente con un chat visible y la app
   en foreground. En background: push FCM (ya operativo) + refresh al volver.
4. **Fotos por Storage + URL**, no base64 embebido como la web. El render acepta ambos
   formatos (compatibilidad con mensajes web viejos).
5. **Tests mientras se construye, no al final** (regla del PO): ciclo TDD por task.

## 1. Arquitectura de datos

### RPC nuevo: `get_my_conversations_list()` (migración en jayalo-main)

Devuelve, para el usuario autenticado, una fila por conversación:

- Columnas de `conversations`: `id, kind, customer_id, provider_user_id, product_name,
  agreed_price, agreed_hourly_rate, product_image_url, status, updated_at`.
- Peer: `peer_name`, `peer_avatar_url` (misma lógica que `get_my_conversation_peers`).
- Último mensaje vía `LEFT JOIN LATERAL ... ORDER BY created_at DESC LIMIT 1`:
  `last_kind, last_body, last_created_at`.
- `unread_count`: conteo de `notifications` no leídas `kind='message_new'` cuyo **link**
  matchea `/messages?c=<id>` o `/messages/<id>` (gotcha #14: NUNCA por `entity_id`).

`SECURITY DEFINER`, `REVOKE ALL FROM PUBLIC/anon`, `GRANT EXECUTE TO authenticated`,
filtra por `auth.uid()` internamente. 1 round-trip; la web podrá migrar a este RPC después.

### Historial paginado (la web baja TODO; la app NO)

- Apertura: últimos **50** mensajes (`order created_at desc, id desc, limit 50`), invertidos
  en cliente.
- Scroll arriba: página anterior por **cursor compuesto `(created_at, id)`** (patrón ya
  probado en `/requests` web — un cursor de una sola columna salta filas con timestamps
  iguales).
- Columnas: `id, sender_id, kind, body, created_at` (nunca `select *`).

### Realtime (batería)

- 1 canal por chat abierto: INSERT + UPDATE de `conversation_messages` filtrado por
  `conversation_id`.
- `AppLifecycleListener`: en `paused/hidden` se cierra el canal; en `resumed` se hace
  1 query de gap (`created_at > último visto`) y se re-suscribe.
- La **lista** no tiene realtime: carga al entrar, refresh al volver de un chat o de
  background (pull-to-refresh manual disponible).
- UPDATE realtime es necesario porque los mensajes `quick` mutan su body al ser
  respondidos.

### Fotos

- Comprimir en cliente (reutilizar helpers del feature fotos-solicitudes-ofertas, commit
  `90909dc`), subir a Storage, mensaje `kind='image'` con `body=<URL pública>`.
- Render: acepta URL http(s) segura **y** `data:image/...;base64` (mensajes web legado).
  Fuera de esos dos formatos, el mensaje se omite (como la web).
- Bucket: el mismo que ya usa el feature de fotos de ofertas (verificar nombre en el plan;
  si hace falta bucket/política nueva, va en la migración).

### Envío optimista

Igual que la web: burbuja inmediata con estado `enviando…` y tempId; reconciliación con la
fila real por `(sender_id, kind, body)` contra la cola de pendientes; si el INSERT falla,
la burbuja se quita y se ofrece reintentar (el texto vuelve al composer). Lógica pura en
Dart, testeada.

## 2. Paridad funcional

### Lista (`/messages`)

- 3 pestañas con conteos: Abierto / Completado / No concretado (`abierto/cerrado/perdido`).
- Búsqueda local (nombre del peer o producto).
- Por fila: avatar+nombre del peer, punto de estado, producto + precio acordado
  (`RD$` con formato existente), preview del último mensaje (`messagePreview` equivalente:
  imagen → "📷 Foto", dirección → "📍 Dirección", quick → la pregunta), hora relativa,
  badge de no-leídos.
- Estados vacíos con guía (como la web: "Las conversaciones empiezan cuando…").
- Entrada: nueva pestaña "Mensajes" en el shell de la app, ambos roles.

### Chat (`/messages/:id`)

- **Header del acuerdo:** imagen del producto, nombre, precio acordado (fijo / por hora +
  horas estimadas / "sin precio fijo"), badge de estado, cliente (si proveedor). Tocar →
  hoja de "Detalles del acuerdo" (producto, precio, solicitud, peer, estado, fecha).
- **Menú ⋮:** proveedor con chat abierto → "Marcar como completado" (diálogo de
  confirmación, RPC `mark_conversation_completed`, mensaje system "✓ Marcado como
  completado…") y "Marcar como perdido" (confirmación destructiva, update `status='perdido'`).
  Ambos roles → "Denunciar cuenta".
- **Burbujas:** texto (max 78% ancho, hora inline) · imagen (tap → lightbox pantalla
  completa) · dirección (borde + encabezado 📍 Dirección) · system/audit (píldora centrada) ·
  **quick** (pregunta + botones de opciones; responde solo el receptor con chat abierto;
  al responder se actualiza el body JSON y se envía el mensaje de confirmación mapeado).
- Separadores por día ("Hoy", "Ayer", fecha) y agrupación de avatar al final de cada grupo
  de mensajes consecutivos del mismo remitente. Avatar tap → preview.
- **Estado cerrado/perdido:** banner con el texto de la web, composer oculto.

### Composer (solo chat abierto)

- Textarea multilinea, máx 1000 caracteres, contador desde el 80%, botón enviar con spinner.
- Menú `+`:
  - Proveedor: "Enviar dirección del local" (negocio + `get_business_address`; toast si no
    hay dirección configurada) · "Mejorar oferta (bajar precio)" (diálogo: precio actual,
    nuevo precio < actual, update `agreed_price` + mensaje system 🎉 con el ahorro).
  - Cliente: "Enviar mis datos de contacto" (perfil: nombre/teléfono/WhatsApp; toast si
    perfil vacío) · "Enviar mi ubicación" (dirección del perfil como kind `address`) ·
    "Enviar foto" (galería/cámara → comprimir → Storage → URL).
- Selector de emojis (la misma lista de 40 de la web).
- **Mensajes predeterminados:** las mismas `QUICK_REPLIES` (cliente) y `PROVIDER_REPLIES`
  (proveedor) de la web, copiadas literal a Dart. Con opciones → mensaje `quick` (JSON
  `{question, options, selected:null, answered_by:null}`); sin opciones → texto plano.

### Flujos automáticos

- **Disclaimer de bienvenida:** 1 vez por conversación (persistido local con
  `shared_preferences`-equivalente o archivo — decidir en plan; clave `chat_welcome_<id>`).
  Config del admin vía `app_settings` con default local idéntico al de la web
  (`DEFAULT_CHAT_WELCOME`); título/cuerpo distintos por rol.
- **Auto-saludo del proveedor:** si es proveedor, chat abierto, 0 mensajes → insertar
  saludo con la plantilla del admin (placeholders `{first_name} {business} {product}
  {price}`), guard para no duplicar.
- **Auditoría 72h:** si chat abierto, sin mensaje `audit` previo y la conversación tiene
  >72h → insertar `kind='audit'` "¿Ya recibiste tu producto?" con `sender_id=null`.
- **Notificaciones leídas al abrir:** update `read_at` de las `message_new` cuyo link
  matchee ambos formatos (`?c=` y legado), y refrescar el badge local.

### Calificación (cliente, chat cerrado, sin rating previo)

- Banner "¡Califica este proveedor!" → formulario: nota 1–10 (botones), 4 checkboxes
  (Calidad/Cumplimiento/Servicio/Condición), comentario opcional, disclaimer legal de la
  web, insert en `conversation_ratings`, overlay de gracias. "Ya enviaste tu calificación"
  si existe.

### Denunciar cuenta

Paridad con `ReportAccountDialog` web: motivo + descripción → insert en la tabla de
reportes (verificar nombre exacto en el plan leyendo el componente web).

### Diferido (NO construir ahora)

`AssistantChatBar` (control del bot), `PortfolioChatButton`, `StoreImagePicker`. Los
mensajes que el bot inserte se muestran como mensajes normales sin trabajo extra.

## 3. Estructura de código

```
lib/domain/chat.dart          # Puro, TDD: reconciliación optimista, agrupación
                              # día/remitente, parse/answer de quick, cursor de
                              # paginación, merge de página+realtime, gap query,
                              # validación de imagen (http/data), plantilla de saludo
lib/data/repos.dart           # + repos: conversationsList(), messagesPage(),
                              # insertMessage(), answerQuick(), markCompleted(),
                              # markLost(), improveOffer(), submitRating(),
                              # reportAccount(), markChatNotificationsRead()
lib/features/chat/
  conversations_screen.dart   # Lista con pestañas
  chat_screen.dart            # Conversación + composer + flujos
  widgets/                    # Burbujas, composer, quick, rating, dialogs
```

Rutas nuevas en `router.dart` dentro del ShellRoute, cada una con `BackGuard` (gotcha
PopScope + predictive back). Pestaña "Mensajes" en `HomeShell`.

## 4. Testing (regla del PO: durante, no al final)

- Cada task: test rojo → implementación → verde → `flutter analyze` 0 → suite completa
  verde → siguiente.
- Dominio puro con suite propia (`test/chat_*_test.dart`): reconciliación optimista
  (match, no-match, fallo), cursor compuesto (timestamps duplicados), agrupación por
  día/remitente, parse de quick (JSON corrupto → ignorar), respuesta quick (mapeo de
  confirmaciones, doble respuesta bloqueada), plantilla de auto-saludo, detección 72h,
  validación de src de imagen, matcher de links de notificación (ambos formatos).
- La migración del RPC se verifica en prod vía MCP (BEGIN/ROLLBACK con seeds) antes de
  darla por buena, patrón habitual del proyecto.
- E2E en device con el PO al final (conversación real web↔app, ambos roles).
  ⚠️ Recordatorio: crear-solicitud sigue sin poder probarse en device por el tema
  Turnstile/WebView; el chat NO depende de eso (las conversaciones nacen de ofertas ya
  existentes o se crean vía web/SQL para la prueba).

## 5. Errores

- Carga de lista/chat fallida → estado visible con "Reintentar" (patrón existente).
- Envío fallido → burbuja se retira, texto vuelve al composer, snackbar de error.
- Quick con JSON corrupto → se omite sin crash (como la web).
- Imagen con formato no permitido → se omite.
- Acciones de menú sin datos (sin dirección, perfil vacío) → snackbar con guía, sin enviar.

## Fuera de alcance

- Panel de control del Asistente IA, portafolio, imágenes de tienda (diferidos).
- Realtime en la lista de conversaciones.
- Migrar la web al RPC nuevo (posible follow-up, no aquí).
- Notificaciones push nuevas (las `message_new` existentes ya cubren el flujo).
