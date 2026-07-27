# Onboarding contextual y progresivo (app)

**Fecha:** 2026-07-27
**Estado:** Diseño validado por el PO — pendiente de plan de implementación
**Alcance:** App Flutter (`jayalo-app`) + una migración en Supabase. La web queda fuera.

## Problema

La app no debe tener pantallas de onboarding al inicio. En su lugar, cada área nueva de
Jayalo debe explicarse **la primera vez que el usuario la visita**, con una guía breve que
resalta el elemento relevante. Hoy solo existe un caso puntual de esto: el coach-mark de
"mantén presionado" (`HoldCoachMark`), con persistencia **local** y lógica propia. Este
proyecto lo generaliza a un **sistema reutilizable de guías**, con persistencia **por
usuario en el backend** para que sobreviva cierre de sesión y cambio de dispositivo.

## Requisitos (del PO)

- Cada guía aparece **solo la primera vez** que el usuario accede a esa sección.
- La pantalla se oscurece con un overlay; el elemento explicado queda **resaltado**.
- Mensaje corto y claro de qué puede hacer el usuario ahí.
- El usuario puede **avanzar, cerrar o saltar**.
- Una vez completada o cerrada, **no vuelve a aparecer** para ese usuario.
- Estado **persistente por usuario**, que sobrevive logout y cambio de dispositivo.
- Cada sección tiene su **estado independiente**.
- No repetir guías ni bloquear la navegación normal.
- Se activa **únicamente** al entrar por primera vez a una funcionalidad relevante.

## Decisiones tomadas (brainstorming CERRADO)

1. **Persistencia = backend (Supabase).** SharedPreferences no cumple cross-device. Tabla
   dedicada por usuario. (Alternativas descartadas: local puro; híbrido local→backend.)
2. **Sin grandfather.** Los usuarios existentes también verán las guías (una vez cada una).
   Mitigación natural: cada guía está anclada a su sección y solo dispara al entrar ahí, así
   que a un veterano **no** le aparecen todas juntas; las encuentra de a una al navegar.
3. **Unificar el coach-mark existente** bajo el sistema nuevo (su estado pasa a backend).
   Con dos matices obligatorios (ver más abajo): completar por acción real e import local.
4. **Alcance v1** = núcleo (6 guías) + Chat (cliente y proveedor) + Créditos. **Mi tienda
   fuera.**
5. **Web fuera de alcance.** Único candidato futuro (no ahora, y como *callout* puntual, no
   tour): el concepto de créditos.

## Arquitectura

### 1. Backend — Supabase

Tabla dedicada (no un `jsonb` en `profiles`, para evitar carreras de escritura si dos guías
se completan casi a la vez):

```sql
create table public.user_onboarding_guides (
  user_id      uuid        not null references auth.users(id) on delete cascade,
  guide_key    text        not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, guide_key)
);
```

- **RLS** activada. Política: el usuario solo ve/inserta filas con `user_id = auth.uid()`.
- **Grants** (mínimo privilegio, doctrina del proyecto): `authenticated` = SELECT + INSERT;
  **REVOKE** de `anon`, `PUBLIC`. Sin UPDATE ni DELETE (marcar visto es un upsert que nunca
  cambia; `on conflict do nothing`).
- **Verificar** con `has_function_privilege`/`has_table_privilege` que `anon` no puede leer
  ni escribir (ver [[jayalo-supabase-execute-grant-anon-gotcha]]).
- Aplicación vía **MCP de Supabase** (autorizado), proyecto `mfaiklvobnvgusbcssbx`.

**Lecturas y escrituras desde la app:**
- Leer estado: `select guide_key from user_onboarding_guides` (RLS filtra al usuario).
- Marcar visto: `upsert {user_id, guide_key} on conflict do nothing` — idempotente.

### 2. Flutter — tres piezas

Siguiendo patrones existentes (`OpenedConversationsStore` en
`features/chat/opened_conversations.dart`, `HoldTutorialStore` y `HoldCoachMark`).

**`OnboardingStore`** (singleton, `ChangeNotifier`) — nuevo, en `features/shared/`.
- Mantiene un `Set<String>` de guías completadas.
- **Carga** del backend al iniciar sesión (una consulta). Cachea el set en SharedPreferences
  como write-through (evita parpadeos y re-mostrar dentro del mismo device).
- API: `bool isDone(String key)`, `Future<void> markDone(String key)`.
- `markDone`: actualiza cache local **al instante** (no re-mostrar esta sesión) y dispara el
  `upsert` best-effort. El backend es la verdad al cambiar de dispositivo.
- **Fail-safe de arranque:** si la carga inicial falla (red), el store entra en modo
  "suprimir" esa sesión — `isDone` devuelve `true` para todo, así **no** se muestran guías
  por un error de red (mejor callar que spamear). Reintenta en el siguiente arranque/foco.

**`OnboardingGuide`** (widget) — el spotlight generalizado a partir de `HoldCoachMark`
(`features/shared/brand_kit.dart`).
- `OverlayPortal` + `LayerLink`/`CompositedTransformFollower`; velo oscuro, elemento
  resaltado, tarjeta con mensaje y botones.
- Soporta **N pasos** (por defecto 1).
- Dos modos: **anclado** (a un elemento vía `LayerLink`) o **de bienvenida** (sin ancla,
  tarjeta centrada).
- Reúsa la **lección de medición + fallback** del fix `f7cf41f`: si el anclaje no se puede
  medir, nunca dejar un elemento inaccesible (retry post-frame; si falla, degradar a tarjeta
  sin spotlight en vez de tapar la UI).

**Disparo** — cada guía se declara por sección, en dos sabores:
- **Anclada:** al montar la sección, si el objetivo existe y está medido y `!isDone(key)` →
  mostrar.
- **Por evento con datos:** dispara solo cuando la condición de datos se cumple (p. ej.
  "recibe ofertas" = lista de ofertas con ≥1 elemento), no al montar la pantalla vacía.

### 3. Completar por acción real (para los gestos)

El sistema expone `markDone(key)` invocable desde la lógica de la app, **desacoplado** del
descarte del overlay. Las guías de gesto se marcan hechas al **primer hold exitoso real**
(no al cerrar). Es una excepción deliberada: su criterio de "aprendida" es *hacer* la acción.

## Catálogo de guías v1

| key | rol | tipo | ancla / archivo |
|---|---|---|---|
| `client.create_request.v1` | cliente | anclada | botón "Crear solicitud" — `features/client/create_request_screen.dart` |
| `client.view_offers.v1` | cliente | evento (ofertas ≥1) | 1ª oferta — `features/client/request_status_screen.dart` (confirmar en plan) |
| `gesture.accept.v1` | cliente | acción real | hold aceptar — `features/client/offer_actions.dart` (absorbe el actual) |
| `client.chat_reveal.v1` | cliente | anclada | 1ª apertura de chat — `features/chat/chat_screen.dart` |
| `provider.requests_list.v1` | proveedor | anclada | listado — `features/provider/inbox_screen.dart` |
| `provider.make_offer.v1` | proveedor | anclada | botón "Hacer oferta" — `features/provider/request_detail_screen.dart` |
| `gesture.unlock.v1` | proveedor | acción real | hold desbloquear — `features/provider/unlock_flow.dart` (absorbe el actual) |
| `provider.chat_reveal.v1` | proveedor | anclada | 1ª apertura de chat — `features/chat/chat_screen.dart` |
| `wallet.credits.v1` | ambos | bienvenida | 1ª vez en wallet/recarga — localizar pantalla en plan (`domain/recharge.dart`) |

**Nota sobre chat_reveal:** cliente y proveedor son claves distintas porque el copy difiere
(al proveedor se le explica cómo/cuándo aparece el contacto de WhatsApp). Ambas anclan en
`chat_screen.dart` pero se eligen por rol.

### Copys propuestos (el PO puede ajustar)

- `client.create_request.v1`: "Aquí puedes contarnos qué necesitas para que los proveedores te hagan ofertas."
- `client.view_offers.v1`: "Aquí podrás comparar las ofertas de los proveedores y elegir la que más te convenga."
- `gesture.accept.v1`: demo de gesto — "Mantén presionado para aceptar." (copy actual)
- `client.chat_reveal.v1`: "Aquí coordinas los detalles con el proveedor antes de cerrar el trato."
- `provider.requests_list.v1`: "Aquí encontrarás personas que están buscando servicios como los que tú ofreces."
- `provider.make_offer.v1`: "Puedes enviar tu oferta gratis. Solo desbloqueas el contacto si el cliente acepta tu propuesta."
- `gesture.unlock.v1`: demo de gesto — "Mantén presionado para desbloquear." (copy actual)
- `provider.chat_reveal.v1`: "Aquí coordinas con el cliente. El contacto de WhatsApp se comparte cuando ambos avanzan."
- `wallet.credits.v1`: "Ofertar siempre es gratis. Los créditos solo se usan para desbloquear el contacto de un cliente que aceptó tu oferta."

## Comportamiento UX

- **Guías informativas:** botones **[Saltar]** y **[Siguiente]/[Entendido]**. Cerrar, saltar
  o terminar → `markDone` **permanente** (cumple "una vez cerrada no vuelve"). Tap fuera del
  elemento = también cierra y marca visto.
- **Guías de gesto (excepción):** reaparecen hasta el **primer hold exitoso real**. Tap fuera
  las descarta *esa vez* pero reaparecen hasta lograr el gesto. Comportamiento actual
  conservado.
- **Multi-paso:** [Siguiente] avanza; el último paso cierra y marca visto. [Saltar] salta la
  guía completa y la marca visto.
- **Nunca dos a la vez:** si por timing coincidieran dos guías, se encolan (una, luego la
  otra).
- **Reduced-motion:** sin demo en bucle; solo resaltado estático + texto (respetar
  `MediaQuery.disableAnimations`).
- **Nunca bloquea:** el overlay siempre es descartable; jamás atrapa al usuario.

## Migración y despliegue seguro

1. Migración de tabla + RLS + grants (MCP de Supabase). Verificar `anon` bloqueado.
2. **Import único local→backend:** en el primer arranque de la versión nueva, si existe el
   flag local `hold_tutorial_done` (de `HoldTutorialStore`), traducirlo a las claves
   `gesture.accept.v1` / `gesture.unlock.v1` y hacer `markDone` (upsert) — para no re-enseñar
   el gesto a quien ya lo domina. Best-effort; marcar el import como hecho localmente para no
   repetirlo.
3. **Fail-safe:** si el fetch inicial del estado falla, no se muestran guías esa sesión.
4. Deshabilitar/retirar la persistencia local propia de `HoldTutorialStore` una vez que el
   estado del gesto vive en el store nuevo (evitar dos fuentes de verdad). El plan decide si
   se borra o se deja como cache secundaria.

## Testing

- **Unitarios `OnboardingStore`:** `isDone`/`markDone`, write-through, idempotencia del
  upsert, modo fail-safe cuando la carga falla, import local→backend una sola vez.
- **Widget `OnboardingGuide`:** avanzar / saltar / cerrar → marca visto; multi-paso; fallback
  de anclaje (objetivo no medible no bloquea la UI); reduced-motion no crashea.
- **Disparo por evento:** `client.view_offers.v1` no aparece con lista vacía y sí con ≥1.
- **Gestos:** `gesture.*` se marcan solo con hold real, no al cerrar; aceptar no apaga el
  tutorial de desbloquear (regresión histórica del coach-mark).
- Mantener la suite verde (hoy **428/428**) y `flutter analyze` en 0.

## Fuera de alcance (v1)

- Guía de "Mi tienda" (proveedor).
- Cualquier onboarding en la web.
- Reaparición por versión (`.v2`): el esquema de clave versionada lo permite, pero no se
  ejercita en v1.

## Relacionado

- [[jayalo-app-tutorial-coach-mark-hold-2026-07-26]] — el coach-mark que este sistema absorbe.
- [[jayalo-app-onboarding-nativo-camino-b]] — onboarding de alta de cuenta (distinto de esto).
- [[jayalo-supabase-execute-grant-anon-gotcha]] — verificación de grants a `anon`.
- [[jayalo-business-reviews-grants-hardening-2026-07-20]] — patrón de RLS + grants mínimos.
