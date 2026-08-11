-- Perfil del cliente visto por el proveedor (mockup aprobado 2026-08-11).
--
-- Decisión PO 2026-08-11: el nombre y la foto REALES del cliente se muestran
-- solo tras pagar un desbloqueo con ese cliente (oferta o interés de
-- producto); antes, el perfil es anónimo (alias + blur).
--
-- Reseñas (regla PO 2026-08-11): el proveedor NUNCA ve sus propios
-- comentarios en el perfil del cliente — reconocería su texto y
-- desanonimizaría al cliente gratis. Se excluyen las reseñas de cualquier
-- negocio del que consulta; las de otros proveedores sí se muestran, también
-- en el perfil anónimo (igual que el promedio que ya expone
-- get_customer_reputation).
--
-- Patrón del proyecto: SECURITY DEFINER + gate computado server-side +
-- REVOKE a anon (el REVOKE es obligatorio: Supabase auto-otorga EXECUTE al
-- recrear funciones).

CREATE OR REPLACE FUNCTION public.get_customer_public_profile(_customer_id uuid)
RETURNS TABLE(unlocked boolean, first_name text, last_name text, avatar_url text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH gate(ok) AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.provider_offers o
      JOIN public.customer_requests r ON r.id::text = o.request_id
      WHERE o.user_id = auth.uid()
        AND o.unlocked_at IS NOT NULL
        AND r.user_id = _customer_id
    ) OR EXISTS (
      SELECT 1
      FROM public.product_interests i
      WHERE i.provider_user_id = auth.uid()
        AND i.unlocked_at IS NOT NULL
        AND i.customer_id = _customer_id
    )
  )
  SELECT g.ok,
         CASE WHEN g.ok THEN p.first_name END,
         CASE WHEN g.ok THEN p.last_name END,
         CASE WHEN g.ok THEN p.avatar_url END
  FROM gate g
  JOIN public.profiles p ON p.user_id = _customer_id
  WHERE auth.uid() IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.get_customer_public_profile(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_customer_public_profile(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_customer_public_profile(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_reviews(_customer_id uuid, _limit integer DEFAULT 5)
RETURNS TABLE(rating integer, comment text, business_name text, created_at timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT cr.rating, cr.comment, b.name, cr.created_at
  FROM public.customer_reviews cr
  LEFT JOIN public.provider_businesses b ON b.id = cr.business_id
  WHERE cr.customer_id = _customer_id
    AND auth.uid() IS NOT NULL
    -- Nunca las reseñas propias (regla PO 2026-08-11): quien escribió el
    -- comentario reconocería su texto y sabría qué cliente es.
    AND NOT EXISTS (
      SELECT 1
      FROM public.provider_businesses own
      WHERE own.id = cr.business_id
        AND own.user_id = auth.uid()
    )
  ORDER BY cr.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(_limit, 5), 1), 20);
$$;

REVOKE ALL ON FUNCTION public.get_customer_reviews(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_customer_reviews(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_customer_reviews(uuid, integer) TO authenticated;
