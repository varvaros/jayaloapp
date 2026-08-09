-- 20260809120000_business_services_chips.sql
-- Chips de servicios del perfil (spec 2026-08-09). Publicación directa, sin
-- moderación (decisión PO 08-09 que supera el spec del 07-26).
alter table public.provider_businesses
  add column if not exists services text[] not null default '{}';

-- Constraint condicional: PostgreSQL no soporta "add constraint if not exists"
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'provider_businesses_services_max20'
      and conrelid = 'public.provider_businesses'::regclass
  ) then
    alter table public.provider_businesses
      add constraint provider_businesses_services_max20
      check (coalesce(array_length(services, 1), 0) <= 20);
  end if;
end $$;

-- Mismo patrón por columna que description: lectura pública, escritura del
-- dueño (la RLS de fila ya limita el UPDATE al user_id propio).
grant select (services) on public.provider_businesses to anon, authenticated;
grant update (services) on public.provider_businesses to authenticated;
