# Barra de navegación flotante con botón central por rol

**Fecha:** 2026-07-18
**Estado:** validado por el PO
**Repos afectados:** `jayalo-app` (solo app; **cero cambios de backend**)

---

## 1. Qué se construye y por qué

La app usa hoy un `NavigationBar` estándar de Material con 4 pestañas por rol
(`app/lib/features/shell/home_shell.dart`). Las cuatro pesan lo mismo, así que la acción que
define a cada rol —crear una solicitud si eres cliente, ver las solicitudes de tu rubro si eres
proveedor— queda igualada con "Ajustes".

Este diseño la separa: una barra flotante en forma de píldora con un **botón circular central
elevado** que lleva la acción principal del rol, con dos iconos a cada lado.

Aprovechando el cambio, cada rol gana un destino nuevo de métricas propias, y el proveedor gana
acceso a las solicitudes fuera de su rubro.

### Alcance — lo que NO entra

El **catálogo de productos y servicios navegable/administrable** queda FUERA, con spec propio
posterior (decisión PO, 2026-07-18). En la web es una feature entera repartida en ~8 archivos
(`ProductDialog`, `ProviderProductsSection`, `StoreImagePicker`,
`provider-catalog.functions.ts`, `products.$productId`, el flujo de interés del cliente).
Portarlo es un proyecto comparable al chat o al onboarding y bloquearía la barra durante
semanas.

Aquí el catálogo aparece solo como **cifra** dentro de Estadísticas ("12 productos · 3
servicios"), en una tarjeta apagada. Cuando exista el catálogo, esa tarjeta se vuelve tocable y
nada más cambia.

Consecuencia aceptada: mientras tanto el proveedor ve cuántos productos tiene pero los sigue
administrando desde la web.

---

## 2. Composición de la barra

| Rol | Izquierda | **Centro** | Derecha |
|---|---|---|---|
| **Cliente** | Mis solicitudes · Reputación | **＋ Nueva solicitud** → `/client/create` | Mensajes · Ajustes |
| **Proveedor** | Mis ofertas · Estadísticas | **🔍 Ver solicitudes** → `/provider` | Mensajes · Ajustes |

**El botón central es un destino más, no un atajo suelto.** Puede estar activo como cualquier
otro (en la referencia visual, el punto verde bajo el círculo central marca justamente ese
estado). Las dos rutas ya existen dentro del `ShellRoute`, así que el estado activo, el
`BackGuard` y las animaciones de cambio de pestaña siguen funcionando sin tocarlos.

La **campana de notificaciones** se queda en el `AppBar` con su badge, como está hoy. No baja a
la barra.

**Dentro de una conversación la barra se oculta** (decisión PO 2026-07-18, tomada durante la
implementación). Todas las rutas cuelgan del mismo `ShellRoute` plano, así que `/messages/:id`
mostraba la barra igual que las demás; con la barra sólida el chat vivía encima de ella, pero al
flotar tapaba el campo de escribir. En un chat no se navega, se conversa — es lo que hacen
WhatsApp y Messenger — y ocultarla devuelve 132 px de alto a una pantalla donde el teclado ya se
come la mitad. La lista de conversaciones (`/messages`) sí la muestra; solo desaparece en el
detalle.

### Iconos

| Destino | Icono |
|---|---|
| Mis solicitudes | `Icons.receipt_long_outlined` (ya en uso) |
| Mis ofertas | `Icons.local_offer_outlined` (ya en uso) |
| Reputación | `Icons.workspace_premium_outlined` |
| Estadísticas | `Icons.insights_outlined` |
| Mensajes | `Icons.chat_bubble_outline` (ya en uso) |
| Ajustes | `Icons.settings_outlined` (ya en uso) |
| Centro — cliente | `Icons.add` |
| Centro — proveedor | `Icons.search` |

---

## 3. Forma y comportamiento

**Píldora flotante.** Márgenes laterales e inferior respecto al borde de la pantalla, esquinas
muy redondeadas, fondo `surfaceContainerLowest` (blanco en claro, `#121824` en oscuro), sombra
suave. Respeta el `SafeArea` inferior: el margen se suma al inset del sistema, nunca lo
sustituye.

**Círculo central.** Sobresale por encima del borde superior de la píldora. Relleno `primary`
(violeta `#7147F2` en claro, azul `#3E98FF` en oscuro), icono en `onPrimary`. Su propia sombra,
un punto más marcada que la de la píldora, para que se lea como una capa por encima.

**Etiquetas: texto solo bajo el icono activo** (decisión PO). La barra queda limpia como la
referencia, pero el usuario siempre puede leer dónde está parado — la doctrina de "a prueba de
tontos" para público analógico se cumple sin engordar la barra con cuatro textos. Al cambiar de
pestaña el texto se desliza a la nueva posición.

**Estados.** Activo: icono teñido de `primary` + su etiqueta debajo. Inactivo:
`onSurfaceVariant`, sin texto. El botón central activo lleva su etiqueta bajo el círculo, fuera
de la píldora.

**El punto de la referencia no se usa.** En la imagen original el punto marca cuál está activo
*porque no hay texto*. Al añadir la etiqueta, el punto pasa a ser un segundo indicador de lo
mismo: dos señales para un solo estado, y la etiqueta ya es la más clara de las dos para este
público. Se queda solo la etiqueta.

**Accesibilidad.** Todos los destinos llevan `Semantics(label:)` con su nombre completo,
tengan texto visible o no. Un lector de pantalla nunca anuncia "botón" a secas.

**Movimiento.** Se respeta la doctrina vigente (`core/motion.dart`): `easeInOutCubic`, y
`JayaloMotion.reduced(context)` desactiva las transiciones cuando el sistema lo pide. El
`AnimatedSwitcher` de fade-through que ya anima el cambio de pestaña en `home_shell.dart` no se
toca.

### El detalle que no se puede olvidar

Una barra flotante **no reserva espacio**: se superpone al contenido. Hoy `NavigationBar` es
sólida y el cuerpo del `Scaffold` termina justo encima de ella.

Al flotar hay que poner `extendBody: true` en el `Scaffold` del shell **y** añadir padding
inferior a los scrolls de todas las pantallas del shell, del alto de la barra más su margen.

Pantallas afectadas: `my_requests_screen`, `create_request_screen`, `request_status_screen`,
`inbox_screen`, `my_offers_screen`, `request_detail_screen`, `conversations_screen`,
`settings_screen`, `notifications_screen`, más las dos nuevas de §4.

Si se olvida en una sola, el usuario pierde el último elemento de esa lista sin entender por
qué. Se expone una constante única con el alto reservado, y las pantallas la consumen — nunca un
número copiado a mano en cada archivo.

---

## 4. Pantallas nuevas

Las dos son de **solo lectura, una sola carga, sin backend nuevo**. Las RPCs ya existen en
producción. Ambas usan `JayaloLoaderBlock` mientras cargan y el patrón de error de las demás
pantallas.

### 4.1 Reputación (cliente) — `/client/reputation`

Fuente única: `get_customer_reputation(_customer_id := <uid propio>)`.

| Dato | Campo |
|---|---|
| ⭐ Calificación promedio y nº de reseñas | `avg_rating`, `reviews_count` |
| Compras completadas | `completed_purchases` |
| Solicitudes hechas | `requests_count` |
| "Regularmente respondes en ~X" | `median_response_minutes`, `response_samples` |

El tiempo de respuesta **solo se muestra con `response_samples >= 5`**, igual que la web
(`src/lib/responseTime.ts`). Con menos muestras la cifra miente y se omite por completo — no se
muestra un "sin datos".

**Estado vacío:** sin reseñas todavía, en vez de una rejilla de ceros va un mensaje que explica
cómo se gana reputación (completar compras y calificar al proveedor).

### 4.2 Estadísticas (proveedor) — `/provider/stats`

Tres fuentes, en paralelo con `Future.wait`:

| Dato | Fuente |
|---|---|
| ⭐ Calificación y reseñas | `get_provider_reviews_summary(_user_id)` → `avg_rating`, `reviews_count` |
| Trabajos realizados | `get_provider_stats(_user_id)` → `completed_count` |
| Clientes atendidos | `get_provider_stats` → `clients_count` |
| Créditos invertidos | `get_provider_stats` → `points_invested` |
| Ingresos | `get_provider_stats` → `revenue_total` |
| Catálogo: "N productos · M servicios" | `count` sobre `provider_products` del negocio, agrupado por tipo |

Los ingresos se formatean en RD$ con separador de miles — nunca `toString()` crudo sobre un
número. Ese formateador ya existe, pero **privado dentro de**
`features/client/request_status_screen.dart:13`. Se extrae a `domain/money.dart` como función
pura con sus tests, y la pantalla original pasa a consumirlo. Es la única forma de que las dos
pantallas muestren el mismo formato sin copiar la expresión regular.

La tarjeta de catálogo va **apagada y no tocable**, con la nota de que los productos se
administran desde la web por ahora. Es el punto de entrada del spec futuro.

**Estado vacío:** proveedor sin trabajos completados → mensaje que explica que las estadísticas
aparecen al completar su primer trabajo, no una rejilla de ceros.

**A verificar durante la implementación:** que `get_provider_stats` y
`get_provider_reviews_summary` tengan `GRANT EXECUTE` a `authenticated` y que la RLS de
`provider_products` permita al dueño contar los suyos. Ambas se usan hoy desde la web con sesión
de usuario, así que se espera que sí — pero se confirma con una llamada real antes de dar la
pantalla por hecha. Precedente: `refresh_provider_stats_cache` quedó sin `GRANT` a
`authenticated` y falla en los logs de producción.

---

## 5. Toggle "Para ti · Todas" en el inbox del proveedor

El inbox (`inbox_screen.dart`) ya tiene un `SegmentedButton` de Todo/Productos/Servicios. Encima
se añade un segundo selector: **"Para ti · Todas"**.

- **Para ti** — lo de hoy: `providerInbox()` → `get_provider_inbox_unified`, filtrado al rubro
  del proveedor.
- **Todas** — solicitudes **abiertas** de cualquier rubro, **excluyendo las propias**. Consulta
  directa a `customer_requests` (`status = 'open'`, `user_id != <uid>`), ordenada por
  `created_at` descendente.

La regla de "Todas" es exactamente la decisión del PO del 2026-07-17 para la web: esa vista
existe para que el marketplace no se vea vacío, así que **nunca** filtra por rubro ni categoría
del proveedor; solo excluye lo suyo. Antes la web aplicaba las preferencias por defecto y dejaba
la pestaña en "0 resultados" aunque hubiera solicitudes abiertas de otros rubros.

El filtro Todo/Productos/Servicios sigue aplicando en las dos vistas.

**Por qué dos filas de controles y no una:** mezclar "de quién es la solicitud" con "qué tipo de
solicitud es" en un único selector obliga al usuario a razonar sobre dos ejes a la vez. Dos
filas claras cuestan alto de pantalla; un selector combinado cuesta comprensión, que es más
caro para este público.

El estado del toggle **no persiste** entre sesiones: al entrar siempre arranca en "Para ti", que
es la vista con solicitudes relevantes para ofertar.

---

## 6. Estructura del código

Se extrae la barra a su propio archivo en vez de engordar `home_shell.dart`:

| Archivo | Responsabilidad |
|---|---|
| `features/shell/floating_nav_bar.dart` | El widget de la barra: píldora, botón central, estados, animación de la etiqueta. Recibe los destinos y el índice activo; **no sabe nada de rutas ni de roles**. |
| `features/shell/nav_destinations.dart` | Función pura: rol → lista de destinos (ruta, icono, etiqueta, si es el central). Testeable sin widgets. |
| `features/shell/home_shell.dart` | Sigue resolviendo el índice activo desde la ruta y navegando. Pierde la construcción de la barra. |
| `features/client/reputation_screen.dart` | Pantalla §4.1 |
| `features/provider/stats_screen.dart` | Pantalla §4.2 |
| `data/repos.dart` | Añade `customerReputation()`, `providerStats()`, `providerCatalogCounts()`, `allOpenRequests()` |
| `domain/money.dart` | Formateo de RD$ extraído de `request_status_screen.dart` (§4.2) |

La separación importa: la barra es puro dibujo y el mapa de destinos es pura lógica. Se puede
cambiar el aspecto sin tocar la navegación, y probar qué destinos ve cada rol sin montar un
widget.

---

## 7. Pruebas

**Unitarias (`nav_destinations.dart`)** — sin widgets:

- Cliente y proveedor reciben 5 destinos cada uno, con el central en la posición correcta.
- El destino central del cliente es `/client/create`; el del proveedor, `/provider`.
- Rol desconocido no revienta.

**Unitarias (`domain/money.dart`)**: cero, un valor menor a mil, el salto de los miles y de los
millones, y el caso nulo.

**De widget (`floating_nav_bar.dart`)**:

- Solo el destino activo muestra texto; los otros tres, únicamente icono.
- El botón central también puede estar activo y mostrar su etiqueta.
- Estar en Estadísticas no enciende el botón central, aunque `/provider/stats` empiece por
  `/provider`.
- Con `reduced motion` activo no se programan animaciones.
- Todos los destinos exponen su `Semantics` label completo.

**De widget (pantallas nuevas)**:

- Reputación oculta el tiempo de respuesta con `response_samples = 4` y lo muestra con `5`.
- Reputación sin reseñas muestra el estado vacío, no ceros.
- Estadísticas sin trabajos muestra el estado vacío.
- La tarjeta de catálogo no responde al toque.

**Manual en device (Redmi), no automatizable:**

- Ninguna lista del shell esconde su último elemento bajo la barra — se recorre **cada una** de
  las 11 pantallas hasta el final.
- La barra respeta la barra de gestos del sistema en MIUI.
- Claro y oscuro.
- El botón ATRÁS del sistema sigue comportándose como hoy (`BackGuard`).

---

## 8. Riesgos conocidos

**El padding inferior es el riesgo real de este cambio.** No lo detectan `flutter analyze` ni
los tests de widget: una lista con el último ítem tapado renderiza sin error. Solo se ve
recorriendo cada pantalla hasta abajo en un device. Por eso la constante de alto es única y la
verificación manual de las 11 pantallas es obligatoria antes de dar el trabajo por hecho.

**El toggle "Todas" depende de una policy de RLS que la app aún no ejercita.** La web lee
solicitudes abiertas ajenas, así que la policy existe; pero la app nunca ha hecho esa consulta.
Se confirma con una llamada real antes de construir la UI encima.

**El botón central sobresaliendo puede chocar con el gesto de "volver atrás" de MIUI** en los
bordes. El círculo está centrado, lejos de los bordes laterales, así que no se espera conflicto
— pero es exactamente el tipo de detalle que solo aparece en el device, no en el emulador.

---

## 9. Decisiones del PO registradas

1. **2026-07-18** — "Ver todas las solicitudes" vive como toggle dentro del inbox, no como
   pestaña propia ni botón flotante aparte.
2. **2026-07-18** — El cuarto destino no es Notificaciones: es **Estadísticas** para el
   proveedor y **Reputación** para el cliente. La campana se queda en el `AppBar`.
3. **2026-07-18** — "Mis solicitudes" del cliente **no se divide** en activas e historial. Sigue
   mostrando todo; la pantalla nueva es solo de métricas y se llama Reputación.
4. **2026-07-18** — El catálogo navegable se saca de este alcance y va a su propio spec.
5. **2026-07-18** — Etiquetas: texto solo bajo el icono activo.
6. **2026-07-18** — La barra se oculta dentro de una conversación (`/messages/:id`), no en la
   lista de mensajes. Decisión tomada durante la implementación, al descubrirse que el plan
   afirmaba erróneamente que el chat no mostraba la barra.
