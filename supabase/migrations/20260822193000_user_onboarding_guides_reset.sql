-- "Reiniciar tutorial" (Ajustes de la app, pedido PO 2026-08-22): el usuario
-- puede olvidar TODAS sus guías vistas para que la ayuda de cada botón vuelva
-- a salir desde cero. Sin borrado remoto no hay reinicio real: limpiar el
-- cache local del teléfono no sirve de nada porque el siguiente SELECT vuelve
-- a traer las guías marcadas.
create policy "own_delete" on public.user_onboarding_guides
  for delete using (user_id = (select auth.uid()));

-- La migración original (20260727000000) REVOCÓ todo sobre la tabla y
-- re-concedió solo select/insert. La política por sí sola no alcanza: sin el
-- privilegio, el DELETE muere en 42501 antes de llegar a evaluarse.
grant delete on public.user_onboarding_guides to authenticated;
