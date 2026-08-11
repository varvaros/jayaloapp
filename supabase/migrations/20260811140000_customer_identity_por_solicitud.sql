-- Decisión PO 2026-08-11 (revisión del smoke): la identidad del cliente se
-- revela POR SOLICITUD, no por cliente. Antes, un solo desbloqueo con un
-- cliente lo revelaba en TODAS sus solicitudes; ahora el llamador debe traer
-- el contexto (solicitud, oferta o interés) y el gate exige que ESE contexto
-- esté pagado por él y pertenezca a ese cliente. Sin contexto → anónimo
-- (default seguro).
--
-- Firma nueva ≠ vieja: hay que DROPear la de un argumento o quedarían dos
-- overloads y PostgREST no sabría cuál llamar. El DROP borra los grants, así
-- que el REVOKE/GRANT final es doblemente obligatorio (gotcha 2026-07-15).

DROP FUNCTION IF EXISTS public.get_customer_public_profile(uuid);

CREATE FUNCTION public.get_customer_public_profile(
  _customer_id uuid,
  _request_id uuid DEFAULT NULL,
  _offer_id uuid DEFAULT NULL,
  _interest_id uuid DEFAULT NULL
)
RETURNS TABLE(unlocked boolean, first_name text, last_name text, avatar_url text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH gate(ok) AS (
    SELECT
      (_request_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.provider_offers o
        JOIN public.customer_requests r ON r.id::text = o.request_id
        WHERE r.id = _request_id
          AND r.user_id = _customer_id
          AND o.user_id = auth.uid()
          AND o.unlocked_at IS NOT NULL
      ))
      OR (_offer_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.provider_offers o
        JOIN public.customer_requests r ON r.id::text = o.request_id
        WHERE o.id = _offer_id
          AND o.user_id = auth.uid()
          AND o.unlocked_at IS NOT NULL
          AND r.user_id = _customer_id
      ))
      OR (_interest_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.product_interests i
        WHERE i.id = _interest_id
          AND i.provider_user_id = auth.uid()
          AND i.unlocked_at IS NOT NULL
          AND i.customer_id = _customer_id
      ))
  )
  SELECT g.ok,
         CASE WHEN g.ok THEN p.first_name END,
         CASE WHEN g.ok THEN p.last_name END,
         CASE WHEN g.ok THEN p.avatar_url END
  FROM gate g
  JOIN public.profiles p ON p.user_id = _customer_id
  WHERE auth.uid() IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.get_customer_public_profile(uuid, uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_customer_public_profile(uuid, uuid, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_customer_public_profile(uuid, uuid, uuid, uuid) TO authenticated;
