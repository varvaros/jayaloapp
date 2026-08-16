-- La bandeja mostraba solicitudes de las que NUNCA se avisaba.
--
-- `notify_new_request_matches` hace el fan-out por RUBRO, pero
-- `get_provider_inbox_unified` lista por CATEGORÍA, que es más ancha. Con los
-- datos del 2026-08-16: de 11 items de bandeja, 10 cruzaban solo categoría —
-- las notificaciones cubrían ~9% de lo que el proveedor veía.
--
-- Eso no importaba mientras el badge de "Solicitudes" contara solicitudes
-- abiertas. Ahora cuenta NO VISTAS (una notificación sin leer), así que la
-- brecha se volvió visible: el badge y el chip "Nueva" quedaban apagados sobre
-- casi toda la bandeja.
--
-- Señal de que el camino faltaba y no es un invento: la función YA calculaba
-- `v_categories` y solo la usaba para el guard de salida temprana — se computa
-- y se descarta. El fan-out era puramente por rubro.
--
-- DOS KINDS, NO UNO. El aviso por categoría es una coincidencia DÉBIL (la RPC
-- misma la ordena debajo con `match_level = 'rubro' DESC`), así que va con kind
-- propio y se queda IN-APP: campana, chip "Nueva" y badge, sin push ni correo.
-- No hace falta tocar `push_on_notification` ni `enqueue_notification_email`:
-- las dos filtran por lista blanca de kinds, así que un kind nuevo queda fuera
-- por construcción. Mandar push de todo habría multiplicado los avisos ~10x y
-- el resultado predecible es que la gente apague las notificaciones.
--
-- El guard de entrada se deja EXACTAMENTE como estaba (exige categorías Y
-- rubros): hoy no existe ninguna solicitud con categorías pero sin rubros
-- (verificado sobre las 12 filas de `customer_requests`), así que relajarlo
-- sería ampliar el alcance del cambio sin arreglar ningún caso real.

CREATE OR REPLACE FUNCTION public.notify_new_request_matches()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_categories text[];
  v_rubros uuid[];
  v_limit int;
BEGIN
  -- Cotización dirigida: SOLO el negocio objetivo se entera. El RETURN va
  -- FUERA del filtro de la notificación: aunque el target esté suspendido o
  -- sea el propio autor (no se notifica a nadie), JAMÁS se cae al fan-out.
  IF NEW.target_business_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
    SELECT b.user_id,
           'request_new_in_category',
           'Te pidieron una cotización',
           COALESCE(NEW.title, 'Un cliente quiere cotizar contigo'),
           '/provider/requests/' || NEW.id::text,
           NEW.user_id,
           'customer_request',
           NEW.id::text
    FROM public.provider_businesses b
    WHERE b.id = NEW.target_business_id
      AND b.suspended_at IS NULL
      AND b.user_id <> NEW.user_id;
    RETURN NEW;
  END IF;

  v_categories := COALESCE(NEW.target_categories, ARRAY[]::text[]);
  v_rubros := COALESCE(NEW.target_rubros, ARRAY[]::uuid[]);

  IF array_length(v_categories, 1) IS NULL OR array_length(v_rubros, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE((value #>> '{}')::int, 500) INTO v_limit
  FROM public.app_settings WHERE key = 'notify_matches_limit';
  v_limit := COALESCE(v_limit, 500);

  -- ── Coincidencia FUERTE: el rubro exacto. Con push y correo. ──────────────
  INSERT INTO public.notifications (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
  SELECT m.user_id,
         'request_new_in_category',
         'Nueva solicitud en tu rubro',
         COALESCE(NEW.title, 'Hay una nueva solicitud que podría interesarte'),
         '/provider/requests/' || NEW.id::text,
         NEW.user_id,
         'customer_request',
         NEW.id::text
  FROM (
    SELECT DISTINCT ON (b.user_id) b.user_id, b.created_at, b.is_wholesale
    FROM public.provider_businesses b
    WHERE b.suspended_at IS NULL
      AND b.user_id <> NEW.user_id
      AND b.country_code = NEW.country_code
      AND (
        (NEW.kind = 'producto' AND b.offers IN ('productos','ambos'))
        OR (NEW.kind = 'servicio' AND b.offers IN ('servicios','ambos'))
        OR NEW.kind NOT IN ('producto','servicio')
      )
      AND EXISTS (
        SELECT 1 FROM public.provider_business_rubros pbr
        WHERE pbr.business_id = b.id AND pbr.rubro_id = ANY(v_rubros)
      )
    ORDER BY b.user_id, b.created_at DESC
  ) m
  ORDER BY (NEW.is_wholesale IS TRUE AND m.is_wholesale IS TRUE) DESC,
           m.created_at DESC
  LIMIT v_limit;

  -- ── Coincidencia DÉBIL: la categoría, sin el rubro. Solo in-app. ──────────
  -- Es exactamente el conjunto que la bandeja muestra con
  -- `match_level = 'categoria'`. El `NOT EXISTS` del rubro no es opcional: sin
  -- él, quien cruza AMBOS recibiría dos avisos de la misma solicitud y el badge
  -- la contaría una sola vez (se deduplica por entity_id), así que el segundo
  -- aviso quedaría imposible de apagar desde la bandeja.
  --
  -- La categoría de un proveedor es la de su negocio O la de cualquiera de sus
  -- rubros: la MISMA unión que arma `v_cats` en `get_provider_inbox_unified`.
  -- Si las dos definiciones se separan, vuelven a aparecer items sin aviso.
  INSERT INTO public.notifications (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
  SELECT m.user_id,
         'request_new_related',
         'Nueva solicitud relacionada',
         COALESCE(NEW.title, 'Hay una nueva solicitud que podría interesarte'),
         '/provider/requests/' || NEW.id::text,
         NEW.user_id,
         'customer_request',
         NEW.id::text
  FROM (
    SELECT DISTINCT ON (b.user_id) b.user_id, b.created_at, b.is_wholesale
    FROM public.provider_businesses b
    WHERE b.suspended_at IS NULL
      AND b.user_id <> NEW.user_id
      AND b.country_code = NEW.country_code
      AND (
        (NEW.kind = 'producto' AND b.offers IN ('productos','ambos'))
        OR (NEW.kind = 'servicio' AND b.offers IN ('servicios','ambos'))
        OR NEW.kind NOT IN ('producto','servicio')
      )
      -- Cruza por categoría…
      AND EXISTS (
        SELECT 1 FROM public.provider_businesses pb2
        WHERE pb2.user_id = b.user_id
          AND (
            pb2.category_id = ANY(v_categories)
            OR EXISTS (
              SELECT 1 FROM public.provider_business_rubros pbr2
              WHERE pbr2.business_id = pb2.id
                AND pbr2.category_id = ANY(v_categories)
            )
          )
      )
      -- …y NO recibió el aviso fuerte. Se mira sobre TODOS sus negocios, no
      -- solo `b`: el fan-out de arriba es por usuario, así que basta con que
      -- UNO de sus negocios lo califique para que ya tenga su aviso.
      --
      -- Este NOT EXISTS repite las condiciones del bloque de arriba
      -- (suspensión, país, `offers`) a propósito: la pregunta que responde no
      -- es "¿tiene el rubro?" sino "¿le llegó ya el aviso fuerte?". Con solo el
      -- rubro, un proveedor con un negocio de productos en el rubro y otro de
      -- servicios en la categoría se quedaría SIN NINGÚN aviso de una solicitud
      -- de servicio: el bloque fuerte lo descarta por `offers` y este lo
      -- descartaría por tener el rubro.
      AND NOT EXISTS (
        SELECT 1
        FROM public.provider_businesses pb3
        WHERE pb3.user_id = b.user_id
          AND pb3.suspended_at IS NULL
          AND pb3.country_code = NEW.country_code
          AND (
            (NEW.kind = 'producto' AND pb3.offers IN ('productos','ambos'))
            OR (NEW.kind = 'servicio' AND pb3.offers IN ('servicios','ambos'))
            OR NEW.kind NOT IN ('producto','servicio')
          )
          AND EXISTS (
            SELECT 1 FROM public.provider_business_rubros pbr3
            WHERE pbr3.business_id = pb3.id AND pbr3.rubro_id = ANY(v_rubros)
          )
      )
    ORDER BY b.user_id, b.created_at DESC
  ) m
  ORDER BY (NEW.is_wholesale IS TRUE AND m.is_wholesale IS TRUE) DESC,
           m.created_at DESC
  LIMIT v_limit;

  RETURN NEW;
END;
$function$;
