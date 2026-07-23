-- 20260723215505_push_include_message_new.sql
-- Suma `message_new` (CHAT) a los kinds que disparan push (pedido PO
-- 2026-07-23). Antes solo empujaban ofertas
-- ('request_new_in_category','offer_new','offer_accepted','offer_unlocked');
-- ahora el CHAT también dispara push → junto con el `notification_count` que
-- ahora setea `send-push`, el badge NUMÉRICO del ícono aparece igual para chat
-- y ofertas. Resto de la función idéntico (aplicado a prod vía MCP; este
-- archivo es la fuente de verdad en el repo).
CREATE OR REPLACE FUNCTION public.push_on_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_secret text;
BEGIN
  IF NEW.kind NOT IN
     ('request_new_in_category', 'offer_new', 'offer_accepted', 'offer_unlocked', 'message_new') THEN
    RETURN NEW;
  END IF;
  SELECT value #>> '{}' INTO v_secret
  FROM public.app_settings WHERE key = 'internal_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;
  PERFORM net.http_post(
    url := 'https://mfaiklvobnvgusbcssbx.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object(
      'user_id', NEW.user_id, 'kind', NEW.kind, 'title', NEW.title,
      'body', NEW.body, 'link', NEW.link)
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Nunca bloquear el INSERT de la notificación in-app por un fallo del push.
  RETURN NEW;
END; $$;

-- Footgun del proyecto (CLAUDE.md): Supabase auto-otorga EXECUTE en funciones;
-- ésta es de TRIGGER, nunca vía PostgREST. Re-revocar tras el CREATE OR REPLACE.
REVOKE ALL ON FUNCTION public.push_on_notification() FROM PUBLIC, anon, authenticated;
