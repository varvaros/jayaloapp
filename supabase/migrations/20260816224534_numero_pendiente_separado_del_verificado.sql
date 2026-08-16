-- `whatsapp_e164` hacía dos trabajos incompatibles: "el número que estoy
-- verificando ahora" y "el número que quedó verificado". Como solo hay una fila
-- por (usuario, negocio), PEDIR un código para otro número pisaba el verificado
-- y el guard `trg_clear_whatsapp_seal_on_number_change` borraba el sello — que
-- es lo correcto dado ese esquema, pero significa que abrir la hoja de OTP con
-- otro número y ABANDONARLA cuesta un sello legítimamente ganado, sin que nadie
-- verifique nada.
--
-- Se separan los dos papeles: el número en vuelo vive en `whatsapp_pending_e164`
-- y solo se PROMUEVE a `whatsapp_e164` al verificarlo, en el mismo UPDATE que
-- pone el sello. A partir de aquí `whatsapp_e164` solo contiene números que
-- alguien verificó de verdad, que es lo que ya asumían sus lectores
-- (`trg_seal_business_whatsapp_from_personal`, el gate de revelado y el chequeo
-- de respaldo del sello de negocio).
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816224534).
alter table public.account_verifications
  add column if not exists whatsapp_pending_e164 text;

comment on column public.account_verifications.whatsapp_pending_e164 is
  'Número E.164 con un código en vuelo. Lo escribe send-otp; consume_whatsapp_otp_attempt lo promueve a whatsapp_e164 al verificar y lo deja en NULL. Nunca implica verificación.';

-- Los códigos que estén en vuelo AHORA MISMO fueron escritos por el send-otp
-- viejo, que puso el número en `whatsapp_e164`. Sin este backfill, esos usuarios
-- reciben "No hay código pendiente" en el primer verify tras el despliegue.
update public.account_verifications
   set whatsapp_pending_e164 = whatsapp_e164
 where whatsapp_otp_hash is not null
   and whatsapp_pending_e164 is null;

-- La RPC del intento atómico (20260816223713) ahora promueve el pendiente.
-- El `coalesce` es deliberado: mientras send-otp no esté desplegado, el número
-- sigue llegando en `whatsapp_e164` y la función tiene que seguir sellando bien.
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
  v_pending text;
  v_final text;
  v_max int := greatest(1, least(coalesce(_max_attempts, 5), 20));
  v_now timestamptz := now();
begin
  if _user_id is null or coalesce(_code_hash, '') = '' then
    return jsonb_build_object('status', 'no_pending');
  end if;

  select av.id, av.whatsapp_otp_hash, av.whatsapp_otp_expires_at,
         av.whatsapp_attempts, av.whatsapp_e164, av.whatsapp_pending_e164
    into v_id, v_hash, v_expires, v_attempts, v_e164, v_pending
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

  v_final := coalesce(nullif(v_pending, ''), v_e164);

  -- El número y el sello se escriben en el MISMO statement a propósito:
  -- `trg_clear_whatsapp_seal_on_number_change` solo respeta un cambio de número
  -- si viene acompañado de su sello, y así sigue cubriendo cualquier otra ruta.
  update public.account_verifications
     set whatsapp_e164 = v_final,
         whatsapp_verified_at = v_now,
         whatsapp_pending_e164 = null,
         whatsapp_otp_hash = null,
         whatsapp_otp_expires_at = null,
         whatsapp_attempts = 0
   where id = v_id;

  return jsonb_build_object(
    'status', 'ok',
    'phone', v_final,
    'verified_at', v_now
  );
end;
$function$;

revoke all on function public.consume_whatsapp_otp_attempt(uuid, uuid, text, int)
  from public, anon, authenticated;
grant execute on function public.consume_whatsapp_otp_attempt(uuid, uuid, text, int)
  to service_role;
