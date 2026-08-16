-- La bandeja del proveedor mostraba SUS PROPIAS solicitudes.
--
-- Una cuenta con negocio que además publica solicitudes como cliente (caso
-- real: amaury@elcorito.com y su "Tablet 10 pulgadas con 128 GB") veía su
-- propia solicitud en "Para ti", y con el badge viejo —que contaba abiertas,
-- no no-leídas— ese contador se quedaba encendido PARA SIEMPRE: no puedes
-- ofertarte a ti mismo, así que no había forma de apagarlo.
--
-- El disparador de notificaciones (`notify_new_request_matches`) ya excluye al
-- autor con `b.user_id <> NEW.user_id` en sus dos caminos; esta RPC era la
-- única pieza que no lo hacía. Solo cambia el `WHERE` del CTE `marketplace`:
-- el resto de la función se recrea idéntica.
--
-- `store` NO lleva el filtro: ahí el proveedor es el dueño del producto y
-- `pi.provider_user_id = v_uid` es justamente lo que quiere ver.

CREATE OR REPLACE FUNCTION public.get_provider_inbox_unified(
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0,
  p_kind text DEFAULT NULL::text,
  p_source text DEFAULT NULL::text
)
RETURNS TABLE(
  id uuid, source text, title text, description text, image_url text,
  urgency text, zone text, created_at timestamp with time zone,
  target_categories text[], kind text, product_id uuid, unlocked boolean,
  match_level text, city text, sector text
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rubros uuid[];
  v_cats text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  SELECT coalesce(array_agg(DISTINCT pbr.rubro_id) FILTER (WHERE pbr.rubro_id IS NOT NULL), ARRAY[]::uuid[])
  INTO v_rubros
  FROM public.provider_business_rubros pbr
  JOIN public.provider_businesses pb ON pb.id = pbr.business_id
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
  ) s;

  RETURN QUERY
  WITH marketplace AS (
    SELECT r.id, 'marketplace'::text AS source, r.title, r.description, r.image_url,
           r.urgency, r.zone, r.created_at, r.target_categories, r.kind,
           NULL::uuid AS product_id, NULL::boolean AS unlocked,
           CASE WHEN r.target_rubros && v_rubros THEN 'rubro' ELSE 'categoria' END::text AS match_level,
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
