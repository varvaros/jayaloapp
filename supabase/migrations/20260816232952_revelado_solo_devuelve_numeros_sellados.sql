-- `get_unlocked_offer_contact` comprobaba el sello en el EXISTS pero devolvía
-- `av.whatsapp_e164` en el RETURN QUERY SIN repetir la comprobación. Con el
-- esquema viejo eso era explotable: `whatsapp_e164` guardaba también el número
-- EN VUELO, así que un número que nadie había verificado podía salir revelado a
-- un proveedor que pagó por el desbloqueo. La migración 20260816224534 (columna
-- `whatsapp_pending_e164`) ya cerró esa vía por construcción.
--
-- Esto es la segunda capa: que la función no dependa de un invariante que no
-- comprueba. Además cierra la ventana entre las dos sentencias — en READ
-- COMMITTED cada una toma su propio snapshot, así que un sello retirado justo
-- después del EXISTS salía igualmente por el RETURN QUERY. Ahora falla hacia el
-- lado cerrado: sin sello no devuelve número.
--
-- No puede quedarse sin filas por este cambio: el EXISTS de arriba ya exige esa
-- misma condición (y una más, `whatsapp_reveal_enabled`), así que lo único que
-- puede pasar es que el sello desaparezca en ese microsegundo — y en ese caso
-- devolver nada es exactamente lo correcto.
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816232952).
CREATE OR REPLACE FUNCTION public.get_unlocked_offer_contact(_offer_id uuid)
 RETURNS TABLE(first_name text, phone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
BEGIN
  SELECT po.customer_id INTO v_customer_id
  FROM public.provider_offers po
  WHERE po.id = _offer_id
    AND po.user_id = auth.uid()
    AND po.status = 'accepted'
    AND po.unlocked_at IS NOT NULL;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Oferta no encontrada o no desbloqueada';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles pr
    JOIN public.account_verifications av
      ON av.user_id = pr.user_id AND av.business_id IS NULL
    WHERE pr.user_id = v_customer_id
      AND pr.whatsapp_reveal_enabled = true
      AND av.whatsapp_verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'El cliente no tiene WhatsApp disponible para revelar';
  END IF;

  UPDATE public.provider_offers
  SET whatsapp_revealed_at = now()
  WHERE id = _offer_id AND whatsapp_revealed_at IS NULL;

  RETURN QUERY
    SELECT pr.first_name, av.whatsapp_e164
    FROM public.profiles pr
    JOIN public.account_verifications av
      ON av.user_id = pr.user_id AND av.business_id IS NULL
    WHERE pr.user_id = v_customer_id
      -- Las dos condiciones del gate, repetidas donde de verdad sale el dato.
      AND pr.whatsapp_reveal_enabled = true
      AND av.whatsapp_verified_at IS NOT NULL;
END;
$function$;
