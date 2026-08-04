# "Cerrada" y los avisos del servidor — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que los carteles del servidor dejen de anunciarse como "Nuevo mensaje" y lleven su propio
aviso a ambas partes, y que una solicitud cuya conversación se cerró sin completarse se vea
"Cerrada" en gris en la app y en la web.

**Architecture:** Dos partes independientes. La A es SQL: `notify_conversation_message` se retira
ante `kind IN ('system','audit')`, y las funciones que escriben esos carteles emiten su propia
notificación a las dos partes, copiando el patrón que `warn_stale_conversations` ya usa. La B es
derivación pura: una fase nueva `RequestPhase.closed` calculada desde `conversations.closed_at`, sin
escribir estado nuevo, replicada en la app y en el detalle de la web; más una excepción al guard de
`cancel_customer_request` para que borrar una "Cerrada" funcione.

**Tech Stack:** PostgreSQL/plpgsql (Supabase, proyecto `mfaiklvobnvgusbcssbx`), Flutter/Dart
(`jayalo-app`), TypeScript/React (`jayalo-main`).

## Global Constraints

- **Spec de referencia:** `docs/superpowers/specs/2026-08-03-cerrada-y-aviso-completado-design.md`
  (repo `jayalo-app`). Ante cualquier duda, manda el spec.
- **Dos repos.** App: `C:\Users\ac\Downloads\jayalo-app` (rama `feat/detalle-cliente-plegable`).
  Web: `C:\Users\ac\Downloads\jayalo-main\jayalo-main` (rama `master`). Las migraciones viven
  **siempre** en el repo web, en `supabase/migrations/`.
- **Nombres de migración:** `YYYYMMDDHHMMSS_descripcion_en_snake_case.sql`. La última existente es
  `20260803120000_grants_update_oferta_desde_la_app.sql`; usar timestamps posteriores.
- **Ninguna migración se aplica a producción sin verificarla antes en `BEGIN` / `ROLLBACK`** vía el
  MCP de Supabase (`execute_sql`), y sin autorización nombrada del PO para esa migración concreta.
- **Copys aprobados por el PO, literales:**
  - Completado — título: `Trato marcado como completado`; cuerpo:
    `El proveedor dio por completado el trato. Ya puedes calificar.`
  - Autocierre — título: `Tu chat se cerró por inactividad`; cuerpo:
    `Nadie escribió en N horas. Puedes calificar la transacción.` (N sale de `v_hours`, no se
    escribe a mano).
  - Chip de la lista: `Cerrada`, a secas, sin conteo de ofertas.
- **Kinds nuevos:** `conversation_completed` y `conversation_closed_inactivity`. **No** se añaden a
  la whitelist de `enqueue_notification_email` (decisión del PO: sin correo por ahora).
- **`sale_completed_provider` NO se reutiliza.** Ya se emite, va al proveedor y arrastra el correo
  con factura.
- **Baselines que no pueden empeorar:** app `flutter test` en verde (742 tests al empezar);
  web `npx tsc --noEmit` en 0 errores, `npm run lint` en 0 errores, `npx vitest run` en verde.
- **Commits:** mensaje en español, prefijo `feat:`/`fix:`/`docs:`, y al final
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Los mensajes de commit del repo de la app
  van **sin tildes** (convención observada en su historial).

---

## Estructura de ficheros

**Repo web (`jayalo-main/jayalo-main`)**

| Fichero | Responsabilidad |
|---|---|
| `supabase/migrations/20260803140000_carteles_servidor_no_son_mensajes.sql` | Crear: toda la parte A. Reemplaza 3 funciones y ajusta 1. |
| `supabase/migrations/20260803150000_cancelar_solicitud_con_trato_cerrado.sql` | Crear: excepción al guard de `cancel_customer_request`. |
| `src/components/marketplace/NotificationsBell.tsx` | Modificar: `iconFor` aprende los 2 kinds nuevos + el que ya le faltaba. |
| `src/routes/requests/$requestId.tsx` | Modificar: deriva la fase `closed` y la pinta. |

**Repo app (`jayalo-app/app`)**

| Fichero | Responsabilidad |
|---|---|
| `lib/domain/phase.dart` | Modificar: `RequestPhase.closed` + `OfferLite.conversationClosed`. |
| `lib/domain/notifications.dart` | Modificar: `iconFor` aprende los 2 kinds nuevos. |
| `lib/data/repos.dart` | Modificar: `offerLite` acepta el dato de conversación; helper nuevo `closedConversationOfferIds`. |
| `lib/features/shared/brand_kit.dart` | Modificar: `toneFor` cubre `closed`. |
| `lib/features/client/my_requests_screen.dart` | Modificar: `phaseChip`, permisos partidos en dos, `_fetch` con la consulta extra, desaturado de la miniatura. |
| `lib/features/client/request_status_screen.dart` | Modificar: el `switch` sobre la fase (lo señala el compilador). |
| `lib/features/client/request_detail_sheet.dart` | Modificar: ídem. |
| `test/phase_test.dart` | Modificar: casos de la fase nueva. |
| `test/my_requests_closed_card_test.dart` | Crear: pintura y permisos de la tarjeta "Cerrada". |
| `test/notifications_icons_test.dart` | Crear o extender: iconos de los kinds nuevos. |

**Orden.** Las tareas 1–4 (parte A) y 5–9 (parte B) son independientes entre bloques. Dentro de cada
bloque el orden sí importa.

---

## PARTE A — los avisos del servidor

### Task 1: Migración — los carteles dejan de ser mensajes y llevan su propio aviso

**Files:**
- Create: `jayalo-main/jayalo-main/supabase/migrations/20260803140000_carteles_servidor_no_son_mensajes.sql`

**Interfaces:**
- Consumes: nada de tareas anteriores.
- Produces: los kinds `conversation_completed` y `conversation_closed_inactivity` en
  `public.notifications.kind`. Las tareas 3 y 4 les ponen icono.

**Contexto que el implementador necesita.** El defecto: `notify_conversation_message` es un trigger
`AFTER INSERT` sobre `conversation_messages` que inserta una notificación `message_new` con título
fijo `'Nuevo mensaje'` para **todo** INSERT, incluidos los `kind='system'` y `kind='audit'`, que son
carteles de plataforma. El molde correcto ya existe en `warn_stale_conversations`, que además de su
cartel inserta una notificación propia a **ambas** partes con
`CROSS JOIN LATERAL (VALUES (c.customer_id), (c.provider_user_id))`. Este es el patrón a copiar.

Las cuatro funciones implicadas están en producción; sus definiciones actuales se leen con
`pg_get_functiondef`. **Esta migración reemplaza las funciones completas** (`CREATE OR REPLACE`),
así que hay que partir del cuerpo real y cambiar solo lo indicado — no reescribirlas de memoria.

- [ ] **Step 1: Volcar las definiciones actuales para partir de ellas**

Vía el MCP de Supabase, `execute_sql` sobre `mfaiklvobnvgusbcssbx`:

```sql
select p.proname, pg_get_functiondef(p.oid) as def
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('notify_conversation_message','mark_conversation_completed',
                    'auto_close_stale_conversations','close_conversation_on_offer_completed')
order by p.proname;
```

Guardar los cuatro cuerpos. Son la base literal de la migración.

- [ ] **Step 2: Escribir la migración**

Crear el fichero con este contenido. Los cuerpos van completos; lo que cambia respecto al original
está marcado con comentario.

```sql
-- Los carteles del servidor dejan de anunciarse como "Nuevo mensaje".
--
-- Hallazgo del PO (2026-08-03): al marcar una conversación como completada, al
-- otro lado le llegaba una notificación titulada "Nuevo mensaje". No era el
-- único caso: `notify_conversation_message` dispara con CADA insert en
-- `conversation_messages` sin mirar el `kind`, así que los cuatro carteles de
-- plataforma (completado, su duplicado, aviso de inactividad y cierre
-- automático) llegaban con ese título.
--
-- El patrón correcto ya existía en `warn_stale_conversations`: cartel en el
-- chat + notificación PROPIA a ambas partes. Aquí se generaliza.

-- 1) Un mensaje del servidor no es un mensaje: no genera `message_new`.
CREATE OR REPLACE FUNCTION public.notify_conversation_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_customer uuid;
  v_provider uuid;
  v_recipient uuid;
  v_title text;
  v_preview text;
BEGIN
  -- CAMBIO: los carteles de plataforma llevan su propia notificación (ver
  -- abajo). Antes caían aquí y se anunciaban como "Nuevo mensaje", con dos
  -- defectos extra: el reparto manda al cliente cuando `sender_id` es NULL
  -- (todos los `audit` lo son), así que el proveedor nunca se enteraba.
  IF NEW.kind IN ('system', 'audit') THEN
    RETURN NEW;
  END IF;

  SELECT customer_id, provider_user_id, COALESCE(product_name, request_title, 'Conversación')
    INTO v_customer, v_provider, v_title
    FROM public.conversations
    WHERE id = NEW.conversation_id;

  IF v_customer IS NULL THEN
    RETURN NEW;
  END IF;

  v_recipient := CASE WHEN NEW.sender_id = v_customer THEN v_provider ELSE v_customer END;
  IF v_recipient IS NULL OR v_recipient = NEW.sender_id THEN
    RETURN NEW;
  END IF;

  -- Preview legible por tipo de mensaje (espejo de messagePreview, chatTime.ts).
  IF NEW.kind = 'quick' THEN
    BEGIN
      v_preview := NULLIF(LEFT(NEW.body::jsonb ->> 'question', 140), '');
    EXCEPTION WHEN others THEN
      v_preview := NULL;
    END;
    v_preview := COALESCE(v_preview, 'Pregunta');
  ELSIF NEW.kind = 'image' THEN
    v_preview := '📷 Foto';
  ELSIF NEW.kind = 'address' THEN
    v_preview := '📍 Dirección';
  ELSE
    v_preview := NULLIF(LEFT(NEW.body, 140), '');
  END IF;

  INSERT INTO public.notifications (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
  VALUES (
    v_recipient,
    'message_new',
    'Nuevo mensaje',
    COALESCE(v_preview, v_title),
    '/messages?c=' || NEW.conversation_id::text,
    NEW.sender_id,
    'conversation_message',
    NEW.id::text
  );
  RETURN NEW;
END;
$function$;

-- 2) Completar emite su propia notificación, a las dos partes.
CREATE OR REPLACE FUNCTION public.mark_conversation_completed(_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_kind text;
  v_source uuid;
  v_customer uuid;
  v_provider uuid;
  v_status text;
  v_request_id text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT kind, source_id, customer_id, provider_user_id, status
    INTO v_kind, v_source, v_customer, v_provider, v_status
  FROM public.conversations
  WHERE id = _conversation_id;

  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Conversation not found';
  END IF;

  IF v_caller <> v_customer AND v_caller <> v_provider THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  UPDATE public.conversations
     SET status = 'cerrado',
         delivered_at = COALESCE(delivered_at, now())
   WHERE id = _conversation_id;

  -- Solo en la transición abierto→cerrado (idempotencia).
  IF v_status = 'abierto' THEN
    INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
    VALUES (_conversation_id, v_caller, 'system',
            '✓ Marcado como completado por el proveedor.');

    -- CAMBIO: notificación propia a AMBAS partes (antes el mensaje `system`
    -- generaba un `message_new` titulado "Nuevo mensaje", que además solo
    -- llegaba a uno de los dos).
    INSERT INTO public.notifications (user_id, kind, title, body, link, entity_type, entity_id)
    SELECT uid, 'conversation_completed',
           'Trato marcado como completado',
           'El proveedor dio por completado el trato. Ya puedes calificar.',
           '/messages?c=' || _conversation_id::text, 'conversation', _conversation_id::text
    FROM (VALUES (v_customer), (v_provider)) AS u(uid)
    WHERE uid IS NOT NULL;
  END IF;

  IF v_kind = 'offer' AND v_source IS NOT NULL THEN
    UPDATE public.provider_offers
       SET status = 'completed'
     WHERE id = v_source
     RETURNING request_id INTO v_request_id;

    IF v_request_id IS NOT NULL THEN
      UPDATE public.customer_requests
         SET status = 'completed'
       WHERE id::text = v_request_id
         AND status <> 'completed';
    END IF;
  END IF;
END;
$function$;

-- 3) El autocierre por inactividad emite la suya.
CREATE OR REPLACE FUNCTION public.auto_close_stale_conversations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[];
  v_hours numeric := COALESCE(
    (SELECT (value #>> '{}')::numeric FROM public.app_settings
      WHERE key = 'conversation_autoclose_hours'), 72);
BEGIN
  SELECT array_agg(t.id) INTO v_ids
  FROM (
    SELECT c.id,
           greatest(c.created_at, COALESCE(lm.last_msg, c.created_at)) AS last_act
    FROM public.conversations c
    LEFT JOIN LATERAL (
      SELECT max(m.created_at) AS last_msg
      FROM public.conversation_messages m
      WHERE m.conversation_id = c.id AND m.kind NOT IN ('system','audit')
    ) lm ON true
    WHERE c.status = 'abierto'
  ) t
  WHERE t.last_act < now() - (v_hours * interval '1 hour');

  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.conversations
     SET status = 'cerrado',
         closed_at = now(),
         delivered_at = COALESCE(delivered_at, now())
   WHERE id = ANY(v_ids) AND status = 'abierto';

  INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
  SELECT id, NULL, 'audit',
         'El chat se cerró automáticamente por inactividad. Puedes calificar la transacción.'
  FROM unnest(v_ids) AS id;

  -- CAMBIO: notificación propia a AMBAS partes. El horizonte sale de `v_hours`,
  -- no se escribe a mano: si el PO cambia `conversation_autoclose_hours` el
  -- texto sigue diciendo la verdad.
  INSERT INTO public.notifications (user_id, kind, title, body, link, entity_type, entity_id)
  SELECT uid, 'conversation_closed_inactivity',
         'Tu chat se cerró por inactividad',
         -- `rtrim` y no `trim`: con FM Postgres suprime los ceros decimales
         -- pero DEJA el separador, así que `to_char(72,'FM…0.99')` da "72." y
         -- el aviso decía "Nadie escribió en 72. horas". Verificado contra
         -- producción: 72→"72", 168→"168", 72.5→"72.5", 0.5→"0.5".
         'Nadie escribió en ' || rtrim(to_char(v_hours, 'FM999999990.99'), '.')
           || ' horas. Puedes calificar la transacción.',
         '/messages?c=' || c.id::text, 'conversation', c.id::text
  FROM public.conversations c
  CROSS JOIN LATERAL (VALUES (c.customer_id), (c.provider_user_id)) AS u(uid)
  WHERE c.id = ANY(v_ids) AND uid IS NOT NULL;

  RETURN COALESCE(array_length(v_ids, 1), 0);
END;
$function$;

-- 4) Se corta el cartel duplicado del completado.
--
-- `mark_conversation_completed` pone la oferta en `completed`, lo que dispara
-- este trigger; su UPDATE no hace nada (la conversación ya está `cerrado`) pero
-- el cartel se insertaba igual, así que el chat mostraba DOS carteles seguidos
-- diciendo lo mismo. Ahora el cartel solo sale si este trigger fue quien cerró.
CREATE OR REPLACE FUNCTION public.close_conversation_on_offer_completed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_conv_id uuid;
  v_closed int;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM 'completed') THEN
    SELECT id INTO v_conv_id
      FROM public.conversations
      WHERE kind = 'offer' AND source_id = NEW.id
      LIMIT 1;
    IF v_conv_id IS NOT NULL THEN
      UPDATE public.conversations
        SET status = 'cerrado',
            delivered_at = COALESCE(delivered_at, now())
        WHERE id = v_conv_id AND status = 'abierto';
      GET DIAGNOSTICS v_closed = ROW_COUNT;
      -- CAMBIO: solo si este trigger cerró de verdad.
      IF v_closed > 0 THEN
        INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
        VALUES (v_conv_id, NULL, 'audit', '✓ Pedido marcado como completado. El chat queda cerrado.');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
```

- [ ] **Step 3: Verificar en BEGIN/ROLLBACK contra producción — el camino feliz**

Vía MCP `execute_sql`, en **una sola** llamada (la transacción no sobrevive entre llamadas). Aplica
la migración, ejecuta el escenario y hace `ROLLBACK`. Sustituir `<PEGAR MIGRACIÓN>` por el contenido
del Step 2:

```sql
BEGIN;
<PEGAR MIGRACIÓN>

-- Escenario: una conversación de oferta abierta, marcada como completada.
-- Se toma una conversación real y se la devuelve a 'abierto' dentro de la transacción.
WITH victima AS (
  SELECT id, customer_id, provider_user_id FROM public.conversations
  WHERE kind = 'offer' AND source_id IS NOT NULL LIMIT 1
)
UPDATE public.conversations c SET status = 'abierto', closed_at = NULL
FROM victima v WHERE c.id = v.id;

-- Simular la llamada del proveedor sin pasar por auth.uid():
-- se replica el efecto insertando el mensaje `system` a mano.
INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
SELECT id, provider_user_id, 'system', '✓ Marcado como completado por el proveedor.'
FROM public.conversations WHERE status = 'abierto' AND kind = 'offer' LIMIT 1;

-- Un mensaje de persona en la misma conversación (control).
INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
SELECT id, customer_id, 'text', 'hola'
FROM public.conversations WHERE status = 'abierto' AND kind = 'offer' LIMIT 1;

SELECT m.kind AS mensaje, n.kind AS notif, n.title
FROM public.conversation_messages m
LEFT JOIN public.notifications n
  ON n.entity_type = 'conversation_message' AND n.entity_id = m.id::text
WHERE m.created_at > now() - interval '1 minute'
ORDER BY m.created_at;
ROLLBACK;
```

Esperado: la fila del mensaje `system` sale con `notif` y `title` en **NULL** (ya no genera
`message_new`); la del `text` sale con `notif = 'message_new'` y `title = 'Nuevo mensaje'`.

- [ ] **Step 4: Verificar que el mensaje de persona no se rompió, por cada tipo**

Misma técnica, un solo `execute_sql`:

```sql
BEGIN;
<PEGAR MIGRACIÓN>
WITH c AS (SELECT id, customer_id FROM public.conversations WHERE status = 'abierto' LIMIT 1)
INSERT INTO public.conversation_messages (conversation_id, sender_id, kind, body)
SELECT c.id, c.customer_id, k.kind, k.body
FROM c, (VALUES
  ('text','un texto normal'),
  ('image','https://x/y.jpg'),
  ('address','Calle 1'),
  ('quick','{"question":"¿Tienes stock?"}')
) AS k(kind, body);

SELECT m.kind, n.title, n.body
FROM public.conversation_messages m
JOIN public.notifications n
  ON n.entity_type = 'conversation_message' AND n.entity_id = m.id::text
WHERE m.created_at > now() - interval '1 minute'
ORDER BY m.kind;
ROLLBACK;
```

Esperado: cuatro filas. `image` → body `📷 Foto`; `address` → `📍 Dirección`; `quick` →
`¿Tienes stock?`; `text` → `un texto normal`. Todas con título `Nuevo mensaje`.

- [ ] **Step 5: Verificar el autocierre**

```sql
BEGIN;
<PEGAR MIGRACIÓN>
-- Envejecer una conversación abierta para que el barrido la coja.
UPDATE public.conversations SET created_at = now() - interval '400 hours'
WHERE id = (SELECT id FROM public.conversations WHERE status = 'abierto' LIMIT 1);
UPDATE public.conversation_messages SET created_at = now() - interval '400 hours'
WHERE conversation_id = (SELECT id FROM public.conversations WHERE status = 'abierto' LIMIT 1);

SELECT public.auto_close_stale_conversations() AS cerradas;

SELECT kind, title, body, count(*) AS destinatarios
FROM public.notifications
WHERE created_at > now() - interval '1 minute'
GROUP BY kind, title, body;
ROLLBACK;
```

Esperado: `cerradas >= 1`; una única fila con `kind = 'conversation_closed_inactivity'`,
título `Tu chat se cerró por inactividad`, cuerpo empezando por `Nadie escribió en 72 horas`, y
`destinatarios = 2` por conversación cerrada. **Ningún** `message_new` nuevo.

- [ ] **Step 6: Pedir autorización al PO y aplicar**

Mostrar al PO el resultado de los Steps 3–5 y pedir autorización **nombrando la migración**
(`20260803140000_carteles_servidor_no_son_mensajes`). Con el sí, aplicarla vía MCP `apply_migration`.

- [ ] **Step 7: Verificar en vivo**

```sql
select p.proname,
       pg_get_functiondef(p.oid) like '%NEW.kind IN (''system'', ''audit'')%' as tiene_guarda
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'notify_conversation_message';
```

Esperado: `tiene_guarda = true`.

- [ ] **Step 8: Commit (repo web)**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main"
git add supabase/migrations/20260803140000_carteles_servidor_no_son_mensajes.sql
git commit -m "fix: los carteles del servidor dejan de anunciarse como \"Nuevo mensaje\"

notify_conversation_message disparaba con cada insert sin mirar el kind, asi que
los cuatro carteles de plataforma llegaban titulados \"Nuevo mensaje\". Ahora se
retira ante system/audit y cada cartel lleva su propia notificacion a AMBAS
partes (los audit van con sender NULL y el reparto los mandaba solo al cliente).
De paso se corta el cartel duplicado del completado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Reconciliar las notificaciones "Nuevo mensaje" ya escritas

**Files:**
- Ninguno. Es una operación de datos, autorizada aparte.

**Interfaces:**
- Consumes: la migración de la Task 1 aplicada.
- Produces: nada que consuman tareas posteriores.

**Contexto.** Las notificaciones `message_new` que apuntan a mensajes `system`/`audit` ya escritas
siguen en la bandeja del usuario diciendo "Nuevo mensaje". La convención del proyecto es **nunca
borrar notificaciones, solo marcar `read_at`** (ver el precedente de 2026-07-16 en el CLAUDE.md del
repo web).

- [ ] **Step 1: Contar el residuo**

```sql
select count(*) as total, count(*) filter (where n.read_at is null) as sin_leer
from public.notifications n
join public.conversation_messages m
  on n.entity_type = 'conversation_message' and n.entity_id = m.id::text
where n.kind = 'message_new' and m.kind in ('system','audit');
```

- [ ] **Step 2: Enseñar el número al PO y pedir autorización**

Decisión suya: marcarlas leídas o dejarlas. Si dice que no, saltar al Step 4 y anotarlo.

- [ ] **Step 3: Marcar leídas (solo con el sí)**

```sql
update public.notifications n
set read_at = now()
from public.conversation_messages m
where n.entity_type = 'conversation_message' and n.entity_id = m.id::text
  and n.kind = 'message_new' and m.kind in ('system','audit')
  and n.read_at is null;
```

- [ ] **Step 4: Verificar y anotar**

Repetir el conteo del Step 1: `sin_leer` debe ser 0 (o el mismo de antes, si el PO dijo que no).
Anotar el resultado en el registro de la sesión.

---

### Task 3: Iconos de los kinds nuevos en la app

**Files:**
- Modify: `jayalo-app/app/lib/domain/notifications.dart:29-49`
- Test: `jayalo-app/app/test/notifications_icons_test.dart` (crear si no existe)

**Interfaces:**
- Consumes: los kinds `conversation_completed` y `conversation_closed_inactivity` de la Task 1.
- Produces: nada.

**Contexto.** `iconFor` mapea kind → icono, con fallback por familia. `conversation_inactivity_warning`
ya está (`Icons.hourglass_bottom`). Los dos nuevos caerían en `NotifFamily.system` → campana
genérica. `familyFor` se deja como está a propósito: no son ofertas ni mensajes.

- [ ] **Step 1: Escribir el test que falla**

Crear `jayalo-app/app/test/notifications_icons_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/notifications.dart';

void main() {
  test('los avisos de cierre de conversación tienen icono propio, no la campana', () {
    // Antes del 2026-08-03 estos carteles llegaban como `message_new`
    // ("Nuevo mensaje"); ahora tienen kind propio y no deben caer al fallback.
    expect(iconFor('conversation_completed'), Icons.check_circle_outline);
    expect(iconFor('conversation_closed_inactivity'), Icons.hourglass_disabled);
    // El aviso PREVIO ya existía y no cambia.
    expect(iconFor('conversation_inactivity_warning'), Icons.hourglass_bottom);
  });

  test('los kinds de conversación son de la familia system', () {
    expect(familyFor('conversation_completed'), NotifFamily.system);
    expect(familyFor('conversation_closed_inactivity'), NotifFamily.system);
  });
}
```

- [ ] **Step 2: Correr el test y ver que falla**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/notifications_icons_test.dart
```

Esperado: FALLA en el primer `expect` — devuelve `Icons.notifications_none` (el fallback de
`system`), no `Icons.check_circle_outline`.

- [ ] **Step 3: Añadir los dos casos**

En `lib/domain/notifications.dart`, dentro del `switch` de `iconFor`, justo debajo del caso de
`conversation_inactivity_warning` (línea 47):

```dart
      // Aviso de que un chat está por cerrarse por inactividad (cron 48h).
      'conversation_inactivity_warning' => Icons.hourglass_bottom,
      // El trato se dio por completado, y el chat se cerró solo por
      // inactividad. Kinds propios desde el 2026-08-03: antes ambos llegaban
      // como `message_new` con el título "Nuevo mensaje".
      'conversation_completed' => Icons.check_circle_outline,
      'conversation_closed_inactivity' => Icons.hourglass_disabled,
```

- [ ] **Step 4: Correr el test y ver que pasa**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/notifications_icons_test.dart
```

Esperado: PASA, 2 tests.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-app"
git add app/lib/domain/notifications.dart app/test/notifications_icons_test.dart
git commit -m "feat(app): icono propio para los avisos de trato completado y chat cerrado

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Iconos de los kinds nuevos en la web

**Files:**
- Modify: `jayalo-main/jayalo-main/src/components/marketplace/NotificationsBell.tsx:44-74`

**Interfaces:**
- Consumes: los kinds de la Task 1.
- Produces: nada.

**Contexto.** El `iconFor` de la web tiene `default: <MessageSquare/>` — un **globo de chat**. Así
que hoy ya pinta `conversation_inactivity_warning` (que existe en producción, 38 filas) con icono de
mensaje: el mismo error de fondo que arregla la parte A, en otra superficie. Se cierran los tres de
una vez. Los iconos vienen de `lucide-react`; hay que añadir los imports que falten.

- [ ] **Step 1: Comprobar qué iconos ya están importados**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && sed -n '1,30p' src/components/marketplace/NotificationsBell.tsx
```

Anotar si `Hourglass`, `HourglassIcon` o `CircleSlash` están ya en el import de `lucide-react`.

- [ ] **Step 2: Añadir los casos**

En `iconFor`, justo antes de `case "request_cancelled_provider"`:

```tsx
    case "conversation_completed":
      return <CheckCircle2 className="h-4 w-4" strokeWidth={1.75} />;
    // El `default` de esta función es un globo de chat, así que sin estos casos
    // un aviso de cierre se pintaba como si fuera un mensaje — el mismo error
    // que motivó el arreglo del backend el 2026-08-03.
    case "conversation_inactivity_warning":
    case "conversation_closed_inactivity":
      return <Hourglass className="h-4 w-4" strokeWidth={1.75} />;
```

Y añadir `Hourglass` al import de `lucide-react` de la cabecera del fichero si no estaba.

- [ ] **Step 3: Verificar tipos y lint**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && npx tsc --noEmit
```

Esperado: 0 errores. Después:

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && npm run lint
```

Esperado: 0 errores.

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main"
git add src/components/marketplace/NotificationsBell.tsx
git commit -m "fix: los avisos de cierre de chat dejan de pintarse con icono de mensaje

El default de iconFor es MessageSquare, asi que conversation_inactivity_warning
(ya en produccion) salia como si fuera un mensaje. Se anaden los tres kinds de
conversacion.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## PARTE B — la fase "Cerrada"

### Task 5: La regla, en el dominio

**Files:**
- Modify: `jayalo-app/app/lib/domain/phase.dart`
- Test: `jayalo-app/app/test/phase_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `enum RequestPhase { waiting, withOffers, accepted, unlocked, completed, closed }`
  - `OfferLite({required String status, DateTime? unlockedAt, bool conversationClosed = false})`
  - `phaseForRequest({required String requestStatus, required List<OfferLite> offers}) → RequestPhase`
    (firma sin cambios; el dato nuevo viaja dentro de `OfferLite`).

**Contexto.** `phaseForRequest` replica la derivación de la web. La regla nueva:
**la oferta aceptada tiene su conversación cerrada y la oferta no está `completed` → `closed`**.
`conversationClosed` tiene default `false` para no romper los llamadores que no lo saben.

**El orden es parte del contrato:** `completed` primero (gana siempre), luego `closed`, luego
`unlocked`, luego `accepted`. Una oferta `completed` nunca cae en `closed`.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final del `main()` de `test/phase_test.dart` (y cambiar el helper `o` de la cabecera):

```dart
OfferLite o(String s, {DateTime? u, bool closed = false}) =>
    OfferLite(status: s, unlockedAt: u, conversationClosed: closed);
```

```dart
  test('cerrada: la conversación de la oferta aceptada murió sin completarse', () {
    // Hallazgo del PO 2026-08-03: el chat se cierra (a mano o por el cron de
    // inactividad) y la solicitud seguía pintándose como trato vivo.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('accepted', closed: true)]),
        RequestPhase.closed);
    // También con el desbloqueo hecho: "En contacto" ya no es verdad.
    expect(
        phaseForRequest(requestStatus: 'open', offers: [
          o('accepted', u: DateTime(2026), closed: true)
        ]),
        RequestPhase.closed);
  });

  test('completada gana siempre sobre cerrada', () {
    // Completar CIERRA la conversación, así que las dos condiciones se dan a la
    // vez: el orden de evaluación es lo único que las distingue.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('completed', closed: true)]),
        RequestPhase.completed);
    expect(
        phaseForRequest(
            requestStatus: 'completed', offers: [o('accepted', closed: true)]),
        RequestPhase.completed);
  });

  test('una conversación viva no cierra nada', () {
    expect(
        phaseForRequest(requestStatus: 'open', offers: [o('accepted')]),
        RequestPhase.accepted);
    // Una oferta NO aceptada no tiene conversación; aunque llegara el dato, la
    // solicitud sigue viva porque el cliente aún puede aceptar otra.
    expect(
        phaseForRequest(
            requestStatus: 'open', offers: [o('pending'), o('rejected')]),
        RequestPhase.withOffers);
  });
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/phase_test.dart
```

Esperado: FALLA al compilar — `RequestPhase.closed` no existe y `OfferLite` no acepta
`conversationClosed`.

- [ ] **Step 3: Implementar**

Reemplazar el contenido de `lib/domain/phase.dart` por:

```dart
enum RequestPhase { waiting, withOffers, accepted, unlocked, completed, closed }

class OfferLite {
  const OfferLite({
    required this.status,
    this.unlockedAt,
    this.conversationClosed = false,
  });
  final String status; // pending | accepted | completed | rejected
  final DateTime? unlockedAt;

  /// La conversación de esta oferta tiene `closed_at` puesto. Solo existen
  /// conversaciones para ofertas aceptadas o completadas (verificado contra
  /// producción 2026-08-03), así que este dato solo llega con sentido ahí.
  /// Default `false`: los llamadores que no consultan conversaciones no
  /// cambian de comportamiento.
  final bool conversationClosed;
}

/// Réplica de la derivación de la web (src/routes/requests/$requestId.tsx
/// ~L1146-1164): completed si la solicitud está completed/closed o la oferta
/// aceptada está completed; CERRADA si esa oferta tiene su conversación cerrada
/// sin haberse completado; unlocked si la aceptada tiene unlocked_at; accepted
/// si hay aceptada; si no, por conteo de ofertas recibidas.
///
/// El ORDEN es parte del contrato: completar cierra la conversación, así que en
/// una completada se cumplen las dos condiciones a la vez y solo el orden las
/// distingue. `completed` va primero y gana siempre.
RequestPhase phaseForRequest({
  required String requestStatus,
  required List<OfferLite> offers,
}) {
  final accepted =
      offers.where((o) => o.status == 'accepted' || o.status == 'completed');
  final acceptedOffer = accepted.isEmpty ? null : accepted.first;
  final requestClosed = requestStatus == 'completed' || requestStatus == 'closed';
  final offerDone = acceptedOffer?.status == 'completed';
  if (requestClosed || offerDone) return RequestPhase.completed;
  // El trato murió: el chat se cerró (a mano, como "no concretado", o por el
  // cron de inactividad) sin que nadie lo diera por completado.
  if (acceptedOffer != null && acceptedOffer.conversationClosed) {
    return RequestPhase.closed;
  }
  if (acceptedOffer != null && acceptedOffer.unlockedAt != null) {
    return RequestPhase.unlocked;
  }
  if (acceptedOffer != null) return RequestPhase.accepted;
  return offers.isEmpty ? RequestPhase.waiting : RequestPhase.withOffers;
}
```

- [ ] **Step 4: Correr y ver que pasa**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/phase_test.dart
```

Esperado: PASA, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-app"
git add app/lib/domain/phase.dart app/test/phase_test.dart
git commit -m "feat(app): fase \"Cerrada\" cuando el chat del trato murio sin completarse

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Los consumidores del enum (y los dos que el compilador NO señala)

**Files:**
- Modify: `jayalo-app/app/lib/features/shared/brand_kit.dart:78-94`
- Modify: `jayalo-app/app/lib/features/client/my_requests_screen.dart:29-58`
- Modify: `jayalo-app/app/lib/features/client/request_detail_sheet.dart:17-37,188`
- Test: `jayalo-app/app/test/my_requests_closed_card_test.dart` (crear)

**Interfaces:**
- Consumes: `RequestPhase.closed` de la Task 5.
- Produces:
  - `toneFor(BuildContext, RequestPhase) → StatusTone` — para `closed` devuelve el mismo gris que
    `completed`.
  - `phaseChip(RequestPhase, int offerCount) → (IconData, String)` — para `closed`,
    `(Icons.lock_outline, 'Cerrada')`.
  - `blockedEditReasonForPhase(RequestPhase) → String?` y
    `blockedDeleteReasonForPhase(RequestPhase) → String?` — sustituyen a `blockedReasonForPhase`.

**Contexto.** Los `switch` sobre `RequestPhase` son exhaustivos, así que el compilador señala esos
sitios. **Pero no todos los consumidores son `switch`**: `request_detail_sheet.dart` usa dos mapas
`const` leídos con `!`, que el compilador no cubre y que revientan en runtime (Step 8). No dar la
tarea por hecha con `flutter analyze` en verde.

El desdoble de permisos es lo único no mecánico. Hoy `blockedReasonForPhase` decide de una vez si se
puede editar **y** borrar, y el swipe hace `blockedReason != null → actions: []`. El PO quiere que
sobre una "Cerrada" se pueda **borrar** pero no **editar**.

- [ ] **Step 1: Obtener la lista de sitios rotos**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter analyze 2>&1 | grep -i "closed\|RequestPhase"
```

Anotar cada fichero y línea. Es la lista **parcial** de trabajo — los mapas del Step 8 no salen ahí.

- [ ] **Step 2: Escribir los tests que fallan**

Crear `jayalo-app/app/test/my_requests_closed_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

/// Pedido PO 2026-08-03: una solicitud cuya conversación se cerró sin
/// completarse debe salir "Cerrada", apagada como la completada pero SIN el
/// violeta — el violeta es para el trato que terminó bien.
///
/// La Task 7 le añade a este fichero el grupo de widget tests, con sus imports.
void main() {
  test('el chip dice "Cerrada", sin conteo de ofertas', () {
    final (icon, label) = phaseChip(RequestPhase.closed, 3);
    expect(label, 'Cerrada');
    expect(icon, Icons.lock_outline);
    // No es "done_all": ese es el de completada y confundirlas es justo el bug.
    expect(icon, isNot(Icons.done_all));
  });

  test('permisos: cerrada se puede borrar pero no editar', () {
    expect(blockedDeleteReasonForPhase(RequestPhase.closed), isNull);
    expect(blockedEditReasonForPhase(RequestPhase.closed), isNotNull);
  });

  test('permisos: las demás fases no cambian', () {
    for (final p in [RequestPhase.waiting, RequestPhase.withOffers]) {
      expect(blockedDeleteReasonForPhase(p), isNull);
      expect(blockedEditReasonForPhase(p), isNull);
    }
    for (final p in [
      RequestPhase.accepted,
      RequestPhase.unlocked,
      RequestPhase.completed
    ]) {
      expect(blockedDeleteReasonForPhase(p), isNotNull);
      expect(blockedEditReasonForPhase(p), isNotNull);
    }
  });
}
```

- [ ] **Step 3: Correr y ver que falla**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/my_requests_closed_card_test.dart
```

Esperado: FALLA al compilar — `blockedEditReasonForPhase` no existe.

- [ ] **Step 4: `toneFor` en brand_kit.dart**

Añadir el caso al `switch` (después del de `completed`, línea 92):

```dart
    RequestPhase.completed =>
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
    // "Cerrada" comparte el gris de la completada a propósito (pedido PO
    // 2026-08-03): las dos están terminadas. Lo que las distingue es la banda
    // violeta, que solo lleva la completada.
    RequestPhase.closed =>
      dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
```

- [ ] **Step 5: `phaseChip` y el desdoble de permisos**

En `my_requests_screen.dart`, añadir al `switch` de `phaseChip` (tras la línea 47):

```dart
  RequestPhase.completed => (Icons.done_all, 'Completada'),
  // Sin el conteo de ofertas que llevan las fases vivas: el trato ya se
  // decidió, cuántas llegaron dejó de ser accionable.
  RequestPhase.closed => (Icons.lock_outline, 'Cerrada'),
};
```

Y **sustituir** `blockedReasonForPhase` (líneas 50-58) por las dos funciones:

```dart
/// Motivo por el que una solicitud NO se puede EDITAR, o null si sí.
///
/// Editar y borrar dejaron de ir juntos el 2026-08-03: sobre una "Cerrada" el
/// cliente puede limpiar la lista, pero editar no aplica — hubo trato.
String? blockedEditReasonForPhase(RequestPhase p) => switch (p) {
  RequestPhase.waiting || RequestPhase.withOffers => null,
  RequestPhase.accepted => 'Ya aceptaste una oferta: no puede editarse',
  RequestPhase.unlocked => 'Ya están en contacto: no puede editarse',
  RequestPhase.completed => 'Solicitud completada',
  RequestPhase.closed => 'El trato se cerró: no puede editarse',
};

/// Motivo por el que una solicitud NO se puede ELIMINAR, o null si sí.
///
/// La RPC `cancel_customer_request` solo acepta solicitudes `open`, y desde el
/// 2026-08-03 también las de trato cerrado aunque el proveedor haya pagado el
/// desbloqueo (el lead ya se consumió y el chat no puede reabrirse).
String? blockedDeleteReasonForPhase(RequestPhase p) => switch (p) {
  RequestPhase.waiting || RequestPhase.withOffers || RequestPhase.closed => null,
  RequestPhase.accepted => 'Ya aceptaste una oferta: no puede eliminarse',
  RequestPhase.unlocked => 'Ya están en contacto: no puede eliminarse',
  RequestPhase.completed => 'Solicitud completada',
};
```

- [ ] **Step 6: Cablear el swipe a los dos permisos**

En `my_requests_screen.dart`, la línea 530 (`firstOpen`) pasa a mirar el permiso de borrado, que es
el que decide si hay gesto útil:

```dart
                          final firstOpen = items.indexWhere(
                            (r) => blockedDeleteReasonForPhase(r.$2) == null,
                          );
```

Y el bloque de la línea 612-661 pasa a construir las acciones por separado:

```dart
                                    final blockedEdit =
                                        blockedEditReasonForPhase(phase);
                                    final blockedDelete =
                                        blockedDeleteReasonForPhase(phase);
                                    // El row queda "bloqueado" (franja gris que
                                    // explica) solo si NINGUNA acción aplica.
                                    final blocked =
                                        blockedDelete != null && blockedEdit != null
                                            ? blockedDelete
                                            : null;
```

y, en el `SwipeToActions`:

```dart
                                      blockedReason: blocked,
                                      peekKey: (blocked == null && i == firstOpen)
                                          ? 'requests.swipe.v1'
                                          : null,
                                      actions: [
                                        if (blockedDelete == null)
                                          SwipeAction(
                                            icon: Icons.delete_outline,
                                            label: 'Eliminar',
                                            color: Theme.of(context).colorScheme.error,
                                            onTap: () => _deleteRequest(id, offerCount),
                                          ),
                                        if (blockedEdit == null)
                                          SwipeAction(
                                            icon: Icons.edit_outlined,
                                            label: 'Editar',
                                            color: const Color(0xFF378ADD),
                                            // Editar llega en una sesión
                                            // próxima (decisión PO).
                                            onTap: () async => showJayaloToast(
                                              context,
                                              'Editar solicitud: próximamente.',
                                            ),
                                          ),
                                      ],
```

**Ojo con el `assert` de `SwipeToActions`** (`swipe_to_actions.dart:44`): exige
`actions.length > 0 || blockedReason != null`. La combinación de arriba lo respeta — si ambas están
bloqueadas, `blocked` no es null; si alguna aplica, la lista no está vacía.

- [ ] **Step 7: Desaturar la miniatura de la cerrada**

En `my_requests_screen.dart:1029`, el `muted` solo desatura la completada. Una "Cerrada" también
está terminada y la foto a todo color la vuelve a leer como viva — el mismo argumento del comentario
que ya está ahí:

```dart
    Widget muted(Widget child) => phase == RequestPhase.completed ||
            phase == RequestPhase.closed
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
            child: child,
          )
        : child;
```

- [ ] **Step 8: ⚠️ Los dos mapas que el compilador NO señala**

**Esto es lo más peligroso de la tarea.** `request_detail_sheet.dart` no usa `switch` para la fase:
usa dos mapas `const` y los lee **con el operador `!`** (`:122` y `:179`):

```dart
StatusChip(label: _phaseTitle[phase]!, tone: tone),
...
Text(_phaseCopy[phase]!, ...)
```

Una clave que falte **no da error de compilación**: da
`Null check operator used on a null value` **en tiempo de ejecución**, al abrir el detalle de una
solicitud "Cerrada". `flutter analyze` pasa limpio y el bug llega al device.

Añadir la entrada a **los dos** mapas (`:17-25` y `:28-37`):

```dart
const _phaseCopy = {
  ...
  RequestPhase.completed: 'Califica al proveedor para ayudar a la comunidad.',
  // Estos mapas se leen con `!`: una clave que falte es un crash en runtime,
  // no un error de compilación. Al añadir una fase hay que tocar LOS DOS.
  // Sin "puedes calificar": el panel de reseña está gateado en `completed`, y
  // `completedReviewBusinessIds` filtra ofertas `status == 'completed'`, que en
  // esta fase por definición no hay. La calificación existe, pero vive en el
  // CHAT — prometerla aquí manda al usuario a buscar algo que no está.
  RequestPhase.closed: 'El chat se cerró sin completarse.',
};

const _phaseTitle = {
  ...
  RequestPhase.completed: 'Completada',
  RequestPhase.closed: 'Cerrada',
};
```

Y el guard de cupos de `:188` — ofrecerle cupos a un trato ya cerrado no tiene sentido:

```dart
          if (offers.isNotEmpty &&
              phase != RequestPhase.completed &&
              phase != RequestPhase.closed) ...[
```

El bloque de `:212` (`if (phase == RequestPhase.completed)`, los paneles de reseña por negocio) se
deja **como está**: solo una oferta `completed` tiene negocio que reseñar, y una "Cerrada" por
definición no la tiene.

`request_status_screen.dart` **no necesita cambios**: importa `phaseChip` pero no hace ningún
`switch` sobre `RequestPhase` (verificado). No perder tiempo ahí.

- [ ] **Step 9: Comprobar que no queda nada**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter analyze
```

Esperado: sin errores. Y para cazar cualquier otro mapa indexado por fase que el analizador no vea:

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && grep -rn "RequestPhase\." lib/ | grep -v "phase.dart"
```

Revisar cada sitio: si es un `switch`, el compilador ya lo cubrió; si es un **mapa**, hay que añadir
la clave a mano.

- [ ] **Step 10: Correr los tests**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test
```

Esperado: todo en verde. Los tests que usaban `blockedReasonForPhase` (si los hay —
`my_requests_swipe_test.dart` es candidato) hay que actualizarlos a las funciones nuevas; el
compilador los señala.

- [ ] **Step 11: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-app"
git add app/lib app/test
git commit -m "feat(app): la solicitud de trato cerrado sale \"Cerrada\" en gris

Chip propio, gris de fase terminada sin la banda violeta (que se queda para la
completada), miniatura desaturada, y permisos partidos en dos: sobre una
cerrada se puede borrar pero no editar.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: La lista trae el estado de las conversaciones

**Files:**
- Modify: `jayalo-app/app/lib/data/repos.dart:431-436`
- Modify: `jayalo-app/app/lib/features/client/my_requests_screen.dart:314-358`
- Modify: `jayalo-app/app/lib/features/client/request_status_screen.dart:~185` — **el otro
  `offers.map(offerLite)`**
- Test: `jayalo-app/app/test/my_requests_closed_card_test.dart` (extender)

⚠️ **Hay DOS sitios que construyen `OfferLite`, no uno.** El de `my_requests_screen._fetch`
alimenta la lista; el de `request_status_screen.dart` alimenta el `RequestDetailSheet`. Si solo se
arregla el primero, **todo el Step 8 de la Task 6 queda como código muerto**: los dos mapas `const`,
el título "Cerrada" y el guard de cupos del detalle no se alcanzarían nunca, y el smoke del detalle
no podría probar nada. Lo destapó la revisión de la Task 6.

**Interfaces:**
- Consumes: `OfferLite.conversationClosed` (Task 5), `phaseChip` y `toneFor` (Task 6).
- Produces:
  - `offerLite(Map<String, dynamic> o, {bool conversationClosed = false}) → OfferLite`
  - `Future<Set<String>> closedConversationOfferIds(List<String> offerIds)` — ids de oferta cuya
    conversación tiene `closed_at`. Devuelve `{}` sin consultar si la lista viene vacía.

**Contexto.** `_fetch` (línea 314) trae las solicitudes y sus `provider_offers`
(`id,request_id,status,unlocked_at`). Falta el estado de la conversación. La pantalla ya pasó por
auditoría de rendimiento, así que la consulta extra debe ser mínima y **no hacerse si no hace
falta**: solo las ofertas `accepted`/`completed` tienen conversación (verificado: 0 conversaciones
para `pending`/`rejected`/`cancelled`).

La consulta es best-effort, como `_fetchUnseenRequests`: si falla, la lista se pinta sin la fase
nueva en vez de romperse.

- [ ] **Step 1: Escribir el test que falla**

Añadir a `test/my_requests_closed_card_test.dart`. Primero, los imports que la Task 6 no puso
(modelo: `my_requests_completed_card_test.dart`):

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
```

Y luego el grupo, dentro del `main()` que ya existe:

```dart
  group('tarjeta', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      onboardingStore.reset();
      await onboardingStore.markDone('client.my_requests.v1');
      await onboardingStore.markDone('client.others_requests.v1');
    });

    Widget host(Widget child) =>
        MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

    Future<List<(Map<String, dynamic>, RequestPhase, int)>> rows() async => [
          (
            {
              'id': 'r1',
              'title': 'Mesa de caoba',
              'kind': 'producto',
              'is_wholesale': false,
              'image_url': null,
              'status': 'open',
              'created_at': DateTime.now().toIso8601String(),
            },
            RequestPhase.closed,
            2,
          ),
        ];

    testWidgets('cerrada: gris de fase terminada y SIN banda violeta',
        (tester) async {
      await tester.pumpWidget(host(MyRequestsScreen(
        myFetch: rows,
        othersFetch: () async => [],
        actions: const [],
      )));
      await tester.pumpAndSettle();

      final card = tester.widget<JayaloCard>(find
          .ancestor(
            of: find.text('Mesa de caoba'),
            matching: find.byType(JayaloCard),
          )
          .first);
      expect(card.tint, JayaloStatus.completedLight.bg);
      expect(find.text('Cerrada'), findsOneWidget);
      // La banda violeta es SOLO de la completada: el violeta significa que el
      // trato terminó bien, y este no terminó — se apagó.
      expect(find.text('Completado'), findsNothing);
    });
  });
```

- [ ] **Step 2: Correr y ver que falla**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test test/my_requests_closed_card_test.dart
```

Esperado: FALLA — si la Task 6 ya está hecha debería pasar; si falla en `find.text('Cerrada')`,
revisar el `phaseChip`.

- [ ] **Step 3: `offerLite` acepta el dato nuevo**

En `lib/data/repos.dart`, sustituir `offerLite` (línea 431):

```dart
OfferLite offerLite(Map<String, dynamic> o, {bool conversationClosed = false}) =>
    OfferLite(
      status: o['status'] as String,
      unlockedAt: o['unlocked_at'] == null
          ? null
          : DateTime.parse(o['unlocked_at'] as String),
      conversationClosed: conversationClosed,
    );

/// Ids de oferta cuya CONVERSACIÓN ya está cerrada (a mano, "no concretado" o
/// el cron de inactividad). Es el dato con el que la lista distingue un trato
/// muerto de uno vivo.
///
/// Best-effort, como `_fetchUnseenRequests`: si la consulta falla, la lista se
/// pinta sin la fase "Cerrada" en vez de romperse.
Future<Set<String>> closedConversationOfferIds(List<String> offerIds) async {
  if (offerIds.isEmpty) return {};
  try {
    final rows = List<Map<String, dynamic>>.from(
      await supa
          .from('conversations')
          .select('source_id')
          .eq('kind', 'offer')
          .inFilter('source_id', offerIds)
          .not('closed_at', 'is', null),
    );
    return rows
        .map((r) => r['source_id'] as String?)
        .whereType<String>()
        .toSet();
  } catch (_) {
    return {};
  }
}
```

- [ ] **Step 4: `_fetch` usa el dato**

En `my_requests_screen.dart`, dentro de `_fetch`, entre el `select` de ofertas (línea 327) y el
bucle que arma `byReq` (línea 328):

```dart
    // Solo las ofertas aceptadas/completadas tienen conversación (verificado
    // contra producción 2026-08-03: cero conversaciones para pending/rejected/
    // cancelled). Si no hay ninguna, no se consulta nada: esta pantalla ya pasó
    // por auditoría de rendimiento y una ida y vuelta de más se nota.
    final dealIds = [
      for (final o in offers)
        if (o['status'] == 'accepted' || o['status'] == 'completed')
          o['id'] as String,
    ];
    final closedOfferIds = await closedConversationOfferIds(dealIds);
    final byReq = <String, List<OfferLite>>{};
    for (final o in offers) {
      byReq.putIfAbsent(o['request_id'] as String, () => []).add(
            offerLite(o,
                conversationClosed: closedOfferIds.contains(o['id'] as String)),
          );
    }
```

(sustituye al `byReq` que ya estaba).

- [ ] **Step 5: Correr los tests**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter test
```

Esperado: todo en verde.

- [ ] **Step 6: Comprobar que la consulta no se dispara de más**

Leer el diff de `_fetch` y confirmar a ojo: si `dealIds` está vacío, `closedConversationOfferIds`
devuelve `{}` **sin** llamar a Supabase. Es la garantía de rendimiento que pide el spec.

- [ ] **Step 7: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-app"
git add app/lib/data/repos.dart app/lib/features/client/my_requests_screen.dart app/test
git commit -m "feat(app): la lista de solicitudes lee si la conversacion del trato murio

Consulta extra minima (solo source_id, y solo para ofertas aceptadas), que no se
hace si no hay ninguna. Best-effort: si falla, la lista pinta sin la fase nueva.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Migración — borrar una "Cerrada" deja de estar bloqueado

**Files:**
- Create: `jayalo-main/jayalo-main/supabase/migrations/20260803150000_cancelar_solicitud_con_trato_cerrado.sql`

**Interfaces:**
- Consumes: nada (la regla se escribe en SQL, espejo de la Task 5).
- Produces: `cancel_customer_request` acepta solicitudes cuyo trato ya murió.

**Contexto y por qué hace falta.** `_deleteRequest` llama a `cancel_customer_request`, que rechaza
con `unlocked_offer_exists` si **alguna** oferta tiene `unlocked_at`. Comprobado contra producción:
las **13** solicitudes cerradas tienen su oferta desbloqueada — es inevitable, porque el proveedor
paga el desbloqueo justo para abrir el chat que después se cerró. Sin esta migración, el botón
"Eliminar" que la Task 6 destapa fallaría **siempre**.

El guard existe para no dejar sin respuesta a quien pagó. Cuando la conversación de esa oferta está
cerrada y la oferta no se completó, el proveedor ya obtuvo el contacto y el chat no puede reabrirse:
el motivo no aplica. **Es una RPC que toca dinero** — verificar con cuidado, incluido el caso que
debe seguir bloqueado.

**La condición SQL es la misma regla de la fase "Cerrada" de la Task 5.** Si una cambia, la otra
también.

- [ ] **Step 1: Escribir la migración**

```sql
-- Borrar una solicitud cuyo trato ya murió deja de estar bloqueado.
--
-- `cancel_customer_request` rechaza si alguna oferta tiene `unlocked_at`: el
-- guard existe para no dejar sin respuesta a un proveedor que pagó por el
-- contacto. Pero cuando la conversación de esa oferta ya está cerrada y la
-- oferta no se completó, el lead se consumió y el chat no puede reabrirse — el
-- motivo del guard no aplica, y sin esta excepción el cliente no puede limpiar
-- de su lista una solicitud muerta (pedido PO 2026-08-03).
--
-- La condición de la excepción es la MISMA regla que la fase "Cerrada" de la
-- app (`lib/domain/phase.dart`). Si una cambia, la otra también.

CREATE OR REPLACE FUNCTION public.cancel_customer_request(_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _req record;
  _unlocked int;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT id, user_id, status INTO _req
  FROM public.customer_requests
  WHERE id = _request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La solicitud no existe' USING ERRCODE = 'P0002';
  END IF;

  IF _req.user_id <> _uid THEN
    RAISE EXCEPTION 'No es tu solicitud' USING ERRCODE = '42501';
  END IF;

  IF _req.status = 'cancelled' THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;

  IF _req.status <> 'open' THEN
    RAISE EXCEPTION 'Solo se puede cancelar una solicitud abierta'
      USING ERRCODE = 'P0001';
  END IF;

  -- CAMBIO: una oferta desbloqueada YA NO bloquea si su conversación está
  -- cerrada y la oferta no llegó a completarse.
  SELECT count(*) INTO _unlocked
  FROM public.provider_offers o
  WHERE o.request_id = _request_id::text
    AND o.unlocked_at IS NOT NULL
    AND o.status <> 'completed'
    AND NOT EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.kind = 'offer' AND c.source_id = o.id AND c.closed_at IS NOT NULL
    );

  IF _unlocked > 0 THEN
    RAISE EXCEPTION 'unlocked_offer_exists' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.customer_requests
  SET status = 'cancelled', updated_at = now()
  WHERE id = _request_id;

  RETURN jsonb_build_object('ok', true, 'already', false);
END;
$function$;
```

**Ojo con la lógica del `NOT EXISTS`:** una oferta desbloqueada bloquea **salvo** que tenga
conversación cerrada. Una oferta desbloqueada **sin** conversación (caso raro, pero posible) sigue
bloqueando — es el lado seguro.

Nota sobre `o.status <> 'completed'`: una solicitud con oferta completada nunca llega aquí (la RPC
ya salió por `_req.status <> 'open'`), pero la condición se deja explícita para que la regla SQL sea
literalmente la misma que la de la app y se lea sin tener que razonar sobre el guard anterior.

- [ ] **Step 2: Verificar el caso que debe DESBLOQUEARSE**

Un solo `execute_sql`, sustituyendo `<PEGAR MIGRACIÓN>`:

```sql
BEGIN;
<PEGAR MIGRACIÓN>
-- Una solicitud real de trato cerrado.
WITH objetivo AS (
  SELECT DISTINCT r.id, r.user_id
  FROM public.customer_requests r
  JOIN public.provider_offers o ON o.request_id = r.id::text
  JOIN public.conversations c ON c.kind = 'offer' AND c.source_id = o.id
  WHERE r.status = 'open' AND c.closed_at IS NOT NULL AND o.status <> 'completed'
  LIMIT 1
)
SELECT id,
       (SELECT count(*) FROM public.provider_offers o
         WHERE o.request_id = objetivo.id::text AND o.unlocked_at IS NOT NULL)
         AS ofertas_desbloqueadas
FROM objetivo;
ROLLBACK;
```

Esperado: una fila con `ofertas_desbloqueadas >= 1` — confirma que el caso existe y que antes habría
sido rechazado. Anotar el `id` para el paso siguiente.

- [ ] **Step 3: Verificar el efecto real, con la sesión del dueño simulada**

```sql
BEGIN;
<PEGAR MIGRACIÓN>
-- Suplantar al dueño de la solicitud objetivo para que auth.uid() lo devuelva.
SELECT set_config('request.jwt.claims',
  json_build_object('sub', r.user_id::text, 'role', 'authenticated')::text, true)
FROM public.customer_requests r
WHERE r.id = '<ID DEL STEP 2>';

SELECT public.cancel_customer_request('<ID DEL STEP 2>') AS resultado;
SELECT status FROM public.customer_requests WHERE id = '<ID DEL STEP 2>';
ROLLBACK;
```

Esperado: `resultado` = `{"ok": true, "already": false}` y `status` = `cancelled`.

- [ ] **Step 4: Verificar el caso que debe SEGUIR BLOQUEADO**

El punto crítico: una oferta desbloqueada con conversación **abierta** no puede desbloquearse.

```sql
BEGIN;
<PEGAR MIGRACIÓN>
-- Reabrir la conversación del caso anterior: vuelve a ser un trato vivo.
UPDATE public.conversations SET closed_at = NULL, status = 'abierto'
WHERE kind = 'offer' AND source_id IN (
  SELECT id FROM public.provider_offers WHERE request_id = '<ID DEL STEP 2>'
);

SELECT set_config('request.jwt.claims',
  json_build_object('sub', r.user_id::text, 'role', 'authenticated')::text, true)
FROM public.customer_requests r WHERE r.id = '<ID DEL STEP 2>';

SELECT public.cancel_customer_request('<ID DEL STEP 2>');
ROLLBACK;
```

Esperado: **excepción `unlocked_offer_exists`**. Si esto NO falla, la migración abrió la puerta de
par en par y **no se aplica** — hay que revisar el `NOT EXISTS`.

- [ ] **Step 5: Pedir autorización al PO y aplicar**

Enseñar los resultados de los Steps 3 y 4 (el que desbloquea y el que sigue bloqueado) y pedir
autorización nombrando `20260803150000_cancelar_solicitud_con_trato_cerrado`. Es una RPC de dinero:
sin el sí explícito, no se aplica. Con el sí, `apply_migration`.

- [ ] **Step 6: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main"
git add supabase/migrations/20260803150000_cancelar_solicitud_con_trato_cerrado.sql
git commit -m "feat: se puede cancelar una solicitud cuyo trato ya murio

El guard de unlocked_offer_exists existe para no dejar sin respuesta a quien
pago por el contacto. Si la conversacion de esa oferta esta cerrada y la oferta
no se completo, el lead ya se consumio y el chat no puede reabrirse: el motivo
no aplica y el cliente no podia limpiar su lista.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: La web dice lo mismo

**Files:**
- Modify: `jayalo-main/jayalo-main/src/routes/requests/$requestId.tsx:1143-1164` y la carga de
  `offerExtras` (alrededor de `:298`)

**Interfaces:**
- Consumes: la regla de la Task 5, traducida a TypeScript.
- Produces: nada.

**Contexto.** La web **no tiene lista de solicitudes del cliente** (`/requests/mine` es un
`redirect` a `/requests`), así que la única superficie afectada es el detalle. Ahí se derivan las
fases en `:1146-1164` con `isCompletedPhase` / `isUnlockedPhase` / `isAcceptedPhase`. El estado por
oferta vive en `offerExtras` (`:298`), un `Record<string, OfferExtras>` que ya se rellena con una
consulta propia — el sitio natural para el dato de conversación.

**El orden importa igual que en la app:** `completed` primero.

- [ ] **Step 1: Localizar la carga de `offerExtras`**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && grep -n "setOfferExtras\|type OfferExtras" src/routes/requests/\$requestId.tsx
```

Anotar dónde se declara el tipo y dónde se hace el `setOfferExtras`. Ahí van los dos cambios.

- [ ] **Step 2: Añadir el campo al tipo y traer el dato**

Al tipo `OfferExtras`, añadir:

```ts
  /** La conversación de esta oferta tiene `closed_at`: el trato murió. */
  conversationClosed?: boolean;
```

Y junto a la consulta que ya rellena `offerExtras`, una consulta a `conversations` por los ids de
oferta ya conocidos, siguiendo el patrón de la que exista ahí (columnas explícitas, nunca
`select("*")` — es convención del repo):

```ts
const { data: convRows } = await supabase
  .from("conversations")
  .select("source_id")
  .eq("kind", "offer")
  .in("source_id", offerIds)
  .not("closed_at", "is", null);
const closedOfferIds = new Set((convRows ?? []).map((c) => c.source_id));
```

y volcarlo en el `setOfferExtras` correspondiente, poniendo
`conversationClosed: closedOfferIds.has(o.id)` en cada entrada.

- [ ] **Step 3: Derivar la fase**

En `:1146-1164`, entre `isCompletedPhase` e `isUnlockedPhase`:

```tsx
              const acceptedExtras = acceptedOffer ? offerExtras[acceptedOffer.id] : undefined;
              const isRequestClosed = req.status === "completed" || req.status === "closed";
              const isCompletedPhase =
                isRequestClosed ||
                acceptedExtras?.status === "completed" ||
                acceptedExtras?.status === "closed";
              // El trato murió: el chat se cerró (a mano, como "no concretado",
              // o por el cron de inactividad) sin que nadie lo completara.
              // Espejo de `phaseForRequest` en la app (lib/domain/phase.dart).
              // El orden importa: completar CIERRA la conversación, así que en
              // una completada se cumplen las dos y solo el orden las separa.
              const isClosedPhase =
                !isCompletedPhase && !!acceptedOffer && !!acceptedExtras?.conversationClosed;
              const isUnlockedPhase =
                !!acceptedOffer && !!acceptedOffer.unlockedAt && !isCompletedPhase && !isClosedPhase;
              const isAcceptedPhase =
                !!acceptedOffer && !isUnlockedPhase && !isCompletedPhase && !isClosedPhase;
              const phase:
                | "waiting" | "with_offers" | "accepted" | "unlocked" | "completed" | "closed" =
                isCompletedPhase
                  ? "completed"
                  : isClosedPhase
                    ? "closed"
                    : isUnlockedPhase
                      ? "unlocked"
                      : isAcceptedPhase
                        ? "accepted"
                        : offers.length === 0
                          ? "waiting"
                          : "with_offers";
```

- [ ] **Step 4: Darle estilo, título y copy a la fase nueva**

Son **cuatro** sitios. El primero lo exige TypeScript; los otros tres son ternarios encadenados que
se irían al `else` en silencio.

**(a) `phaseStyles` (`:1166-1200`)** — es un `Record<typeof phase, …>`, así que sin la clave nueva
`tsc` falla. Añadir tras la entrada `completed`:

```tsx
                completed: {
                  wrap: "border-border bg-muted/50",
                  icon: "text-muted-foreground",
                  title: "text-muted-foreground",
                  sub: "text-muted-foreground",
                },
                // Mismo apagado que la completada: las dos están terminadas.
                closed: {
                  wrap: "border-border bg-muted/50",
                  icon: "text-muted-foreground",
                  title: "text-muted-foreground",
                  sub: "text-muted-foreground",
                },
```

**(b) `PhaseIcon` (`:1203-1212`)** — hoy cae al `else` (`MessageSquare`, un globo de chat) para
cualquier fase no contemplada. Añadir la rama antes del `else`, con `Lock` de `lucide-react` (hay
que importarlo):

```tsx
              const PhaseIcon =
                phase === "waiting"
                  ? Clock
                  : phase === "accepted"
                    ? Trophy
                    : phase === "unlocked"
                      ? Check
                      : phase === "completed"
                        ? Check
                        : phase === "closed"
                          ? Lock
                          : MessageSquare;
```

**(c) El título (`:1218-1247`)** — sin esto, una "Cerrada" caería al `else` final y mostraría el
contador grande de ofertas recibidas, como si siguiera esperando. Añadir la rama tras la de
`completed`:

```tsx
                    ) : phase === "completed" ? (
                      <p className={`text-lg font-bold leading-tight ${ps.title}`}>
                        Solicitud completada
                      </p>
                    ) : phase === "closed" ? (
                      <p className={`text-lg font-bold leading-tight ${ps.title}`}>
                        Cerrada
                      </p>
```

**(d) El subtítulo (`:1249-1261`)** — mismo problema: el `else` dice "Solo verás identidad y
contacto del proveedor que aceptes", que en un trato ya cerrado es falso. Añadir tras `completed`:

```tsx
                        : phase === "completed"
                          ? "Califica al proveedor para ayudar a la comunidad."
                          : phase === "closed"
                            ? "El chat se cerró sin completarse. Puedes calificar al proveedor."
```

**(e) El mensaje de cupos (`:1262`)** — ofrecerle cupos a un trato cerrado no tiene sentido:

```tsx
                  {phase !== "completed" && phase !== "closed" && offers.length > 0 && (
```

**Ojo:** las comparaciones `offerExtras[o.id]?.status === "closed"` de `:1396` y `:1893` son otra
cosa — el estado de la **oferta**, no de la conversación. No tocarlas.

- [ ] **Step 5: Verificar tipos, lint y tests**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && npx tsc --noEmit
```

Esperado: 0 errores. Luego:

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && npm run lint
```

Esperado: 0 errores. Luego:

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main" && npx vitest run
```

Esperado: en verde, sin regresiones.

- [ ] **Step 6: Commit**

```bash
cd "C:/Users/ac/Downloads/jayalo-main/jayalo-main"
git add src/routes/requests/\$requestId.tsx
git commit -m "feat: el detalle de solicitud distingue el trato cerrado del completado

Misma regla que la app: si la conversacion de la oferta aceptada esta cerrada y
la oferta no se completo, la solicitud esta \"Cerrada\", no \"En contacto\".

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Smoke en device — el único gate real

**Files:**
- Create: `jayalo-app/docs/qa/2026-08-03-smoke-cerrada-y-avisos.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: el registro de QA.

**Contexto.** Ni la parte A (que vive en SQL) ni el cableado de la parte B los cubre ningún test
automatizado de punta a punta. El spec lo dice explícitamente: **el smoke es el único gate real.**

Recordatorio de la casa: un **APK debug NO se instala encima de un release**. Si el device tiene un
build de testers, hay que desinstalar primero — y eso borra la sesión.

- [ ] **Step 1: Compilar e instalar**

```bash
cd "C:/Users/ac/Downloads/jayalo-app/app" && flutter build apk --debug
```

- [ ] **Step 2: Parte A — el completado**

Con dos cuentas (cliente y proveedor) y una conversación de oferta abierta: el proveedor marca
"Marcar como completado". Comprobar en el device del **cliente**:
- llega **una** notificación titulada **"Trato marcado como completado"**, no "Nuevo mensaje";
- **no** llega ninguna otra notificación por ese hecho;
- en el chat aparece **un** cartel de completado, no dos;
- el icono de la notificación es el check, no la campana.

Y en el device del **proveedor**: llega la misma notificación.

- [ ] **Step 3: Parte A — el mensaje normal no se rompió**

En una conversación abierta, mandar un texto, una foto y una dirección. Comprobar que cada uno sigue
generando su "Nuevo mensaje" con el preview correcto (`📷 Foto`, `📍 Dirección`), y que el badge de
mensajes sin leer sube.

- [ ] **Step 4: Parte B — la lista**

En la lista de solicitudes del cliente, comprobar:
- una solicitud de trato cerrado sale en **gris** con la píldora **"Cerrada"** y **sin** banda
  violeta, con la miniatura desaturada;
- una **completada** sigue en gris **con** su banda violeta "Completado";
- las fases vivas (esperando / con ofertas / aceptada / en contacto) no cambiaron;
- la lista abre igual de rápido que antes.

- [ ] **Step 5: Parte B — los permisos**

Deslizar una "Cerrada": debe ofrecer **Eliminar** y **no** Editar. Ejecutar el borrado hasta el
final y comprobar que **funciona** — que no sale el toast de `unlocked_offer_exists` — y que la
solicitud desaparece de la lista.

Deslizar una **completada**: no debe ofrecer ninguna de las dos, y debe mostrar la franja gris con
su motivo.

- [ ] **Step 6: Parte B — la web coincide**

Abrir en la web el detalle de la **misma** solicitud que en el Step 4 salía "Cerrada". Debe decir lo
mismo, no "En contacto".

- [ ] **Step 7: Escribir el registro y commitear**

Crear `docs/qa/2026-08-03-smoke-cerrada-y-avisos.md` con: qué se probó, en qué device, con qué
cuentas, qué pasó en cada paso, y **qué no se pudo probar** (el autocierre por inactividad tarda
72 h reales; se puede forzar bajando `app_settings.conversation_autoclose_hours` con autorización
del PO, o darlo por verificado en el `BEGIN`/`ROLLBACK` de la Task 1 Step 5 y anotarlo como tal).

```bash
cd "C:/Users/ac/Downloads/jayalo-app"
git add docs/qa/2026-08-03-smoke-cerrada-y-avisos.md
git commit -m "docs(app): smoke de \"Cerrada\" y de los avisos del servidor

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Riesgos y cabos conocidos

- **El badge de chats sin leer cambia de comportamiento.** Los carteles del servidor dejan de
  encenderlo (el aviso llega por su notificación propia). Es correcto y está aprobado, pero se ve
  → Step 3 del smoke.
- **El correo del completado desaparece.** Hoy sale por la vía `message_new`; los kinds nuevos no
  entran a la whitelist. Aprobado por el PO. Si más adelante se quiere, es una tanda aparte con su
  plantilla en `notification-templates.ts` **y** su entrada en `enqueue_notification_email`.
- **La regla vive escrita tres veces**: `phase.dart` (app), `$requestId.tsx` (web) y el `NOT EXISTS`
  de `cancel_customer_request` (SQL). No hay forma barata de unificarlas; los tres sitios llevan un
  comentario que apunta a los otros. Si alguien cambia la regla, tiene que tocar los tres.
- **⚠️ Añadir un valor al enum NO es una operación que el compilador cubra entera.** Los `switch`
  sí; pero `request_detail_sheet.dart` tiene dos mapas `const` leídos con `!` (`:122`, `:179`) y la
  web tiene tres ternarios encadenados con `else` silencioso. Una clave que falte es un **crash al
  abrir el detalle** (app) o un texto falso (web), con `flutter analyze` y `tsc` en verde. Está
  cubierto en la Task 6 Step 8 y la Task 9 Step 4; si aparece una fase más en el futuro, esos son
  los sitios que hay que revisar a mano.
- **`auto_close_stale_conversations` cierra conversaciones `product_interest` además de `offer`.**
  Esas no cuelgan de ninguna solicitud, así que no afectan a la parte B — pero sí reciben la
  notificación nueva de la parte A, que es lo correcto.
- **La rama de la app (`feat/detalle-cliente-plegable`) arrastra 61 commits y tiene el PR #1
  abierto** hacia `master`. Este trabajo se apila encima. No mergear sin decisión del PO.
