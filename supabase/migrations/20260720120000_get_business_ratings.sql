-- Reputación agregada por negocio para el catálogo (avg + conteo), por lote.
-- SECURITY DEFINER: agrega business_reviews sin exponer reviewer_id ni filas
-- individuales; solo devuelve promedio y conteo. Escala 1-10 (igual que
-- conversation_ratings / get_provider_reviews_summary), sin convertir a 5.
create or replace function public.get_business_ratings(_business_ids uuid[])
returns table (business_id uuid, avg_rating numeric, reviews_count integer)
language sql
security definer
set search_path = public
as $$
  select br.business_id,
         round(avg(br.rating)::numeric, 1) as avg_rating,
         count(*)::int                     as reviews_count
  from business_reviews br
  where br.business_id = any(_business_ids)
  group by br.business_id;
$$;

-- REVOKE FROM public (no solo anon): CREATE FUNCTION auto-otorga EXECUTE a
-- PUBLIC, así que revocar solo anon deja el grant heredado vivo (gotcha
-- Supabase). El catálogo va detrás de login → solo authenticated.
revoke all on function public.get_business_ratings(uuid[]) from public;
grant execute on function public.get_business_ratings(uuid[]) to authenticated;
