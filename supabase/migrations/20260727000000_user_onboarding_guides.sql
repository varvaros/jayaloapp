-- Guías de onboarding contextual ya vistas, por usuario. Persistencia
-- cross-device del sistema de spotlight. Marcar visto = INSERT idempotente.
create table if not exists public.user_onboarding_guides (
  user_id      uuid        not null references auth.users(id) on delete cascade,
  guide_key    text        not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, guide_key)
);

alter table public.user_onboarding_guides enable row level security;

-- El usuario solo ve sus filas.
create policy "own_select" on public.user_onboarding_guides
  for select using (user_id = auth.uid());

-- El usuario solo inserta filas propias.
create policy "own_insert" on public.user_onboarding_guides
  for insert with check (user_id = auth.uid());

-- Mínimo privilegio: nada para anon/PUBLIC ni por defecto para authenticated
-- (Supabase concede ALL a authenticated en public por defecto — hay que
-- revocarlo antes de re-conceder solo SELECT/INSERT).
revoke all on public.user_onboarding_guides from anon, authenticated, public;
grant select, insert on public.user_onboarding_guides to authenticated;
