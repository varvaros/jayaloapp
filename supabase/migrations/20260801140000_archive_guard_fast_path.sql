-- El guard de archivado cobraba un `has_role()` en CADA mensaje de chat.
--
-- `enforce_archive_own_side` (migración 20260801100000) comprobaba el ROL antes
-- de mirar si las columnas de archivado habían cambiado siquiera. Y
-- `trg_bump_conversation_last_message_at` (20260726000000) hace un UPDATE sobre
-- `conversations` en CADA inserción de mensaje → cada mensaje de chat de toda la
-- plataforma pagaba una consulta a `user_roles` para preguntar si el remitente
-- es admin, solo para descubrir después que no había tocado ninguna columna de
-- archivado. Lo mismo en `improveOfferPrice`, `markConversationLost`,
-- `mark_conversation_completed` y los cambios de estado de embudo.
--
-- El guard hermano del proyecto (`enforce_agreed_price_provider_only`,
-- 20260729210000) ya lo hace en el orden correcto: compara las columnas
-- vigiladas primero y solo consulta el rol si de verdad cambiaron. Esto lo
-- alinea con ese patrón.
--
-- Hallazgo de la revisión final de rama (2026-08-01). Sin cambio de
-- comportamiento: las mismas escrituras se bloquean y las mismas se permiten.

CREATE OR REPLACE FUNCTION public.enforce_archive_own_side()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $fn$
BEGIN
  -- SALIDA RÁPIDA, y va primero a propósito: si no cambió ninguna columna de
  -- archivado, este trigger no tiene nada que vigilar y no debe costar una
  -- consulta a `user_roles`. Es el caso del 99% de los UPDATE sobre
  -- `conversations` (el bump de `last_message_at` de cada mensaje).
  IF NEW.archived_by_customer IS NOT DISTINCT FROM OLD.archived_by_customer
     AND NEW.archived_by_provider IS NOT DISTINCT FROM OLD.archived_by_provider
  THEN
    RETURN NEW;
  END IF;

  -- service_role no tiene auth.uid(): se deja pasar (backfills, soporte).
  IF (select auth.uid()) IS NULL
     OR (select public.has_role((select auth.uid()), 'admin'::app_role)) THEN
    RETURN NEW;
  END IF;

  IF NEW.archived_by_provider IS DISTINCT FROM OLD.archived_by_provider
     AND (select auth.uid()) <> OLD.provider_user_id THEN
    RAISE EXCEPTION 'Only the provider can archive the provider side'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.archived_by_customer IS DISTINCT FROM OLD.archived_by_customer
     AND (select auth.uid()) <> OLD.customer_id THEN
    RAISE EXCEPTION 'Only the customer can archive the customer side'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

-- Trigger-only → sin EXECUTE directo (Supabase Cloud lo auto-otorga al recrear
-- la función, así que hay que revocarlo de nuevo tras cada CREATE OR REPLACE).
REVOKE EXECUTE ON FUNCTION public.enforce_archive_own_side()
  FROM PUBLIC, anon, authenticated;

-- El trigger NO se recrea: `CREATE OR REPLACE FUNCTION` conserva la misma firma
-- y `trg_enforce_archive_own_side` sigue apuntando a ella.
