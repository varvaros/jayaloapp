# Onboarding — guías granulares por elemento (tour encadenado) — Design

Fecha: 2026-07-27
Estado: aprobado por el PO, listo para plan

## Contexto

El sistema de onboarding contextual ya existe (ver
`2026-07-27-onboarding-contextual-progresivo-design.md`): `OnboardingGuide`
(velo oscuro con hueco recortado sobre **un** elemento, o modo `welcome` sin
ancla), `OnboardingStore` (estado por usuario en Supabase, coordinador "una
guía a la vez"), copys en `onboarding_copy.dart`. Guías de cliente vivas hoy:
`client.create_request` (botón **enviar** dentro de crear-solicitud),
`client.view_offers`, `client.chat_reveal` (welcome).

El PO quiere señaladores **más granulares, a nivel de elemento**, en el flujo
de **cliente**. Las 8 guías que pide no existen. Este spec las agrega.

## Decisión de comportamiento (aprobada)

**Tour encadenado.** En una pantalla con varios señaladores, salen uno tras
otro en orden (Siguiente → … → Entendido) la primera vez que se entra a la
sección; luego no vuelven (estado `markDone` por guía, como hoy).

## Limitación actual y cambio al store

El coordinador de hoy (`OnboardingStore.acquire/release`) solo garantiza "una
a la vez" y le da el turno **al primero que mide su ancla** — sin orden. Para
un tour encadenado con orden definido se elige:

**Coordinador ordenado en el store (Approach A).**
- `OnboardingGuide` acepta un `order` (int, default 0).
- El store junta las guías candidatas del frame y le concede el turno a la de
  **menor `order`**; las demás esperan. Al liberar (guía terminada/saltada),
  se reevalúa y entra la siguiente candidata de menor orden.
- Las guías siguen "tontas": solo declaran su `order`; toda la lógica de
  secuencia vive en el store (central, testeable sin montar UI).

Alternativas descartadas: encadenar por `enabled` (desparrama el orden por
pantalla, frágil con elementos condicionales) y un controlador de tour por
pantalla (componente nuevo, se aparta del patrón por-elemento existente).

### Contrato del coordinador ordenado

- `acquire(key, {int order = 0})` deja de conceder el turno de forma síncrona
  e inmediata. En su lugar registra la candidata `(key, order)` y difiere la
  resolución al final del frame (post-frame): si `_active == null`, elige la
  candidata de menor `order` (desempate estable por orden de registro), la fija
  como `_active`, limpia el resto de candidatas y `notifyListeners()`.
- La guía deja de decidir con el booleano de `acquire`; tras la notificación
  consulta si es la activa (`onboardingStore.isActive(key)`) para mostrar su
  portal. Las no elegidas quedan en espera y reintentan cuando llega la
  próxima notificación (misma mecánica de reintento que ya existe en `_onStore`).
- `release(key)` limpia `_active` si era suya, notifica, y las candidatas en
  espera vuelven a intentar → entra la de menor `order` siguiente.
- Sin `order` explícito (todas 0) el comportamiento es equivalente al actual
  (una a la vez, desempate por registro) → las guías existentes no cambian.

## Guías nuevas

Copys centralizados en `onboarding_copy.dart`, claves versionadas `.v1`.

### Pantalla Solicitudes (`my_requests_screen.dart`) — rol cliente

| order | clave | ancla | copy |
|---|---|---|---|
| 1 | `client.plus.v1` | Botón central `+` de la barra flotante | "Aquí creas una nueva solicitud." |
| 2 | `client.my_requests.v1` | **Tarjeta de ejemplo** del estado vacío | "Aquí se verán tus solicitudes y en qué van." |
| 3 | `client.others_requests.v1` | Pestaña "Ver solicitudes de usuarios" | "Y aquí ves qué están pidiendo otros usuarios." |

- El `+` vive en `floating_nav_bar.dart` (barra compartida por ambos roles).
  La guía se limita al **rol cliente** y a la pantalla de aterrizaje del
  cliente (`/client`), para no dispararse en el proveedor (su tour es aparte).
  Requiere un hook para anclar sobre el botón central (envolver/medir el
  círculo del centro desde el shell).
- Si por algún camino el cliente ya tiene solicitudes (p. ej. creó una en la
  web), no hay tarjeta de ejemplo → la guía #2 no puede medir su ancla y se
  omite (fallback de anclaje existente: hijo en línea, sin overlay). Aceptable.

### Crear solicitud (`create_request_screen.dart`, estado vacío) — cliente

La guía existente del botón **enviar** (`client.create_request.v1`) se
**mantiene** y entra al tour como último paso.

| order | clave | ancla | copy |
|---|---|---|---|
| 1 | `client.request_kind.v1` | Fila de tipo (`_kindPill`: Producto/Servicio) | "Aquí eliges si buscas un producto o un servicio." |
| 2 | `client.request_photo.v1` | Chips Tomar foto / Galería (**una** guía sobre ambos) | "Aquí tomas una foto o subes una imagen de lo que buscas." |
| 3 | `client.create_request.v1` (existe) | Botón enviar | (copy actual, sin cambio) |

Fuera del tour (disparo propio al aparecer su elemento):

| clave | ancla | copy |
|---|---|---|
| `client.request_wholesale.v1` | Píldora "Al por mayor" | "¿Necesitas grandes cantidades? Actívalo aquí." |

La píldora "Al por mayor" solo se monta tras elegir Producto; su guía se
dispara sola en ese momento (progresión natural), no forma parte de la cadena
inicial. Sin `order` en cadena — muestra cuando su ancla existe y el
coordinador esté libre.

### Catálogo (`catalog_screen.dart`) — cliente

| clave | modo | copy |
|---|---|---|
| `client.catalog.v1` | `welcome` (sin ancla, robusto aunque el catálogo esté vacío) | "Aquí ves productos que los proveedores ofrecen en sus tiendas." |

### Chat (`chat_screen.dart` / `composer.dart`) — ambos roles

La guía existente `*.chat_reveal.v1` (welcome) se mantiene como paso 1.

| order | clave | ancla | copy |
|---|---|---|---|
| 1 | `client.chat_reveal.v1` / `provider.chat_reveal.v1` (existe) | welcome | (copy actual) |
| 2 | `chat.quick_replies.v1` | Botón ✨ (`auto_awesome_outlined`) del composer | "Aquí eliges mensajes predefinidos para responder rápido." |
| 3 | `chat.report.v1` | Botón ⋮ (`more_vert`) del header | "¿Sientes algo deshonesto? Denúncialo desde aquí." |

- `quick_replies` y `report` aplican a **ambos roles** (composer y header son
  compartidos); usan clave única sin prefijo de rol.
- El ítem "Denunciar cuenta" vive dentro del popup ⋮; no se puede anclar un
  ítem del popup, así que la guía resalta el **botón ⋮**.

## Tarjeta de ejemplo

Card **no interactiva** en el estado vacío de "Mis solicitudes", con el mismo
lenguaje visual que `_RequestCard` pero **atenuada** y con etiqueta "Ejemplo":

- Título de muestra (ej. *"Nevera 11 pies, poco uso"*), chip de estado de
  muestra y el timeline de 5 fases.
- No navega (sin `onTap`).
- Se muestra solo cuando la lista de solicitudes propias está vacía; desaparece
  en cuanto hay una solicitud real.
- Es el ancla de la guía `client.my_requests.v1` y da sustancia visual al
  "aquí se verán tus solicitudes".

## Alcance y no-objetivos

- Solo se agregan señaladores y la tarjeta de ejemplo. No se cambia ningún
  flujo funcional (crear solicitud, catálogo, chat siguen igual).
- El tour del `+`, tipo, foto, mayoreo, catálogo, "mis solicitudes" y "otros"
  es de **cliente**. `quick_replies` y `report` son de ambos roles. El tour de
  proveedor no se toca en este spec.
- No se siembran datos: la solicitud de ejemplo es puramente visual.

## Testing

- **Coordinador ordenado (store):** con varias candidatas, gana la de menor
  `order`; al liberar entra la siguiente; sin `order` (todas 0) el
  comportamiento equivale al actual. Unit test del store sin montar UI.
- **Guías nuevas:** cada una ancla su elemento o se omite limpio si el ancla no
  existe (widget test con el fallback de anclaje).
- **Tarjeta de ejemplo:** aparece solo con lista vacía; no navega.
- Regresión: las guías existentes (`create_request`, `view_offers`,
  `chat_reveal`) siguen funcionando; `flutter analyze` en 0; suite verde.

## Archivos afectados (previsto)

- `features/shared/onboarding_store.dart` — coordinador ordenado (`order`,
  candidatas, `isActive`).
- `features/shared/onboarding_guide.dart` — parámetro `order`, mostrar según
  `isActive`.
- `features/shared/onboarding_copy.dart` — copys nuevos.
- `features/client/my_requests_screen.dart` — guías `+`/mis/otros + tarjeta de
  ejemplo.
- `features/shell/floating_nav_bar.dart` (+ shell) — hook para anclar el `+`.
- `features/client/create_request_screen.dart` — guías tipo/foto/mayoreo.
- `features/client/catalog_screen.dart` — guía catálogo (welcome).
- `features/chat/chat_screen.dart` — guía report (⋮).
- `features/chat/widgets/composer.dart` — guía quick_replies (✨).
