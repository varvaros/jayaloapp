# UI/UX del resto de pantallas — plan y guía de línea gráfica

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Fecha:** 2026-07-18 · **Estado:** plan de handoff (escrito para que otro modelo/sesión continúe sin re-derivar la línea gráfica)

**Goal:** Llevar la dirección visual "tarjetas que respiran" (aprobada por el PO en `/notifications`) al resto de pantallas de la app Flutter, sin tocar backend ni lógica de dominio.

**Architecture:** Primero se extrae un kit compartido de widgets de marca (`brand_kit.dart`) desde los patrones ya aprobados en `notifications_screen.dart`; después cada pantalla se rediseña en su propio commit aislado consumiendo el kit. El proceso por grupo de pantallas es: mockups → elección del PO → implementación → verificación.

**Tech Stack:** Flutter (Material 3), `flutter_animate` (ya es dependencia), `go_router`, tokens de `core/brand.dart`, mascota/loader de `features/shared/jayalo_loader.dart`.

## Global Constraints

- **Solo UI.** Cero migraciones, cero Edge Functions, cero cambios en `domain/` o `data/` (salvo helper puro nuevo con test).
- **Base obligatoria (encargo del PO 2026-07-18):** `core/brand.dart` + `jayalo_loader.dart`. Referencia de estilo = pantalla `/notifications`.
- **Prohibido:** `CircularProgressIndicator` (usar `JayaloLoaderBlock` / `JayaloSpinner`), colores `Colors.*` hardcodeados (usar `ColorScheme` o `JayaloStatus`), violeta como primario en dark (en oscuro el primario es **azul** `#3E98FF`, ver brand.dart — no es un error).
- **Reversibilidad (feedback PO permanente):** cada rediseño de pantalla va en SU PROPIO commit aislado, y al entregar se dice qué `sha` lo revierte. Nunca mezclar dos pantallas en un commit.
- **Verificación por task:** `flutter analyze` → 0 issues; `flutter test` → verde (baseline actual 134). Correr desde `app/`.
- **Copy:** español de RD, tuteo, sin jerga técnica ("Aún no has pedido nada. Toca ‘Crear’ y dinos qué buscas."). Dinero siempre `RD$`.
- **Accesibilidad:** todo lo animado respeta `MediaQuery.disableAnimationsOf(context)` (patrón de `JayaloLoader`); targets táctiles ≥ 44px; contraste verificado en light Y dark.
- **Proceso:** antes de implementar cada grupo de pantallas se presentan 2–3 mockups de dirección y el PO elige (así se decidió "tarjetas que respiran"). No implementar sin esa elección.

---

## Parte 1 — Canon de la línea gráfica (leer antes de tocar cualquier pantalla)

Esto NO es opinión: es lo que ya está aprobado y en producción visual en `/notifications`. Todo rediseño debe verse como hermano de esa pantalla.

### 1.1 Tokens — `app/lib/core/brand.dart`

- `JayaloColors`: paleta portada de `src/styles.css` de la web (misma marca). Primario claro = violeta `#7147F2`; primario oscuro = **azul** `#3E98FF`. Mascota siempre violeta `#6C3BF5` en ambos temas.
- `JayaloStatus`: pares `(bg, ink)` light/dark portados de los `--status-*` de la web. **Son la única fuente para colorear estados y familias.** Mapa canónico:

| Concepto | Tono `JayaloStatus` |
|---|---|
| Esperando / pendiente | `pending*` (ámbar apagado) |
| Respondida / ofertas / ventas | `responded*` (violeta) |
| Aceptada / wallet / créditos | `accepted*` (ámbar fuerte) |
| Desbloqueado / mensajes / éxito | `unlocked*` (verde) |
| Completada / sistema / neutro | `completed*` (gris) |
| Reseñas | `review*` (rosa, derivado con la receta oklch de la web) |

- Todo lo demás sale del `ColorScheme` M3 (`jayaloScheme`), nunca de constantes sueltas. Roles útiles ya mapeados: `primaryContainer`/`onPrimaryContainer` = acento violeta suave, `surfaceContainerHighest` = relleno de inputs/leído, `outlineVariant` = bordes.

### 1.2 Anatomía de la "tarjeta que respira" (referencia: `_NotifCard` en `notifications_screen.dart`)

- Radius **16**, padding interno **12**, margen `horizontal: 16, vertical: 4`.
- Ícono en contenedor redondeado (40×40, radius 12, fondo = color del ícono al **14%** alpha) a la izquierda.
- Título `w700` (estado activo/sin leer) o `w500` (estado neutro); body 13px al 80% del color; metadato (hora relativa) 11px al 65%.
- Estado "vivo" (sin leer / requiere acción): fondo teñido del tono de su familia `JayaloStatus`. Estado "apagado": `surfaceContainerHighest` al 55% + textos `onSurfaceVariant`.
- Transición entre estados con `AnimatedContainer` de **300ms** `easeOut` (el color se desvanece, nada desaparece de golpe).
- Tap con `InkWell` con el mismo `borderRadius` que la tarjeta (que el ripple no se salga del redondeado).

### 1.3bis Transición de pantalla — doctrina de movimiento (decisión PO 2026-07-18)

**Toda transición debe sentirse premium: deslizado suave con ease-out, nunca el
zoom/fade genérico de Android por defecto.** Se resuelve UNA sola vez en
`app.dart` (`_JayaloPageTransitionsBuilder` en el `pageTransitionsTheme` de
`jayaloTheme`), no ruta por ruta: cubre las ~15 `GoRoute` de `core/router.dart`
sin tocarlas. Entrante desliza 6% del ancho desde la derecha + fade-in;
saliente (al empujar, no al volver) se desliza 4% a la izquierda y se atenúa a
40% de opacidad — profundidad tipo "shared axis" de M3, no un corte plano.
Curva `easeOutCubic` (entrada) / `easeInCubic` (reversa), duración 300ms
(la que ya trae `MaterialPageRoute` por defecto — no hace falta forzarla).
Test de contrato: `test/page_transitions_test.dart` (si alguien revierte el
tema sin querer, el `SlideTransition` desaparece y el test lo detecta, porque
el zoom por defecto de M3 usa Scale+Fade, no Slide).

Modales y diálogos (`showModalBottomSheet`, `showDialog`) NO llevan
`transitionDuration` propia en ningún archivo del proyecto — ya heredan las
animaciones fluidas de Material 3 (fade+scale en diálogos, deslizado hacia
arriba en hojas). Si se agrega un modal nuevo, NO fijarle una duración
personalizada salvo que se note más abrupto que esto.

### 1.3 Vocabulario de animación (`flutter_animate`)

- **Cascada de entrada de listas:** `fadeIn(250ms)` + `slideY(begin: .10, curve: easeOutCubic)` con stagger de **40ms** por ítem, tope en ~14 ítems (`min(index, 14)`).
- **Llegada en vivo (realtime):** `slideY(begin: -.35, 300ms, easeOutCubic)` + `fadeIn(250ms)` + `shimmer(700ms)` del color de familia al 35%.
- **Aparición/desaparición de contadores y píldoras:** `AnimatedScale` 250ms `easeOutBack` (pop elástico hacia 1, encoge hacia 0).
- **Cascadas de estado masivo** (p.ej. "marcar todas"): delay incremental de **60ms** por ítem.
- Nada de animaciones > 700ms ni loops decorativos fuera del loader. Las transiciones de ruta son las nativas de M3.

### 1.4 Estados obligatorios de toda pantalla con datos

- **Cargando:** `JayaloLoaderBlock()` (pantalla completa) o `JayaloSpinner` (en botones / footers). Jamás un spinner Material.
- **Vacío:** `JayaloMascot` (mirando abajo-izquierda, "buscando algo que no encontró") + texto centrado con guía de qué hacer + CTA si aplica. Envuelto en `ListView` para que el pull-to-refresh siga funcionando en vacío.
- **Error:** ícono `cloud_off` 48 + mensaje amable + `FilledButton` "Reintentar". Nunca un error en inglés ni un stack trace.
- **Refresh:** `RefreshIndicator` en toda lista.
- **Paginación:** botón "Cargar más" (`OutlinedButton`) mientras la última página venga llena; no scroll infinito.

### 1.5 Estructura de pantalla

- `AppBar` simple con título en español; acciones a la derecha (la campana `NotificationBell` va SOLO en las 4 raíces: my_requests, create_request, inbox, my_offers).
- Encabezados de sección: 12px `w700` `letterSpacing: .4` en `onSurfaceVariant`, padding `fromLTRB(20, 16, 20, 6)` (patrón de los encabezados de día).
- Píldoras informativas: radius 99, `primaryContainer`/`onPrimaryContainer`, 12px `w700`.

### 1.6 Gotchas de navegación/plataforma que el rediseño NO debe romper

- Raíces de pestaña (`/client`, `/provider`, `/provider/offers`, `/messages`): navegar con `context.go()`, nunca `push()` (duplica el home dentro del ShellRoute y rompe BackGuard).
- `PopScope`/BackGuard vive DENTRO de cada ruta hija del shell, no en el builder del shell (predictive back de Android lo desregistra; gotcha `c1a5400`).
- Nada con red/permisos `await`-eado antes de `runApp` (pantalla en blanco; gotcha `7f67e6a`).
- Los `ListView` de las pestañas raíz usan `homeScrollController` (scroll-to-top al re-tocar la pestaña) — conservarlo al rediseñar.
- E2E en el Redmi está limitado por permisos MIUI; la verificación estándar es analyze + tests + APK manual cuando el PO pueda.

---

## Parte 2 — Inventario y orden de trabajo

Pantallas existentes en `app/lib/features/` y su estado visual actual:

| # | Pantalla | Archivo | Estado actual |
|---|---|---|---|
| — | Notificaciones | `notifications/notifications_screen.dart` | ✅ REFERENCIA — no tocar |
| 1 | Mis solicitudes (cliente) | `client/my_requests_screen.dart` | `Card`+`ListTile` genéricos; `phaseBadge` usa `Colors.amber/green` fuera de marca |
| 2 | Estado de solicitud (cliente) | `client/request_status_screen.dart` | funcional, sin línea gráfica |
| 3 | Crear solicitud | `client/create_request_screen.dart` | formulario plano |
| 4 | Inbox proveedor | `provider/inbox_screen.dart` | listas genéricas (2 pestañas) |
| 5 | Mis ofertas (proveedor) | `provider/my_offers_screen.dart` | listas genéricas |
| 6 | Detalle de solicitud (proveedor) | `provider/request_detail_screen.dart` | funcional, sin línea gráfica |
| 7 | Conversaciones | `chat/conversations_screen.dart` | funcional (chat recién hecho) |
| 8 | Chat | `chat/chat_screen.dart` + widgets | funcional; solo pulido visual fino |
| 9 | Ajustes | `settings/settings_screen.dart` | lista plana |
| 10 | Login | `auth/login_screen.dart` | básico |
| 11 | Onboarding (gate, rol, consumer, provider) | `onboarding/*.dart` | funcional, wizard plano |
| 12 | Verificación (banner + OTP sheet) | `verification/*.dart` | funcional |

**Orden recomendado** (impacto/uso primero, riesgo después): grupos A→E de la Parte 3. Login y onboarding al final: son flujos ya E2E-verificados en device y con más riesgo de regresión funcional; se tocan cuando el kit esté maduro.

---

## Parte 3 — Tasks

### Task 1: Kit compartido de marca (`brand_kit.dart`)

Extrae los patrones aprobados de `/notifications` a widgets reutilizables. TODO lo demás del plan consume esto — es lo primero y lo único sin mockup previo (no introduce diseño nuevo, solo consolida el existente).

**Files:**
- Create: `app/lib/features/shared/brand_kit.dart`
- Test: `app/test/brand_kit_test.dart`

**Interfaces (Produces):**
- `class JayaloCard extends StatelessWidget` — `({Key? key, required Widget child, VoidCallback? onTap, Color? tint, EdgeInsetsGeometry padding = const EdgeInsets.all(12)})`. Radius 16, margen `horizontal:16, vertical:4`, `AnimatedContainer` 300ms, InkWell con el mismo radius. `tint == null` → fondo `surfaceContainerLowest` (card neutra).
- `class StatusChip extends StatelessWidget` — `({Key? key, required String label, required StatusTone tone, IconData? icon})`. Píldora radius 99, fondo `tone.bg`, texto/ícono `tone.ink`, 12px w700.
- `StatusTone toneFor(BuildContext context, RequestPhase phase)` — mapa canónico §1.1 (pending/responded/accepted/unlocked/completed) resolviendo light/dark por `Theme.brightness`.
- `class SectionHeader extends StatelessWidget` — `({Key? key, required String text})`, estilo §1.5.
- `class EmptyState extends StatelessWidget` — `({Key? key, required String message, String? ctaLabel, VoidCallback? onCta})`. Mascota + texto + `FilledButton` opcional, dentro de `ListView` (compatible con RefreshIndicator). Acepta `ScrollController?` opcional para las raíces con `homeScrollController`.
- `class ErrorRetry extends StatelessWidget` — `({Key? key, required Future<void> Function() onRetry, String message = 'No se pudo cargar'})` (generaliza el `_ErrorRetry` de notificaciones).
- `extension CascadeIn on Widget` — `Widget cascadeIn(int index, {Key? key})` que aplica la cascada §1.3 (fadeIn 250ms + slideY .10, stagger 40ms, tope 14).

- [ ] **Step 1: Escribir tests de widget que fallen** (`app/test/brand_kit_test.dart`): `StatusChip` pinta label y usa `tone.bg`; `toneFor` devuelve `pendingLight` para `RequestPhase.waiting` en light y `pendingDark` en dark; `EmptyState` muestra mensaje y CTA cuando se pasa; `JayaloCard` dispara `onTap`.
- [ ] **Step 2:** `flutter test test/brand_kit_test.dart` → FAIL (símbolos no existen).
- [ ] **Step 3:** Implementar `brand_kit.dart` copiando el estilo EXACTO de `notifications_screen.dart` (números de §1.2–§1.5; no inventar valores nuevos).
- [ ] **Step 4:** `flutter test` → verde (baseline + nuevos); `flutter analyze` → 0.
- [ ] **Step 5:** Commit aislado: `git commit -m "feat(ui): kit compartido de marca extraído de /notifications"`.

### Task 2: Grupo A — Home del cliente (mis solicitudes + estado de solicitud)

**Files:** Modify `client/my_requests_screen.dart`, `client/request_status_screen.dart`.

**Dirección de diseño (base para los mockups):**
- Tarjeta de solicitud = tarjeta que respira: título w700, hora relativa 11px, `StatusChip` con `toneFor(phase)` — esto ELIMINA los `Colors.amber.shade800`/`green.shade700` fuera de marca de `phaseBadge`.
- Solicitudes en fase "viva" (`withOffers`, `accepted`, `unlocked`) llevan tinte de familia; `waiting`/`completed` van neutras (misma semántica leído/sin-leer de notificaciones).
- Cascada de entrada al cargar la lista; vacío con `EmptyState` (CTA "Crear solicitud" → `/client/create`).
- `request_status_screen`: línea de fases como secuencia de `StatusChip`s + ofertas como tarjetas con tinte `responded`; botones de acción existentes intactos (solo re-vestidos).

- [ ] **Step 1: Mockups.** Presentar al PO 2–3 variantes de la tarjeta de solicitud y del detalle (mock HTML o widget de visualización, como se hizo con notificaciones). Esperar elección.
- [ ] **Step 2:** Implementar la variante elegida usando SOLO el kit + tokens (sin estilos ad-hoc).
- [ ] **Step 3:** Verificar: `flutter analyze` 0, `flutter test` verde, `homeScrollController` sigue conectado, navegación intacta (`go` a raíces, `push` a detalle).
- [ ] **Step 4:** Un commit POR PANTALLA, mensaje `feat(ui): rediseño <pantalla> (línea tarjetas-que-respiran)`. Reportar al PO el sha que revierte cada uno.

### Task 3: Grupo B — Home del proveedor (inbox + mis ofertas + detalle)

**Files:** Modify `provider/inbox_screen.dart`, `provider/my_offers_screen.dart`, `provider/request_detail_screen.dart`.

**Dirección:** misma receta del Grupo A. Ofertas con tinte `responded`; desbloqueos con `unlocked`; créditos/costos SIEMPRE con tono `accepted` (ámbar = dinero). El detalle de solicitud muestra fotos (feature `90909dc`) — respetar esa grilla, solo envolverla en la tarjeta. Recordar doctrina: ofertar es gratis, el riesgo es el unlock — la UI no debe asustar con el costo antes de tiempo, pero el costo en créditos debe verse claro ANTES de confirmar el unlock.

- [ ] **Step 1:** Mockups → elección del PO.
- [ ] **Step 2:** Implementar con el kit.
- [ ] **Step 3:** Verificar (analyze 0, tests verdes, flujo ofertar/desbloquear intacto).
- [ ] **Step 4:** Un commit por pantalla + shas de reversa.

### Task 4: Grupo C — Crear solicitud (formulario)

**Files:** Modify `client/create_request_screen.dart`.

**Dirección:** el formulario es la pantalla de más fricción para el público analógico de RD (ver QA de usabilidad). Campos con `surfaceContainerHighest` de fondo y radius 12–16; labels claros con ejemplo ("¿Qué necesitas? · Ej: Reparar una nevera"); errores inline en `destructive` con mensaje en español llano; botón enviar `FilledButton` full-width con `JayaloSpinner` mientras envía. La sección de fotos existente se conserva tal cual funcionalmente. ⚠️ El envío en device sigue sin poderse probar E2E (Turnstile/WebView diferido a App Check) — no intentar depurarlo; la verificación es analyze+tests.

- [ ] **Step 1:** Mockups → elección del PO.
- [ ] **Step 2:** Implementar. NO tocar la lógica de submit ni el manejo de fotos.
- [ ] **Step 3:** Verificar (analyze 0, tests verdes).
- [ ] **Step 4:** Commit aislado + sha de reversa.

### Task 5: Grupo D — Conversaciones, chat (pulido) y ajustes

**Files:** Modify `chat/conversations_screen.dart`, `chat/widgets/bubbles.dart` (solo colores/radius si hace falta), `settings/settings_screen.dart`.

**Dirección:** conversaciones = tarjetas que respiran con avatar/inicial, último mensaje 13px al 80%, hora relativa, tinte `unlocked` cuando hay no-leídos. El chat en sí ya pasó E2E — SOLO pulido de tokens (burbujas propias en `primaryContainer`, ajenas en `surfaceContainerHigh`), sin tocar composer ni lógica realtime. Ajustes: secciones con `SectionHeader`, filas con ícono en contenedor 40×40 al 14% (anatomía §1.2), zona de peligro (cerrar sesión) en `destructive`.

- [ ] **Step 1:** Mockups (conversaciones y ajustes; el chat no necesita mockup, es pulido de tokens) → elección del PO.
- [ ] **Step 2:** Implementar.
- [ ] **Step 3:** Verificar: analyze 0, tests verdes — OJO: el chat tiene suite grande (108+); cualquier test rojo = revertir el cambio visual que lo rompió, no adaptar el test.
- [ ] **Step 4:** Un commit por pantalla + shas de reversa.

### Task 6: Grupo E — Login, onboarding y verificación (al final, con más cuidado)

**Files:** Modify `auth/login_screen.dart`, `onboarding/gate_screen.dart`, `onboarding/choose_role_screen.dart`, `onboarding/consumer_onboarding_screen.dart`, `onboarding/provider_onboarding_screen.dart`, `verification/verify_banner.dart`, `verification/otp_sheet.dart`.

**Dirección:** login = mascota `JayaloMascot` grande + botones de auth con jerarquía clara (Google primero). Onboarding = wizard con indicador de paso (píldoras), un concepto por pantalla, copy RD. Banner de verificación = tinte `pending` (ámbar suave), cerrable como está. OTP sheet = campos grandes, tono `unlocked` al verificar. ⚠️ Este flujo está E2E-verificado en device y es bloqueante de Play Store: cambios SOLO de presentación; ni un `await`, ni un provider, ni un orden de inicialización se mueve.

- [ ] **Step 1:** Mockups → elección del PO.
- [ ] **Step 2:** Implementar pantalla por pantalla.
- [ ] **Step 3:** Verificar: analyze 0, tests verdes (los 29 de onboarding intactos), y pedir al PO un pase E2E en el Redmi antes de dar el grupo por cerrado.
- [ ] **Step 4:** Un commit por pantalla + shas de reversa.

### Task 7: Barrido final de coherencia

- [ ] **Step 1:** `grep -rn "CircularProgressIndicator\|Colors\.\(amber\|green\|red\|blue\|grey\)" app/lib` → 0 resultados (excepto `Colors.white`/`transparent` justificados).
- [ ] **Step 2:** Revisar cada pantalla en light Y dark (el PO en device o screenshots de emulador): ningún texto ilegible, ningún violeta como primario en dark.
- [ ] **Step 3:** `flutter analyze` 0 + `flutter test` verde global.
- [ ] **Step 4:** Commit de limpieza si algo quedó + resumen al PO: lista pantalla→commit→sha de reversa.

---

## Self-review

- Cobertura: las 12 superficies del inventario están en los grupos A–E; notificaciones excluida a propósito (es la referencia).
- Los valores de diseño (radius, alphas, duraciones, staggers) están copiados del código real de `notifications_screen.dart`, no inventados.
- Tipos consistentes: `StatusTone` viene de `brand.dart`; `RequestPhase` de `domain/phase.dart`; `toneFor` es el único puente nuevo.
- Sin placeholders: cada grupo tiene dirección concreta; el detalle fino por pantalla queda intencionalmente para los mockups porque el PO decide entre variantes (proceso aprobado, no un TBD).
