-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Open por horas: cuánta gente viene a cada hora
-- Ejecuta una vez en Supabase → SQL Editor. Se puede repetir.
-- Necesita docs/hibrido.sql (tabla open_sessions) y docs/seguridad-1.sql.
--   · Los atletas solo pueden leer SUS open. Esta función segura les deja ver
--     cuántos open hay a cada hora (fecha, hora e id), sin nombres ni notas,
--     para repartirse y respetar el máximo por hora.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.open_roster(p_from text, p_to text)
returns table(date text, "time" text, client_id uuid)
language sql stable security definer set search_path = public as $$
  select o.date::text, o.time, o.client_id
    from public.open_sessions o
   where public.is_member() and o.date::text between p_from and p_to
$$;
