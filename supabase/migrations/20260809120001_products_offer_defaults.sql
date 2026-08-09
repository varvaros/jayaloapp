-- 20260809120001_products_offer_defaults.sql
-- Molde de oferta del ítem de tienda (spec 2026-08-09): lo que no tiene
-- columna propia viaja en jsonb y la web lo ignora.
alter table public.provider_products
  add column if not exists offer_defaults jsonb;

grant select (offer_defaults), insert (offer_defaults),
      update (offer_defaults) on public.provider_products to authenticated;
