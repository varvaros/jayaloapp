-- 20260716120000_device_tokens_and_push.sql
-- Push nativo (app Flutter jayalo-app, spec 2026-07-16). Todo ADITIVO:
-- 1 tabla nueva + 2 triggers + 2 funciones. Cero cambios a objetos existentes.
--
-- ⚠️ ANTES DE APLICAR: verificar en pg_proc el cualificador real de http_post
-- que usa enqueue_notification_email (la relocación de pg_net del 2026-07-14
-- pudo moverlo de `net.` a otro schema) y ajustar abajo si difiere.

-- 1) Tokens de dispositivo (FCM). Sin datos sensibles: RLS de dueño + grants CRUD.
CREATE TABLE public.device_tokens (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'android',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY device_tokens_owner_all ON public.device_tokens
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
REVOKE ALL ON public.device_tokens FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;

-- 2) Notificación al CLIENTE cuando el proveedor desbloquea (hoy NO existe
--    este evento en `notifications` — de paso la web gana la notificación in-app).
CREATE OR REPLACE FUNCTION public.notify_customer_on_unlock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications
      (user_id, kind, title, body, link, actor_id, entity_type, entity_id)
    VALUES
      (NEW.customer_id, 'offer_unlocked', 'Contacto desbloqueado',
       COALESCE(NEW.request_title, 'El proveedor ya puede contactarte'),
       '/requests/' || NEW.request_id, NEW.user_id, 'offer', NEW.id::text);
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_notify_customer_on_unlock
  AFTER UPDATE OF unlocked_at ON public.provider_offers
  FOR EACH ROW
  WHEN (OLD.unlocked_at IS NULL AND NEW.unlocked_at IS NOT NULL)
  EXECUTE FUNCTION public.notify_customer_on_unlock();

-- 3) Fan-out a push: cada notification de un kind del corazón dispara la Edge
--    Function. Mismo patrón de secreto que enqueue_notification_email
--    (app_settings.internal_webhook_secret).
CREATE OR REPLACE FUNCTION public.push_on_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_secret text;
BEGIN
  IF NEW.kind NOT IN
     ('request_new_in_category', 'offer_new', 'offer_accepted', 'offer_unlocked') THEN
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
END; $$;

CREATE TRIGGER trg_push_on_notification
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.push_on_notification();
