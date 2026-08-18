-- Pedir hablar con una persona ya existía a medias: el asistente de la web
-- (`sales-assistant-reply.server.ts`) detecta la frase, pone
-- `handover_requested = true`, se pausa y escribe un mensaje de sistema DENTRO
-- del chat. El agujero es que ese mensaje solo lo ve quien ya está mirando el
-- chat: si el proveedor no lo tiene abierto, un cliente que pidió atención
-- humana se queda esperando sin que nadie se entere.
--
-- Se cierra en la BASE y no en el cliente a propósito: el código que hoy pide
-- el handover vive en el repo de la web, y mañana puede pedirlo un botón de la
-- app o cualquier otra ruta. Colgándolo del cambio de la columna, todas avisan
-- sin coordinar despliegues.
--
-- Aplicada a producción vía MCP el 2026-08-18 (version 20260818231915).

-- ── 1. Pedir humano APAGA el bot, lo pida quien lo pida ─────────────────────
-- Hoy la web manda `paused: true` en el mismo UPDATE, pero eso es cortesía del
-- que llama. Aquí pasa a ser garantía del modelo de datos: no existe estado
-- "quiere humano pero el bot sigue hablando".
create or replace function public.pause_assistant_on_handover()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if NEW.handover_requested and not coalesce(OLD.handover_requested, false) then
    NEW.paused := true;
    NEW.active := false;
    NEW.pause_reason := coalesce(
      nullif(NEW.pause_reason, ''),
      'El cliente pidió hablar con una persona');
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_pause_assistant_on_handover on public.conversation_assistant_state;
create trigger trg_pause_assistant_on_handover
  before update of handover_requested on public.conversation_assistant_state
  for each row execute function public.pause_assistant_on_handover();

-- ── 2. Y avisa al proveedor ────────────────────────────────────────────────
create or replace function public.notify_assistant_handover()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.handover_requested and not coalesce(OLD.handover_requested, false) then
    begin
      insert into public.notifications
        (user_id, kind, title, body, link, entity_type, entity_id)
      values (
        NEW.owner_id,
        'assistant_handover_requested',
        'Un cliente quiere hablar contigo',
        'Pidió atención de una persona. El asistente se apagó en ese chat: '
          || 'te toca a ti.',
        '/messages?c=' || NEW.conversation_id::text,
        'conversation',
        NEW.conversation_id
      );
    exception when others then
      -- Fail-open DELIBERADO: si el aviso no se puede escribir, la pausa del
      -- bot NO se cae con él. Lo contrario sería peor — el bot seguiría
      -- hablándole encima a un cliente que pidió una persona. Queda traza en
      -- el log de Postgres para que el fallo no sea invisible.
      raise log 'notify_assistant_handover: no se pudo avisar al proveedor (conversacion %): %',
        NEW.conversation_id, SQLERRM;
    end;
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_notify_assistant_handover on public.conversation_assistant_state;
create trigger trg_notify_assistant_handover
  after update of handover_requested on public.conversation_assistant_state
  for each row execute function public.notify_assistant_handover();

-- ── 3. Ese aviso viaja como PUSH ───────────────────────────────────────────
-- Sin esto la notificación solo aparecería en la campana, que es justo el mismo
-- problema que el mensaje de sistema: hay que estar mirando para enterarse.
create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_secret text;
BEGIN
  IF NEW.kind NOT IN
     ('request_new_in_category', 'offer_new', 'offer_accepted', 'offer_unlocked', 'message_new',
      'conversation_completed', 'conversation_closed_inactivity', 'offer_improved',
      'conversation_inactivity_warning', 'product_interest_new',
      'request_cancelled_provider', 'offer_cancelled_customer',
      'wallet_low_balance', 'wallet_empty',
      -- NUEVO: un cliente esperando a una persona es lo más urgente que puede
      -- pasar en un chat, y el bot ya no va a contestar por nadie.
      'assistant_handover_requested') THEN
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
  RETURN NEW;
END;
$function$;
