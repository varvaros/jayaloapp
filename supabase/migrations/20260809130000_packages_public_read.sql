-- 20260809130000_packages_public_read.sql
-- Tienda pública del cliente (spec 2026-08-09-tienda-editable-app): la
-- pantalla que ve el CLIENTE (`provider_store_screen.dart`) ahora también
-- pinta PAQUETES, igual que ya hace con `provider_products` y
-- `provider_portfolio_items` — pero `provider_packages` hoy SOLO tiene la
-- política de dueño ("Owner can read own packages", `user_id = auth.uid()`),
-- verificado en prod: sin lectura pública, la RPC no lanza error (RLS
-- filtra, no revienta) pero devuelve lista vacía a cualquiera que no sea el
-- dueño. Esta migración añade la MISMA política pública que ya tiene
-- `provider_portfolio_items` (`for select to public using (true)`): no
-- expone nada nuevo (sin datos de contacto en esta tabla), solo iguala el
-- trato de lectura entre las tres tablas del escaparate.
--
-- Idempotente: `drop policy if exists` + `create policy` es seguro de
-- re-ejecutar sin importar el nombre de política previo; el `grant select`
-- es idempotente por naturaleza (repetirlo no falla ni duplica el permiso).
drop policy if exists "Public can read packages" on public.provider_packages;

create policy "Public can read packages"
  on public.provider_packages
  for select
  to public
  using (true);

grant select on public.provider_packages to anon, authenticated;
