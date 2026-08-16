-- `is_whatsapp_taken` solo miraba provider_businesses, así que el pre-chequeo
-- del alta NUNCA detectaba una colisión entre consumidores: el usuario gastaba
-- un SMS verificando su número y recién al guardar el perfil chocaba con el
-- índice único `profiles_phone_unique_idx` (23505), con un error genérico.
--
-- Se conserva intacto todo lo demás: la exclusión del número de prueba de la
-- revisión de Play (nunca ocupado) y el `_exclude_user` con el que un usuario
-- no se detecta a sí mismo.
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816173847).
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
        -- El teléfono del perfil es el que lleva el índice único; una cuenta
        -- anonimizada lo deja en NULL, así que no bloquea a nadie.
        select 1 from public.profiles p
        where coalesce(p.phone, '') <> ''
          and p.deleted_at is null
          and public.normalize_whatsapp(p.phone)
              = public.normalize_whatsapp(_whatsapp)
          and (_exclude_user is null or p.user_id <> _exclude_user)
      )
    );
$function$;
