-- `profiles_phone_unique_idx` era único sobre CUALQUIER teléfono escrito, sin
-- pedir prueba de control. Reclamar un número ajeno no requiere nada: el alta
-- (app y web) lo escribe desde los metadatos del signup, así que quien teclee el
-- teléfono de otra persona le BLOQUEA el registro legítimo — a la víctima le
-- sale "ese teléfono ya está en uso" y no tiene forma de recuperarlo. Es una
-- denegación de registro dirigida, gratis y silenciosa.
--
-- La unicidad pasa a aplicar SOLO a números verificados: una reclamación sin
-- verificar no bloquea a nadie, y el número es de quien PRUEBE que lo controla.
-- La prueba es la que ya existe (el OTP), así que no hay un mecanismo nuevo.
--
-- Cinco piezas, que son una sola cosa:
--   1. `profiles.phone_verified_at`, el sello del teléfono del perfil.
--   2. Backfill desde los sellos personales ya ganados.
--   3. Guard que retira el sello si el número cambia (mismo patrón que
--      `clear_whatsapp_seal_on_number_change`), porque `authenticated` SÍ puede
--      escribir `profiles.phone` de su propia fila.
--   4. El índice único, ahora parcial sobre verificados.
--   5. Los lectores que decían "ocupado" sin mirar si estaba verificado.
--
-- OJO: esta migración NACE INCOMPLETA y la siguiente (20260816230900) es
-- obligatoria. `profiles` tiene INSERT/UPDATE a nivel de TABLA para
-- `authenticated`, así que el permiso alcanza solo con existir a la columna
-- nueva y el sello sería auto-servicio. Nunca aplicar esta sin aquella.
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816230658).

-- ── 1. Columna ──────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists phone_verified_at timestamptz;

comment on column public.profiles.phone_verified_at is
  'Cuándo se probó el control de profiles.phone por OTP. Lo escribe SOLO consume_whatsapp_otp_attempt (no hay grant de UPDATE para authenticated). NULL = número reclamado pero sin probar, que no reserva nada.';

-- ── 2. Backfill: los sellos personales ya ganados no se pierden ─────────────
update public.profiles p
   set phone_verified_at = av.whatsapp_verified_at
  from public.account_verifications av
 where av.user_id = p.user_id
   and av.business_id is null
   and av.whatsapp_verified_at is not null
   and public.normalize_whatsapp(av.whatsapp_e164) = public.normalize_whatsapp(p.phone)
   and coalesce(p.phone, '') <> ''
   and p.phone_verified_at is null;

-- ── 3. Guard: cambiar el número retira el sello ────────────────────────────
-- Sin esto la unicidad es de papel: `authenticated` puede escribir `phone` de su
-- propia fila, así que bastaría verificar un número y luego cambiarlo para
-- quedarse ocupando el índice con un número que nadie probó.
create or replace function public.clear_phone_seal_on_number_change()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  -- Si el MISMO statement sella (escribe phone_verified_at junto al número),
  -- se respeta: es lo que hace consume_whatsapp_otp_attempt al promover.
  if regexp_replace(coalesce(NEW.phone, ''), '[^0-9]', '', 'g')
       is distinct from regexp_replace(coalesce(OLD.phone, ''), '[^0-9]', '', 'g')
     and NEW.phone_verified_at is not distinct from OLD.phone_verified_at then
    NEW.phone_verified_at := null;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_clear_phone_seal_on_number_change on public.profiles;
create trigger trg_clear_phone_seal_on_number_change
  before update on public.profiles
  for each row execute function public.clear_phone_seal_on_number_change();

-- ── 4. El índice ───────────────────────────────────────────────────────────
drop index if exists public.profiles_phone_unique_idx;
create unique index if not exists profiles_phone_verified_unique_idx
  on public.profiles (regexp_replace(phone, '[^0-9]', '', 'g'))
  where phone is not null and phone <> '' and phone_verified_at is not null
        and deleted_at is null;

-- ── 5a. La promoción del OTP también sella el teléfono del perfil ──────────
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
  v_digits text;
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

  update public.account_verifications
     set whatsapp_e164 = v_final,
         whatsapp_verified_at = v_now,
         whatsapp_pending_e164 = null,
         whatsapp_otp_hash = null,
         whatsapp_otp_expires_at = null,
         whatsapp_attempts = 0
   where id = v_id;

  -- Solo la fila PERSONAL define el teléfono del perfil; la de un negocio
  -- verifica el WhatsApp público de ese negocio, que es otra cosa.
  v_digits := regexp_replace(coalesce(v_final, ''), '[^0-9]', '', 'g');
  if _business_id is null and length(v_digits) >= 8 then
    -- Quien acaba de PROBAR control del número se queda con él. Al anterior
    -- tenedor se le retira el sello (conserva el número escrito, que no reserva
    -- nada sin sello): el índice parcial solo admite un verificado por número, y
    -- entre dos pruebas gana la de ahora — es el caso real de un número reciclado.
    update public.profiles
       set phone_verified_at = null
     where user_id <> _user_id
       and phone_verified_at is not null
       and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = v_digits;

    -- Número y sello en el MISMO statement: es lo que el guard de arriba exige
    -- para no retirar el sello que acabamos de ganar.
    update public.profiles
       set phone = v_final,
           phone_verified_at = v_now
     where user_id = _user_id;
  end if;

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

-- ── 5b. Los lectores dejan de contar reclamaciones sin probar ──────────────
-- Sin esto el arreglo es a medias: el índice ya no bloquea a la víctima, pero
-- estos dos le seguirían diciendo "ese número ya está en uso" y no la dejarían
-- avanzar igual.
create or replace function public.is_whatsapp_taken(
  _whatsapp text,
  _exclude_user uuid default null::uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select
    length(public.normalize_whatsapp(_whatsapp)) >= 10
    and public.normalize_whatsapp(_whatsapp)
        <> public.normalize_whatsapp('+18090000000')
    and (
      exists (
        select 1 from public.provider_businesses b
        where b.whatsapp <> ''
          and b.whatsapp = public.normalize_whatsapp(_whatsapp)
          and (_exclude_user is null or b.user_id <> _exclude_user)
      )
      or exists (
        -- Solo teléfonos VERIFICADOS: una reclamación sin probar no ocupa el
        -- número ni en el índice ni aquí.
        select 1 from public.profiles p
        where coalesce(p.phone, '') <> ''
          and p.phone_verified_at is not null
          and p.deleted_at is null
          and public.normalize_whatsapp(p.phone)
              = public.normalize_whatsapp(_whatsapp)
          and (_exclude_user is null or p.user_id <> _exclude_user)
      )
    );
$function$;

create or replace function public.check_account_exists(
  _email text default null::text,
  _phone text default null::text,
  _rnc text default null::text,
  _whatsapp text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_email_norm text := lower(trim(coalesce(_email, '')));
  v_phone_norm text := regexp_replace(coalesce(_phone, ''), '[^0-9]', '', 'g');
  v_rnc_norm   text := trim(coalesce(_rnc, ''));
  v_wa_norm    text := regexp_replace(coalesce(_whatsapp, ''), '[^0-9]', '', 'g');
  v_email_taken boolean := false;
  v_phone_taken boolean := false;
  v_rnc_taken   boolean := false;
  v_wa_taken    boolean := false;
begin
  if v_email_norm <> '' then
    v_email_taken := exists (select 1 from profiles p where lower(p.email) = v_email_norm);
  end if;
  if v_phone_norm <> '' and length(v_phone_norm) >= 8 then
    -- `phone_verified_at is not null`: antes bastaba con que ALGUIEN hubiera
    -- escrito el número para declararlo ocupado, y eso es justo lo que permitía
    -- bloquear el alta de su dueño legítimo.
    v_phone_taken := exists (
      select 1 from profiles p
      where p.phone_verified_at is not null
        and p.deleted_at is null
        and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = v_phone_norm);
  end if;
  if v_rnc_norm <> '' then
    v_rnc_taken := exists (select 1 from provider_businesses where rnc = v_rnc_norm);
  end if;
  if v_wa_norm <> '' and length(v_wa_norm) >= 8 then
    v_wa_taken := exists (
      select 1 from provider_businesses
      where regexp_replace(coalesce(whatsapp, ''), '[^0-9]', '', 'g') = v_wa_norm);
  end if;
  if not v_email_taken and not v_phone_taken and not v_rnc_taken and not v_wa_taken then
    return null;
  end if;
  return jsonb_build_object(
    'email_taken', v_email_taken, 'phone_taken', v_phone_taken,
    'rnc_taken', v_rnc_taken, 'whatsapp_taken', v_wa_taken);
end;
$function$;
