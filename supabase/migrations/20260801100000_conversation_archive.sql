-- Archivar una conversación: ocultarla de la bandeja SIN borrarla.
--
-- Por qué columnas y no un store local: archivar que no sobrevive a un
-- reinstall o a otro dispositivo se lee como un bug. Y por qué DOS columnas:
-- la fila es compartida por los dos participantes, y archivar es una decisión
-- privada de cada uno.
--
-- NO existe borrado de conversaciones, a propósito: la conversación es el
-- registro de un lead que el proveedor pagó con créditos.

-- 1) Columnas.
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS archived_by_customer boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_by_provider boolean NOT NULL DEFAULT false;

-- 2) Grant por columna, SUMÁNDOSE al existente (status, agreed_price,
--    agreed_hourly_rate, agreed_estimated_hours, updated_at — migración
--    20260615032752). Un GRANT por columna es aditivo: no pisa al anterior.
GRANT UPDATE (archived_by_customer, archived_by_provider)
  ON public.conversations TO authenticated;

-- 3) Guard: cada participante solo puede tocar SU columna. La política RLS
--    `Participants can update status` es simétrica (cualquiera de los dos
--    pasa el USING/WITH CHECK), así que sin este trigger el cliente podría
--    archivar del lado del proveedor. Mismo patrón que
--    enforce_agreed_price_provider_only (20260729210000): SECURITY INVOKER,
--    BEFORE UPDATE, y exención para admin/service_role.
CREATE OR REPLACE FUNCTION public.enforce_archive_own_side()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- service_role no tiene auth.uid(): se deja pasar (backfills, soporte).
  IF (select auth.uid()) IS NULL
     OR (select public.has_role((select auth.uid()), 'admin'::app_role)) THEN
    RETURN NEW;
  END IF;

  IF NEW.archived_by_provider IS DISTINCT FROM OLD.archived_by_provider
     AND (select auth.uid()) <> OLD.provider_user_id THEN
    RAISE EXCEPTION 'Only the provider can archive the provider side'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.archived_by_customer IS DISTINCT FROM OLD.archived_by_customer
     AND (select auth.uid()) <> OLD.customer_id THEN
    RAISE EXCEPTION 'Only the customer can archive the customer side'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger-only → sin EXECUTE directo (Supabase Cloud lo auto-otorga al crear).
REVOKE EXECUTE ON FUNCTION public.enforce_archive_own_side()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_archive_own_side ON public.conversations;
CREATE TRIGGER trg_enforce_archive_own_side
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_archive_own_side();

-- 4) La RPC de la lista devuelve `archived` YA RESUELTO para quien llama.
--    Sigue devolviendo TODAS las filas: el filtrado es del cliente, para que
--    la píldora "Archivados N" cuente sin un viaje extra.
--
--    ⚠️ Cambia el return type → DROP obligatorio (42P13), y el DROP BORRA LOS
--    GRANTS: el REVOKE/GRANT del final no es opcional.
DROP FUNCTION IF EXISTS public.get_my_conversations_list();
CREATE FUNCTION public.get_my_conversations_list()
RETURNS TABLE(
  id uuid, kind text, customer_id uuid, provider_user_id uuid,
  product_name text, agreed_price numeric, agreed_hourly_rate numeric,
  product_image_url text, status text, updated_at timestamptz,
  peer_name text, peer_avatar_url text,
  last_kind text, last_body text, last_created_at timestamptz,
  unread_count integer, archived boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    c.id, c.kind::text, c.customer_id, c.provider_user_id,
    c.product_name, c.agreed_price, c.agreed_hourly_rate,
    c.product_image_url, c.status::text, c.updated_at,
    CASE
      WHEN c.customer_id = auth.uid() THEN
        COALESCE(NULLIF(b.name,''), NULLIF(p.business_name,''),
                 NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)),''), 'Proveedor')
      ELSE
        COALESCE(NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)),''),
                 NULLIF(p.business_name,''), 'Cliente')
    END AS peer_name,
    CASE
      WHEN c.customer_id = auth.uid() THEN NULLIF(b.logo_url,'')
      ELSE COALESCE(NULLIF(p.avatar_url,''), NULLIF(cp.photo_url,''))
    END AS peer_avatar_url,
    lm.kind::text, lm.body, lm.created_at,
    COALESCE(un.cnt, 0) AS unread_count,
    CASE WHEN c.customer_id = auth.uid()
         THEN c.archived_by_customer ELSE c.archived_by_provider END AS archived
  FROM public.conversations c
  JOIN public.profiles p ON p.user_id =
    CASE WHEN c.customer_id = auth.uid() THEN c.provider_user_id ELSE c.customer_id END
  LEFT JOIN LATERAL (
    SELECT pb.name, pb.logo_url FROM public.provider_businesses pb
    WHERE pb.user_id = c.provider_user_id
    ORDER BY pb.created_at ASC LIMIT 1
  ) b ON c.customer_id = auth.uid()
  LEFT JOIN LATERAL (
    SELECT cp1.photo_url FROM public.candidate_profiles cp1
    WHERE cp1.user_id = c.customer_id LIMIT 1
  ) cp ON c.provider_user_id = auth.uid()
  LEFT JOIN LATERAL (
    SELECT m.kind, m.body, m.created_at
    FROM public.conversation_messages m
    WHERE m.conversation_id = c.id
    ORDER BY m.created_at DESC, m.id DESC LIMIT 1
  ) lm ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::int AS cnt FROM public.notifications n
    WHERE n.user_id = auth.uid() AND n.kind = 'message_new' AND n.read_at IS NULL
      AND (n.link = '/messages?c=' || c.id::text OR n.link = '/messages/' || c.id::text)
  ) un ON true
  WHERE c.customer_id = auth.uid() OR c.provider_user_id = auth.uid()
  ORDER BY c.last_message_at DESC, c.updated_at DESC, c.id DESC;
$$;

-- OBLIGATORIO tras el DROP: los grants se fueron con la función vieja.
REVOKE ALL ON FUNCTION public.get_my_conversations_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_conversations_list() TO authenticated;
