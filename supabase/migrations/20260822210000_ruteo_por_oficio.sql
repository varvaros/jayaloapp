-- Los avisos de una solicitud tienen que llegarle también a quien declaró la
-- PROFESIÓN que hace ese trabajo (pedido PO 2026-08-22: "los documentos legales
-- llegarle a abogados, los diseños gráficos a publicistas y diseñadores").
--
-- El fallo: el registro guarda la profesión en `provider_business_oficios`,
-- pero los TRES sitios que deciden quién ve qué leían solo
-- `provider_business_rubros`. Un abogado registrado como abogado era invisible:
-- ni push, ni correo, ni bandeja, ni podía abrir la solicitud.
--
-- El puente es `oficio_categories` (oficio → categorías). Un oficio apunta a
-- CATEGORÍAS, no a rubros, así que la coincidencia por profesión es de grano
-- grueso — y aun así cuenta como FUERTE (con push y correo), decisión del PO:
-- "es mejor que tenga solicitudes pendientes que no le interesan pero sean de
-- su profesión, a que estén vacías".
--
-- ⚠️ NO se exige `approved_at`: `set_business_oficios` no lo rellena, así que
-- filtrar por aprobado dejaría invisible a todo profesional nuevo — el mismo
-- bug que esto viene a cerrar. Si algún día la aprobación es un requisito de
-- verdad, hay que rellenarla en el alta ANTES de añadir el filtro aquí.

-- 1) Bandeja del proveedor: que la solicitud aparezca en "Para ti".
CREATE OR REPLACE FUNCTION public.get_provider_inbox_unified(
  p_limit integer DEFAULT 100, p_offset integer DEFAULT 0,
  p_kind text DEFAULT NULL::text, p_source text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, source text, title text, description text, image_url text,
   urgency text, zone text, created_at timestamp with time zone,
   target_categories text[], kind text, product_id uuid, unlocked boolean,
   match_level text, city text, sector text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rubros uuid[];
  v_cats text[];
  v_oficio_cats text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  SELECT coalesce(array_agg(DISTINCT pbr.rubro_id) FILTER (WHERE pbr.rubro_id IS NOT NULL), ARRAY[]::uuid[])
  INTO v_rubros
  FROM public.provider_business_rubros pbr
  JOIN public.provider_businesses pb ON pb.id = pbr.business_id
  WHERE pb.user_id = v_uid;

  -- Categorías que le dan sus PROFESIONES. Se calculan aparte de `v_cats`
  -- porque además de ampliar la bandeja suben el orden: una solicitud de tu
  -- profesión va arriba, como si fuera de tu rubro.
  SELECT coalesce(array_agg(DISTINCT oc.category_id) FILTER (WHERE coalesce(oc.category_id, '') <> ''), ARRAY[]::text[])
  INTO v_oficio_cats
  FROM public.provider_business_oficios pbo
  JOIN public.provider_businesses pb ON pb.id = pbo.business_id
  JOIN public.oficio_categories oc ON oc.oficio_id = pbo.oficio_id
  WHERE pb.user_id = v_uid;

  SELECT coalesce(array_agg(DISTINCT s.c), ARRAY[]::text[])
  INTO v_cats
  FROM (
    SELECT pb.category_id AS c
      FROM public.provider_businesses pb
     WHERE pb.user_id = v_uid AND coalesce(pb.category_id, '') <> ''
    UNION
    SELECT pbr.category_id
      FROM public.provider_business_rubros pbr
      JOIN public.provider_businesses pb2 ON pb2.id = pbr.business_id
     WHERE pb2.user_id = v_uid AND coalesce(pbr.category_id, '') <> ''
    UNION
    SELECT unnest(v_oficio_cats)
  ) s;

  RETURN QUERY
  WITH marketplace AS (
    SELECT r.id, 'marketplace'::text AS source, r.title, r.description, r.image_url,
           r.urgency, r.zone, r.created_at, r.target_categories, r.kind,
           NULL::uuid AS product_id, NULL::boolean AS unlocked,
           CASE
             WHEN r.target_rubros && v_rubros
               OR r.target_categories && v_oficio_cats THEN 'rubro'
             ELSE 'categoria'
           END::text AS match_level,
           r.city, r.sector
    FROM public.customer_requests r
    WHERE r.status = 'open'
      -- El fix: nadie se ve a sí mismo en su propia bandeja.
      AND r.user_id <> v_uid
      AND (p_kind IS NULL OR r.kind = p_kind)
      AND r.target_categories && v_cats
  ),
  store AS (
    SELECT pi.id,
           'store'::text,
           pi.product_name,
           pi.message,
           COALESCE(pp.image_urls[1], ''),
           NULL::text,
           NULL::text,
           pi.created_at,
           NULL::text[],
           COALESCE(pp.kind, 'producto'),
           pi.product_id,
           (pi.unlocked_at IS NOT NULL),
           'rubro'::text,
           NULL::text,
           NULL::text
    FROM public.product_interests pi
    LEFT JOIN public.provider_products pp ON pp.id = pi.product_id
    WHERE pi.provider_user_id = v_uid
      AND (p_kind IS NULL OR COALESCE(pp.kind, 'producto') = p_kind)
  )
  SELECT u.* FROM (
    SELECT * FROM marketplace
    UNION ALL
    SELECT * FROM store
  ) u
  WHERE p_source IS NULL OR u.source = p_source
  ORDER BY (u.match_level = 'rubro') DESC, u.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- 2) Guard de lectura: que pueda ABRIR la solicitud que le avisamos.
CREATE OR REPLACE FUNCTION public.provider_business_matches_request(_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := (select auth.uid());
  v_rubros uuid[];
  v_cats text[];
  v_oficio_cats text[];
  v_target_rubros uuid[];
  v_target_categories text[];
  v_target_business uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT r.target_rubros, r.target_categories, r.target_business_id
  INTO v_target_rubros, v_target_categories, v_target_business
  FROM public.customer_requests r
  WHERE r.id = _request_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_target_business IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.provider_businesses pb
    WHERE pb.id = v_target_business AND pb.user_id = v_uid
  ) THEN
    RETURN false;
  END IF;

  SELECT
    coalesce(array_agg(DISTINCT pbr.rubro_id) FILTER (WHERE pbr.rubro_id IS NOT NULL), ARRAY[]::uuid[]),
    coalesce(array_agg(DISTINCT pbr.category_id) FILTER (WHERE pbr.category_id IS NOT NULL), ARRAY[]::text[])
  INTO v_rubros, v_cats
  FROM public.provider_business_rubros pbr
  JOIN public.provider_businesses pb ON pb.id = pbr.business_id
  WHERE pb.user_id = v_uid;

  SELECT coalesce(array_agg(DISTINCT oc.category_id) FILTER (WHERE coalesce(oc.category_id, '') <> ''), ARRAY[]::text[])
  INTO v_oficio_cats
  FROM public.provider_business_oficios pbo
  JOIN public.provider_businesses pb ON pb.id = pbo.business_id
  JOIN public.oficio_categories oc ON oc.oficio_id = pbo.oficio_id
  WHERE pb.user_id = v_uid;

  IF array_length(v_rubros, 1) IS NULL AND array_length(v_cats, 1) IS NULL THEN
    SELECT coalesce(array_agg(DISTINCT pb.category_id) FILTER (WHERE pb.category_id IS NOT NULL), ARRAY[]::text[])
    INTO v_cats
    FROM public.provider_businesses pb
    WHERE pb.user_id = v_uid;
  END IF;

  -- La profesión abre puerta SIEMPRE, no como último recurso. Antes esto era
  -- un IF/ELSIF: quien tenía rubros nunca llegaba a que se le mirara nada más,
  -- así que un abogado CON rubros de otra cosa seguía sin poder abrir una
  -- solicitud legal.
  IF array_length(v_oficio_cats, 1) > 0
     AND v_target_categories IS NOT NULL
     AND v_target_categories && v_oficio_cats THEN
    RETURN true;
  END IF;

  IF array_length(v_rubros, 1) > 0 THEN
    RETURN v_target_rubros IS NOT NULL AND v_target_rubros && v_rubros;
  ELSIF array_length(v_cats, 1) > 0 THEN
    RETURN v_target_categories IS NOT NULL AND v_target_categories && v_cats;
  END IF;

  RETURN false;
END;
$function$;

-- 3) El disparador de avisos: la profesión cuenta como coincidencia FUERTE
--    (notificación + push + correo), decisión del PO.
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
  -- Cotizacion dirigida: SOLO el negocio objetivo se entera.
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

  -- Antes se exigian AMBOS. Ahora basta con las categorias: la coincidencia por
  -- profesion se decide con ellas, y sin rubros el EXISTS de rubro simplemente
  -- no encuentra a nadie (comparar contra un array vacio no casa).
  IF array_length(v_categories, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE((value #>> '{}')::int, 500) INTO v_limit
  FROM public.app_settings WHERE key = 'notify_matches_limit';
  v_limit := COALESCE(v_limit, 500);

  -- Coincidencia FUERTE: el rubro exacto, O la profesion declarada. Con push y
  -- correo. Un abogado que se registro como abogado entra por la segunda.
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
      AND (
        EXISTS (
          SELECT 1 FROM public.provider_business_rubros pbr
          WHERE pbr.business_id = b.id AND pbr.rubro_id = ANY(v_rubros)
        )
        OR EXISTS (
          SELECT 1
          FROM public.provider_business_oficios pbo
          JOIN public.oficio_categories oc ON oc.oficio_id = pbo.oficio_id
          WHERE pbo.business_id = b.id AND oc.category_id = ANY(v_categories)
        )
      )
    ORDER BY b.user_id, b.created_at DESC
  ) m
  ORDER BY (NEW.is_wholesale IS TRUE AND m.is_wholesale IS TRUE) DESC,
           m.created_at DESC
  LIMIT v_limit;

  -- Coincidencia DEBIL: la categoria, sin el rubro ni la profesion. Solo
  -- in-app (el kind 'request_new_related' queda fuera de las listas blancas de
  -- push y correo).
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
      -- Nadie recibe los dos avisos: se excluye a quien ya entro por el FUERTE.
      -- Esta condicion es el ESPEJO de la de arriba; si se toca una, la otra
      -- tambien, o el mismo proveedor recibe push y ademas "relacionada".
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
          AND (
            EXISTS (
              SELECT 1 FROM public.provider_business_rubros pbr3
              WHERE pbr3.business_id = pb3.id AND pbr3.rubro_id = ANY(v_rubros)
            )
            OR EXISTS (
              SELECT 1
              FROM public.provider_business_oficios pbo3
              JOIN public.oficio_categories oc3 ON oc3.oficio_id = pbo3.oficio_id
              WHERE pbo3.business_id = pb3.id AND oc3.category_id = ANY(v_categories)
            )
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
