# Crear solicitud gamificada — "Jayi te entrevista" (concepto A + barrita de C)

Fecha: 2026-07-19 · Aprobado por el PO en sesión (mockups comparados: A elegido,
con la barra de avance del concepto C). Reemplaza la presentación tipo chat de
`create_request_screen.dart`. La IA y el backend NO cambian (mismo contrato de
turnos de `/api/ai/chat-stream`, ADR-0032 vigente).

## Problema

1. El flujo se siente un chat (burbujas estilo WhatsApp) — "se pierde la
   esencia" de estar armando una solicitud (feedback PO 2026-07-19).
2. El aviso de envío es un `SnackBar` pegado al borde inferior: la navbar
   flotante lo tapa → "no veo aviso de que fue enviado".
3. `my_requests_screen` carga su lista una vez (`late Future _load = _fetch()`)
   y "Crear" es pestaña del shell → al volver con `go('/client')` la lista no
   refresca y la solicitud nueva no aparece.

## Diseño

### Pantalla de crear (sin chat)

- **Header violeta intacto** (toggle Producto/Servicio + "Al por mayor" antes
  de empezar). **Arranque intacto** (mascota + copy + chips cámara/galería +
  composer "¿Qué estás buscando?").
- Tras el primer mensaje, la lista de burbujas desaparece. La pantalla es una
  columna scrolleable:
  1. **Mascota entrevistadora** (`JayaloMascot`, ~64 px, centrada). Micro-
     reacción al llegar cada pregunta (pop de escala ~200 ms). Mientras la IA
     piensa: estado "pensando" (mascota + "Pensando…"). Nada lento — lección
     PO: "solo le das clic y pasa".
  2. **La pregunta en grande**: tipografía de titular ligera (`jayaloHead`,
     w500, ~20 px), centrada. Debajo, contador sutil "Pregunta N".
  3. **Opciones como botones de ancho completo** (tarjeta blanca, radio 14,
     tap → responde y avanza). `image_request` → botones Cámara / Galería /
     "Seguir sin foto". `kind_switch` → sus opciones. El **composer queda
     abajo** para responder con texto libre (siempre disponible).
  4. **Tarjeta "Tu solicitud"** (lila `EDEBFF`, como el detalle): miniaturas de
     fotos, la descripción inicial, y cada respuesta dada como línea con check
     (`✓ <respuesta>`). Dentro, **barra de avance honesta**: "N de ~M" donde
     M = 4 estimado (7 si mayorista, presupuesto real del prompt); nunca llega
     al 100 % hasta el turno `ready`; si N supera el estimado, M crece
     (M = max(base, N+1)). Turno `routing` sigue auto-respondiendo "ok" (solo
     se refleja como avance de barra, sin UI propia).
  5. **Turno `ready`**: la tarjeta final actual (título + bullets + chip
     mayorista) pasa a protagonista con "Enviar solicitud" y "Corregir algo".
     "Corregir algo" vuelve al modo pregunta con el texto fijo "¿Qué quieres
     corregir?" y el composer activo (mismo mecanismo `_ready = null`).

### Éxito al enviar

- Estado interno de la misma pantalla (sin ruta nueva): mascota grande
  celebrando + **confeti breve** (painter propio, ~800 ms, una vez, sin
  dependencias nuevas), titular "¡Tu solicitud está publicada!", subtítulo
  "Los proveedores empezarán a enviarte ofertas." y botón
  "Ver mis solicitudes" → `go('/client')`. Desaparece el SnackBar de éxito.

### Refresco de la lista (bug 3)

- `requestsChanged` (`ValueNotifier<int>` en `data/repos.dart`): `submitRequest`
  lo incrementa al insertar OK. `my_requests_screen` lo escucha y re-lanza
  `_fetch()`. El pull-to-refresh existente se mantiene.

### Avisos visibles (bug 2)

- Helper `showJayaloToast(context, msg)` (en `brand_kit`): SnackBar flotante
  con margen inferior `navBarReservedSpace(context)` — visible por encima de
  la navbar. Los errores de este flujo ("No se pudo enviar…", 429, etc.) lo
  usan. Adopción en el resto de pantallas: fuera de alcance (tarea futura).

## Qué NO cambia

Backend/IA (cero cambios de servidor), toggle Producto/Servicio y mayorista,
límite 2 fotos y su validación, navbar, paleta y doctrina estética, contrato
de `submitRequest`/`uploadRequestImage`.

## Reversibilidad y verificación

- Commits separados y reversibles: (1) bugs — notifier de refresco + toast
  visible; (2) rediseño gamificado + pantalla de éxito.
- Tests: los 315 actuales en verde; nuevos tests para el estimador de avance
  (pura), las líneas de resumen Q→A, y widget test del estado de éxito.
- QA en device (Redmi): flujo completo crear→publicar, ver el confeti, volver
  y encontrar la solicitud arriba sin pull-to-refresh.
