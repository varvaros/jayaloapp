-- `profiles` tenía INSERT/UPDATE a nivel de TABLA para `authenticated`, así que
-- el permiso alcanza a toda columna nueva automáticamente — incluida
-- `phone_verified_at`, que acaba de nacer en la migración anterior.
--
-- Con eso, la unicidad sobre verificados nacía rota y PEOR que lo que sustituye:
-- cualquiera podía escribir en SU PROPIA fila el teléfono de otra persona y
-- sellarlo a mano (`update profiles set phone = '<víctima>', phone_verified_at =
-- now()`), quedándose con el número en el índice y haciendo que
-- `check_account_exists` e `is_whatsapp_taken` lo declararan ocupado por un
-- "verificado" que nadie verificó. La RLS no lo impide: limita la fila, no la
-- columna, y la fila es suya.
--
-- El sello lo escribe SOLO `consume_whatsapp_otp_attempt`, que es SECURITY
-- DEFINER y no depende de estos grants. Se pasa a lista blanca por columna, que
-- es el patrón de mínimo privilegio que el proyecto ya aplica en las tablas de
-- dinero y de autorización.
--
-- La lista se calcula en vez de escribirse a mano para que este archivo no se
-- desincronice del esquema real: es "todas las columnas menos el sello".
--
-- Aplicada a producción vía MCP el 2026-08-16 (version 20260816230900).
do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'profiles'
     and column_name <> 'phone_verified_at';

  -- Revocar el grant de tabla es el punto: mientras exista, cubre por sí solo
  -- cualquier columna futura y esta lista blanca es decorativa.
  execute 'revoke insert, update on public.profiles from authenticated';
  execute format('grant insert (%s) on public.profiles to authenticated', v_cols);
  execute format('grant update (%s) on public.profiles to authenticated', v_cols);
end $$;
