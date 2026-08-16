-- El contador de intentos del OTP era leer-e-incrementar desde la edge function:
-- SELECT de whatsapp_attempts, comprobación en JS, UPDATE con el valor leído + 1.
-- Dos peticiones concurrentes leen el mismo valor y ambas escriben el mismo +1,
-- así que el tope de 5 intentos se puede rebasar disparando peticiones en
-- paralelo: con suficiente paralelismo, el espacio de 900.000 códigos se
-- recorre sin que el contador avance a la par.
--
-- Aquí todo el ciclo (leer, decidir, incrementar o sellar) ocurre dentro de una
-- sola sentencia con la fila bloqueada, así que las peticiones concurrentes del
-- mismo usuario se serializan y cada una ve el contador ya incrementado por la
-- anterior.
--
-- El hash del código se compara AQUÍ, no en el cliente: la función recibe el
-- SHA-256 y nunca el código en claro, igual que hoy hace la edge function.
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816223713).
create or replace function public.consume_whatsapp_otp_attempt(
  _user_id uuid,
  _business_id uuid,
  _code_hash text,
  _max_attempts int default 5
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_hash text;
  v_expires timestamptz;
  v_attempts int;
  v_e164 text;
  -- El tope vive en la edge function (MAX_ATTEMPTS); se acota por si acaso, para
  -- que un valor absurdo no convierta el tope en "infinito".
  v_max int := greatest(1, least(coalesce(_max_attempts, 5), 20));
  v_now timestamptz := now();
begin
  if _user_id is null or coalesce(_code_hash, '') = '' then
    return jsonb_build_object('status', 'no_pending');
  end if;

  -- FOR UPDATE es el punto entero de esta función: serializa a los concurrentes.
  -- El par (user_id, business_id) es único (account_verifications_user_id_business_id_key
  -- y el parcial account_verifications_personal_unique), así que es una fila o ninguna.
  select av.id, av.whatsapp_otp_hash, av.whatsapp_otp_expires_at,
         av.whatsapp_attempts, av.whatsapp_e164
    into v_id, v_hash, v_expires, v_attempts, v_e164
    from public.account_verifications av
   where av.user_id = _user_id
     and case when _business_id is null
              then av.business_id is null
              else av.business_id = _business_id end
   for update;

  if v_id is null or v_hash is null then
    return jsonb_build_object('status', 'no_pending');
  end if;
  if v_expires is not null and v_expires < v_now then
    return jsonb_build_object('status', 'expired');
  end if;
  if coalesce(v_attempts, 0) >= v_max then
    return jsonb_build_object('status', 'too_many');
  end if;

  if v_hash is distinct from _code_hash then
    update public.account_verifications
       set whatsapp_attempts = coalesce(whatsapp_attempts, 0) + 1
     where id = v_id
    returning whatsapp_attempts into v_attempts;
    return jsonb_build_object(
      'status', 'wrong',
      'attempts_left', greatest(v_max - coalesce(v_attempts, 0), 0)
    );
  end if;

  -- Acierto: se sella y se quema el código en la misma transacción, así que un
  -- código correcto no se puede reutilizar ni siquiera en una carrera.
  update public.account_verifications
     set whatsapp_verified_at = v_now,
         whatsapp_otp_hash = null,
         whatsapp_otp_expires_at = null,
         whatsapp_attempts = 0
   where id = v_id;

  return jsonb_build_object(
    'status', 'ok',
    'phone', v_e164,
    'verified_at', v_now
  );
end;
$function$;

-- Mínimo privilegio: solo la edge function (service_role) puede llamarla. Con
-- EXECUTE para authenticated, cualquiera podría sellar la verificación de otro
-- usuario pasando su user_id — la función es SECURITY DEFINER y no mira auth.uid().
revoke all on function public.consume_whatsapp_otp_attempt(uuid, uuid, text, int)
  from public, anon, authenticated;
grant execute on function public.consume_whatsapp_otp_attempt(uuid, uuid, text, int)
  to service_role;
